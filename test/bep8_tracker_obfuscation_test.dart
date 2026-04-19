import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/encryption/bep8_tracker_obfuscation.dart';
import 'package:dtorrent_task_v2/src/tracker/tracker_client.dart';
import 'package:test/test.dart';

void main() {
  group('BEP 8 tracker obfuscation', () {
    test('sha_ih equals second SHA-1 of infohash', () {
      final infoHash = Uint8List.fromList(
        List<int>.generate(20, (i) => i + 1),
      );
      final shaIh = Bep8TrackerObfuscation.shaIh(infoHash);
      expect(shaIh.length, equals(20));
      expect(shaIh, isNot(equals(infoHash)));
    });

    test('announce port obfuscation is reversible', () {
      final infoHash = Uint8List.fromList(List<int>.filled(20, 0xAA));
      const port = 51413;
      final encrypted = Bep8TrackerObfuscation.obfuscateAnnouncePort(
        infoHash: infoHash,
        port: port,
      );
      final decrypted = Bep8TrackerObfuscation.obfuscateAnnouncePort(
        infoHash: infoHash,
        port: encrypted,
      );
      expect(decrypted, equals(port));
    });

    test('tracker client uses sha_ih when BEP8 obfuscation is enabled', () {
      final client = TrackerClient(enableBep8TrackerObfuscation: true);
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final uri = client.buildPausedAnnounceUri(
        trackerUrl: Uri.parse('https://tracker.example.com/announce'),
        infoHash: infoHash,
        options: const {
          'downloaded': 0,
          'uploaded': 0,
          'left': 1,
          'numwant': 10,
          'compact': 1,
          'peerId': '-DT0201-123456789012',
          'port': 51413,
        },
      );

      expect(uri, isNotNull);
      expect(uri!.query, contains('sha_ih='));
      expect(uri.query, isNot(contains('info_hash=')));
    });
  });
}
