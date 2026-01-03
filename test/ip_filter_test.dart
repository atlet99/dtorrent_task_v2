import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('CIDRBlock', () {
    test('parse valid CIDR notation', () {
      final block = CIDRBlock.parse('192.168.1.0/24');
      expect(block.network.address, '192.168.1.0');
      expect(block.prefixLength, 24);
    });

    test('parse throws on invalid format', () {
      expect(() => CIDRBlock.parse('192.168.1.0'), throwsFormatException);
      expect(() => CIDRBlock.parse('invalid'), throwsFormatException);
    });

    test('parse throws on invalid prefix length', () {
      expect(() => CIDRBlock.parse('192.168.1.0/33'), throwsFormatException);
      expect(() => CIDRBlock.parse('192.168.1.0/-1'), throwsFormatException);
    });

    test('contains IP address', () {
      final block = CIDRBlock.parse('192.168.1.0/24');
      expect(block.contains(InternetAddress('192.168.1.1')), isTrue);
      expect(block.contains(InternetAddress('192.168.1.255')), isTrue);
      expect(block.contains(InternetAddress('192.168.0.1')), isFalse);
      expect(block.contains(InternetAddress('192.168.2.1')), isFalse);
    });

    test('contains with /32 (single IP)', () {
      final block = CIDRBlock.parse('192.168.1.1/32');
      expect(block.contains(InternetAddress('192.168.1.1')), isTrue);
      expect(block.contains(InternetAddress('192.168.1.2')), isFalse);
    });

    test('contains with /16', () {
      final block = CIDRBlock.parse('192.168.0.0/16');
      expect(block.contains(InternetAddress('192.168.1.1')), isTrue);
      expect(block.contains(InternetAddress('192.168.255.255')), isTrue);
      expect(block.contains(InternetAddress('192.169.1.1')), isFalse);
    });

    test('toString returns CIDR notation', () {
      final block = CIDRBlock.parse('192.168.1.0/24');
      expect(block.toString(), '192.168.1.0/24');
    });

    test('equality', () {
      final block1 = CIDRBlock.parse('192.168.1.0/24');
      final block2 = CIDRBlock.parse('192.168.1.0/24');
      final block3 = CIDRBlock.parse('192.168.1.0/25');
      expect(block1 == block2, isTrue);
      expect(block1 == block3, isFalse);
    });
  });

  group('IPFilter', () {
    test('default mode is blacklist', () {
      final filter = IPFilter();
      expect(filter.mode, IPFilterMode.blacklist);
    });

    test('set mode', () {
      final filter = IPFilter();
      filter.setMode(IPFilterMode.whitelist);
      expect(filter.mode, IPFilterMode.whitelist);
      filter.setMode(IPFilterMode.blacklist);
      expect(filter.mode, IPFilterMode.blacklist);
    });

    test('add and remove IP address', () {
      final filter = IPFilter();
      final ip = InternetAddress('192.168.1.1');

      expect(filter.ipCount, 0);
      filter.addIP(ip);
      expect(filter.ipCount, 1);
      expect(filter.ipAddresses.contains(ip), isTrue);

      expect(filter.removeIP(ip), isTrue);
      expect(filter.ipCount, 0);
      expect(filter.removeIP(ip), isFalse);
    });

    test('add IP from string', () {
      final filter = IPFilter();
      filter.addIPFromString('192.168.1.1');
      expect(filter.ipCount, 1);
      expect(
          filter.ipAddresses.contains(InternetAddress('192.168.1.1')), isTrue);
    });

    test('add and remove CIDR block', () {
      final filter = IPFilter();
      final block = CIDRBlock.parse('192.168.1.0/24');

      expect(filter.cidrCount, 0);
      filter.addCIDR(block);
      expect(filter.cidrCount, 1);
      expect(filter.cidrBlocks.contains(block), isTrue);

      expect(filter.removeCIDR(block), isTrue);
      expect(filter.cidrCount, 0);
      expect(filter.removeCIDR(block), isFalse);
    });

    test('add CIDR from string', () {
      final filter = IPFilter();
      filter.addCIDRFromString('192.168.1.0/24');
      expect(filter.cidrCount, 1);
    });

    test('clear all rules', () {
      final filter = IPFilter();
      filter.addIP(InternetAddress('192.168.1.1'));
      filter.addCIDRFromString('10.0.0.0/8');
      expect(filter.totalRules, 2);

      filter.clear();
      expect(filter.totalRules, 0);
      expect(filter.ipCount, 0);
      expect(filter.cidrCount, 0);
    });

    group('blacklist mode', () {
      test('block IPs in filter', () {
        final filter = IPFilter();
        filter.setMode(IPFilterMode.blacklist);
        filter.addIP(InternetAddress('192.168.1.1'));

        expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
        expect(filter.isAllowed(InternetAddress('192.168.1.1')), isFalse);
        expect(filter.isBlocked(InternetAddress('192.168.1.2')), isFalse);
        expect(filter.isAllowed(InternetAddress('192.168.1.2')), isTrue);
      });

      test('block CIDR ranges', () {
        final filter = IPFilter();
        filter.setMode(IPFilterMode.blacklist);
        filter.addCIDRFromString('192.168.1.0/24');

        expect(filter.isBlocked(InternetAddress('192.168.1.1')), isTrue);
        expect(filter.isBlocked(InternetAddress('192.168.1.255')), isTrue);
        expect(filter.isBlocked(InternetAddress('192.168.2.1')), isFalse);
      });
    });

    group('whitelist mode', () {
      test('allow only IPs in filter', () {
        final filter = IPFilter();
        filter.setMode(IPFilterMode.whitelist);
        filter.addIP(InternetAddress('192.168.1.1'));

        expect(filter.isAllowed(InternetAddress('192.168.1.1')), isTrue);
        expect(filter.isBlocked(InternetAddress('192.168.1.1')), isFalse);
        expect(filter.isAllowed(InternetAddress('192.168.1.2')), isFalse);
        expect(filter.isBlocked(InternetAddress('192.168.1.2')), isTrue);
      });

      test('allow only CIDR ranges', () {
        final filter = IPFilter();
        filter.setMode(IPFilterMode.whitelist);
        filter.addCIDRFromString('192.168.1.0/24');

        expect(filter.isAllowed(InternetAddress('192.168.1.1')), isTrue);
        expect(filter.isAllowed(InternetAddress('192.168.1.255')), isTrue);
        expect(filter.isAllowed(InternetAddress('192.168.2.1')), isFalse);
      });
    });

    test('export rules', () {
      final filter = IPFilter();
      filter.addIP(InternetAddress('192.168.1.1'));
      filter.addCIDRFromString('10.0.0.0/8');

      final rules = filter.exportRules();
      expect(rules.length, 2);
      expect(rules, contains('192.168.1.1'));
      expect(rules, contains('10.0.0.0/8'));
    });
  });
}
