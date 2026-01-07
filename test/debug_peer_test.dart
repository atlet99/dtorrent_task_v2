import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';

void main() {
  test('Simple peer handshake test', () async {
    final infoHash = Uint8List.fromList(List.generate(20, (i) => i));
    final piecesNum = 100;

    final completer = Completer<void>();
    bool serverHandshakeReceived = false;
    bool clientHandshakeReceived = false;

    // Start server
    final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final serverPort = serverSocket.port;

    serverSocket.listen((socket) async {
      print('[SERVER] Connection accepted');
      final serverPeer = Peer.newTCPPeer(
        CompactAddress(socket.address, socket.port),
        infoHash,
        piecesNum,
        socket,
        PeerSource.incoming,
      );

      final serverListener = serverPeer.createListener();

      serverListener.on<PeerConnected>((event) {
        print('[SERVER] PeerConnected event');
        event.peer.sendHandShake('SERVER_PEER_ID_00000000');
      });

      serverListener.on<PeerHandshakeEvent>((event) {
        print('[SERVER] PeerHandshakeEvent - received client handshake');
        print(
            '[SERVER] remoteEnableFastPeer: ${event.peer.remoteEnableFastPeer}');
        print(
            '[SERVER] localEnableFastPeer: ${event.peer.localEnableFastPeer}');
        serverHandshakeReceived = true;

        // Try to send HaveAll
        print('[SERVER] Attempting to send HaveAll...');
        event.peer.sendHaveAll();
        print('[SERVER] sendHaveAll() called');
      });

      await serverPeer.connect();
      print('[SERVER] Peer connected');
    });

    // Connect client
    print('[CLIENT] Connecting to server...');
    final clientSocket = await Socket.connect('127.0.0.1', serverPort);
    print('[CLIENT] Socket connected');

    final clientPeer = Peer.newTCPPeer(
      CompactAddress(InternetAddress('127.0.0.1'), serverPort),
      infoHash,
      piecesNum,
      clientSocket,
      PeerSource.manual,
    );

    final clientListener = clientPeer.createListener();

    clientListener.on<PeerConnected>((event) {
      print('[CLIENT] PeerConnected event');
      // Send handshake immediately when connected
      print('[CLIENT] Sending handshake...');
      event.peer.sendHandShake('CLIENT_PEER_ID_00000000');
    });

    clientListener.on<PeerHandshakeEvent>((event) {
      print('[CLIENT] PeerHandshakeEvent - received server handshake');
      print(
          '[CLIENT] remoteEnableFastPeer: ${event.peer.remoteEnableFastPeer}');
      print('[CLIENT] localEnableFastPeer: ${event.peer.localEnableFastPeer}');
      clientHandshakeReceived = true;
    });

    clientListener.on<PeerHaveAll>((event) {
      print('[CLIENT] PeerHaveAll event received!');
      print('[CLIENT] remoteBitfield: ${event.peer.remoteBitfield}');
      completer.complete();
    });

    await clientPeer.connect();
    print('[CLIENT] Peer connected');

    // Wait for HaveAll
    print('[TEST] Waiting for HaveAll event...');
    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        print('[TEST] TIMEOUT! Events received:');
        print('  - Server handshake received: $serverHandshakeReceived');
        print('  - Client handshake received: $clientHandshakeReceived');
        throw TimeoutException('Did not receive HaveAll');
      },
    );

    print('[TEST] TEST PASSED!');
    await clientPeer.dispose();
    await serverSocket.close();
  });
}
