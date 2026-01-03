import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Proxy Example
///
/// Demonstrates how to use HTTP and SOCKS5 proxies with torrent tasks.
///
/// Features:
/// - HTTP/HTTPS proxy for tracker requests
/// - SOCKS5 proxy for peer connections
/// - Basic authentication support
/// - Dynamic proxy configuration
void main(List<String> args) async {
  // Handle --help
  if (args.contains('--help') || args.contains('-h') || args.isEmpty) {
    _showHelp();
    exit(0);
  }

  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('type',
        abbr: 't',
        help: 'Proxy type: http, https, or socks5',
        allowed: ['http', 'https', 'socks5'],
        defaultsTo: 'http')
    ..addOption('host', abbr: 'h', help: 'Proxy host', defaultsTo: 'localhost')
    ..addOption('port', abbr: 'p', help: 'Proxy port', defaultsTo: '8080')
    ..addOption('username', abbr: 'u', help: 'Proxy username (optional)')
    ..addOption('password', abbr: 'w', help: 'Proxy password (optional)')
    ..addFlag('for-trackers',
        help: 'Use proxy for tracker requests', defaultsTo: true)
    ..addFlag('for-peers',
        help: 'Use proxy for peer connections', defaultsTo: false)
    ..addFlag('test',
        abbr: 'T',
        help: 'Test proxy connection (without torrent)',
        negatable: false);

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print('Error: $e');
    print('');
    _showHelp();
    exit(1);
  }

  final typeStr = results['type'] as String;
  final host = results['host'] as String;
  final portStr = results['port'] as String;
  final username = results['username'] as String?;
  final password = results['password'] as String?;
  final forTrackers = results['for-trackers'] as bool;
  final forPeers = results['for-peers'] as bool;
  final testOnly = results['test'] as bool;

  final port = int.tryParse(portStr);
  if (port == null || port < 1 || port > 65535) {
    print('Error: Invalid port number: $portStr');
    print('Port must be between 1 and 65535');
    exit(1);
  }

  print('Proxy Example');
  print('=' * 60);
  print('Type: $typeStr');
  print('Host: $host');
  print('Port: $port');
  if (username != null) {
    print('Username: $username');
    print('Password: ${password != null ? "***" : "(not set)"}');
  }
  print('For trackers: $forTrackers');
  print('For peers: $forPeers');
  print('');

  // Create proxy configuration
  ProxyConfig config;
  switch (typeStr.toLowerCase()) {
    case 'http':
      config = ProxyConfig.http(
        host: host,
        port: port,
        username: username,
        password: password,
        useForTrackers: forTrackers,
        useForPeers: forPeers,
      );
      break;
    case 'https':
      config = ProxyConfig.https(
        host: host,
        port: port,
        username: username,
        password: password,
        useForTrackers: forTrackers,
        useForPeers: forPeers,
      );
      break;
    case 'socks5':
      config = ProxyConfig.socks5(
        host: host,
        port: port,
        username: username,
        password: password,
        useForTrackers: forTrackers,
        useForPeers: forPeers,
      );
      break;
    default:
      print('Error: Unknown proxy type: $typeStr');
      exit(1);
  }

  print('Proxy configuration created:');
  print('  $config');
  print('');

  // Create proxy manager
  final manager = ProxyManager(config);
  print('Proxy manager created');
  print('  Should use for trackers: ${manager.shouldUseForTrackers()}');
  print('  Should use for peers: ${manager.shouldUseForPeers()}');
  print('');

  if (testOnly) {
    print('Testing proxy connection...');
    print('(This will attempt to connect through the proxy)');
    print('');

    if (config.type == ProxyType.socks5 && manager.socks5Client != null) {
      try {
        // Test SOCKS5 connection to a public server
        final testAddress = InternetAddress('8.8.8.8');
        final testPort = 80;
        print('Testing SOCKS5 connection to $testAddress:$testPort...');
        final socket = await manager.connectThroughProxy(
          testAddress,
          testPort,
          timeout: const Duration(seconds: 10),
        );
        await socket.close();
        print('✓ SOCKS5 proxy connection successful!');
      } catch (e) {
        print('✗ SOCKS5 proxy connection failed: $e');
        print('');
        print('Possible reasons:');
        print('  - Proxy server is not running');
        print('  - Proxy host/port is incorrect');
        print('  - Authentication failed');
        print('  - Network connectivity issue');
        exit(1);
      }
    } else if (config.type == ProxyType.http ||
        config.type == ProxyType.https) {
      print('HTTP proxy testing requires a torrent task.');
      print('Use proxy with a real torrent to test HTTP proxy.');
    }
    print('');
    exit(0);
  }

  print('To use this proxy with a torrent task:');
  print('');
  print('  final proxy = ProxyConfig.$typeStr(');
  print('    host: \'$host\',');
  print('    port: $port,');
  if (username != null) {
    print('    username: \'$username\',');
    if (password != null) {
      print('    password: \'$password\',');
    }
  }
  print('    useForTrackers: $forTrackers,');
  print('    useForPeers: $forPeers,');
  print('  );');
  print('');
  print('  final task = TorrentTask.newTask(');
  print('    torrent,');
  print('    savePath,');
  print('    proxyConfig: proxy,');
  print('  );');
  print('');
  print('  // Or set proxy after task creation:');
  print('  task.setProxyConfig(proxy);');
  print('');
  print('=' * 60);
  print('Example completed!');
  print('');
}

void _showHelp() {
  print('Proxy Example');
  print('');
  print('Usage:');
  print('  dart run example/proxy_example.dart [options]');
  print('');
  print('Options:');
  final helpParser = ArgParser()
    ..addOption('type',
        abbr: 't',
        help: 'Proxy type: http, https, or socks5',
        allowed: ['http', 'https', 'socks5'],
        defaultsTo: 'http')
    ..addOption('host', abbr: 'h', help: 'Proxy host', defaultsTo: 'localhost')
    ..addOption('port', abbr: 'p', help: 'Proxy port', defaultsTo: '8080')
    ..addOption('username', abbr: 'u', help: 'Proxy username (optional)')
    ..addOption('password', abbr: 'w', help: 'Proxy password (optional)')
    ..addFlag('for-trackers',
        help: 'Use proxy for tracker requests', defaultsTo: true)
    ..addFlag('for-peers',
        help: 'Use proxy for peer connections', defaultsTo: false)
    ..addFlag('test',
        abbr: 'T',
        help: 'Test proxy connection (without torrent)',
        negatable: false);
  print(helpParser.usage);
  print('');
  print('Examples:');
  print('  # HTTP proxy for trackers');
  print(
      '  dart run example/proxy_example.dart -t http -h proxy.example.com -p 8080');
  print('');
  print('  # SOCKS5 proxy for peers');
  print(
      '  dart run example/proxy_example.dart -t socks5 -h socks.example.com -p 1080 --for-peers');
  print('');
  print('  # Proxy with authentication');
  print(
      '  dart run example/proxy_example.dart -t http -h proxy.example.com -p 8080 -u user -w pass');
  print('');
  print('  # Test proxy connection');
  print(
      '  dart run example/proxy_example.dart -t socks5 -h socks.example.com -p 1080 --test');
  print('');
}
