import 'dart:io';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Helper functions for tests

/// Creates a test torrent file for testing
/// Returns the created Torrent model
Future<Torrent> createTestTorrent({
  int fileSize = 1024 * 100, // 100KB default
  int pieceLength = 16384, // 16KB default
  List<Uri>? trackers,
}) async {
  // Create a temporary file
  final tempFile = File(
      '${Directory.systemTemp.path}/test_file_${DateTime.now().millisecondsSinceEpoch}.dat');
  await tempFile.writeAsBytes(List<int>.generate(fileSize, (i) => i % 256));

  // Create torrent
  final options = TorrentCreationOptions(
    pieceLength: pieceLength,
    trackers: trackers ?? [],
    comment: 'Test torrent for unit tests',
    createdBy: 'dtorrent_task_v2_test',
  );

  final torrent = await TorrentCreator.createTorrent(tempFile.path, options);

  // Clean up temp file
  try {
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
  } catch (e) {
    // Ignore errors when deleting temp file (may already be deleted)
  }

  return torrent;
}

/// Creates a test torrent file in a directory (multi-file torrent)
Future<Torrent> createTestMultiFileTorrent({
  int filesCount = 3,
  int fileSize = 1024 * 50, // 50KB per file default
  int pieceLength = 16384,
  List<Uri>? trackers,
}) async {
  // Create a temporary directory
  final tempDir = Directory(
      '${Directory.systemTemp.path}/test_dir_${DateTime.now().millisecondsSinceEpoch}');
  await tempDir.create();

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
