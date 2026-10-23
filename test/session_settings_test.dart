import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/settings/rate_limiter.dart';
import 'package:test/test.dart';

import 'mocks/mock_socket.dart';
import 'test_helpers.dart';

bool _isPortConflict(Object e) {
  if (e is SocketException) {
    return e.message.contains('Address already in use') ||
        e.osError?.errorCode == 48;
  }
  final str = e.toString();
  return str.contains('Address already in use') ||
      str.contains('errno = 48') ||
      str.contains('port = 6771') ||
      str.contains('Failed to create datagram socket');
}

void main() {
  group('SessionSettings', () {
    test('defaults match libretorrent', () {
      const settings = SessionSettings();

      expect(settings.maxConnections, 200);
      expect(settings.maxConnectionsPerTorrent, 50);
      expect(settings.maxIncomingConnectionsPerTorrent, 10);
      expect(settings.maxUploadsPerTorrent, 4);
      expect(settings.downloadRateLimit, 0);
      expect(settings.uploadRateLimit, 0);
      expect(settings.connectionBudget, isNull);
      expect(settings.effectiveMaxConnectionsPerTorrent, 50);
    });

    test('effective connection cap is the most restrictive', () {
      expect(
        const SessionSettings(maxConnections: 2)
            .effectiveMaxConnectionsPerTorrent,
        2,
      );
      expect(
        const SessionSettings(maxConnections: 0, maxConnectionsPerTorrent: 7)
            .effectiveMaxConnectionsPerTorrent,
        7,
      );
      expect(
        const SessionSettings(maxConnections: 3, maxConnectionsPerTorrent: 0)
            .effectiveMaxConnectionsPerTorrent,
        3,
      );
      expect(
        const SessionSettings(maxConnections: 0, maxConnectionsPerTorrent: 0)
            .effectiveMaxConnectionsPerTorrent,
        0,
      );
    });

    test('copyWith replaces only the given fields', () {
      const settings = SessionSettings(downloadRateLimit: 100);
      final updated = settings.copyWith(uploadRateLimit: 50);

      expect(updated.downloadRateLimit, 100);
      expect(updated.uploadRateLimit, 50);
      expect(updated.maxConnections, settings.maxConnections);
    });
  });

  group('RateLimiter', () {
    test('paces reservations and refills over time', () {
      var now = DateTime(2026);
      final limiter = RateLimiter(1000, clock: () => now);

      expect(limiter.reserve(600), Duration.zero);
      expect(limiter.reserve(600), const Duration(milliseconds: 200));

      now = now.add(const Duration(milliseconds: 200));
      expect(limiter.reserve(100), const Duration(milliseconds: 100));
    });
  });

  group('Connection limits', () {
    test('PeersManager caps known peers and upload slots', () async {
      final torrent = await createTestTorrent();
      final manager = PeersManager('test-peer-id', torrent,
          maxConnections: 2, maxUploadSlots: 6);
      final sockets = <MockSocket>[];

      try {
        for (var i = 1; i <= 3; i++) {
          final socket = MockSocket.create(
            InternetAddress.loopbackIPv4,
            50000 + i,
            InternetAddress('10.0.0.$i'),
            6000 + i,
          );
          sockets.add(socket);
          manager.addNewPeerAddress(
            CompactAddress(socket.remoteAddress, socket.remotePort),
            PeerSource.manual,
            type: PeerType.tcp,
            socket: socket,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(manager.peersNumber, 2);
        expect(manager.connectedPeersNumber, 2);
        expect(manager.maxUploadSlots, 6);

        manager.maxConnections = 1;
        await _waitFor(() => manager.connectedPeersNumber == 1);

        expect(manager.connectedPeersNumber, 1);
        expect(manager.peersNumber, 1);

        final extra = MockSocket.create(
          InternetAddress.loopbackIPv4,
          50004,
          InternetAddress('10.0.0.4'),
          6004,
        );
        sockets.add(extra);
        manager.addNewPeerAddress(
          CompactAddress(extra.remoteAddress, extra.remotePort),
          PeerSource.manual,
          type: PeerType.tcp,
          socket: extra,
        );

        expect(manager.peersNumber, 1);
      } finally {
        await manager.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
      }
    });

    test('shared budget caps peers across managers', () async {
      final torrent = await createTestTorrent();
      final budget = SessionConnectionBudget();
      final first = PeersManager('first', torrent, maxConnections: 50);
      final second = PeersManager('second', torrent, maxConnections: 50);
      first.setConnectionBudget(budget, sessionMaxConnections: 2);
      second.setConnectionBudget(budget, sessionMaxConnections: 2);
      final sockets = <MockSocket>[];

      try {
        sockets.add(_addPeer(first, 1));
        sockets.add(_addPeer(first, 2));
        sockets.add(_addPeer(second, 3));

        expect(first.peersNumber, 2);
        expect(second.peersNumber, 0);
        expect(budget.total, 2);

        await Future<void>.delayed(const Duration(milliseconds: 20));
        await first.dispose();
        expect(budget.total, 0);

        sockets.add(_addPeer(second, 4));
        expect(second.peersNumber, 1);
        expect(budget.total, 1);
      } finally {
        await second.dispose();
        for (final socket in sockets) {
          socket.destroy();
        }
      }
    });

    test('task applies session settings at start and at runtime', () async {
      final torrent = await createTestTorrent();
      final dir = await getTestDownloadDirectory();
      const settings = SessionSettings(
        maxConnections: 2,
        maxIncomingConnectionsPerTorrent: 3,
        maxUploadsPerTorrent: 6,
      );
      final task = TorrentTask.newTask(
        torrent,
        dir.path,
        false,
        null,
        null,
        null,
        null,
        false,
        null,
        null,
        settings,
      );
      final incomingSockets = <MockSocket>[];

      try {
        expect(task.sessionSettings.maxConnections, 2);

        try {
          await task.start();
        } catch (e) {
          if (_isPortConflict(e)) return;
          rethrow;
        }

        final peers = task.peersManager!;
        expect(peers.maxConnections, 2);
        expect(peers.maxUploadSlots, 6);

        for (var i = 1; i <= 2; i++) {
          final socket = MockSocket.create(
            InternetAddress.loopbackIPv4,
            6100 + i,
            InternetAddress('10.0.10.$i'),
            7100 + i,
          );
          incomingSockets.add(socket);
          task.addPeer(
            CompactAddress(socket.remoteAddress, socket.remotePort),
            PeerSource.incoming,
            type: PeerType.tcp,
            socket: socket,
          );
        }
        await _waitFor(() => task.connectedPeersNumber == 2);
        expect(task.connectedPeersNumber, 2);

        task.applySessionSettings(
          settings.copyWith(maxIncomingConnectionsPerTorrent: 1),
        );
        await _waitFor(() => task.connectedPeersNumber == 1);
        expect(task.connectedPeersNumber, 1);

        task.applySessionSettings(settings.copyWith(
          maxConnections: 1,
          maxUploadsPerTorrent: 2,
          downloadRateLimit: 1024,
          uploadRateLimit: 512,
        ));

        expect(peers.maxConnections, 1);
        expect(peers.maxUploadSlots, 2);
        expect(task.sessionSettings.downloadRateLimit, 1024);
        expect(task.sessionSettings.uploadRateLimit, 512);
        expect(peers.reserveDownloadBytes(1024), Duration.zero);
        expect(peers.reserveDownloadBytes(1024), greaterThan(Duration.zero));

        task.addScheduleWindow(ScheduleWindow(
          id: 'always',
          weekdays: {DateTime.now().weekday},
          start: Duration.zero,
          end: const Duration(days: 1),
          maxDownloadRate: 256,
        ));
        expect(task.scheduledMaxDownloadRate, 256);
        expect(peers.reserveDownloadBytes(256), Duration.zero);
        expect(peers.reserveDownloadBytes(1), greaterThan(Duration.zero));

        task.clearScheduleWindows();
        expect(task.scheduledMaxDownloadRate, isNull);
        expect(task.sessionSettings.downloadRateLimit, 1024);
        expect(peers.reserveDownloadBytes(1024), Duration.zero);

        task.applySessionSettings(
          settings.copyWith(maxConnections: 1, maxUploadsPerTorrent: 2),
        );
        expect(task.sessionSettings.downloadRateLimit, 0);
        expect(peers.reserveDownloadBytes(1024), Duration.zero);

        await task.stop();
      } finally {
        await task.dispose();
        for (final socket in incomingSockets) {
          socket.destroy();
        }
        await cleanupTestDirectory(dir);
      }
    });
  });
}

Future<void> _waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

MockSocket _addPeer(PeersManager manager, int index) {
  final socket = MockSocket.create(
    InternetAddress.loopbackIPv4,
    50000 + index,
    InternetAddress('10.0.0.$index'),
    6000 + index,
  );
  manager.addNewPeerAddress(
    CompactAddress(socket.remoteAddress, socket.remotePort),
    PeerSource.manual,
    type: PeerType.tcp,
    socket: socket,
  );
  return socket;
}
