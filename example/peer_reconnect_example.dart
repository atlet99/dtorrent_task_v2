import 'dart:async';
import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';

/// Run with `dart run example/peer_reconnect_example.dart`.
/// The first retry follows the initial connection failure after one second.
Future<void> main() async {
  final dir = await Directory.systemTemp.createTemp('peer_reconnect_');
  PeersManager? manager;
  try {
    final source = File('${dir.path}/source.txt');
    await source.writeAsString('Peer reconnect example');
    final torrent = await TorrentCreator.createTorrent(
      source.path,
      TorrentCreationOptions(pieceLength: 16384, trackers: []),
    );
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final address = CompactAddress(server.address, server.port);
    await server.close();

    manager = PeersManager('example-peer-id', torrent);
    manager.ignoreIps.remove(InternetAddress.loopbackIPv4);
    final listener = manager.createListener();
    final finished = Completer<void>();
    final elapsed = Stopwatch()..start();
    var failures = 0;
    listener.on<PeerDisposeEvent>((event) {
      failures++;
      print('Connection failure $failures at ${elapsed.elapsedMilliseconds}ms');
      if (failures == 2) finished.complete();
    });
    manager.addNewPeerAddress(address, PeerSource.manual);
    await finished.future.timeout(const Duration(seconds: 10));
    listener.dispose();
  } finally {
    await manager?.dispose();
    await dir.delete(recursive: true);
  }
}
