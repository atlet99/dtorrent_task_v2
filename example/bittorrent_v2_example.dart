import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Example demonstrating BitTorrent v2 protocol support
///
/// This example shows how to use the BitTorrent v2 (BEP 52) features:
/// - Support for v2 info hash (32 bytes instead of 20)
/// - SHA-256 piece hashing for v2 torrents
/// - Hybrid torrent support (v1 + v2)
void main() async {
  print('BitTorrent v2 Protocol Example');
  print('==============================\n');

  // Example 1: Check torrent version
  final torrentPath = 'path/to/your/torrent.torrent';
  final torrentFile = File(torrentPath);

  if (!await torrentFile.exists()) {
    print('Torrent file not found: $torrentPath');
    print('Please update the path to a valid torrent file.\n');
    return;
  }

  try {
    final torrent = await TorrentModel.parse(torrentPath);
    final version = TorrentVersionHelper.detectVersion(torrent);

    print('Torrent Information:');
    print('  Name: ${torrent.name}');
    print('  Version: $version');
    print('  Info Hash Length: ${torrent.infoHashBuffer.length} bytes');

    if (TorrentVersionHelper.isV2InfoHash(torrent.infoHashBuffer)) {
      print('  This is a v2 torrent (32-byte info hash)');
    } else if (TorrentVersionHelper.isV1InfoHash(torrent.infoHashBuffer)) {
      print('  This is a v1 torrent (20-byte info hash)');
    }

    // Example 2: Create a task with v2 support
    final savePath = Directory.systemTemp.path;
    print('\nCreating torrent task...');
    final task = TorrentTask.newTask(torrent, savePath);

    // The task will automatically detect the torrent version
    // and use the appropriate hash algorithm (SHA-1 for v1, SHA-256 for v2)

    print('Task created successfully!');
    print('  Torrent version detected: $version');
    print(
        '  Piece hash algorithm: ${TorrentVersionHelper.getHashAlgorithm(version)}');

    // Example 3: Start downloading
    print('\nStarting download...');

    // Create event listener
    final listener = task.createListener();
    listener
      ..on<TaskStarted>((event) {
        print('Download started!');
      })
      ..on<StateFileUpdated>((event) {
        print('Progress: ${(task.progress * 100).toStringAsFixed(2)}%');
        print(
            'Downloaded: ${(task.downloaded! / 1024 / 1024).toStringAsFixed(2)} MB');
      })
      ..on<TaskCompleted>((event) {
        print('\nDownload completed!');
        print(
            'All pieces validated using ${TorrentVersionHelper.getHashAlgorithm(version)}');
      });

    await task.start();

    // Wait a bit to see progress
    await Future.delayed(const Duration(seconds: 5));

    // Stop the task
    print('\nStopping task...');
    await task.stop();
    await task.dispose();

    print('\nExample completed!');
  } catch (e) {
    print('Error: $e');
  }
}
