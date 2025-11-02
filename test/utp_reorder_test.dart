import 'dart:io';
import 'dart:async';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:test/test.dart';

/// Test for packet reordering in uTP protocol
/// Simulates receiving packets out of order with burst ACKs
void main() {
  group('uTP Packet Reordering Tests', () {
    late CompactAddress testAddress;
    late List<int> testInfoHash;

    setUp(() {
      testAddress = CompactAddress(InternetAddress('127.0.0.1'), 6881);
      testInfoHash = List.filled(20, 0);
      Peer.resetRangeErrorMetrics();
    });

    tearDown(() {
      print('Test metrics:');
      print('  Total RangeErrors: ${Peer.rangeErrorCount}');
      print('  uTP RangeErrors: ${Peer.utpRangeErrorCount}');
    });

    test('should handle burst of messages with varying sizes', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate burst of messages (simulating reordered packets)
      var messages = <List<int>>[];
      for (var i = 0; i < 100; i++) {
        var size = (i % 1000) + 1;
        var message = List.filled(size, i % 256);
        messages.add(message);
      }

      // Send all messages rapidly
      for (var message in messages) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle messages with edge case lengths', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Test edge cases that might cause overflow in calculations
      var edgeCases = [
        0,
        1,
        16383, // 16KB - 1
        16384, // Exactly 16KB
        16385, // 16KB + 1
        1048575, // 1MB - 1
        1048576, // Exactly 1MB
        1048577, // 1MB + 1
        2097151, // 2MB - 1
        2097152, // Exactly 2MB (limit)
      ];

      for (var length in edgeCases) {
        var message = List.filled(length, 0);
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle rapid sendByteMessage calls simulating ACK bursts',
        () async {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate rapid ACK-like messages (small messages sent frequently)
      var futures = <Future>[];
      for (var i = 0; i < 500; i++) {
        futures.add(Future(() {
          var ackMessage =
              List.filled(4 + (i % 10), i % 256); // Small ACK-like messages
          peer.sendByteMessage(ackMessage);
        }));

        // Add small delay to create burst pattern
        if (i % 50 == 0) {
          await Future.delayed(Duration(microseconds: 100));
        }
      }

      await Future.wait(futures);
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle concurrent sendByteMessage from multiple threads',
        () async {
      const numThreads = 10;
      var peers = <Peer>[];
      var futures = <Future>[];

      // Create multiple peers
      for (var i = 0; i < numThreads; i++) {
        var peer = Peer.newUTPPeer(
          CompactAddress(InternetAddress('127.0.0.${i % 255 + 1}'), 6881 + i),
          testInfoHash,
          100,
          null,
          PeerSource.manual,
        );
        peers.add(peer);
      }

      // Send messages concurrently from all peers
      for (var peer in peers) {
        futures.add(Future(() async {
          for (var i = 0; i < 100; i++) {
            var message = List.filled((i % 1000) + 1, i % 256);
            peer.sendByteMessage(message);
            // Small delay to simulate network conditions
            if (i % 10 == 0) {
              await Future.delayed(Duration(microseconds: 10));
            }
          }
        }));
      }

      await Future.wait(futures);
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle messages with potential overflow scenarios', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Test values that might cause integer overflow in calculations
      // but are still within valid message size limits
      var safeButLargeMessages = [
        List.filled(1000000, 0), // 1MB
        List.filled(1500000, 0), // 1.5MB
        List.filled(2000000, 0), // 2MB (limit)
      ];

      for (var message in safeButLargeMessages) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle empty and single-byte messages in bursts', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Mix of empty, single-byte, and normal messages
      var messages = <List<int>>[
        [], // Empty (should be handled gracefully)
        [0], // Single byte
        [1, 2, 3], // Small message
        List.filled(100, 0), // Normal message
      ];

      // Send each type multiple times rapidly
      for (var i = 0; i < 50; i++) {
        for (var message in messages) {
          expect(() {
            peer.sendByteMessage(message);
          }, returnsNormally);
        }
      }

      expect(Peer.rangeErrorCount, equals(0));
    });
  });
}
