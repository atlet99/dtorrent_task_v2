import 'dart:io';
import 'dart:math';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'package:test/test.dart';

/// Test for extreme values in uTP protocol
/// Tests large seq/ack values, overflows, and boundary conditions
void main() {
  group('uTP Extreme Values Tests', () {
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

    test('should handle maximum valid message size (2MB)', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Exactly 2MB (the limit)
      var maxMessage = List.filled(2 * 1024 * 1024, 0);
      expect(() {
        peer.sendByteMessage(maxMessage);
      }, returnsNormally);

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should reject messages over 2MB limit gracefully', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Over 2MB - should be rejected but not crash
      var oversizedMessages = [
        List.filled(2 * 1024 * 1024 + 1, 0), // 2MB + 1
        List.filled(3 * 1024 * 1024, 0), // 3MB
        List.filled(10 * 1024 * 1024, 0), // 10MB
      ];

      for (var message in oversizedMessages) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      // Should not crash, but might log warnings
      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle very large message counts without overflow', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Send many messages to test cumulative buffer handling
      const numMessages = 10000;
      var messages = <List<int>>[];

      // Create messages of varying sizes
      for (var i = 0; i < numMessages; i++) {
        var size = (i % 1000) + 1;
        messages.add(List.filled(size, i % 256));
      }

      // Send all messages
      for (var message in messages) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle messages with patterns simulating seq/ack', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Simulate message patterns that might come from seq/ack values
      // In uTP, seq/ack are typically 16-bit values, but we test edge cases
      var patterns = <List<int>>[];

      // Simulate various seq/ack-like patterns
      for (var seq = 0; seq < 1000; seq++) {
        // Create messages with seq-like patterns in first bytes
        var message = <int>[];

        // Add seq-like value (simulating 16-bit sequence number)
        message.add((seq >> 8) & 0xFF);
        message.add(seq & 0xFF);

        // Add ack-like value
        var ack = seq - 10; // Simulate ACK for previous packets
        if (ack < 0) ack = 0;
        message.add((ack >> 8) & 0xFF);
        message.add(ack & 0xFF);

        // Add payload
        message.addAll(List.filled(100, seq % 256));
        patterns.add(message);
      }

      // Send all pattern messages
      for (var message in patterns) {
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle boundary values for message sizes', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Test boundary values around common block sizes
      var boundarySizes = [
        0, // Empty (should be handled)
        1, // Minimum non-empty
        16383, // 16KB - 1
        16384, // Exactly 16KB (common block size)
        16385, // 16KB + 1
        32767, // 32KB - 1
        32768, // Exactly 32KB
        65535, // 64KB - 1
        65536, // Exactly 64KB
        131071, // 128KB - 1
        131072, // Exactly 128KB
        1048575, // 1MB - 1
        1048576, // Exactly 1MB
        2097151, // 2MB - 1
        2097152, // Exactly 2MB (limit)
      ];

      for (var size in boundarySizes) {
        if (size == 0) {
          // Empty message - should be handled gracefully
          expect(() {
            peer.sendByteMessage([]);
          }, returnsNormally);
        } else {
          var message = List.filled(size, size % 256);
          expect(() {
            peer.sendByteMessage(message);
          }, returnsNormally);
        }
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle rapid succession of max-size messages', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Send multiple max-size messages rapidly
      const numMessages = 10;
      for (var i = 0; i < numMessages; i++) {
        var message = List.filled(2 * 1024 * 1024, i % 256); // 2MB
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle random message sizes without crashing', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      var random = Random(42); // Fixed seed for reproducibility
      const numMessages = 1000;

      for (var i = 0; i < numMessages; i++) {
        // Random size up to 2MB
        var size = random.nextInt(2 * 1024 * 1024);
        var message = List.filled(size, random.nextInt(256));

        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle messages with all possible byte values', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Create messages with all possible byte values (0-255)
      for (var byteValue = 0; byteValue < 256; byteValue++) {
        var message = List.filled(100, byteValue);
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });

    test('should handle large number of small messages', () {
      var peer = Peer.newUTPPeer(
        testAddress,
        testInfoHash,
        100,
        null,
        PeerSource.manual,
      );

      // Send many small messages (simulating high-frequency ACKs)
      const numMessages = 50000;
      for (var i = 0; i < numMessages; i++) {
        var message = [i % 256, (i >> 8) % 256]; // 2-byte messages
        expect(() {
          peer.sendByteMessage(message);
        }, returnsNormally);
      }

      expect(Peer.rangeErrorCount, equals(0));
    });
  });
}
