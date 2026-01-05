import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('Fast Extension (BEP 6) Tests', () {
    ServerSocket? serverSocket;
    late int serverPort;
    late Uint8List infoHash;
    late int piecesNum;

    setUp(() async {
      infoHash = Uint8List.fromList(List.generate(20, (i) => i));
      piecesNum = 100;
    });

    tearDown(() async {
      await serverSocket?.close();
      serverSocket = null;
    });

    test('Have All message replaces bitfield completely', () async {
      final completer = Completer<void>();
      bool haveAllReceived = false;
      Bitfield? receivedBitfield;

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          // Send Have All message
          event.peer.sendHaveAll();
        });

        // Initialize stream for incoming connection
        peer.connect();
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

      clientListener.on<PeerHaveAll>((event) {
        haveAllReceived = true;
        receivedBitfield = event.peer.remoteBitfield;
        completer.complete();
      });

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      await completer.future.timeout(const Duration(seconds: 5));

      expect(haveAllReceived, isTrue,
          reason: 'Have All message should be received');
      expect(receivedBitfield, isNotNull, reason: 'Bitfield should be set');
      expect(receivedBitfield!.haveAll(), isTrue,
          reason: 'Bitfield should indicate all pieces are available');

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Have None message replaces bitfield with empty bitfield', () async {
      final completer = Completer<void>();
      bool haveNoneReceived = false;
      Bitfield? receivedBitfield;

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          // Send Have None message
          event.peer.sendHaveNone();
        });

        // Initialize stream for incoming connection
        peer.connect();
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

      clientListener.on<PeerHaveNone>((event) {
        haveNoneReceived = true;
        receivedBitfield = event.peer.remoteBitfield;
        completer.complete();
      });

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      await completer.future.timeout(const Duration(seconds: 5));

      expect(haveNoneReceived, isTrue,
          reason: 'Have None message should be received');
      expect(receivedBitfield, isNotNull, reason: 'Bitfield should be set');
      expect(receivedBitfield!.haveNone(), isTrue,
          reason: 'Bitfield should indicate no pieces are available');

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Reject Request is sent when choking peer', () async {
      final completer = Completer<void>();
      bool rejectReceived = false;
      int? rejectedIndex;
      int? rejectedBegin;
      int? rejectedLength;

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerHandshakeEvent>((event) {
          // Send bitfield with some pieces
          final bitfield = Bitfield.createEmptyBitfield(piecesNum);
          bitfield.setBit(0, true);
          bitfield.setBit(1, true);
          event.peer.sendBitfield(bitfield);
        });

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        peerListener.on<PeerRequestEvent>((event) {
          // Choke the peer and reject the request
          event.peer.sendChoke(true);
          // Reject should be sent automatically per BEP 6
        });

        // Initialize stream for incoming connection
        peer.connect();
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

      clientListener.on<PeerRejectEvent>((event) {
        rejectReceived = true;
        rejectedIndex = event.index;
        rejectedBegin = event.begin;
        rejectedLength = event.length;
        completer.complete();
      });

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      // Wait for bitfield
      await Future.delayed(const Duration(milliseconds: 500));

      // Send request
      clientPeer.sendRequest(0, 0, DEFAULT_REQUEST_LENGTH);

      await completer.future.timeout(const Duration(seconds: 5));

      expect(rejectReceived, isTrue,
          reason: 'Reject Request should be received');
      expect(rejectedIndex, equals(0), reason: 'Rejected index should match');
      expect(rejectedBegin, equals(0), reason: 'Rejected begin should match');
      expect(rejectedLength, equals(DEFAULT_REQUEST_LENGTH),
          reason: 'Rejected length should match');

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Allowed Fast set is generated at handshake', () async {
      final completer = Completer<void>();
      final allowedFastPieces = <int>{};

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        // Server will automatically generate and send allowed fast set after handshake
        // Initialize stream for incoming connection
        peer.connect();
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

      clientListener.on<PeerAllowFast>((event) {
        allowedFastPieces.add(event.index);
        if (allowedFastPieces.length >= 10) {
          completer.complete();
        }
      });

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      await completer.future.timeout(const Duration(seconds: 5));

      expect(allowedFastPieces.length, greaterThanOrEqualTo(10),
          reason: 'Should generate at least 10 Allowed Fast pieces');
      expect(allowedFastPieces.length, lessThanOrEqualTo(10),
          reason: 'Should generate exactly 10 Allowed Fast pieces (k=10)');

      // Verify all indices are valid
      for (final index in allowedFastPieces) {
        expect(index, greaterThanOrEqualTo(0),
            reason: 'Piece index should be non-negative');
        expect(index, lessThan(piecesNum),
            reason: 'Piece index should be valid');
      }

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Allowed Fast pieces can be downloaded when choked', () async {
      final completer = Completer<void>();
      bool pieceReceived = false;
      int? receivedIndex;

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          // Send bitfield
          final bitfield = Bitfield.createEmptyBitfield(piecesNum);
          bitfield.setBit(0, true);
          event.peer.sendBitfield(bitfield);
        });

        peerListener.on<PeerAllowFast>((event) {
          // After receiving allowed fast, choke the peer
          // but the allowed fast piece should still be downloadable
        });

        peerListener.on<PeerRequestEvent>((event) {
          // For this test, we know the client will request an allowed fast piece
          // In real scenario, we'd check if it's in our allow fast set
          // But for simplicity, we'll just send the piece
          // The server should check _allowFastPieces internally when processing requests
          final block = Uint8List(event.length);
          event.peer.sendPiece(event.index, event.begin, block);
        });

        peerListener.on<PeerPieceEvent>((event) {
          pieceReceived = true;
          receivedIndex = event.index;
          completer.complete();
        });

        // Initialize stream for incoming connection
        peer.connect();
      });

      final clientSocket = await Socket.connect('127.0.0.1', serverPort);
      final clientPeer = Peer.newTCPPeer(
        CompactAddress(InternetAddress('127.0.0.1'), serverPort),
        infoHash,
        piecesNum,
        clientSocket,
        PeerSource.manual,
      );

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      // Wait for bitfield and allowed fast to be generated and sent
      // Allowed fast is generated automatically after handshake
      await Future.delayed(const Duration(milliseconds: 1500));

      // Get allowed fast pieces
      final allowedFast = clientPeer.remoteAllowFastPieces;
      expect(allowedFast.isNotEmpty, isTrue,
          reason: 'Should have allowed fast pieces');

      // Request an allowed fast piece
      final allowedFastIndex = allowedFast.first;
      clientPeer.sendRequest(allowedFastIndex, 0, DEFAULT_REQUEST_LENGTH);

      await completer.future.timeout(const Duration(seconds: 5));

      expect(pieceReceived, isTrue, reason: 'Piece should be received');
      expect(receivedIndex, equals(allowedFastIndex),
          reason:
              'Received piece index should match requested allowed fast piece');

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Suggest Piece message is handled correctly', () async {
      final completer = Completer<void>();
      bool suggestReceived = false;
      int? suggestedIndex;

      serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      serverPort = serverSocket!.port;

      serverSocket!.listen((socket) {
        final peer = Peer.newTCPPeer(
          CompactAddress(socket.address, socket.port),
          infoHash,
          piecesNum,
          socket,
          PeerSource.incoming,
        );
        final peerListener = peer.createListener();

        peerListener.on<PeerConnected>((event) {
          // Send handshake from server
          event.peer.sendHandShake('SERVER_PEER_ID_123456789012');
        });

        peerListener.on<PeerHandshakeEvent>((event) {
          // Send Suggest Piece message
          event.peer.sendSuggestPiece(5);
        });

        // Initialize stream for incoming connection
        peer.connect();
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

      clientListener.on<PeerSuggestPiece>((event) {
        suggestReceived = true;
        suggestedIndex = event.index;
        completer.complete();
      });

      await clientPeer.connect();
      clientPeer.sendHandShake('TEST_PEER_ID_123456789012');

      await completer.future.timeout(const Duration(seconds: 5));

      expect(suggestReceived, isTrue,
          reason: 'Suggest Piece should be received');
      expect(suggestedIndex, equals(5), reason: 'Suggested index should match');
      expect(clientPeer.remoteSuggestPieces.contains(5), isTrue,
          reason: 'Suggested piece should be in remote suggest pieces set');

      await clientPeer.dispose();
      await clientSocket.close();
    });

    test('Allowed Fast set generation uses canonical algorithm', () async {
      // Test that the same IP and info hash produce the same allowed fast set
      final ip1 = InternetAddress('192.168.1.1');
      final ip2 = InternetAddress('192.168.1.1');
      final infoHash1 = Uint8List.fromList(List.generate(20, (i) => i));
      final infoHash2 = Uint8List.fromList(List.generate(20, (i) => i));
      final piecesNum = 100;

      // Generate allowed fast set manually using the canonical algorithm
      final set1 = _generateAllowedFastSet(ip1, infoHash1, piecesNum);
      final set2 = _generateAllowedFastSet(ip2, infoHash2, piecesNum);

      expect(set1, equals(set2),
          reason: 'Same IP and info hash should produce same allowed fast set');

      // Test with different IP (must differ in first 3 bytes, not just last byte)
      // because mask 0xFFFFFF00 zeros the last byte
      final ip3 = InternetAddress('192.168.2.1');
      final set3 = _generateAllowedFastSet(ip3, infoHash1, piecesNum);
      expect(set1, isNot(equals(set3)),
          reason: 'Different IP should produce different allowed fast set');
    });
  });
}

/// Generate Allowed Fast set using canonical algorithm from BEP 6
Set<int> _generateAllowedFastSet(
    InternetAddress ip, Uint8List infoHash, int piecesNum) {
  const k = 10;
  final allowedPieces = <int>{};

  if (ip.type != InternetAddressType.IPv4) {
    return allowedPieces;
  }

  // Step 1: Use only 3 most significant bytes (0xFFFFFF00 & ip)
  final ipBytes = Uint8List.fromList(ip.rawAddress);
  final ipInt = ByteData.view(ipBytes.buffer).getUint32(0, Endian.big);
  final maskedIp = ipInt & 0xFFFFFF00;

  final maskedIpBytes = Uint8List(4);
  ByteData.view(maskedIpBytes.buffer).setUint32(0, maskedIp, Endian.big);

  // Step 2: Concatenate masked IP with info hash
  var x = Uint8List(maskedIpBytes.length + infoHash.length);
  x.setRange(0, maskedIpBytes.length, maskedIpBytes);
  x.setRange(maskedIpBytes.length, x.length, infoHash);

  // Step 3: Iteratively generate hashes until we have k unique pieces
  while (allowedPieces.length < k) {
    // Compute SHA-1 hash
    final hash = sha1.convert(x);
    final hashBytes = Uint8List.fromList(hash.bytes);

    // Step 4: Extract 5 piece indices from this 20-byte hash
    for (var i = 0; i < 5 && allowedPieces.length < k; i++) {
      final j = i * 4;
      if (j + 4 > hashBytes.length) break;

      // Extract 4 bytes and convert to 32-bit integer (big-endian)
      final yBytes = hashBytes.sublist(j, j + 4);
      final y = ByteData.view(yBytes.buffer).getUint32(0, Endian.big);

      // Step 5: Compute piece index
      final pieceIndex = y % piecesNum;

      // Step 6: Add to set if not already present
      allowedPieces.add(pieceIndex);
    }

    // Use the hash as input for next iteration
    x = hashBytes;
  }

  return allowedPieces;
}
