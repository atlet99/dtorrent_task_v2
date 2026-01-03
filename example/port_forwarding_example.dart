import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_task_v2/src/nat/port_forwarding_manager.dart';

/// Example demonstrating UPnP and NAT-PMP port forwarding functionality
///
/// This example shows how to:
/// - Discover available port forwarding methods (UPnP/NAT-PMP)
/// - Forward ports automatically
/// - Get external IP address
/// - Remove port forwardings
///
/// Usage:
///   dart run example/port_forwarding_example.dart --port 6881
///   dart run example/port_forwarding_example.dart -p 6881 --method upnp
///   dart run example/port_forwarding_example.dart -p 6881 --method natpmp
void main(List<String> args) async {
  // Handle --help before parsing
  if (args.contains('--help') || args.contains('-h') || args.isEmpty) {
    _showHelp();
    exit(0);
  }

  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', help: 'Port to forward', defaultsTo: '6881')
    ..addOption('method',
        abbr: 'm',
        help: 'Port forwarding method: auto, upnp, or natpmp',
        allowed: ['auto', 'upnp', 'natpmp'],
        defaultsTo: 'auto')
    ..addFlag('discover-only',
        abbr: 'd',
        help: 'Only discover available methods, do not forward port',
        negatable: false)
    ..addFlag('remove',
        abbr: 'r',
        help: 'Remove port forwarding instead of adding',
        negatable: false)
    ..addFlag('external-ip',
        abbr: 'e', help: 'Get external IP address', negatable: false);

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print('Error: $e');
    print('');
    _showHelp();
    exit(1);
  }

  final portStr = results['port'] as String;
  final methodStr = results['method'] as String;
  final discoverOnly = results['discover-only'] as bool;
  final remove = results['remove'] as bool;
  final getExternalIP = results['external-ip'] as bool;

  final port = int.tryParse(portStr);
  if (port == null || port < 1 || port > 65535) {
    print('Error: Invalid port number: $portStr');
    print('Port must be between 1 and 65535');
    exit(1);
  }

  // Parse method
  PortForwardingMethod method;
  switch (methodStr.toLowerCase()) {
    case 'upnp':
      method = PortForwardingMethod.upnp;
      break;
    case 'natpmp':
      method = PortForwardingMethod.natpmp;
      break;
    case 'auto':
    default:
      method = PortForwardingMethod.auto;
      break;
  }

  print('Port Forwarding Example');
  print('=' * 60);
  print('Port: $port');
  print('Method: $methodStr');
  print('');

  // Create port forwarding manager
  final manager = PortForwardingManager(
    preferredMethod: method,
    timeout: const Duration(seconds: 10),
  );

  try {
    // Discover available method
    print('Discovering port forwarding method...');
    print('(Trying UPnP first, then NAT-PMP if needed...)');
    print('(This may take up to 10 seconds...)');
    print('');

    final stopwatch = Stopwatch()..start();
    final discoveredMethod = await manager.discover();
    stopwatch.stop();

    if (discoveredMethod == null) {
      print('✗ No port forwarding method available');
      print('(Discovery took ${stopwatch.elapsedMilliseconds}ms)');
      print('');
      print('Possible reasons:');
      print('  - Router does not support UPnP or NAT-PMP');
      print('  - UPnP/NAT-PMP is disabled on router');
      print('  - Not connected to a local network');
      print('  - Firewall blocking discovery packets');
      print('  - Router is not responding');
      exit(1);
    }

    print('✓ Port forwarding method available: $discoveredMethod');
    print('');

    // Get external IP if requested
    if (getExternalIP) {
      print('Getting external IP address...');
      final externalIP = await manager.getExternalIP();
      if (externalIP != null) {
        print('✓ External IP: ${externalIP.address}');
      } else {
        print('✗ Failed to get external IP');
      }
      print('');
    }

    // If discover-only, exit here
    if (discoverOnly) {
      print('Discovery complete. Exiting.');
      await manager.removeAllPortForwardings();
      exit(0);
    }

    // Remove port forwarding if requested
    if (remove) {
      print('Removing port forwarding for port $port...');
      final success = await manager.removePortForwarding(port: port);

      if (success) {
        print('✓ Port forwarding removed successfully');
      } else {
        print('✗ Failed to remove port forwarding');
        print('  Port may not be in active mappings');
      }
      print('');
      exit(success ? 0 : 1);
    }

    // Forward port
    print('Forwarding port $port...');
    print('');

    final result = await manager.forwardPort(
      port: port,
      protocol: 'TCP',
      description: 'dtorrent_task_v2_example',
      leaseDuration: 3600, // 1 hour
    );

    if (result.success) {
      print('✓ Port forwarding successful!');
      print('');
      print('Details:');
      print('  Method: ${result.method}');
      if (result.externalIP != null) {
        print('  External IP: ${result.externalIP!.address}');
      }
      print('  Port: $port');
      print('  Protocol: TCP');
      print('');

      // Show active mappings
      final activeMappings = manager.activeMappings;
      if (activeMappings.isNotEmpty) {
        print('Active port mappings:');
        for (var entry in activeMappings.entries) {
          print('  Port ${entry.key}: ${entry.value}');
        }
        print('');
      }

      print('Port forwarding is active.');
      print('Press Ctrl+C to stop and remove port forwarding...');
      print('');

      // Wait for user interrupt
      try {
        await Future.delayed(const Duration(hours: 24));
      } catch (e) {
        // Ignore
      }
    } else {
      print('✗ Port forwarding failed: ${result.error}');
      print('');
      print('Possible reasons:');
      print('  - Port is already in use');
      print('  - Router rejected the request');
      print('  - Network configuration issue');
      exit(1);
    }
  } catch (e, stackTrace) {
    print('✗ Error: $e');
    print('');
    print('Stack trace:');
    print(stackTrace);
    exit(1);
  } finally {
    // Cleanup
    print('');
    print('Cleaning up...');
    await manager.removeAllPortForwardings();
    print('Done!');
  }
}

/// Show help message
void _showHelp() {
  print('Port Forwarding Example');
  print('');
  print('Usage:');
  print('  dart run example/port_forwarding_example.dart [options]');
  print('');
  print('Options:');
  print('  -p, --port          Port to forward (default: 6881)');
  print(
      '  -m, --method        Port forwarding method: auto, upnp, or natpmp (default: auto)');
  print(
      '  -d, --discover-only Only discover available methods, do not forward port');
  print('  -r, --remove        Remove port forwarding instead of adding');
  print('  -e, --external-ip   Get external IP address');
  print('  -h, --help          Show this help message');
  print('');
  print('Examples:');
  print('  dart run example/port_forwarding_example.dart --port 6881');
  print('  dart run example/port_forwarding_example.dart -p 6881 -m upnp');
  print('  dart run example/port_forwarding_example.dart -d');
  print('  dart run example/port_forwarding_example.dart -p 6881 -e');
  print('  dart run example/port_forwarding_example.dart -p 6881 -r');
}
