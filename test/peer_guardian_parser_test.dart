import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('PeerGuardianParser', () {
    test('parse single IP', () {
      final filter = IPFilter();
      final count = PeerGuardianParser.parseString('192.168.1.1', filter);
      expect(count, 1);
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
    });

    test('parse CIDR notation', () {
      final filter = IPFilter();
      final count = PeerGuardianParser.parseString('192.168.1.0/24', filter);
      expect(count, 1);
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.1.255')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.2.1')), isFalse);
    });

    test('parse IP range', () {
      final filter = IPFilter();
      final count =
          PeerGuardianParser.parseString('192.168.1.0-192.168.1.255', filter);
      expect(count, greaterThan(0));
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.1.255')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.2.1')), isFalse);
    });

    test('parse with description', () {
      final filter = IPFilter();
      final count = PeerGuardianParser.parseString(
          '192.168.1.1 : Some description', filter);
      expect(count, 1);
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
    });

    test('parse multiple lines', () {
      final filter = IPFilter();
      final content = '''
192.168.1.1
10.0.0.0/8
172.16.0.0-172.16.255.255
''';
      final count = PeerGuardianParser.parseString(content, filter);
      expect(count, greaterThanOrEqualTo(3));
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
      expect(filter.isBlocked(InternetAddress('10.0.0.1')), isTrue);
      expect(filter.isBlocked(InternetAddress('172.16.1.1')), isTrue);
    });

    test('ignore comments', () {
      final filter = IPFilter();
      final content = '''
# This is a comment
192.168.1.1
# Another comment
10.0.0.0/8
''';
      final count = PeerGuardianParser.parseString(content, filter);
      expect(count, 2);
    });

    test('ignore empty lines', () {
      final filter = IPFilter();
      final content = '''

192.168.1.1


10.0.0.0/8

''';
      final count = PeerGuardianParser.parseString(content, filter);
      expect(count, 2);
    });

    test('handle invalid lines gracefully', () {
      final filter = IPFilter();
      final content = '''
192.168.1.1
invalid line
10.0.0.0/8
''';
      // Should not throw, but may skip invalid lines
      expect(() => PeerGuardianParser.parseString(content, filter),
          returnsNormally);
    });
  });
}
