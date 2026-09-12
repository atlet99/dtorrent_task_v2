import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Demonstrates the DHT bootstrap regression fixes.
///
/// - unroutable addresses (0.0.0.0, ::, broadcast) are skipped
/// - dead sockets are dropped so the next bootstrap binds new ones
/// - clearBootstrapNodes() lets callers replace the built-in router list
Future<void> main() async {
  final dht = StandaloneDHT();

  // Replace the built-in router list with custom nodes.
  dht.clearBootstrapNodes();
  await dht.addBootstrapNode(Uri.parse('udp://0.0.0.0:6881'));

  // Even an unroutable node must not take bootstrap down.
  final port = await dht.bootstrap();
  print('DHT bound to port: $port');

  if (port != null) {
    print('DHT is up, announce can proceed');
  } else {
    print('DHT bootstrap failed, announce is skipped');
  }

  await dht.stop();
}
