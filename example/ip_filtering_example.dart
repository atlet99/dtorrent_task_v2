import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// IP Filtering Example
///
/// Demonstrates how to use IP filtering to block/allow peer connections
/// based on IP addresses and CIDR blocks.
///
/// Features:
/// - Add/remove IP addresses and CIDR blocks
/// - Blacklist and whitelist modes
/// - Load filters from eMule dat and PeerGuardian formats
/// - Dynamic filter updates
void main(List<String> args) async {
  // Handle --help
  if (args.contains('--help') || args.contains('-h') || args.isEmpty) {
    _showHelp();
    exit(0);
  }

  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('mode',
        abbr: 'm',
        help: 'Filter mode: blacklist or whitelist',
        allowed: ['blacklist', 'whitelist'],
        defaultsTo: 'blacklist')
    ..addMultiOption('ip', abbr: 'i', help: 'Add IP address(es) to filter')
    ..addMultiOption('cidr',
        abbr: 'c', help: 'Add CIDR block(s) to filter (e.g., 192.168.1.0/24)')
    ..addOption('emule-dat', help: 'Load filter from eMule dat file')
    ..addOption('peer-guardian',
        help: 'Load filter from PeerGuardian format file')
    ..addFlag('test',
        abbr: 't', help: 'Test IP addresses against filter', negatable: false)
    ..addMultiOption('test-ip', help: 'IP address(es) to test against filter');

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print('Error: $e');
    print('');
    _showHelp();
    exit(1);
  }

  // Create IP filter
  final filter = IPFilter();

  // Set mode
  final modeStr = results['mode'] as String;
  final mode =
      modeStr == 'whitelist' ? IPFilterMode.whitelist : IPFilterMode.blacklist;
  filter.setMode(mode);
  print('IP Filter Example');
  print('=' * 60);
  print('Mode: $modeStr');
  print('');

  // Load from eMule dat file
  final emuleDat = results['emule-dat'] as String?;
  if (emuleDat != null) {
    print('Loading eMule dat file: $emuleDat');
    try {
      final count = await EmuleDatParser.parseFile(emuleDat, filter);
      print('  ✓ Loaded $count rules from eMule dat file');
    } catch (e) {
      print('  ✗ Failed to load eMule dat file: $e');
      exit(1);
    }
    print('');
  }

  // Load from PeerGuardian file
  final peerGuardian = results['peer-guardian'] as String?;
  if (peerGuardian != null) {
    print('Loading PeerGuardian file: $peerGuardian');
    try {
      final count = await PeerGuardianParser.parseFile(peerGuardian, filter);
      print('  ✓ Loaded $count rules from PeerGuardian file');
    } catch (e) {
      print('  ✗ Failed to load PeerGuardian file: $e');
      exit(1);
    }
    print('');
  }

  // Add IP addresses
  final ips = results['ip'] as List<String>;
  if (ips.isNotEmpty) {
    print('Adding IP addresses:');
    for (final ipStr in ips) {
      filter.addIPFromString(ipStr);
      print('  ✓ Added: $ipStr');
    }
    print('');
  }

  // Add CIDR blocks
  final cidrs = results['cidr'] as List<String>;
  if (cidrs.isNotEmpty) {
    print('Adding CIDR blocks:');
    for (final cidrStr in cidrs) {
      filter.addCIDRFromString(cidrStr);
      print('  ✓ Added: $cidrStr');
    }
    print('');
  }

  // Show filter statistics
  print('Filter Statistics:');
  print('  Total rules: ${filter.totalRules}');
  print('  IP addresses: ${filter.ipCount}');
  print('  CIDR blocks: ${filter.cidrCount}');
  print('');

  // Test IP addresses
  final testMode = results['test'] as bool;
  final testIPs = results['test-ip'] as List<String>;
  if (testMode || testIPs.isNotEmpty) {
    print('Testing IP addresses:');
    print('');

    final ipsToTest = testIPs.isNotEmpty
        ? testIPs
        : [
            '192.168.1.1',
            '10.0.0.1',
            '172.16.0.1',
            '8.8.8.8',
          ];

    for (final ipStr in ipsToTest) {
      final ip = InternetAddress.tryParse(ipStr);
      if (ip == null) {
        print('  ✗ Invalid IP: $ipStr');
        continue;
      }

      final isBlocked = filter.isBlocked(ip);
      final status = isBlocked ? 'BLOCKED' : 'ALLOWED';
      final symbol = isBlocked ? '✗' : '✓';

      print('  $symbol $ipStr: $status');
    }
    print('');
  }

  // Export rules
  print('Exported rules (first 10):');
  final rules = filter.exportRules();
  for (var i = 0; i < rules.length && i < 10; i++) {
    print('  ${i + 1}. ${rules[i]}');
  }
  if (rules.length > 10) {
    print('  ... and ${rules.length - 10} more');
  }
  print('');

  print('=' * 60);
  print('Example completed!');
  print('');
  print('To use this filter with a torrent task:');
  print('  final filter = IPFilter();');
  print('  filter.addCIDRFromString("192.168.1.0/24");');
  print('  filter.setMode(IPFilterMode.blacklist);');
  print('  task.setIPFilter(filter);');
  print('');
}

void _showHelp() {
  print('IP Filtering Example');
  print('');
  print('Usage:');
  print('  dart run example/ip_filtering_example.dart [options]');
  print('');
  print('Options:');
  final helpParser = ArgParser()
    ..addOption('mode',
        abbr: 'm',
        help: 'Filter mode: blacklist or whitelist',
        allowed: ['blacklist', 'whitelist'],
        defaultsTo: 'blacklist')
    ..addMultiOption('ip', abbr: 'i', help: 'Add IP address(es) to filter')
    ..addMultiOption('cidr',
        abbr: 'c', help: 'Add CIDR block(s) to filter (e.g., 192.168.1.0/24)')
    ..addOption('emule-dat', help: 'Load filter from eMule dat file')
    ..addOption('peer-guardian',
        help: 'Load filter from PeerGuardian format file')
    ..addFlag('test',
        abbr: 't', help: 'Test IP addresses against filter', negatable: false)
    ..addMultiOption('test-ip', help: 'IP address(es) to test against filter');
  print(helpParser.usage);
  print('');
  print('Examples:');
  print('  # Add IP addresses and CIDR blocks');
  print(
      '  dart run example/ip_filtering_example.dart -i 192.168.1.1 -c 10.0.0.0/8');
  print('');
  print('  # Load from PeerGuardian file and test');
  print(
      '  dart run example/ip_filtering_example.dart --peer-guardian filter.txt --test');
  print('');
  print('  # Whitelist mode with CIDR');
  print(
      '  dart run example/ip_filtering_example.dart -m whitelist -c 192.168.0.0/16');
  print('');
}
