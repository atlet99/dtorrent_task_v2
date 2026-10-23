import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
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
        expect(manager.maxUploadSlots, 6);

        manager.maxConnections = 1;
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

        expect(manager.peersNumber, 2);
      } finally {
        await manager.dispose();
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

        await task.stop();
      } finally {
        await task.dispose();
        await cleanupTestDirectory(dir);
      }
    });
  });
}
