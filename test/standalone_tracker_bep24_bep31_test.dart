import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker/tracker/tracker_exception.dart';
import 'package:test/test.dart';

class _StubAnnounceOptionsProvider implements AnnounceOptionsProvider {
  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) async {
    return <String, dynamic>{
      'downloaded': 0,
      'uploaded': 0,
      'left': 0,
      'compact': 1,
      'numwant': 20,
      'port': 6881,
      'peerId': '-DT0201-123456789012',
    };
  }
}

class _FakeTrackerGenerator implements TrackerGenerator {
  @override
  Tracker? createTracker(Uri announce, Uint8List infoHashBuffer,
      AnnounceOptionsProvider provider) {
    return _FakeTracker(announce, infoHashBuffer, provider: provider);
  }
}

class _FakeTracker extends Tracker {
  _FakeTracker(Uri uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super('fake:${uri.host}:${uri.port}', uri, infoHashBuffer,
            provider: provider);

  @override
  Future<PeerEvent?> announce(
      String eventType, Map<String, dynamic> options) async {
    return PeerEvent(
      infoHash,
      announceUrl,
      interval: 3600,
      externalIp: InternetAddress('8.8.8.8'),
    );
  }

  @override
  Future close() async {}
}

void main() {
  group('Standalone tracker BEP 24/31', () {
    late HttpTracker tracker;

    setUp(() {
      tracker = HttpTracker(
        Uri.parse('http://tracker.example.org/announce'),
        Uint8List(20),
        provider: _StubAnnounceOptionsProvider(),
      );
    });

    test('parses external ip and retry in from announce response', () {
      final payload = <String, dynamic>{
        'interval': 1800,
        'external ip': Uint8List.fromList(<int>[1, 2, 3, 4]),
        'retry in': 42,
        'peers': Uint8List(0),
      };

      final event = tracker.processResponseData(
        Uint8List.fromList(encode(payload)),
      );

      expect(event.interval, 1800);
      expect(event.retryIn, 42);
      expect(event.externalIp, isNotNull);
      expect(event.externalIp!.address, '1.2.3.4');
    });

    test('throws TrackerException with retryIn when failure reason exists', () {
      final payload = <String, dynamic>{
        'failure reason': Uint8List.fromList('tracker overloaded'.codeUnits),
        'retry in': 7,
      };

      expect(
        () => tracker.processResponseData(Uint8List.fromList(encode(payload))),
        throwsA(
          isA<TrackerException>().having((e) => e.retryIn, 'retryIn', 7).having(
              (e) => e.failureReason, 'failureReason', 'tracker overloaded'),
        ),
      );
    });

    test('truncates malformed compact peer payload safely', () {
      final payload = <String, dynamic>{
        'interval': 1200,
        // 7 bytes: one full IPv4 compact entry (6 bytes) + trailing garbage.
        'peers': Uint8List.fromList(<int>[1, 2, 3, 4, 0x1A, 0xE1, 0xFF]),
      };

      final event = tracker.processResponseData(
        Uint8List.fromList(encode(payload)),
      );

      expect(event.peers.length, 1);
      final peer = event.peers.first;
      expect(peer.address.address, '1.2.3.4');
      expect(peer.port, 6881);
    });

    test('supports non-compact peer list fallback', () {
      final payload = <String, dynamic>{
        'interval': 1200,
        'peers': <Map<String, dynamic>>[
          <String, dynamic>{'ip': '5.6.7.8', 'port': 6881}
        ],
      };

      final event = tracker.processResponseData(
        Uint8List.fromList(encode(payload)),
      );

      expect(event.peers.length, 1);
      final peer = event.peers.first;
      expect(peer.address.address, '5.6.7.8');
      expect(peer.port, 6881);
    });
  });

  group('Standalone tracker API extensions', () {
    test('stores and exposes tracker external ip', () async {
      final provider = _StubAnnounceOptionsProvider();
      final announceTracker = TorrentAnnounceTracker(
        provider,
        trackerGenerator: _FakeTrackerGenerator(),
      );
      final listener = announceTracker.createListener();
      final uri = Uri.parse('http://tracker.example.org/announce');
      final completer = Completer<void>();
      listener.on<AnnouncePeerEventEvent>((event) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      });

      announceTracker.runTracker(uri, Uint8List(20));
      await completer.future.timeout(const Duration(seconds: 2));

      expect(announceTracker.externalIp, isNotNull);
      expect(announceTracker.externalIp!.address, '8.8.8.8');
      expect(announceTracker.externalIpByTracker[uri], isNotNull);
      expect(announceTracker.externalIpByTracker[uri]!.address, '8.8.8.8');

      listener.dispose();
      await announceTracker.dispose();
    });
  });
}
