import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Demonstrates real progress reporting for multi-file torrents.
///
/// `progress` uses totalSize, which falls back to the sum of file
/// sizes, instead of length, which only exists for single-file
/// torrents.
Future<void> main() async {
  final workDir = await Directory.systemTemp.createTemp('progress_demo_');

  // Build a multi-file torrent with three files.
  for (var i = 0; i < 3; i++) {
    final file = File(path.join(workDir.path, 'part_$i.bin'));
    await file
        .writeAsBytes(List<int>.generate(1024 * 32, (j) => (i + j) % 256));
  }
  final torrent = await TorrentCreator.createTorrent(
      workDir.path, TorrentCreationOptions(pieceLength: 16384, trackers: []));

  print('Files: ${torrent.files.length}');
  print('length: ${torrent.length} (null for multi-file torrents)');
  print('totalSize: ${torrent.totalSize}');

  // Persist partial state so the task resumes with real progress.
  final saveDir = await Directory.systemTemp.createTemp('progress_save_');
  final stateFile = await StateFileV2.getStateFile(saveDir.path, torrent);
  for (var i = 0; i < 5 && i < stateFile.bitfield.piecesNum; i++) {
    await stateFile.updateBitfield(i);
  }
  await stateFile.close();

  final task = TorrentTask.newTask(torrent, saveDir.path);
  try {
    await task.start();
    print('Downloaded: ${task.downloaded} bytes');
    print('Progress: ${(task.progress * 100).toStringAsFixed(2)}%');
    await task.stop();
  } finally {
    await task.dispose();
  }

  await workDir.delete(recursive: true);
  await saveDir.delete(recursive: true);
}
