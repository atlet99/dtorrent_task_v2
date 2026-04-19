import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';

import 'mocks/mock_socket.dart';

void main() {
  group('Mock Socket Tests', () {
    late Uint8List infoHash;
    late int piecesNum;

    setUp(() {
      infoHash = Uint8List.fromList(List.generate(20, (i) => i));
      piecesNum = 100;
    });

    test('Mock sockets deliver data synchronously', () async {
      final completer = Completer<void>();

      // Create mock server socket
      final serverSocket =
          await MockServerSocket.bind(InternetAddress.loopbackIPv4, 12345);

      // Create mock client socket
      final clientSocket = MockSocket.create(
        InternetAddress.loopbackIPv4,
        50000,
        InternetAddress.loopbackIPv4,
        12345,
      );

      // Setup server peer
      serverSocket.listen((socket) async {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );

        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          event.peer.sendHandShake(_normalizePeerId('SERVER'));
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          event.peer.sendHaveAll();
        });

        await peer.connect();
      });

      // Setup client peer BEFORE accepting connection
      final clientPeer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, 12345),
        infoHash,
        piecesNum,
        clientSocket,
        PeerSource.manual,
      );

      final clientListener = clientPeer.createListener();

      clientListener.on<PeerConnected>((event) {
        event.peer.sendHandShake(_normalizePeerId('CLIENT'));
      });

      clientListener.on<PeerHaveAll>((event) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      // NOW accept connection (this creates server peer and calls connect())
      serverSocket.acceptConnection(clientSocket);

      // Connect client
      await clientPeer.connect();

      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Did not receive HaveAll - mock socket issue');
        },
      );

      await clientPeer.dispose();
      await serverSocket.close();
    });
  });
}

String _normalizePeerId(String seed) {
  return seed.padRight(20, '0').substring(0, 20);
}
