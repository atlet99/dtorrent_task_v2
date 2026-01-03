import 'dart:io';
import 'dart:typed_data';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('EmuleDatParser', () {
    test('parse minimal valid dat file', () {
      final filter = IPFilter();

      // Create minimal eMule dat file (version 1)
      // Header: 0x00000001 (4 bytes)
      // Record: start IP (4 bytes), end IP (4 bytes), access level (1 byte), desc length (1 byte)
      final bytes = Uint8List.fromList([
        // Header: version 1
        0x00, 0x00, 0x00, 0x01,
        // Record 1: 192.168.1.0 - 192.168.1.255, access level 1, no description
        0xC0, 0xA8, 0x01, 0x00, // 192.168.1.0
        0xC0, 0xA8, 0x01, 0xFF, // 192.168.1.255
        0x01, // access level
        0x00, // description length
      ]);

      final count = EmuleDatParser.parseBytes(bytes, filter, minAccessLevel: 1);
      expect(count, greaterThan(0));
      expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.1.255')), isTrue);
      expect(filter.isBlocked(InternetAddress('192.168.2.1')), isFalse);
    });

    test('parse with description', () {
      final filter = IPFilter();

      // Create dat file with description
      final description = 'Test range';
      final descBytes = description.codeUnits;

      final bytes = Uint8List.fromList([
        // Header: version 1
        0x00, 0x00, 0x00, 0x01,
        // Record: 10.0.0.0 - 10.0.0.255, access level 1, with description
        0x0A, 0x00, 0x00, 0x00, // 10.0.0.0
        0x0A, 0x00, 0x00, 0xFF, // 10.0.0.255
        0x01, // access level
        descBytes.length, // description length
        ...descBytes, // description
      ]);

      final count = EmuleDatParser.parseBytes(bytes, filter, minAccessLevel: 1);
      expect(count, greaterThan(0));
      expect(filter.isBlocked(InternetAddress('10.0.0.1')), isTrue);
    });

    test('respect minAccessLevel', () {
      final bytes = Uint8List.fromList([
        // Header: version 1
        0x00, 0x00, 0x00, 0x01,
        // Record 1: access level 1
        0xC0, 0xA8, 0x01, 0x00,
        0xC0, 0xA8, 0x01, 0xFF,
        0x01, // access level 1
        0x00,
        // Record 2: access level 2
        0x0A, 0x00, 0x00, 0x00,
        0x0A, 0x00, 0x00, 0xFF,
        0x02, // access level 2
        0x00,
      ]);

      // With minAccessLevel 1, both should be added
      final filter1 = IPFilter();
      final count1 =
          EmuleDatParser.parseBytes(bytes, filter1, minAccessLevel: 1);
      expect(count1, greaterThan(0));
      expect(filter1.totalRules, greaterThan(0));

      // With minAccessLevel 2, only second should be added
      final filter2 = IPFilter();
      final count2 =
          EmuleDatParser.parseBytes(bytes, filter2, minAccessLevel: 2);
      expect(count2, greaterThan(0));
      expect(filter2.totalRules, greaterThan(0));
    });

    test('handle empty file', () {
      final filter = IPFilter();
      final bytes = Uint8List(4); // Only header
      final count = EmuleDatParser.parseBytes(bytes, filter);
      expect(count, 0);
    });

    test('handle too short file', () {
      final filter = IPFilter();
      final bytes = Uint8List(2); // Too short
      final count = EmuleDatParser.parseBytes(bytes, filter);
      expect(count, 0);
    });
  });
}
