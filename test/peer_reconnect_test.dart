import 'dart:async';
import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:test/test.dart';

import 'mocks/mock_socket.dart';
import 'test_helpers.dart';

class _RetryTimer implements Timer {
  _RetryTimer(this.callback);

  final void Function() callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    callback();
  }

  @override
  void cancel() => _active = false;

  @override
  bool get isActive => _active;

  @override
  int get tick => _active ? 0 : 1;
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('peer event');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('successful handshake resets retries and shutdown cancels the timer',
      () async {
    final torrent = await createTestTorrent();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final address = CompactAddress(socket.address, socket.port);
    await socket.close();
    final timers = <_RetryTimer>[];
    final delays = <Duration>[];

    await runZoned(() async {
      final manager = PeersManager('test-peer-id', torrent);
      manager.ignoreIps.remove(InternetAddress.loopbackIPv4);
      final incoming = MockSocket.create(
          InternetAddress.loopbackIPv4, 50000, address.address, address.port);
      try {
        manager.addNewPeerAddress(address, PeerSource.tracker);
        await _waitFor(() => timers.isNotEmpty);
        manager.addNewPeerAddress(address, PeerSource.incoming,
            socket: incoming);
        await _waitFor(() => manager.activePeers.isNotEmpty);
        final peer = manager.activePeers.single;
        peer.events.emit(PeerHandshakeEvent(peer, 'remote-peer', []));
        await Future<void>.delayed(Duration.zero);
        await peer.dispose('connection lost');
        await _waitFor(() => timers.length == 2);
        expect(
            delays, [const Duration(seconds: 1), const Duration(seconds: 1)]);
        expect(timers.first.isActive, isFalse);
        await manager.dispose();
        expect(timers.last.isActive, isFalse);
      } finally {
        await manager.dispose();
        incoming.destroy();
      }
    }, zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if (duration == const Duration(seconds: 1)) {
          delays.add(duration);
          final timer = _RetryTimer(zone.bindCallback(callback));
          timers.add(timer);
          return timer;
        }
        return parent.createTimer(zone, duration, callback);
      },
    ));
  });

  test('failed peers back off, stop after three retries and ignore rediscovery',
      () async {
    final torrent = await createTestTorrent();
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final address = CompactAddress(socket.address, socket.port);
    await socket.close();
    final delays = <Duration>[];
    final timers = <_RetryTimer>[];
    final failures = <PeerDisposeEvent>[];
    late PeersManager manager;

    await runZoned(() async {
      manager = PeersManager('test-peer-id', torrent);
      manager.ignoreIps.remove(InternetAddress.loopbackIPv4);
      final listener = manager.createListener();
      listener.on<PeerDisposeEvent>(failures.add);
      try {
        manager.addNewPeerAddress(address, PeerSource.tracker);
        for (var i = 0; i < 3; i++) {
          await _waitFor(() => timers.length > i);
          expect(failures, hasLength(i + 1));
          manager.addNewPeerAddress(address, PeerSource.dht);
          expect(manager.peersNumber, 0);
          timers[i].fire();
        }
        await _waitFor(() => failures.length == 4);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(delays, [
          const Duration(seconds: 1),
          const Duration(seconds: 5),
          const Duration(seconds: 15),
        ]);
        manager.addNewPeerAddress(address, PeerSource.pex);
        expect(manager.peersNumber, 0);
        expect(timers, hasLength(3));

        final other = PeersManager('test-peer-id', torrent);
        other.ignoreIps.remove(InternetAddress.loopbackIPv4);
        other.addNewPeerAddress(address, PeerSource.tracker);
        await _waitFor(() => timers.length == 4);
        await other.dispose();
        expect(timers.last.isActive, isFalse);
        timers.last.fire();
        expect(other.peersNumber, 0);
      } finally {
        listener.dispose();
        await manager.dispose();
      }
    }, zoneSpecification: ZoneSpecification(
      createTimer: (self, parent, zone, duration, callback) {
        if ([1, 5, 15].contains(duration.inSeconds) &&
            duration.inMilliseconds == duration.inSeconds * 1000) {
          delays.add(duration);
          final timer = _RetryTimer(zone.bindCallback(callback));
          timers.add(timer);
          return timer;
        }
        return parent.createTimer(zone, duration, callback);
      },
    ));
  });
}
