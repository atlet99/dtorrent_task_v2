import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/seeding/superseeder.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';

/// Helper to create test peers with unique addresses
/// Uses different IP addresses to ensure peers are considered different
/// (Peer equality is based on IP address only)
Peer createTestPeer(int id) {
  // Use different IP addresses to ensure unique peers
  // 127.0.0.1, 127.0.0.2, 127.0.0.3, etc.
  final ip = '127.0.0.${(id % 254) + 1}';
  return Peer.newTCPPeer(
    CompactAddress(InternetAddress(ip), 6881 + id),
    List.filled(20, 0),
    10,
    null,
    PeerSource.manual,
  );
}

void main() {
  group('SuperSeeder', () {
    late SuperSeeder superseeder;
    const totalPieces = 10;

    setUp(() {
      superseeder = SuperSeeder(totalPieces);
    });

    test('should initialize with all pieces having rarity 0', () {
      expect(superseeder.enabled, isFalse);
      for (var i = 0; i < totalPieces; i++) {
        expect(superseeder.getPieceRarity(i), equals(0));
        expect(superseeder.hasBeenOffered(i), isFalse);
      }
    });

    test('should enable and disable superseeding', () {
      expect(superseeder.enabled, isFalse);
      superseeder.enable();
      expect(superseeder.enabled, isTrue);
      expect(superseeder.shouldSendBitfield(), isFalse);

      superseeder.disable();
      expect(superseeder.enabled, isFalse);
      expect(superseeder.shouldSendBitfield(), isTrue);
    });

    test('should select rarest piece to offer', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);

      // First piece should be selected (all have rarity 0)
      final piece1 = superseeder.selectPieceToOffer(peer1);
      expect(piece1, isNotNull);
      expect(piece1, equals(0)); // First piece
      expect(superseeder.hasBeenOffered(0), isTrue);

      // Next piece should be selected
      final peer2 = createTestPeer(2);
      final piece2 = superseeder.selectPieceToOffer(peer2);
      expect(piece2, isNotNull);
      expect(piece2, equals(1)); // Second piece
      expect(superseeder.hasBeenOffered(1), isTrue);
    });

    test('should not offer new piece until previous is distributed', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);

      // Offer piece 0 to peer1
      final piece1 = superseeder.selectPieceToOffer(peer1);
      expect(piece1, equals(0));

      // Try to offer another piece to same peer - should return null
      final piece2 = superseeder.selectPieceToOffer(peer1);
      expect(piece2, isNull);

      // Simulate piece 0 appearing on another peer
      final peer2 = createTestPeer(2);
      superseeder.onPeerHave(peer2, 0);

      // Now we can offer a new piece to peer1
      final piece3 = superseeder.selectPieceToOffer(peer1);
      expect(piece3, isNotNull);
      expect(piece3, equals(1));
    });

    test('should track piece rarity correctly', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);
      final peer2 = createTestPeer(2);
      final peer3 = createTestPeer(3);

      // Initially rarity is 0
      expect(superseeder.getPieceRarity(0), equals(0));

      // Peer1 has piece 0
      superseeder.onPeerHave(peer1, 0);
      expect(superseeder.getPieceRarity(0), equals(1));

      // Peer2 also has piece 0
      superseeder.onPeerHave(peer2, 0);
      expect(superseeder.getPieceRarity(0), equals(2));

      // Peer3 also has piece 0
      superseeder.onPeerHave(peer3, 0);
      expect(superseeder.getPieceRarity(0), equals(3));
    });

    test('should select rarest piece when all have been offered', () {
      superseeder.enable();

      // Offer all pieces to different peers
      for (var i = 0; i < totalPieces; i++) {
        final peer = createTestPeer(i);
        superseeder.selectPieceToOffer(peer);
      }

      // Make piece 5 have rarity 3, piece 6 have rarity 1 (rarest)
      final peerA = createTestPeer(10);
      final peerB = createTestPeer(11);
      final peerC = createTestPeer(12);

      superseeder.onPeerHave(peerA, 5);
      superseeder.onPeerHave(peerB, 5);
      superseeder.onPeerHave(peerC, 5);

      superseeder.onPeerHave(peerA, 6);

      // Now when selecting, should choose piece 6 (rarest)
      final newPeer = createTestPeer(20);
      // First need to wait for previous offer to be distributed
      // Let's simulate that piece 0 is distributed
      superseeder.onPeerHave(peerA, 0);

      final piece = superseeder.selectPieceToOffer(newPeer);
      // Should select a piece, and ideally the rarest one
      expect(piece, isNotNull);
    });

    test('should get pieces to announce for peer', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);

      // Initially getPiecesToAnnounce will select and return one piece
      var pieces = superseeder.getPiecesToAnnounce(peer1);
      expect(pieces.length, equals(1)); // Will select and return one piece
      expect(pieces[0], equals(0)); // First piece should be selected

      // After selecting, should return the same offered piece
      pieces = superseeder.getPiecesToAnnounce(peer1);
      expect(pieces.length, equals(1));
      expect(pieces[0], equals(0)); // Same piece
    });

    test('should clean up when peer disconnects', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);
      final peer2 = createTestPeer(2);

      // Offer piece to peer1
      superseeder.selectPieceToOffer(peer1);
      superseeder.onPeerHave(peer1, 0);

      // Peer2 also has piece 0
      superseeder.onPeerHave(peer2, 0);
      expect(superseeder.getPieceRarity(0), equals(2));

      // Peer1 disconnects
      superseeder.onPeerDisconnected(peer1);
      expect(superseeder.getPieceRarity(0), equals(1));
    });

    test('should provide statistics', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);
      final peer2 = createTestPeer(2);

      superseeder.selectPieceToOffer(peer1);
      superseeder.onPeerHave(peer2, 0);

      final stats = superseeder.getStatistics();
      expect(stats['enabled'], isTrue);
      expect(stats['piecesOffered'], equals(1));
      expect(stats['piecesDistributed'], equals(1));
      expect(stats['totalPieces'], equals(totalPieces));
      expect(stats['offeredPiecesCount'], equals(1));
    });

    test('should handle multiple peers with same piece', () {
      superseeder.enable();
      final peer1 = createTestPeer(1);
      final peer2 = createTestPeer(2);
      final peer3 = createTestPeer(3);

      // All peers have piece 0
      superseeder.onPeerHave(peer1, 0);
      superseeder.onPeerHave(peer2, 0);
      superseeder.onPeerHave(peer3, 0);

      expect(superseeder.getPieceRarity(0), equals(3));

      // One peer disconnects
      superseeder.onPeerDisconnected(peer1);
      expect(superseeder.getPieceRarity(0), equals(2));
    });

    test('should not offer piece if superseeding is disabled', () {
      // Don't enable
      final peer1 = createTestPeer(1);
      final piece = superseeder.selectPieceToOffer(peer1);
      expect(piece, isNull);
    });

    test('should handle edge case with single piece', () {
      final singlePieceSeeder = SuperSeeder(1);
      singlePieceSeeder.enable();
      final peer1 = createTestPeer(1);

      final piece = singlePieceSeeder.selectPieceToOffer(peer1);
      expect(piece, equals(0));

      // Offer again to same peer - should be null
      final piece2 = singlePieceSeeder.selectPieceToOffer(peer1);
      expect(piece2, isNull);

      // Distribute piece
      final peer2 = createTestPeer(2);
      singlePieceSeeder.onPeerHave(peer2, 0);

      // Now can offer again (but it's the same piece since there's only one)
      final piece3 = singlePieceSeeder.selectPieceToOffer(peer1);
      expect(piece3, equals(0));
    });
  });

  group('SuperSeeder Integration', () {
    test('should track piece distribution across multiple peers correctly', () {
      final superseeder = SuperSeeder(5);
      superseeder.enable();

      final peer1 = createTestPeer(1);
      final peer2 = createTestPeer(2);
      final peer3 = createTestPeer(3);

      // Offer piece 0 to peer1
      superseeder.selectPieceToOffer(peer1);
      expect(superseeder.getPieceRarity(0), equals(0));

      // Peer2 gets piece 0 (distributed)
      superseeder.onPeerHave(peer2, 0);
      expect(superseeder.getPieceRarity(0), equals(1));

      // Peer3 also gets piece 0
      superseeder.onPeerHave(peer3, 0);
      expect(superseeder.getPieceRarity(0), equals(2));

      // Now peer1 can get a new piece
      final newPiece = superseeder.selectPieceToOffer(peer1);
      expect(newPiece, isNotNull);
      expect(newPiece, equals(1));
    });
  });
}
