import 'dart:io';
import 'dart:async';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:test/test.dart';

/// Stress test for uTP RangeError protection
/// Tests multiple parallel connections and edge cases
void main() {
  group('uTP Stress Tests - RangeError Protection', () {
    late CompactAddress testAddress;
    late List<int> testInfoHash;

    setUp(() {
      testAddress = CompactAddress(InternetAddress('127.0.0.1'), 6881);
      testInfoHash = List.filled(20, 0); // 20 bytes for infohash
      // Reset metrics before each test
      Peer.resetRangeErrorMetrics();
    });

    tearDown(() {
      // Log metrics after each test
      print('Test metrics:');
      print('  Total RangeErrors: ${Peer.rangeErrorCount}');
      print('  uTP RangeErrors: ${Peer.utpRangeErrorCount}');
      print('  Errors by reason: ${Peer.rangeErrorByReason}');
    });

    test('should handle multiple parallel uTP peer creations', () async {
      const numPeers = 50;
      var peers = <Peer>[];
      var errors = <dynamic>[];

      // Create many peers in parallel
      for (var i = 0; i < numPeers; i++) {
        try {
          var peer = Peer.newUTPPeer(
            CompactAddress(InternetAddress('127.0.0.${i % 255 + 1}'), 6881 + i),
            testInfoHash,
            100,
            null,
            PeerSource.manual,
          );
          peers.add(peer);
        } catch (e) {
          errors.add(e);
        }
      }

      expect(peers.length, equals(numPeers));
      expect(errors.length, equals(0));
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle burst of sendByteMessage calls', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Send many messages rapidly
      for (var i = 0; i < 1000; i++) {
        var message = List.filled(i % 16384, i % 256); // Varying sizes
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      // Should not have crashed
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle edge case message sizes', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Test edge cases
      var edgeCases = <List<int>>[
        [], // Empty
        [0], // Single byte
        List.filled(16384, 0), // Exactly 16KB (common block size)
        List.filled(16384 + 1, 0), // 16KB + 1
        List.filled(1024 * 1024, 0), // 1MB
        List.filled(1024 * 1024 * 2, 0), // 2MB (limit)
        List.filled(1024 * 1024 * 2 + 1, 0), // Over limit
      ];

      for (var message in edgeCases) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      // Should not have crashed
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle concurrent operations on multiple peers', () async {
      const numPeers = 20;
      var peers = <Peer>[];
      var futures = <Future>[];

      // Create peers
      for (var i = 0; i < numPeers; i++) {
        var peer = Peer.newUTPPeer(
          CompactAddress(InternetAddress('127.0.0.${i % 255 + 1}'), 6881 + i),
          testInfoHash,
          100,
          null,
          PeerSource.manual,
        );
        peers.add(peer);
      }

      // Perform concurrent operations
      for (var peer in peers) {
        futures.add(Future(() {
          for (var j = 0; j < 100; j++) {
            var message = List.filled((j % 1000) + 1, j % 256);
            peer.sendByteMessage(message);
          }
        }));
      }

      // Wait for all operations
      await Future.wait(futures);

      // Should not have crashed
      expect(Peer.rangeErrorCount, equals(0));
      expect(peers.length, equals(numPeers));
    });

    test('should track RangeError metrics correctly', () {
      expect(Peer.rangeErrorCount, equals(0));
      expect(Peer.utpRangeErrorCount, equals(0));
      expect(Peer.rangeErrorByReason.isEmpty, isTrue);

      // Note: We can't easily trigger RangeError in tests without mocking,
      // but we verify the metrics infrastructure works
      Peer.resetRangeErrorMetrics();
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle invalid infohash lengths gracefully', () {
      var invalidLengths = [0, 1, 10, 19, 21, 100];

      for (var length in invalidLengths) {
        var invalidInfoHash = List.filled(length, 0);
        // Should create peer (validation happens later)
        var peer = Peer.newUTPPeer(
          testAddress,
          invalidInfoHash,
          100,
          null,
          PeerSource.manual,
        );
        expect(peer, isNotNull);
      }
    });

    test('should handle rapid connect attempts without crashes', () async {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Multiple rapid connect attempts (will fail but shouldn't crash)
      for (var i = 0; i < 10; i++) {
        expect(() async {
          try {
            await peer.connect(1); // Very short timeout
          } catch (e) {
            // Expected to fail, but shouldn't crash
          }
        }, returnsNormally);
        // Small delay between attempts
        await Future.delayed(Duration(milliseconds: 10));
      }

      expect(Peer.rangeErrorCount, equals(0));
    });
  });
}
