import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

Future<void> main(List<String> args) async {
  final torrentPath = args.isNotEmpty ? args.first : 'example.torrent';
  final torrentFile = File(torrentPath);
  if (!torrentFile.existsSync()) {
    print('Usage: dart run example/auto_move_example.dart <path-to-torrent>');
    print('Torrent file not found: $torrentPath');
    return;
  }

  final torrent = await TorrentModel.parse(torrentPath);
  final task = TorrentTask.newTask(torrent, './downloads');

  task.configureAutoMove(
    const AutoMoveConfig(
      defaultDestinationDirectory: './downloads/completed',
      allowExternalDisks: true,
      rules: [
        AutoMoveRule(
          extensions: {'mp4', 'mkv', 'avi'},
          destinationDirectory: './downloads/video',
        ),
        AutoMoveRule(
          extensions: {'mp3', 'flac'},
          destinationDirectory: './downloads/audio',
        ),
      ],
    ),
  );
  print('Auto-move configured. Rules: video/audio by extension.');

  await task.start();
  await task.stop();
}
