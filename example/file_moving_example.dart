import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

Future<void> main(List<String> args) async {
  final torrentPath = args.isNotEmpty ? args.first : 'example.torrent';
  final torrentFile = File(torrentPath);
  if (!torrentFile.existsSync()) {
    print('Usage: dart run example/file_moving_example.dart <path-to-torrent>');
    print('Torrent file not found: $torrentPath');
    return;
  }

  final torrent = await TorrentModel.parse(torrentPath);
  final task = TorrentTask.newTask(torrent, './downloads');

  await task.start();

  if (torrent.files.isEmpty) {
    print('Torrent has no files');
    await task.stop();
    return;
  }

  // Move one file while task is active.
  final file = torrent.files.first;
  final newPath = './downloads_moved/${file.path}';
  await task.moveDownloadedFile(
    file.path,
    newPath,
  );
  print('Move requested: ${file.path} -> $newPath');

  // Re-scan for externally moved files.
  final moved = await task.detectMovedFiles();
  print('Detected moved files: $moved');

  await task.stop();
}
