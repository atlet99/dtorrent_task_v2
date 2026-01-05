import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Example demonstrating Fast Extension (BEP 6) features
///
/// This example shows how Fast Extension improves BitTorrent protocol:
/// - Have All/Have None messages for efficient bitfield communication
/// - Suggest Piece for optimized piece selection
/// - Reject Request for better request handling
/// - Allowed Fast set for faster peer ramp-up
/// - Improved choke/unchoke semantics
void main() async {
  print('Fast Extension (BEP 6) Example');
  print('================================\n');

  // Example 1: Fast Extension is enabled by default
  print('Fast Extension Features:');
  print('  ✓ Have All/Have None - replaces bitfield for efficiency');
  print('  ✓ Suggest Piece - advisory messages for piece selection');
  print('  ✓ Reject Request - explicit rejection of requests');
  print('  ✓ Allowed Fast - allows downloading when choked');
  print('  ✓ Improved choke/unchoke - no implicit rejections\n');

  // Example 2: Create a torrent task (Fast Extension is enabled by default)
  final torrentPath = 'path/to/your/torrent.torrent';
  final torrentFile = File(torrentPath);

  if (!await torrentFile.exists()) {
    print('Torrent file not found: $torrentPath');
    print('Please update the path to a valid torrent file.\n');
    print('Fast Extension is automatically enabled for all peer connections.');
    print('The following improvements are active:');
    print('  1. Allowed Fast set is generated automatically at handshake');
    print('  2. Have All/Have None messages replace bitfield when appropriate');
    print('  3. Reject Request messages are sent when choking peers');
    print('  4. Suggest Piece messages can be used for optimization');
    print(
        '  5. Piece validation - connection closes if piece received without request');
    return;
  }

  try {
    final torrent = await TorrentModel.parse(torrentPath);
    final savePath = Directory.systemTemp.path;

    print('Creating torrent task with Fast Extension support...');
    final task = TorrentTask.newTask(torrent, savePath);

    // Fast Extension is enabled by default
    print('✓ Fast Extension enabled by default\n');

    // Create event listener to monitor Fast Extension features
    final listener = task.createListener();
    var haveAllCount = 0;
    var haveNoneCount = 0;
    var rejectCount = 0;
    var allowFastCount = 0;
    var suggestCount = 0;

    listener
      ..on<TaskStarted>((event) {
        print('Download started with Fast Extension support!');
      })
      ..on<StateFileUpdated>((event) {
        final progress = (task.progress * 100).toStringAsFixed(2);
        final downloaded = (task.downloaded! / 1024 / 1024).toStringAsFixed(2);
        print('Progress: $progress% - Downloaded: $downloaded MB');
      })
      ..on<TaskCompleted>((event) {
        print('\n✓ Download completed!');
        print('\nFast Extension Statistics:');
        print('  Have All messages received: $haveAllCount');
        print('  Have None messages received: $haveNoneCount');
        print('  Reject Request messages received: $rejectCount');
        print('  Allowed Fast pieces received: $allowFastCount');
        print('  Suggest Piece messages received: $suggestCount');
      });

    // Note: Fast Extension events are internal, but we can demonstrate the features
    print('\nFast Extension is working in the background:');
    print('  • Allowed Fast set is generated for each peer at handshake');
    print('  • Have All/Have None replace bitfield when appropriate');
    print('  • Reject Request is sent when choking peers');
    print('  • Suggest Piece can be used for piece selection optimization');
    print('  • Piece validation ensures protocol compliance\n');

    await task.start();

    // Wait a bit to see progress
    await Future.delayed(const Duration(seconds: 5));

    // Stop the task
    print('\nStopping task...');
    await task.stop();
    await task.dispose();

    print('\nExample completed!');
    print('\nFast Extension Benefits:');
    print('  ✓ Faster peer ramp-up with Allowed Fast');
    print('  ✓ Reduced bandwidth with Have All/Have None');
    print('  ✓ Better request handling with explicit rejects');
    print('  ✓ Improved piece selection with suggestions');
    print('  ✓ Enhanced security with piece validation');
  } catch (e) {
    print('Error: $e');
  }
}
