import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';

void main() {
  group('Peer Communication Tests', () {
    ServerSocket? serverSocket;
    late int serverPort;
    late Uint8List infoBuffer;
    late int piecesNum;
    late Bitfield bitfield;
    late Map<String, bool> callMap;

    setUp(() async {
      infoBuffer = Uint8List.fromList(randomBytes(20));
      piecesNum = 20;
      bitfield = Bitfield.createEmptyBitfield(piecesNum);
      bitfield.setBit(10, true);
      callMap = <String, bool>{
        'connect1': false,
        'handshake1': false,
        'connect2': false,
        'handshake2': false,
        'choke': false,
        'interested': false,
        'bitfield': false,
        'have': false,
        'request': false,
        'piece': false,
        'port': false,
        'have_all': false,
        'have_none': false,
        'keep_live': false,
        'cancel': false,
        'reject_request': false,
        'allow_fast': false,
        'suggest_piece': false,
      };
    });

    tearDown(() async {
      await serverSocket?.close();
      serverSocket = null;
    });

    test('should handle full peer communication protocol', () async {
      final completer = Completer<void>();

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoBuffer,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener
          ..on<PeerConnected>((event) {
            callMap['connect1'] = true;
            event.peer.sendHandShake(generatePeerId());
          })
          ..on<PeerHandshakeEvent>((event) {
            callMap['handshake1'] = true;
            event.peer.sendInterested(true);
          })
          ..on<PeerBitfieldEvent>((event) {
            expect(event.bitfield?.getBit(10), isTrue);
            callMap['bitfield'] = true;
          })
          ..on<PeerInterestedChanged>((event) {
            callMap['interested'] = true;
            event.peer.sendChoke(false);
          })
          ..on<PeerChokeChanged>((event) {
            callMap['choke'] = true;
          })
          ..on<PeerRequestEvent>((event) {
            callMap['request'] = true;
            expect(event.begin, equals(0));
            expect(event.length, equals(DEFAULT_REQUEST_LENGTH));
            if (event.index == 1) {
              event.peer.sendRejectRequest(
                event.index,
                event.begin,
                DEFAULT_REQUEST_LENGTH,
              );
            }
          })
          ..on<PeerCancelEvent>((event) {
            callMap['cancel'] = true;
            expect(event.index, equals(1));
            expect(event.begin, equals(0));
            expect(event.length, equals(DEFAULT_REQUEST_LENGTH));
          })
          ..on<PeerPortChanged>((event) {
            callMap['port'] = true;
            expect(event.port, equals(3321));
          })
          ..on<PeerHaveEvent>((event) {
            callMap['have'] = true;
            expect(event.indices[0], equals(2));
          })
          ..on<PeerKeepAlive>((event) {
            callMap['keep_live'] = true;
          })
          ..on<PeerHaveAll>((event) {
            callMap['have_all'] = true;
          })
          ..on<PeerHaveNone>((event) {
            callMap['have_none'] = true;
          })
          ..on<PeerSuggestPiece>((event) {
            expect(event.index, equals(3));
            callMap['suggest_piece'] = true;
            event.peer.sendRequest(event.index, 0);
          })
          ..on<PeerAllowFast>((event) {
            // Index can be any value from allowed fast set, not necessarily 4
            callMap['allow_fast'] = true;
            Timer.run(() => event.peer.sendRequest(event.index, 0));
          })
          ..on<PeerPieceEvent>((event) async {
            callMap['piece'] = true;
            expect(event.block.length, equals(DEFAULT_REQUEST_LENGTH));
            expect(event.block[0], equals(event.index));
            expect(event.block[1], equals(event.begin));
            final id = String.fromCharCodes(event.block.getRange(2, 22));
            expect(id, equals(peer.remotePeerId));
            // Check if this is an allowed fast piece
            if (peer.remoteAllowFastPieces.contains(event.index)) {
              await peer.dispose(BadException('Testing completed'));
            }
          })
          ..on<PeerDisposeEvent>((event) async {
            await serverSocket?.close();
            serverSocket = null;
            if (!completer.isCompleted) {
              completer.complete();
            }
          });

        // Initialize stream for incoming connection
        peer.connect();
      });

      final pid = generatePeerId();
      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress.tryParse('127.0.0.1')!, serverPort),
        infoBuffer,
        piecesNum,
        null,
        PeerSource.manual,
      );
      final peerListener = peer.createListener();

      peerListener
        ..on<PeerConnected>((event) {
          callMap['connect2'] = true;
          event.peer.sendHandShake(pid);
        })
        ..on<PeerHandshakeEvent>((event) {
          callMap['handshake2'] = true;
          event.peer.sendBitfield(bitfield);
          event.peer.sendInterested(true);
          event.peer.sendChoke(false);
        })
        ..on<PeerChokeChanged>((event) {
          if (!event.choked) {
            event.peer.sendRequest(1, 0);
            event.peer.requestCancel(1, 0, DEFAULT_REQUEST_LENGTH);
            event.peer.sendRequest(1, 0);
            event.peer.sendHave(2);
            event.peer.sendKeepAlive();
            event.peer.sendPortChange(3321);
            event.peer.sendHaveAll();
            event.peer.sendHaveNone();
            event.peer.sendSuggestPiece(3);
          }
        })
        ..on<PeerRejectEvent>((event) {
          expect(event.index, equals(1));
          expect(event.begin, equals(0));
          expect(event.length, equals(DEFAULT_REQUEST_LENGTH));
          callMap['reject_request'] = true;
        })
        ..on<PeerRequestEvent>((event) {
          final content = Uint8List(DEFAULT_REQUEST_LENGTH);
          final view = ByteData.view(content.buffer);
          view.setUint8(0, event.index);
          view.setUint8(1, event.begin);
          final idContent = utf8.encode(pid);
          for (var i = 0; i < idContent.length; i++) {
            view.setUint8(i + 2, idContent[i]);
          }
          event.peer.sendPiece(event.index, event.begin, content);
          event.peer.sendChoke(true); // Testing "allow fast".
          event.peer.sendAllowFast(4);
        })
        ..on<PeerDisposeEvent>((event) async {
          await serverSocket?.close();
          serverSocket = null;
          if (!completer.isCompleted) {
            completer.complete();
          }
        });

      await peer.connect();

      // Wait for test completion with timeout
      await completer.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Peer communication test timed out');
        },
      );

      // Verify all events were called
      final allCalled = callMap.values.every((value) => value);
      expect(allCalled, isTrue, reason: 'Not all peer events were triggered');
    }, timeout: Timeout(const Duration(seconds: 15)));
  });
}
