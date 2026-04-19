import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/ssl/ssl_config.dart';
import 'package:dtorrent_task_v2/src/tracker/tracker_client.dart';
import 'package:test/test.dart';

void main() {
  group('SSLConfig', () {
    test('default config validates certificates', () {
      const config = SSLConfig();
      expect(config.validateCertificates, isTrue);
      expect(config.allowSelfSigned, isFalse);
      expect(config.enableForPeers, isFalse);
    });

    test('self-signed mode allows bad certificates callback', () {
      const config = SSLConfig(
        validateCertificates: true,
        allowSelfSigned: true,
      );

      // Callback should allow certs in self-signed mode.
      expect(config.onBadCertificate, isA<Function>());
    });
  });

  group('TrackerClient HTTPS support', () {
    test('buildPausedAnnounceUri works for https tracker', () {
      final client = TrackerClient(
        sslConfig: const SSLConfig(validateCertificates: true),
      );

      final uri = client.buildPausedAnnounceUri(
        trackerUrl: Uri.parse('https://tracker.example.com/announce'),
        infoHash: Uint8List.fromList(List<int>.filled(20, 1)),
        options: const {
          'downloaded': 0,
          'uploaded': 0,
          'left': 10,
          'numwant': 1,
          'compact': 1,
          'peerId': '-DT0201-123456789012',
          'port': 51413,
        },
      );

      expect(uri, isNotNull);
      expect(uri!.scheme, equals('https'));
      expect(uri.query, contains('event=paused'));
    });
  });
}
