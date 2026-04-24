import 'dart:async';
import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:test/test.dart';

void main() {
  group('Peer Message Validation Tests', () {
    late List<int> infoHash;

    setUp(() {
      infoHash = List<int>.generate(20, (i) => i);
    });

    test('disposes peer when incoming message length is negative', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverSideCompleter = Completer<Socket>();
      server.listen((socket) {
        if (!serverSideCompleter.isCompleted) {
          serverSideCompleter.complete(socket);
        }
      });
      final clientSocket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      final serverSocket = await serverSideCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, server.port),
        infoHash,
        64,
        clientSocket,
        PeerSource.manual,
      );

      final disposeCompleter = Completer<PeerDisposeEvent>();
      final listener = peer.createListener();
      listener.on<PeerDisposeEvent>((event) {
        if (!disposeCompleter.isCompleted) {
          disposeCompleter.complete(event);
        }
      });

      await peer.connect();

      // -1 in signed int32 (big-endian): invalid message length.
      serverSocket.add(const [0xFF, 0xFF, 0xFF, 0xFF]);

      final disposeEvent = await disposeCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(peer.isDisposed, isTrue);
      expect(
        disposeEvent.reason.toString(),
        contains('Invalid message length'),
      );

      await peer.dispose();
      await clientSocket.close();
      await serverSocket.close();
      await server.close();
    });

    test('disposes peer when incoming message length exceeds 2MB', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverSideCompleter = Completer<Socket>();
      server.listen((socket) {
        if (!serverSideCompleter.isCompleted) {
          serverSideCompleter.complete(socket);
        }
      });
      final clientSocket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      final serverSocket = await serverSideCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, server.port),
        infoHash,
        64,
        clientSocket,
        PeerSource.manual,
      );

      final disposeCompleter = Completer<PeerDisposeEvent>();
      final listener = peer.createListener();
      listener.on<PeerDisposeEvent>((event) {
        if (!disposeCompleter.isCompleted) {
          disposeCompleter.complete(event);
        }
      });

      await peer.connect();

      // 2MB + 1 byte -> invalid by maxMessageSize.
      serverSocket.add(const [0x00, 0x20, 0x00, 0x01]);

      final disposeEvent = await disposeCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(peer.isDisposed, isTrue);
      expect(
        disposeEvent.reason.toString(),
        contains('Invalid message length'),
      );

      await peer.dispose();
      await clientSocket.close();
      await serverSocket.close();
      await server.close();
    });

    test('accepts fragmented valid HAVE message without false dispose',
        () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final serverSideCompleter = Completer<Socket>();
      server.listen((socket) {
        if (!serverSideCompleter.isCompleted) {
          serverSideCompleter.complete(socket);
        }
      });
      final clientSocket =
          await Socket.connect(InternetAddress.loopbackIPv4, server.port);
      final serverSocket = await serverSideCompleter.future.timeout(
        const Duration(seconds: 2),
      );

      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, server.port),
        infoHash,
        64,
        clientSocket,
        PeerSource.manual,
      );

      final haveCompleter = Completer<PeerHaveEvent>();
      final disposeCompleter = Completer<PeerDisposeEvent>();
      final listener = peer.createListener();
      listener
        ..on<PeerHaveEvent>((event) {
          if (!haveCompleter.isCompleted) {
            haveCompleter.complete(event);
          }
        })
        ..on<PeerDisposeEvent>((event) {
          if (!disposeCompleter.isCompleted) {
            disposeCompleter.complete(event);
          }
        });

      await peer.connect();

      // HAVE message: <len=0005><id=4><piece-index=7>
      // Send in two chunks to verify cache buffering and non-false-positive disposal.
      serverSocket.add(const [0x00, 0x00, 0x00, 0x05, 0x04, 0x00]);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(peer.isDisposed, isFalse);
      serverSocket.add(const [0x00, 0x00, 0x07]);

      final haveEvent = await haveCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(haveEvent.indices, equals([7]));
      expect(peer.isDisposed, isFalse);

      // Ensure we did not accidentally dispose while assembling fragmented message.
      await expectLater(
        disposeCompleter.future.timeout(const Duration(milliseconds: 100)),
        throwsA(isA<TimeoutException>()),
      );

      await peer.dispose();
      await clientSocket.close();
      await serverSocket.close();
      await server.close();
    });
  });
}
