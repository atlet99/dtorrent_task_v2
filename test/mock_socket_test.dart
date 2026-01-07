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
      final serverSocket = await MockServerSocket.bind(InternetAddress.loopbackIPv4, 12345);

      // Create mock client socket  
      final clientSocket = MockSocket.create(
        InternetAddress.loopbackIPv4,
        50000,
        InternetAddress.loopbackIPv4,
        12345,
      );

      // Setup server peer
      serverSocket.listen((socket) async {
        print('[TEST SERVER] Accepted connection');
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );

        // CRITICAL: Create listener BEFORE connect()
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          print('[TEST SERVER] PeerConnected event fired!');
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
          print('[TEST SERVER] sendHandShake called');
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          print('[TEST SERVER] PeerHandshakeEvent fired!');
          event.peer.sendHaveAll();
          print('[TEST SERVER] sendHaveAll called');
        });

        print('[TEST SERVER] Calling peer.connect()');
        await peer.connect();
        print('[TEST SERVER] peer.connect() completed');
      });

      // Setup client peer BEFORE accepting connection
      print('[TEST CLIENT] Creating client peer');
      final clientPeer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, 12345),
        infoHash,
        piecesNum,
        clientSocket,
        PeerSource.manual,
      );
      
      // CRITICAL: Create listener BEFORE connect()
      final clientListener = clientPeer.createListener();

      clientListener.on<PeerConnected>((event) {
        print('[TEST CLIENT] PeerConnected event fired!');
        event.peer.sendHandShake('TEST_PEER_ID_123456789012');
        print('[TEST CLIENT] sendHandShake called');
      });

      clientListener.on<PeerHaveAll>((event) {
        print('[TEST CLIENT] ✅ PeerHaveAll event fired!');
        completer.complete();
      });

      // NOW accept connection (this creates server peer and calls connect())
      print('[TEST] Accepting connection');
      serverSocket.acceptConnection(clientSocket);

      // Connect client
      print('[TEST CLIENT] Calling peer.connect()');
      await clientPeer.connect();
      print('[TEST CLIENT] peer.connect() completed');

      await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          throw TimeoutException('Did not receive HaveAll - mock socket issue');
        },
      );

      print('[TEST] ✅ Mock socket test PASSED!');
      
      await clientPeer.dispose();
      await serverSocket.close();
    });
  });
}
