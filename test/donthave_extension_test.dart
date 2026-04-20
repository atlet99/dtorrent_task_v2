import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:test/test.dart';

void main() {
  group('lt_donthave Extension (BEP 54)', () {
    ServerSocket? serverSocket;
    late int serverPort;
    late Uint8List infoHash;
    const piecesNum = 32;

    setUp(() async {
      infoHash = Uint8List.fromList(List.generate(20, (i) => i + 1));
      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;
    });

    tearDown(() async {
      await serverSocket?.close();
      serverSocket = null;
    });

    test('receives donthave and clears remote piece bit', () async {
      final donthaveCompleter = Completer<void>();
      bool haveReceived = false;
      bool donthaveReceived = false;

      serverSocket!.listen((socket) async {
        final serverPeer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final listener = serverPeer.createListener();

        listener.on<PeerConnected>((event) {
          event.peer.registerExtend(EXTENSION_LT_DONTHAVE);
          event.peer.sendHandShake(_peerId('SERVER'));
        });

        listener.on<ExtendedEvent>((event) {
          if (event.eventName == 'handshake') {
            serverPeer.sendHave(7);
            Future<void>.delayed(const Duration(milliseconds: 80), () {
              serverPeer.sendDontHave(7);
            });
          }
        });

        await serverPeer.connect();
      });

      final client = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, serverPort),
        infoHash,
        piecesNum,
        null,
        PeerSource.manual,
      );
      final clientListener = client.createListener();

      clientListener.on<PeerConnected>((event) {
        event.peer.registerExtend(EXTENSION_LT_DONTHAVE);
        event.peer.sendHandShake(_peerId('CLIENT'));
      });

      clientListener.on<PeerHaveEvent>((event) {
        if (event.indices.contains(7)) {
          haveReceived = true;
        }
      });

      clientListener.on<PeerDontHaveEvent>((event) {
        if (event.index == 7) {
          donthaveReceived = true;
          if (!donthaveCompleter.isCompleted) {
            donthaveCompleter.complete();
          }
        }
      });

      await client.connect();
      await donthaveCompleter.future.timeout(const Duration(seconds: 5));

      expect(haveReceived, isTrue);
      expect(donthaveReceived, isTrue);
      expect(client.remoteHave(7), isFalse);
      await client.dispose('test done');
    });

    test('ignores invalid donthave for piece not previously advertised',
        () async {
      bool donthaveReceived = false;

      serverSocket!.listen((socket) async {
        final serverPeer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final listener = serverPeer.createListener();

        listener.on<PeerConnected>((event) {
          event.peer.registerExtend(EXTENSION_LT_DONTHAVE);
          event.peer.sendHandShake(_peerId('SERVER'));
        });

        listener.on<ExtendedEvent>((event) {
          if (event.eventName == 'handshake') {
            serverPeer.sendDontHave(5);
          }
        });

        await serverPeer.connect();
      });

      final client = Peer.newTCPPeer(
        CompactAddress(InternetAddress.loopbackIPv4, serverPort),
        infoHash,
        piecesNum,
        null,
        PeerSource.manual,
      );
      final clientListener = client.createListener();

      clientListener.on<PeerConnected>((event) {
        event.peer.registerExtend(EXTENSION_LT_DONTHAVE);
        event.peer.sendHandShake(_peerId('CLIENT'));
      });

      clientListener.on<PeerDontHaveEvent>((event) {
        donthaveReceived = true;
      });

      await client.connect();
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(donthaveReceived, isFalse);
      expect(client.remoteHave(5), isFalse);
      await client.dispose('test done');
    });
  });
}

String _peerId(String prefix) {
  final normalized = '-DTT54-$prefix';
  if (normalized.length >= 20) {
    return normalized.substring(0, 20);
  }
  return normalized.padRight(20, '0');
}
