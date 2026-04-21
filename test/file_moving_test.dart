import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

import 'test_helpers.dart';

List<Piece> _buildPieces(TorrentModel torrent) {
  final pieces = torrent.pieces;
  if (pieces == null) {
    throw StateError('Expected v1/hybrid torrent with pieces');
  }

  final list = <Piece>[];
  for (var i = 0; i < pieces.length; i++) {
    final hash = pieces[i];
    final byteLength =
        i == pieces.length - 1 ? torrent.lastPieceLength : torrent.pieceLength;
    list.add(Piece(
      String.fromCharCodes(hash),
      i,
      byteLength,
      i * torrent.pieceLength,
      isComplete: true,
    ));
  }
  return list;
}

void main() {
  group('Move files while downloading (5.1)', () {
    test('should move file and persist moved path in state', () async {
      final torrent = await createTestTorrent(fileSize: 32 * 1024);
      final downloadDir = await getTestDownloadDirectory();

      final state = await StateFileV2.getStateFile(downloadDir.path, torrent);
      final manager = await DownloadFileManager.createFileManager(
        torrent,
        downloadDir.path,
        state,
        _buildPieces(torrent),
      );

      final file = manager.files.first;
      final source = File(file.filePath);
      await source.parent.create(recursive: true);
      await source.writeAsBytes(List<int>.filled(file.length, 1));

      final movedPath =
          '${downloadDir.path}${Platform.pathSeparator}moved${Platform.pathSeparator}${file.originalFileName}';
      final moved = await manager.moveFile(file.torrentFilePath, movedPath);

      expect(moved, isTrue);
      expect(await File(movedPath).exists(), isTrue);
      expect(state.resolveFilePath(file.torrentFilePath), movedPath);

      await manager.close();
      await cleanupTestDirectory(downloadDir);
    });

    test('should detect externally moved files inside save directory',
        () async {
      final torrent = await createTestTorrent(fileSize: 32 * 1024);
      final downloadDir = await getTestDownloadDirectory();

      final state = await StateFileV2.getStateFile(downloadDir.path, torrent);
      final manager = await DownloadFileManager.createFileManager(
        torrent,
        downloadDir.path,
        state,
        _buildPieces(torrent),
      );

      final file = manager.files.first;
      final source = File(file.filePath);
      await source.parent.create(recursive: true);
      await source.writeAsBytes(List<int>.filled(file.length, 2));

      final externalMovedPath =
          '${downloadDir.path}${Platform.pathSeparator}external_move${Platform.pathSeparator}${file.originalFileName}';
      await File(externalMovedPath).parent.create(recursive: true);
      await source.rename(externalMovedPath);

      final moved = await manager.detectMovedFiles();
      expect(moved[file.torrentFilePath], externalMovedPath);
      expect(await manager.validateMovedFile(file.torrentFilePath), isTrue);

      await manager.close();
      await cleanupTestDirectory(downloadDir);
    });
  });
}
