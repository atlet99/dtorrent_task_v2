import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';

void main() {
  test('Simple peer handshake test', () async {
    final infoHash = Uint8List.fromList(List.generate(20, (i) => i));
    final piecesNum = 100;

    final completer = Completer<void>();
    var serverHandshakeReceived = false;
    var clientHandshakeReceived = false;

    // Start server
    final serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    final serverPort = serverSocket.port;

    serverSocket.listen((socket) async {
      final serverPeer = Peer.newTCPPeer(
        CompactAddress(socket.address, socket.port),
        infoHash,
        piecesNum,
        socket,
        PeerSource.incoming,
      );

      final serverListener = serverPeer.createListener();

      serverListener.on<PeerConnected>((event) {
        event.peer.sendHandShake(_normalizePeerId('SERVER'));
      });

      serverListener.on<PeerHandshakeEvent>((event) {
        serverHandshakeReceived = true;
        event.peer.sendHaveAll();
      });

      await serverPeer.connect();
    });

    final clientSocket = await Socket.connect('127.0.0.1', serverPort);

    final clientPeer = Peer.newTCPPeer(
      CompactAddress(InternetAddress('127.0.0.1'), serverPort),
      infoHash,
      piecesNum,
      clientSocket,
      PeerSource.manual,
    );

    final clientListener = clientPeer.createListener();

    clientListener.on<PeerConnected>((event) {
      event.peer.sendHandShake(_normalizePeerId('CLIENT'));
    });

    clientListener.on<PeerHandshakeEvent>((event) {
      clientHandshakeReceived = true;
    });

    clientListener.on<PeerHaveAll>((event) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    await clientPeer.connect();

    await completer.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        throw TimeoutException('Did not receive HaveAll');
      },
    );

    expect(serverHandshakeReceived, isTrue);
    expect(clientHandshakeReceived, isTrue);
    await clientPeer.dispose();
    await serverSocket.close();
  });
}

String _normalizePeerId(String seed) {
  return seed.padRight(20, '0').substring(0, 20);
}
