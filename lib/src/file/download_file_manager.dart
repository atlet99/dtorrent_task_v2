import 'dart:async';
import 'dart:io';

import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:dtorrent_task_v2/src/file/download_file_manager_events.dart';
import 'package:dtorrent_task_v2/src/file/utils.dart';
import 'package:dtorrent_task_v2/src/task_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import '../peer/peer_base.dart';

import '../piece/piece.dart';
import 'download_file.dart';
import 'file_validator.dart';
import 'state_file.dart';
import 'state_file_v2.dart';
import '../torrent/file_tree.dart';
import '../torrent/torrent_version.dart';

var _log = Logger("DownloadFileManager");

class DownloadFileManager with EventsEmittable<DownloadFileManagerEvent> {
  final TorrentModel metainfo;

  final List<DownloadFile> _files = [];

  List<DownloadFile> get files => _files;
  final List<Piece> _pieces;
  List<List<DownloadFile>?>? _piece2fileMap;
  List<List<DownloadFile>?>? get piece2fileMap => _piece2fileMap;

  final Map<String, List<Piece>> _file2pieceMap = {};
  final Object _stateFile; // Can be StateFile or StateFileV2
  String? _baseDirectory;

  /// TODO: File read caching
  DownloadFileManager(
    this.metainfo,
    this._stateFile,
    this._pieces,
  ) {
    _piece2fileMap = List.filled(_bitfield.piecesNum, null);
  }

  static Future<DownloadFileManager> createFileManager(TorrentModel metainfo,
      String localDirectory, Object stateFile, List<Piece> pieces,
      {bool validateOnResume = false}) async {
    final manager = DownloadFileManager(metainfo, stateFile, pieces);
    await manager._init(localDirectory);

    // Validate files on resume if requested
    if (validateOnResume) {
      await manager._validateOnResume(localDirectory);
    }

    return manager;
  }

  /// Validate files on resume
  Future<void> _validateOnResume(String directory) async {
    _log.info('Validating files on resume...');
    try {
      final validator = FileValidator(metainfo, _pieces, directory);

      // Quick validation first
      final quickValid = await validator.quickValidate();
      if (!quickValid) {
        _log.warning(
            'Quick validation failed - some files may be missing or corrupted');
      }

      // Validate pieces that are marked as complete
      final completedPieces = _bitfield.completedPieces;
      if (completedPieces.isNotEmpty) {
        _log.info('Validating ${completedPieces.length} completed pieces...');
        var invalidCount = 0;

        for (var pieceIndex in completedPieces) {
          if (pieceIndex < _pieces.length) {
            final isValid = await validator.validatePiece(pieceIndex);
            if (!isValid) {
              _log.warning(
                  'Piece $pieceIndex failed validation, marking for re-download');
              await _updateStateBitfield(pieceIndex, false);
              invalidCount++;
            }
          }
        }

        if (invalidCount > 0) {
          _log.warning(
              'Found $invalidCount invalid pieces, they will be re-downloaded');
        } else {
          _log.info('All completed pieces validated successfully');
        }
      }
    } catch (e, stackTrace) {
      _log.warning('File validation on resume failed', e, stackTrace);
      // Don't fail the resume if validation fails
    }
  }

  Future<DownloadFileManager> _init(String directory) async {
    if (!directory.endsWith(Platform.pathSeparator)) {
      directory = '$directory${Platform.pathSeparator}';
    }
    _baseDirectory = directory;
    _initFileMap(directory);
    await detectMovedFiles();
    await _restoreFileAttributes();
    return this;
  }

  Bitfield get localBitfield => _bitfield;

  bool localHave(int index) {
    return _bitfield.getBit(index);
  }

  bool get isAllComplete {
    return _bitfield.piecesNum == _bitfield.completedPieces.length;
  }

  int get piecesNumber => _bitfield.piecesNum;

  Future<bool> updateBitfield(int index, [bool have = true]) async {
    final updated = await _updateStateBitfield(index, have);
    if (updated) events.emit(StateFileUpdated());
    return updated;
  }

  // Future<bool> updateBitfields(List<int> indices, [List<bool> haves]) {
  //   return _stateFile.updateBitfields(indices, haves);
  // }

  Future<bool> updateUpload(int uploaded) async {
    final updated = await _updateStateUploaded(uploaded);
    if (updated) events.emit(StateFileUpdated());
    return updated;
  }

  int get downloaded => _downloadedFromState;

  /// This method appears to only write the buffer content to the disk, but in
  /// reality,every time the cache is written, it is considered that the [Piece]
  /// corresponding to [pieceIndex] has been completed. Therefore, it will
  /// remove the file's corresponding piece index from the _file2pieceMap. When
  /// all the pieces have been removed, a File Complete event will be triggered.
  Future<bool> flushFiles(Set<int> pieceIndices) async {
    final d = _downloadedFromState;
    final flushed = <String>{};
    for (final pieceIndex in pieceIndices) {
      final files = _piece2fileMap?[pieceIndex];
      if (files == null || files.isEmpty) continue;
      for (final file in files) {
        final pieces = _file2pieceMap[file.torrentFilePath];
        if (pieces == null) continue;
        if (flushed.add(file.filePath)) {
          await file.requestFlush();
          // Emit only once per file
          if (file.completelyFlushed) {
            await _applyFileAttributes(file);
            events.emit(DownloadManagerFileCompleted(file));
          }
        }
      }
    }
    events.emit(StateFileUpdated());
    final totalLength = metainfo.length;
    final progress =
        totalLength == null || totalLength == 0 ? 0.0 : (d / totalLength) * 100;
    final msg =
        'downloaded：${d / (1024 * 1024)} mb , Progress ${progress.toStringAsFixed(2)} %';
    _log.finer(msg);
    return true;
  }

  void _initFileMap(String directory) {
    // Check if this is a v2 torrent with file tree
    final torrentVersion = TorrentVersionHelper.detectVersion(metainfo);

    if ((torrentVersion == TorrentVersion.v2 ||
            torrentVersion == TorrentVersion.hybrid) &&
        metainfo.fileTree != null) {
      // Use v2 file tree structure
      _log.info('Using v2 file tree structure');
      _initFileMapFromTree(directory, metainfo.fileTree!);
      return;
    }

    // Use v1 file structure (files array)
    for (var i = 0; i < metainfo.files.length; i++) {
      var file = metainfo.files[i];
      var startPiece = file.offset ~/ metainfo.pieceLength;
      var endPiece = file.end ~/ metainfo.pieceLength;
      if (file.end.remainder(metainfo.pieceLength) == 0) endPiece--;

      var pieces = _file2pieceMap[file.path];
      if (pieces == null) {
        pieces = <Piece>[];
        _file2pieceMap[file.path] = pieces;
      }
      var downloadFile = DownloadFile(
        _resolveInitialPath(directory, file.path),
        file.offset,
        file.length,
        file.path,
        pieces,
        attributes: file.attributes,
        isPaddingFile: file.isPaddingFile,
        symlinkPath: file.symlinkPath,
      );

      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var downloadFileList = _piece2fileMap?[pieceIndex];
        if (downloadFileList == null) {
          downloadFileList = <DownloadFile>[];
          _piece2fileMap?[pieceIndex] = downloadFileList;
        }
        if (pieceIndex < _pieces.length) {
          pieces.add(_pieces[pieceIndex]);
          downloadFileList.add(downloadFile);
        }
      }

      _files.add(downloadFile);
    }
  }

  /// Initialize file map from file tree (v2 format)
  ///
  /// This method is used when file tree is available from torrent
  void _initFileMapFromTree(
      String directory, Map<String, FileTreeEntry> fileTree) {
    final files = FileTreeHelper.extractFiles(fileTree, '');
    var currentOffset = 0;

    for (var fileInfo in files) {
      // Calculate which pieces this file spans
      var startPiece = currentOffset ~/ metainfo.pieceLength;
      var fileEnd = currentOffset + fileInfo.length;
      var endPiece = fileEnd ~/ metainfo.pieceLength;
      if (fileEnd.remainder(metainfo.pieceLength) == 0) endPiece--;

      var pieces = _file2pieceMap[fileInfo.path];
      if (pieces == null) {
        pieces = <Piece>[];
        _file2pieceMap[fileInfo.path] = pieces;
      }

      var downloadFile = DownloadFile(
          _resolveInitialPath(directory, fileInfo.path),
          currentOffset,
          fileInfo.length,
          fileInfo.path,
          pieces,
          attributes: fileInfo.attributes,
          isPaddingFile: fileInfo.isPaddingFile,
          symlinkPath: fileInfo.symlinkPath);

      for (var pieceIndex = startPiece; pieceIndex <= endPiece; pieceIndex++) {
        var downloadFileList = _piece2fileMap?[pieceIndex];
        if (downloadFileList == null) {
          downloadFileList = <DownloadFile>[];
          _piece2fileMap?[pieceIndex] = downloadFileList;
        }
        if (pieceIndex < _pieces.length) {
          pieces.add(_pieces[pieceIndex]);
          downloadFileList.add(downloadFile);
        }
      }

      _files.add(downloadFile);
      currentOffset = fileEnd;
    }
  }

  String _resolveInitialPath(String directory, String torrentPath) {
    final persisted = _resolvePathFromState(torrentPath);
    if (persisted != null && persisted.isNotEmpty) {
      return persisted;
    }
    return directory + torrentPath;
  }

  String? _resolvePathFromState(String torrentPath) {
    return switch (_stateFile) {
      StateFile state => state.resolveFilePath(torrentPath),
      StateFileV2 state => state.resolveFilePath(torrentPath),
      _ => null,
    };
  }

  Future<void> _persistMovedPath(
      String torrentPath, String absolutePath) async {
    switch (_stateFile) {
      case final StateFile state:
        await state.updateFilePath(torrentPath, absolutePath);
      case final StateFileV2 state:
        await state.updateFilePath(torrentPath, absolutePath);
      default:
        return;
    }
  }

  Future<void> _removePersistedMovedPath(String torrentPath) async {
    switch (_stateFile) {
      case final StateFile state:
        await state.removeFilePath(torrentPath);
      case final StateFileV2 state:
        await state.removeFilePath(torrentPath);
      default:
        return;
    }
  }

  /// Move a torrent file while download is active and persist new path in state.
  Future<bool> moveFile(
    String torrentFilePath,
    String newAbsolutePath, {
    bool validateAfterMove = true,
  }) async {
    final file = _files.firstWhere(
      (element) => element.torrentFilePath == torrentFilePath,
      orElse: () => throw ArgumentError.value(
          torrentFilePath, 'torrentFilePath', 'file not found in torrent'),
    );
    if (file.isVirtualFile) return false;

    await file.requestFlush();
    await file.moveToPath(newAbsolutePath);
    await _persistMovedPath(torrentFilePath, newAbsolutePath);

    if (!validateAfterMove) return true;
    return validateMovedFile(torrentFilePath);
  }

  /// Detect externally moved files and rebind runtime paths.
  Future<Map<String, String>> detectMovedFiles() async {
    final baseDirectory = _baseDirectory;
    if (baseDirectory == null) return const {};

    final moved = <String, String>{};
    for (final file in _files) {
      if (file.isVirtualFile) continue;
      if (await File(file.filePath).exists()) continue;

      final expectedName =
          file.torrentFilePath.split(Platform.pathSeparator).last;
      final candidate = await _findMovedCandidate(
        baseDirectory,
        expectedName,
        file.length,
      );
      if (candidate == null) {
        await _removePersistedMovedPath(file.torrentFilePath);
        continue;
      }

      await file.rebindPath(candidate.path);
      await _persistMovedPath(file.torrentFilePath, candidate.path);
      moved[file.torrentFilePath] = candidate.path;
    }
    return moved;
  }

  Future<File?> _findMovedCandidate(
      String root, String fileName, int expectedSize) async {
    final dir = Directory(root);
    if (!await dir.exists()) return null;
    try {
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        if (!entity.path.endsWith(fileName)) continue;
        final stat = await entity.stat();
        if (stat.size == expectedSize) return entity;
      }
    } catch (e, stackTrace) {
      _log.warning('Failed to detect moved files', e, stackTrace);
    }
    return null;
  }

  /// Validate moved file with basic size checks.
  Future<bool> validateMovedFile(String torrentFilePath) async {
    final index = metainfo.files.indexWhere((f) => f.path == torrentFilePath);
    if (index == -1) return false;
    final file = _files.firstWhere(
      (element) => element.torrentFilePath == torrentFilePath,
      orElse: () => throw ArgumentError.value(
          torrentFilePath, 'torrentFilePath', 'file not found in torrent'),
    );
    if (file.isVirtualFile) return true;
    final ioFile = File(file.filePath);
    if (!await ioFile.exists()) return false;
    final stat = await ioFile.stat();
    return stat.size == metainfo.files[index].length;
  }

  Future<void> _restoreFileAttributes() async {
    for (final file in _files) {
      if (file.isPaddingFile) continue;
      await _applyFileAttributes(file);
    }
  }

  Future<void> _applyFileAttributes(DownloadFile file) async {
    if (file.isPaddingFile) return;
    if (file.isSymlinkFile) {
      await _ensureSymlinkFile(file);
      return;
    }

    final exists = await File(file.filePath).exists();
    if (!exists) return;

    if (file.attributes?.isExecutable == true) {
      await _setExecutablePermission(file.filePath);
    }
  }

  Future<void> _ensureSymlinkFile(DownloadFile file) async {
    final targetSegments = file.symlinkPath;
    if (targetSegments == null || targetSegments.isEmpty) return;
    if (Platform.isWindows) {
      _log.fine('Skip symlink restoration on Windows for ${file.filePath}');
      return;
    }

    final linkFile = File(file.filePath);
    final parentDir = linkFile.parent;
    if (!await parentDir.exists()) {
      await parentDir.create(recursive: true);
    }

    final link = Link(file.filePath);
    try {
      if (await link.exists()) {
        await link.delete();
      } else if (await linkFile.exists()) {
        await linkFile.delete();
      }
      final target = targetSegments.join(Platform.pathSeparator);
      await link.create(target);
    } catch (e, stackTrace) {
      _log.warning(
          'Failed to restore symlink for ${file.filePath}', e, stackTrace);
    }
  }

  Future<void> _setExecutablePermission(String path) async {
    if (Platform.isWindows) return;
    try {
      final result = await Process.run('chmod', <String>['+x', path]);
      if (result.exitCode != 0) {
        _log.warning('chmod failed for $path: ${result.stderr}');
      }
    } catch (e, stackTrace) {
      _log.warning(
          'Failed to apply executable attribute for $path', e, stackTrace);
    }
  }

  Future<List<int>?> readFile(int pieceIndex, int begin, int length) async {
    final piece = _pieces[pieceIndex];

    final files = _piece2fileMap?[pieceIndex];
    final startByte = piece.offset + begin;
    final endByte = startByte + length;
    if (files == null || files.isEmpty) return null;
    final futures = <Future<List<int>>>[];
    for (final tempFile in files) {
      final re =
          blockToDownloadFilePosition(startByte, endByte, length, tempFile);
      if (re == null) continue;
      futures
          .add(tempFile.requestRead(re.position, re.blockEnd - re.blockStart));
    }
    final blocks = await Future.wait(futures);
    final block = blocks.fold<List<int>>(<int>[], (previousValue, element) {
      previousValue.addAll(element);
      return previousValue;
    });

    events.emit(SubPieceReadCompleted(pieceIndex, begin, block));

    return block;
  }

  ///
  // Writes the content of a Sub Piece to the file. After completion, a sub piece complete event will be sent.
  /// If it fails, a sub piece failed event will be sent.
  ///
  /// The Sub Piece is from the Piece corresponding to [pieceIndex], and the content is [block] starting from [begin].
  /// This class does not validate if the written Sub Piece is a duplicate; it simply overwrites the previous content.
  Future<bool> writeFile(int pieceIndex, int begin, List<int> block) async {
    final tempFiles = _piece2fileMap?[pieceIndex];
    // TODO: Does this work for last piece?
    // this is the start position relative to  start of the entire torrent block
    final startByte = pieceIndex * metainfo.pieceLength + begin;
    final blockSize = block.length;
    // this is the end position relative to  start of the entire torrent block
    final endByte = startByte + blockSize;
    if (tempFiles == null || tempFiles.isEmpty) return false;
    final futures = <Future<bool>>[];
    for (final tempFile in tempFiles) {
      final re =
          blockToDownloadFilePosition(startByte, endByte, blockSize, tempFile);
      if (re == null) continue;
      futures.add(tempFile.requestWrite(
          re.position, block, re.blockStart, re.blockEnd));
    }
    final written = await Stream.fromFutures(futures).fold<bool>(true, (p, a) {
      return p && a;
    });

    if (written) {
      events.emit(SubPieceWriteCompleted(pieceIndex, begin, blockSize));
    } else {
      events.emit(SubPieceWriteFailed(pieceIndex, begin, blockSize));
    }

    return written;
  }

  Future<void> close() async {
    events.dispose();
    await _closeStateFile();
    for (final file in _files) {
      await file.close();
    }
    _clean();
  }

  void _clean() {
    _file2pieceMap.clear();
    _piece2fileMap = null;
  }

  Future<void> delete() async {
    await _deleteStateFile();
    for (final file in _files) {
      await file.delete();
    }
    _clean();
  }

  Bitfield get _bitfield => switch (_stateFile) {
        StateFile state => state.bitfield,
        StateFileV2 state => state.bitfield,
        _ => throw StateError(
            'Unsupported state file type: ${_stateFile.runtimeType}'),
      };
  int get _downloadedFromState => switch (_stateFile) {
        StateFile state => state.downloaded,
        StateFileV2 state => state.downloaded,
        _ => throw StateError(
            'Unsupported state file type: ${_stateFile.runtimeType}'),
      };

  Future<bool> _updateStateBitfield(int index, bool have) async {
    return switch (_stateFile) {
      StateFile state => state.updateBitfield(index, have),
      StateFileV2 state => state.updateBitfield(index, have),
      _ => Future<bool>.error(
          StateError('Unsupported state file type: ${_stateFile.runtimeType}')),
    };
  }

  Future<bool> _updateStateUploaded(int uploaded) async {
    return switch (_stateFile) {
      StateFile state => state.updateUploaded(uploaded),
      StateFileV2 state => state.updateUploaded(uploaded),
      _ => Future<bool>.error(
          StateError('Unsupported state file type: ${_stateFile.runtimeType}')),
    };
  }

  Future<void> _closeStateFile() async {
    switch (_stateFile) {
      case final StateFile state:
        await state.close();
      case final StateFileV2 state:
        await state.close();
      default:
        return;
    }
  }

  Future<void> _deleteStateFile() async {
    switch (_stateFile) {
      case final StateFile state:
        await state.delete();
      case final StateFileV2 state:
        await state.delete();
      default:
        return;
    }
  }
}
