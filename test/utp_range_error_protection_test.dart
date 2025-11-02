import 'dart:io';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:test/test.dart';

void main() {
  group('uTP RangeError Protection Tests', () {
    late CompactAddress testAddress;
    late List<int> testInfoHash;

    setUp(() {
      testAddress = CompactAddress(InternetAddress('127.0.0.1'), 6881);
      testInfoHash = List.filled(20, 0); // 20 bytes for infohash
    });

    test('should create uTP peer with valid parameters', () {
      // Create a peer instance - this tests that the constructor works
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100, // piecesNum
        null, // socket
        PeerSource.manual,
      );

      expect(peer, isNotNull);
      expect(peer.address, equals(testAddress));
    });

    test('should validate sendByteMessage with empty bytes', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Should not crash on empty message
      expect(() {
        peer.sendByteMessage([]);
      }, returnsNormally);
    });

    test('should validate sendByteMessage with large message', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Create a message larger than 2MB limit
      var largeMessage = List.filled(3 * 1024 * 1024, 0); // 3MB

      // Should not crash but log warning
      expect(() {
        peer.sendByteMessage(largeMessage);
      }, returnsNormally);
    });

    test('should validate infoHash buffer length on creation', () {
      var validInfoHash = List.filled(20, 0);
      var invalidInfoHash = List.filled(10, 0); // Too short

      // Should create peer with valid infohash
      var peer1 = Peer.newUTPPeer(
        testAddress,
        validInfoHash,
        100,
        null,
        PeerSource.manual,
      );
      expect(peer1, isNotNull);

      // Invalid infohash should also create peer (validation happens later on handshake)
      var peer2 = Peer.newUTPPeer(
        testAddress,
        invalidInfoHash,
        100,
        null,
        PeerSource.manual,
      );
      expect(peer2, isNotNull);
    });
  });
}
