import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Helper functions for tests

/// Creates a test torrent file for testing
/// Returns the created Torrent model
Future<TorrentModel> createTestTorrent({
  int fileSize = 1024 * 100, // 100KB default
  int pieceLength = 16384, // 16KB default
  List<Uri>? trackers,
}) async {
  // Create unique temp directory to avoid path collisions in parallel tests.
  final tempDir = await Directory.systemTemp.createTemp('dtorrent_test_file_');
  final tempFile = File(path.join(tempDir.path, 'test_input.dat'));

  // Write data and ensure file is flushed to disk
  await tempFile.writeAsBytes(List<int>.generate(fileSize, (i) => i % 256));

  // Verify file exists and is readable
  if (!await tempFile.exists()) {
    throw StateError('Test file was not created');
  }

  // Create torrent
  final options = TorrentCreationOptions(
    pieceLength: pieceLength,
    trackers: trackers ?? [],
    comment: 'Test torrent for unit tests',
    createdBy: 'dtorrent_task_v2_test',
  );

  // Create torrent while file still exists
  final torrent = await TorrentCreator.createTorrent(tempFile.path, options);

  // Clean up temporary directory after torrent is created
  try {
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  } catch (e) {
    // Ignore cleanup errors in tests.
  }

  return torrent;
}

/// Creates a test torrent file in a directory (multi-file torrent)
Future<TorrentModel> createTestMultiFileTorrent({
  int filesCount = 3,
  int fileSize = 1024 * 50, // 50KB per file default
  int pieceLength = 16384,
  List<Uri>? trackers,
}) async {
  // Create a unique temporary directory for parallel-safe test execution.
  final tempDir = await Directory.systemTemp.createTemp('dtorrent_test_dir_');

  // Create multiple files
  for (var i = 0; i < filesCount; i++) {
    final file = File(path.join(tempDir.path, 'file_$i.txt'));
    await file
        .writeAsBytes(List<int>.generate(fileSize, (j) => (i * 100 + j) % 256));
  }

  // Create torrent
  final options = TorrentCreationOptions(
    pieceLength: pieceLength,
    trackers: trackers ?? [],
    comment: 'Test multi-file torrent for unit tests',
    createdBy: 'dtorrent_task_v2_test',
  );

  final torrent = await TorrentCreator.createTorrent(tempDir.path, options);

  // Clean up temp directory
  if (await tempDir.exists()) {
    await tempDir.delete(recursive: true);
  }

  return torrent;
}

/// Gets a temporary directory for test downloads
Future<Directory> getTestDownloadDirectory() async {
  final dir = Directory(
      '${Directory.systemTemp.path}/dtorrent_test_${DateTime.now().millisecondsSinceEpoch}');
  await dir.create(recursive: true);
  return dir;
}

/// Cleans up a test directory
Future<void> cleanupTestDirectory(Directory dir) async {
  if (await dir.exists()) {
    try {
      await dir.delete(recursive: true);
    } catch (e) {
      // If deletion fails, try again after a short delay
      // This can happen if files are still being written
      await Future.delayed(const Duration(milliseconds: 100));
      try {
        await dir.delete(recursive: true);
      } catch (e2) {
        // Ignore if still fails - test cleanup is best effort
      }
    }
  }
}
