import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

Future<void> main(List<String> args) async {
  final torrentPath = args.isNotEmpty ? args.first : 'example.torrent';
  final torrentFile = File(torrentPath);
  if (!torrentFile.existsSync()) {
    print('Usage: dart run example/scheduling_example.dart <path-to-torrent>');
    print('Torrent file not found: $torrentPath');
    return;
  }

  final torrent = await TorrentModel.parse(torrentPath);
  final task = TorrentTask.newTask(torrent, './downloads');

  task.addScheduleWindow(
    const ScheduleWindow(
      id: 'work-hours',
      weekdays: {1, 2, 3, 4, 5},
      start: Duration(hours: 9),
      end: Duration(hours: 18),
      maxDownloadRate: 2 * 1024 * 1024,
      maxUploadRate: 512 * 1024,
      pauseOutsideWindow: true,
    ),
  );
  task.startScheduling(tick: const Duration(minutes: 1));
  print('Scheduling enabled: work-hours window with bandwidth limits.');

  await task.start();
  await task.stop();
}
