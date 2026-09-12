import 'dart:async';

import 'package:dtorrent_task_v2/src/standalone/dht/standalone_dht.dart';
import 'package:test/test.dart';

void main() {
  group('DHT bootstrap regression (unroutable nodes, dead sockets)', () {
    test('skips unroutable bootstrap node without send failure', () async {
      final driver = InRepoStandaloneDHTDriver();
      final errors = <StandaloneDHTDriverErrorEvent>[];
      final listener = driver.events.listen((event) {
        if (event is StandaloneDHTDriverErrorEvent) errors.add(event);
      });

      driver.clearBootstrapNodes();
      await driver.addBootstrapNode(Uri.parse('udp://0.0.0.0:6881'));

      final port = await driver.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port, isNotNull);
      expect(errors, isEmpty);

      await listener.cancel();
      await driver.stop();
    });

    test('skips IPv6 and broadcast unroutable bootstrap nodes', () async {
      final driver = InRepoStandaloneDHTDriver();
      final errors = <StandaloneDHTDriverErrorEvent>[];
      final listener = driver.events.listen((event) {
        if (event is StandaloneDHTDriverErrorEvent) errors.add(event);
      });

      driver.clearBootstrapNodes();
      await driver.addBootstrapNode(Uri.parse('udp://[::]:6881'));
      await driver.addBootstrapNode(Uri.parse('udp://255.255.255.255:6881'));

      final port = await driver.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port, isNotNull);
      expect(errors, isEmpty);

      await listener.cancel();
      await driver.stop();
    });

    test('clearBootstrapNodes replaces built-in router list', () async {
      final driver = InRepoStandaloneDHTDriver();
      final errors = <StandaloneDHTDriverErrorEvent>[];
      final listener = driver.events.listen((event) {
        if (event is StandaloneDHTDriverErrorEvent) errors.add(event);
      });

      driver.clearBootstrapNodes();
      await driver.addBootstrapNode(Uri.parse('udp://0.0.0.0:6881'));

      final port = await driver.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port, isNotNull);
      for (final error in errors) {
        expect(
            error.message.contains('router.bittorrent.com') ||
                error.message.contains('router.utorrent.com') ||
                error.message.contains('dht.transmissionbt.com'),
            isFalse,
            reason: 'built-in router must not be contacted after clear');
      }

      await listener.cancel();
      await driver.stop();
    });

    test('adapter reports port without retries for unroutable node', () async {
      final driver = InRepoStandaloneDHTDriver();
      final dht = BittorrentDHTAdapter(
        driver: driver,
        bootstrapMaxAttempts: 3,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        retryJitterRatio: 0,
      );

      final retries = <StandaloneDHTRetryEvent>[];
      final errors = <StandaloneDHTErrorEvent>[];
      final listener = dht.createListener();
      listener
        ..on<StandaloneDHTRetryEvent>(retries.add)
        ..on<StandaloneDHTErrorEvent>(errors.add);

      dht.clearBootstrapNodes();
      await dht.addBootstrapNode(Uri.parse('udp://0.0.0.0:6881'));

      final port = await dht.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port, isNotNull);
      expect(retries, isEmpty);
      expect(errors, isEmpty);

      listener.dispose();
      await dht.stop();
    });

    test('facade clearBootstrapNodes delegates to driver', () async {
      final dht = StandaloneDHT();

      dht.clearBootstrapNodes();
      final port = await dht.bootstrap();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(port, isNotNull);

      await dht.stop();
    });
  });
}
