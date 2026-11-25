import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker/tracker/tracker.dart';

/// Demonstrates safe tracker options during and after socket shutdown.
///
/// Run with `dart run example/task_socket_shutdown_example.dart`.
Future<void> main() async {
  final workDir = await Directory.systemTemp.createTemp('torrent_shutdown_');
  TorrentTask? task;
  try {
    final source = File('${workDir.path}/source.txt');
    await source.writeAsString('Torrent shutdown example');
    final torrent = await TorrentCreator.createTorrent(
      source.path,
      TorrentCreationOptions(pieceLength: 16384, trackers: []),
    );
    task = TorrentTask.newTask(torrent, '${workDir.path}/download');
    final options = task as AnnounceOptionsProvider;
    final uri = Uri.parse('http://localhost/announce');

    final started = await task.start();
    print('Listening on port: ${started['tcp_socket']}');
    print(
        'Tracker port: ${(await options.getOptions(uri, torrent.infoHash))['port']}');

    final stopping = task.stop();
    await options.getOptions(uri, torrent.infoHash);
    await stopping;
    final port = (await options.getOptions(uri, torrent.infoHash))['port'];
    if (port != null) throw StateError('Port should be cleared after stop');
    print('Stopped; late tracker request sees port: $port');
  } finally {
    await task?.dispose();
    await workDir.delete(recursive: true);
  }
}
