import 'dart:io';

import 'package:dtorrent_task_v2/src/peer/peer_priority.dart';
import 'package:test/test.dart';

void main() {
  group('PeerPriority (BEP 40)', () {
    test('matches BEP 40 IPv4 example #1', () {
      final priority = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('123.213.32.10'),
        clientPort: 51413,
        peerIp: InternetAddress('98.76.54.32'),
        peerPort: 51413,
      );

      expect(priority, equals(0xec2d7224));
    });

    test('matches BEP 40 IPv4 example #2', () {
      final priority = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('123.213.32.10'),
        clientPort: 51413,
        peerIp: InternetAddress('123.213.32.234'),
        peerPort: 51413,
      );

      expect(priority, equals(0x99568189));
    });

    test('is symmetric for endpoint order', () {
      final a = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('203.0.113.10'),
        clientPort: 51413,
        peerIp: InternetAddress('198.51.100.7'),
        peerPort: 6881,
      );
      final b = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('198.51.100.7'),
        clientPort: 6881,
        peerIp: InternetAddress('203.0.113.10'),
        peerPort: 51413,
      );

      expect(a, equals(b));
    });

    test('uses ports when IPs are the same', () {
      final p1 = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('127.0.0.1'),
        clientPort: 51413,
        peerIp: InternetAddress('127.0.0.1'),
        peerPort: 6881,
      );
      final p2 = PeerPriority.canonicalPriority(
        clientIp: InternetAddress('127.0.0.1'),
        clientPort: 6881,
        peerIp: InternetAddress('127.0.0.1'),
        peerPort: 51413,
      );

      expect(p1, equals(p2));
    });

    test('provides diverse priorities for different peers', () {
      final clientIp = InternetAddress('203.0.113.50');
      final values = <int>{};
      for (var i = 1; i <= 20; i++) {
        values.add(
          PeerPriority.canonicalPriority(
            clientIp: clientIp,
            clientPort: 51413,
            peerIp: InternetAddress('198.51.100.$i'),
            peerPort: 6000 + i,
          ),
        );
      }

      expect(values.length, greaterThan(5));
    });
  });
}
