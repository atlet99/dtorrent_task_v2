import 'dart:async';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('DHTPubSub (BEP 50)', () {
    test('delivers push updates to subscribed topic', () async {
      final pubSub = DHTPubSub();
      final received = <DHTPubSubMessage>[];
      final sub = pubSub
          .subscribe(topic: 'updates')
          .listen((message) => received.add(message));

      final published = pubSub.publish(
        topic: 'updates',
        payload: 'hello'.codeUnits,
        publisherId: 'node-a',
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(received, hasLength(1));
      expect(received.first.topic, 'updates');
      expect(received.first.payload, 'hello'.codeUnits);
      expect(received.first.publisherId, 'node-a');
      expect(published.sequenceNumber, 1);

      await sub.cancel();
      await pubSub.close();
    });

    test('isolates topics by network', () async {
      final pubSub = DHTPubSub();
      final mainnet = <DHTPubSubMessage>[];
      final testnet = <DHTPubSubMessage>[];

      final subMain = pubSub
          .subscribe(topic: 'announcements', network: 'mainnet')
          .listen(mainnet.add);
      final subTest = pubSub
          .subscribe(topic: 'announcements', network: 'testnet')
          .listen(testnet.add);

      pubSub.publish(
        topic: 'announcements',
        network: 'mainnet',
        payload: 'm'.codeUnits,
      );
      pubSub.publish(
        topic: 'announcements',
        network: 'testnet',
        payload: 't'.codeUnits,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(mainnet, hasLength(1));
      expect(testnet, hasLength(1));
      expect(mainnet.first.network, 'mainnet');
      expect(testnet.first.network, 'testnet');

      await subMain.cancel();
      await subTest.cancel();
      await pubSub.close();
    });

    test('tracks known topics and increments sequence numbers', () async {
      final pubSub = DHTPubSub();
      unawaited(pubSub.subscribe(topic: 'topic-a').drain<void>());

      final m1 = pubSub.publish(topic: 'topic-a', payload: [1]);
      final m2 = pubSub.publish(topic: 'topic-a', payload: [2]);

      expect(m1.sequenceNumber, 1);
      expect(m2.sequenceNumber, 2);
      expect(pubSub.topics, contains('default::topic-a'));

      await pubSub.close();
    });
  });
}
