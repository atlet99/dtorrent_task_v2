import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Example demonstrating the new TorrentParser with full BEP 52 support
Future<void> main(List<String> args) async {
  try {
    // Get script directory
    var scriptDir = path.dirname(Platform.script.path);
    var torrentsPath =
        path.canonicalize(path.join(scriptDir, '..', '..', '..', 'torrents'));

    // Try to find a torrent file
    var torrentFile = path.join(torrentsPath, 'big-buck-bunny.torrent');
    if (!await File(torrentFile).exists()) {
      print('Torrent file not found: $torrentFile');
      if (args.isNotEmpty) {
        torrentFile = args[0];
      } else {
        print('Please provide a torrent file path as an argument');
        return;
      }
    }

    print('Parsing torrent: $torrentFile');
    print('');

    // Parse using new TorrentModel
    final torrent = await TorrentModel.parse(torrentFile);

    // Display basic information
    print('=== Torrent Information ===');
    print('Name: ${torrent.name}');
    print('Version: ${torrent.version}');
    print('Info Hash: ${torrent.infoHash}');
    print('Info Hash Length: ${torrent.infoHashBuffer.length} bytes');
    print('Piece Length: ${torrent.pieceLength} bytes');
    print(
        'Total Size: ${torrent.totalSize} bytes (${(torrent.totalSize / 1024 / 1024).toStringAsFixed(2)} MB)');
    print('Files: ${torrent.files.length}');
    print('Pieces: ${torrent.pieces?.length ?? 0}');
    print('Trackers: ${torrent.announces.length}');
    print('DHT Nodes: ${torrent.nodes.length}');
    print('');

    // Display version-specific information
    if (torrent.version == TorrentVersion.v2 ||
        torrent.version == TorrentVersion.hybrid) {
      print('=== BitTorrent v2 Information ===');
      print('Meta Version: ${torrent.metaVersion}');
      if (torrent.fileTree != null) {
        print(
            'File Tree: Available (${torrent.fileTree!.length} root entries)');
        final treeFiles = FileTreeHelper.extractFiles(torrent.fileTree!, '');
        print('Files from tree: ${treeFiles.length}');
      } else {
        print('File Tree: Not available');
      }
      if (torrent.pieceLayers != null) {
        print(
            'Piece Layers: Available (${torrent.pieceLayers!.length} layers)');
      } else {
        print('Piece Layers: Not available');
      }
      if (torrent.rootHash != null) {
        print('Root Hash: Available (${torrent.rootHash!.length} bytes)');
      } else {
        print('Root Hash: Not available');
      }
      print('');

      if (torrent.v2InfoHash != null) {
        final v2Hash = torrent.v2InfoHash!;
        print(
            'v2 Info Hash: ${v2Hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        print('v2 Info Hash Length: ${v2Hash.length} bytes');
      }
    }

    if (torrent.version == TorrentVersion.v1 ||
        torrent.version == TorrentVersion.hybrid) {
      if (torrent.v1InfoHash != null) {
        final v1Hash = torrent.v1InfoHash!;
        print(
            'v1 Info Hash: ${v1Hash.map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
        print('v1 Info Hash Length: ${v1Hash.length} bytes');
      }
    }

    print('');
    print('=== Files ===');
    for (var i = 0; i < torrent.files.length; i++) {
      final file = torrent.files[i];
      print('${i + 1}. ${file.path}');
      print(
          '   Size: ${file.length} bytes (${(file.length / 1024 / 1024).toStringAsFixed(2)} MB)');
      print('   Offset: ${file.offset}');
    }

    print('');
    print('=== Trackers ===');
    for (var i = 0; i < torrent.announces.length; i++) {
      print('${i + 1}. ${torrent.announces[i]}');
    }

    if (torrent.nodes.isNotEmpty) {
      print('');
      print('=== DHT Nodes ===');
      for (var i = 0; i < torrent.nodes.length; i++) {
        print('${i + 1}. ${torrent.nodes[i]}');
      }
    }

    print('');
    print('=== Comparison with TorrentVersionHelper ===');
    final detectedVersion = TorrentVersionHelper.detectVersion(torrent);
    print('Detected Version: $detectedVersion');
    print('Matches: ${detectedVersion == torrent.version}');
  } catch (e, stackTrace) {
    print('Error: $e');
    print('Stack trace: $stackTrace');
  }
}
