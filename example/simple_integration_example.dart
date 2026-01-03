import 'dart:io';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Simple integration example demonstrating all features
///
/// This example automatically:
/// 1. Creates a test torrent (if needed)
/// 2. Starts download task
/// 3. Demonstrates automatic port forwarding (UPnP/NAT-PMP)
/// 4. Demonstrates tracker scrape (BEP 48)
/// 5. Shows download statistics
///
/// Dependencies:
/// - Port forwarding works only if router supports UPnP or NAT-PMP
/// - Scrape works only if tracker supports BEP 48
/// - Download works only if there are available peers
void main() async {
  print('=' * 70);
  print('Simple Integration Example');
  print('=' * 70);
  print('');

  // ========================================================================
  // STEP 1: Create test torrent
  // ========================================================================
  // Depends on: availability of temporary directory for creating files
  print('Step 1: Creating test torrent...');
  final tempDir = Directory.systemTemp;
  final testFile = File(
      '${tempDir.path}/test_file_${DateTime.now().millisecondsSinceEpoch}.dat');

  // Create test file (100KB)
  await testFile.writeAsBytes(List.generate(100 * 1024, (i) => i % 256));
  print('  ✓ Test file created: ${testFile.path}');
  print(
      '  File size: ${(await testFile.length() / 1024).toStringAsFixed(2)} KB');
  print('');

  // Create torrent with trackers
  // Depends on: TorrentCreator, tracker availability (using public trackers for example)
  final torrentOptions = TorrentCreationOptions(
    pieceLength: 16 * 1024, // 16KB pieces
    trackers: [
      // Public trackers for testing
      // Depends on: availability of these trackers on the network
      Uri.parse('udp://tracker.openbittorrent.com:6969/announce'),
      Uri.parse('udp://tracker.leechers-paradise.org:6969/announce'),
    ],
    comment: 'Test torrent for integration example',
    createdBy: 'dtorrent_task_v2',
  );

  final torrent =
      await TorrentCreator.createTorrent(testFile.path, torrentOptions);
  print('  ✓ Torrent created');
  print('  Info hash: ${torrent.infoHash}');
  print('  Trackers: ${torrent.announces.length}');
  for (var i = 0; i < torrent.announces.length; i++) {
    print('    ${i + 1}. ${torrent.announces.elementAt(i)}');
  }
  print('');

  // Save torrent to file
  final torrentFile = File(
      '${tempDir.path}/test_${DateTime.now().millisecondsSinceEpoch}.torrent');
  final torrentMap = <String, dynamic>{
    'info': {
      'name': torrent.name,
      'piece length': torrent.pieceLength,
      'pieces': torrent.pieces,
      if (torrent.files.length == 1)
        'length': torrent.length
      else
        'files': torrent.files
            .map((f) => {
                  'length': f.length,
                  'path': f.path,
                })
            .toList(),
    },
    'announce': torrent.announces.isNotEmpty
        ? torrent.announces.first.toString()
        : null,
    'announce-list': torrent.announces.map((a) => [a.toString()]).toList(),
    'creation date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'created by': 'dtorrent_task_v2',
    'comment': 'Test torrent',
  };

  // Use b_encode_decode to save
  final encoded = encode(torrentMap);
  await torrentFile.writeAsBytes(encoded);
  print('  ✓ Torrent file saved: ${torrentFile.path}');
  print('');

  // Delete original test file (no longer needed)
  await testFile.delete();
  print('  ✓ Test file cleaned up');
  print('');

  // ========================================================================
  // STEP 2: Create download task
  // ========================================================================
  // Depends on: TorrentTask, available disk space for saving
  print('Step 2: Creating download task...');
  final savePath =
      '${tempDir.path}/download_${DateTime.now().millisecondsSinceEpoch}';
  await Directory(savePath).create(recursive: true);

  final task = TorrentTask.newTask(torrent, savePath);
  print('  ✓ Task created');
  print('  Save path: $savePath');
  print('');

  // ========================================================================
  // STEP 3: Tracker Scrape (BEP 48)
  // ========================================================================
  // Depends on:
  // - Tracker must support BEP 48 (scrape endpoint)
  // - Tracker must be accessible on the network
  // - Tracker must know about our torrent (may not know if just created)
  print('Step 3: Testing Tracker Scrape (BEP 48)...');
  print('  (This depends on tracker supporting BEP 48 and being accessible)');

  try {
    // Try scrape from first tracker
    if (torrent.announces.isNotEmpty) {
      final firstTracker = torrent.announces.first;
      print('  Trying scrape from: $firstTracker');

      final scrapeResult = await task.scrapeTracker(firstTracker);

      if (scrapeResult.isSuccess) {
        print('  ✓ Scrape successful!');
        final infoHashHex = torrent.infoHash.toLowerCase();
        final stats = scrapeResult.getStatsForInfoHash(infoHashHex);

        if (stats != null) {
          print('  Statistics:');
          print('    Seeders: ${stats.complete}');
          print('    Leechers: ${stats.incomplete}');
          print('    Downloads: ${stats.downloaded}');
        } else {
          print('  ⚠ Statistics not found (torrent may be new)');
        }
      } else {
        print('  ⚠ Scrape failed: ${scrapeResult.error}');
        print('    (This is normal if tracker does not support scrape)');
      }
    } else {
      print('  ⚠ No trackers available for scraping');
    }
  } catch (e) {
    print('  ⚠ Scrape error: $e');
    print('    (This is normal if tracker is unreachable)');
  }
  print('');

  // ========================================================================
  // STEP 4: Start task (automatic port forwarding)
  // ========================================================================
  // Depends on:
  // - Port forwarding: router must support UPnP or NAT-PMP
  // - Port forwarding: router must be accessible on local network
  // - Port forwarding: UPnP/NAT-PMP must be enabled on router
  // - Tracker announce: tracker must be accessible
  // - Peers: must have available peers for download
  print('Step 4: Starting download task...');
  print('  (Port forwarding will be attempted automatically)');
  print('  (This depends on router supporting UPnP/NAT-PMP)');

  final startResult = await task.start();
  print('  ✓ Task started');
  print('  Listening port: ${startResult['tcp_socket']}');
  print('  Total pieces: ${startResult['total_pieces_num']}');
  print('  Downloaded: ${startResult['downloaded']} bytes');
  print('');
  print(
      '  Note: Port forwarding attempt happens in background (non-blocking).');
  print('        Check router logs or port forwarding settings to verify.');
  print(
      '        If router supports UPnP/NAT-PMP, port should be forwarded automatically.');
  print('');
  print('  Note: Port forwarding attempt happens in background.');
  print('        Check router logs or port forwarding settings to verify.');
  print(
      '        If router supports UPnP/NAT-PMP, port should be forwarded automatically.');
  print('');

  // ========================================================================
  // STEP 5: Monitor progress
  // ========================================================================
  // Depends on: availability of active peers and data
  print('Step 5: Monitoring download progress...');
  print('  (Progress depends on available peers and data)');
  print('  (Press Ctrl+C to stop)');
  print('');

  // Subscribe to progress events
  // Depends on: StateFileUpdated events being emitted by task
  final listener = task.createListener();
  listener.on<StateFileUpdated>((event) {
    final progress = (task.progress * 100).toStringAsFixed(2);
    final downloaded = (task.downloaded! / 1024 / 1024).toStringAsFixed(2);
    final total = (task.metaInfo.length / 1024 / 1024).toStringAsFixed(2);
    final downloadSpeed = (task.currentDownloadSpeed / 1024).toStringAsFixed(2);
    final uploadSpeed = (task.uploadSpeed / 1024).toStringAsFixed(2);

    print(
        '\r  Progress: $progress% | Downloaded: ${downloaded}MB / ${total}MB | '
        'Speed: ${downloadSpeed}KB/s ↓ ${uploadSpeed}KB/s ↑ | '
        'Peers: ${task.allPeersNumber}');
  });

  // Wait a bit for demonstration
  // Note: For a newly created torrent, there may be no peers available
  // This is normal - the torrent was just created and trackers don't know about it yet
  print('  Waiting 10 seconds to show progress...');
  print(
      '  (Note: For newly created torrents, peers may not be available immediately)');
  await Future.delayed(const Duration(seconds: 10));

  // Show final statistics
  print('');
  print('  Final statistics:');
  print('    Progress: ${(task.progress * 100).toStringAsFixed(2)}%');
  print('    Downloaded: ${(task.downloaded! / 1024).toStringAsFixed(2)} KB');
  final uploaded = task.stateFile?.uploaded ?? 0;
  print('    Uploaded: ${(uploaded / 1024).toStringAsFixed(2)} KB');
  print(
      '    Average download speed: ${(task.averageDownloadSpeed / 1024).toStringAsFixed(2)} KB/s');
  print(
      '    Average upload speed: ${(task.averageUploadSpeed / 1024).toStringAsFixed(2)} KB/s');
  print('    Total peers: ${task.allPeersNumber}');
  print('    Active peers: ${task.activePeers?.length ?? 0}');
  print('    Seeders: ${task.seederNumber}');
  print('');

  // ========================================================================
  // STEP 6: Stop and cleanup
  // ========================================================================
  // Port forwarding will be automatically removed when task stops
  // Depends on: correct work of dispose() method
  print('Step 6: Stopping task and cleaning up...');
  print('  (Port forwarding will be automatically removed)');

  listener.dispose();
  await task.stop();
  await task.dispose();
  print('  ✓ Task stopped');
  print('  ✓ Port forwarding removed (if was active)');
  print('');

  // Cleanup temporary files
  try {
    if (await torrentFile.exists()) {
      await torrentFile.delete();
    }
    if (await Directory(savePath).exists()) {
      await Directory(savePath).delete(recursive: true);
    }
    print('  ✓ Temporary files cleaned up');
  } catch (e) {
    print('  ⚠ Cleanup warning: $e');
  }
  print('');

  print('=' * 70);
  print('Example completed successfully!');
  print('=' * 70);
  print('');
  print('Summary:');
  print('  ✓ Torrent created and saved');
  print('  ✓ Tracker scrape tested (may fail if tracker does not support it)');
  print('  ✓ Download task started');
  print(
      '  ✓ Port forwarding attempted (may fail if router does not support it)');
  print('  ✓ Progress monitored');
  print('  ✓ Task stopped and cleaned up');
  print('');
  print('Note: Some features may not work depending on:');
  print('  - Router UPnP/NAT-PMP support (for port forwarding)');
  print('  - Tracker BEP 48 support (for scrape)');
  print('  - Network connectivity and available peers');
  print('');
}
