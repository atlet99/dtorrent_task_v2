import 'dart:async';

import 'package:dtorrent_task_v2/src/standalone/dht/standalone_dht.dart';
import 'package:test/test.dart';

class _FakeDHTDriver implements StandaloneDHTDriver {
  final StreamController<StandaloneDHTDriverEvent> _events =
      StreamController<StandaloneDHTDriverEvent>.broadcast();

  int bootstrapCalls = 0;
  int announceCalls = 0;
  int requestPeersCalls = 0;
  int stopCalls = 0;
  int addNodeCalls = 0;

  int failBootstrapAttempts = 0;
  int failAnnounceAttempts = 0;
  int failRequestPeersAttempts = 0;

  @override
  Stream<StandaloneDHTDriverEvent> get events => _events.stream;

  @override
  Future<int?> bootstrap({int port = 0}) async {
    bootstrapCalls++;
    if (bootstrapCalls <= failBootstrapAttempts) {
      throw StateError('bootstrap failure #$bootstrapCalls');
    }
    return 7777;
  }

  @override
  void announce(String infoHash, int port) {
    announceCalls++;
    if (announceCalls <= failAnnounceAttempts) {
      throw StateError('announce failure #$announceCalls');
    }
  }

  @override
  void requestPeers(String infoHash) {
    requestPeersCalls++;
    if (requestPeersCalls <= failRequestPeersAttempts) {
      throw StateError('requestPeers failure #$requestPeersCalls');
    }
  }

  @override
  Future<void> addBootstrapNode(Uri url) async {
    addNodeCalls++;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
    if (!_events.isClosed) {
      await _events.close();
    }
  }

  void emitNewPeer(int i) {
    _events.add(
      StandaloneDHTDriverNewPeerEvent(
        address: Object(),
        infoHash: 'peer-$i',
      ),
    );
  }
}

void main() {
  group('StandaloneDHT', () {
    test('should create standalone DHT facade', () {
      final dht = StandaloneDHT();
      expect(dht, isNotNull);
    });

    test('should stop idempotently', () async {
      final dht = StandaloneDHT();

      await dht.stop();
      await dht.stop();

      expect(true, isTrue);
    });

    test('should allow safe no-op calls after stop', () async {
      final dht = StandaloneDHT();

      await dht.stop();
      dht.announce('12345678901234567890', 6881);
      dht.requestPeers('12345678901234567890');

      expect(true, isTrue);
    });

    test('should accept bootstrap node before bootstrap', () async {
      final dht = StandaloneDHT();

      await dht.addBootstrapNode(Uri.parse('udp://127.0.0.1:6881'));
      await dht.stop();

      expect(true, isTrue);
    });

    test('should retry bootstrap on failures and then succeed', () async {
      final driver = _FakeDHTDriver()..failBootstrapAttempts = 2;
      final dht = BittorrentDHTAdapter(
        driver: driver,
        bootstrapMaxAttempts: 3,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        retryJitterRatio: 0,
      );

      final retries = <StandaloneDHTRetryEvent>[];
      final listener = dht.createListener();
      listener.on<StandaloneDHTRetryEvent>(retries.add);

      final port = await dht.bootstrap();

      expect(port, 7777);
      expect(driver.bootstrapCalls, 3);
      expect(retries.length, 2);
      expect(retries.every((e) => e.operation == 'bootstrap'), isTrue);

      listener.dispose();
      await dht.stop();
    });

    test('should retry requestPeers once when first attempt fails', () async {
      final driver = _FakeDHTDriver()..failRequestPeersAttempts = 1;
      final dht = BittorrentDHTAdapter(
        driver: driver,
        operationMaxAttempts: 2,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        retryJitterRatio: 0,
      );

      final retries = <StandaloneDHTRetryEvent>[];
      final listener = dht.createListener();
      listener.on<StandaloneDHTRetryEvent>(retries.add);

      dht.requestPeers('12345678901234567890');
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(driver.requestPeersCalls, 2);
      expect(retries.length, 1);
      expect(retries.first.operation, 'requestPeers');

      listener.dispose();
      await dht.stop();
    });

    test('should retry announce once when first attempt fails', () async {
      final driver = _FakeDHTDriver()..failAnnounceAttempts = 1;
      final dht = BittorrentDHTAdapter(
        driver: driver,
        operationMaxAttempts: 2,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        retryJitterRatio: 0,
      );

      final retries = <StandaloneDHTRetryEvent>[];
      final listener = dht.createListener();
      listener.on<StandaloneDHTRetryEvent>(retries.add);

      dht.announce('12345678901234567890', 6881);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(driver.announceCalls, 2);
      expect(retries.length, 1);
      expect(retries.first.operation, 'announce');

      listener.dispose();
      await dht.stop();
    });

    test('should handle peer event floods without dropping stream', () async {
      final driver = _FakeDHTDriver();
      final dht = BittorrentDHTAdapter(
        driver: driver,
        retryBaseDelay: Duration.zero,
        retryMaxDelay: Duration.zero,
        retryJitterRatio: 0,
      );

      var peers = 0;
      final listener = dht.createListener();
      listener.on<StandaloneDHTNewPeerEvent>((_) => peers++);

      for (var i = 0; i < 1000; i++) {
        driver.emitNewPeer(i);
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(peers, 1000);

      listener.dispose();
      await dht.stop();
    });
  });
}
