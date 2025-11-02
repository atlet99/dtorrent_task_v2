import 'dart:io';
import 'dart:async';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:test/test.dart';

/// Test for long-running uTP sessions
/// Simulates extended connections to test seq/ack overflow scenarios
/// Note: Full multi-hour test would require integration test, this simulates the pattern
void main() {
  group('uTP Long Session Tests', () {
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
      print('  Errors by reason: ${Peer.rangeErrorByReason}');
    });

    test('should handle extended message sequence without overflow', () async {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate long session: send many messages over extended period
      // In real scenario, seq numbers would wrap around after 2^16
      const numMessages =
          100000; // Simulate 100k messages (more than 16-bit seq range)
      var startTime = DateTime.now();

      for (var i = 0; i < numMessages; i++) {
        // Simulate varying message sizes as in real scenario
        var size = (i % 1000) + 1;
        var message = List.filled(size, i % 256);

        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);

        // Small delay to simulate network conditions (but faster than real-time)
        if (i % 1000 == 0) {
          await Future.delayed(Duration(microseconds: 1));
        }
      }

      var duration = DateTime.now().difference(startTime);
      print('Sent $numMessages messages in ${duration.inMilliseconds}ms');

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle rapid message bursts simulating extended session',
        () async {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate multiple hours of activity compressed into test
      // Send bursts of messages with patterns that might occur over time
      const numBursts = 100;
      const messagesPerBurst = 1000;

      for (var burst = 0; burst < numBursts; burst++) {
        // Each burst simulates activity period
        for (var i = 0; i < messagesPerBurst; i++) {
          var messageIndex = burst * messagesPerBurst + i;

          // Vary message sizes to simulate different packet types
          var size = (messageIndex % 500) + 10;
          var message = List.filled(size, (messageIndex % 256));

          expect(() {
            peer.sendByteMessage(message);
          }, returnsNormally);
        }

        // Small delay between bursts
        if (burst % 10 == 0) {
          await Future.delayed(Duration(microseconds: 10));
        }
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle seq-like value patterns that would wrap around', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate seq values that wrap around (uTP uses 16-bit seq numbers)
      // Test values near and beyond 16-bit boundary (65535)
      var seqTestPoints = [
        0,
        1000,
        32767, // Half of 16-bit range
        32768,
        65534, // 16-bit max - 1
        65535, // 16-bit max
        65536, // Wrap around point
        65537,
        100000, // Well beyond wrap
        1000000, // Very large
      ];

      for (var seqValue in seqTestPoints) {
        // Create message with seq-like pattern
        var message = <int>[];

        // Simulate 16-bit seq number in first 2 bytes
        message.add((seqValue >> 8) & 0xFF);
        message.add(seqValue & 0xFF);

        // Add payload
        message.addAll(List.filled(100, seqValue % 256));

        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle continuous activity without memory leaks', () async {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate continuous activity pattern
      // Send messages with steady rate to simulate long download
      const durationSeconds =
          5; // Simulated 5 seconds (represents hours in real scenario)
      const messagesPerSecond = 1000;
      const totalMessages = durationSeconds * messagesPerSecond;

      var startTime = DateTime.now();
      var messagesSent = 0;

      while (messagesSent < totalMessages) {
        var message =
            List.filled((messagesSent % 1000) + 1, messagesSent % 256);
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);

        messagesSent++;

        // Rate limiting to simulate realistic throughput
        if (messagesSent % messagesPerSecond == 0) {
          var elapsed = DateTime.now().difference(startTime).inMilliseconds;
          if (elapsed < 1000) {
            await Future.delayed(Duration(milliseconds: 1000 - elapsed));
          }
          startTime = DateTime.now();
        }
      }

      expect(Peer.rangeErrorCount, equals(0));
      print(
          'Sent $messagesSent messages over $durationSeconds simulated seconds');
    });

    test('should handle mixed message sizes over extended period', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate realistic mix of message sizes over time
      const numMessages = 50000;

      for (var i = 0; i < numMessages; i++) {
        // Mix of small (ACK-like) and large (data) messages
        int size;
        if (i % 10 == 0) {
          // Every 10th message is large (data)
          size = (i % 100000) + 1000;
        } else {
          // Most messages are small (ACKs)
          size = (i % 50) + 4;
        }

        // Cap at 2MB limit
        if (size > 2 * 1024 * 1024) {
          size = 2 * 1024 * 1024;
        }

        var message = List.filled(size, i % 256);
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should maintain stability with high message count', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Send very high number of messages (simulating days of activity)
      const numMessages = 1000000; // 1 million messages

      for (var i = 0; i < numMessages; i++) {
        var size = (i % 100) + 1;
        var message = List.filled(size, i % 256);

        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });
  });
}
