import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/task.dart';
import 'package:dtorrent_task_v2/src/tracker/scrape_client.dart';
import 'package:dtorrent_task_v2/src/tracker/tracker_client.dart';
import 'package:test/test.dart';

void main() {
  group('Partial Seeds (BEP 21)', () {
    test('TrackerClient builds paused announce URL for HTTP tracker', () {
      final client = TrackerClient();
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));

      final uri = client.buildPausedAnnounceUri(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        infoHash: infoHash,
        options: {
          'downloaded': 1024,
          'uploaded': 2048,
          'left': 4096,
          'numwant': 25,
          'compact': 1,
          'peerId': '-DT0201-123456789012',
          'port': 51413,
        },
      );

      expect(uri, isNotNull);
      final query = uri!.query;
      expect(query, contains('event=paused'));
      expect(query, contains('downloaded=1024'));
      expect(query, contains('uploaded=2048'));
      expect(query, contains('left=4096'));
      expect(query, contains('port=51413'));
      expect(query, contains('info_hash='));
    });

    test('TrackerClient returns null for UDP paused announce URL', () {
      final client = TrackerClient();
      final infoHash = Uint8List.fromList(List<int>.filled(20, 1));

      final uri = client.buildPausedAnnounceUri(
        trackerUrl: Uri.parse('udp://tracker.example.com:6969/announce'),
        infoHash: infoHash,
        options: const {},
      );

      expect(uri, isNull);
    });

    test('ScrapeStats supports downloaders field', () {
      final stats = ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
        downloaders: 3,
      );

      expect(stats.downloaders, equals(3));
      expect(stats.toString(), contains('downloaders: 3'));
    });

    test('PartialSeedStatus stores status snapshot', () {
      final status = PartialSeedStatus(
        enabled: true,
        isPartialSeed: true,
        completedPieces: 5,
        totalPieces: 20,
        trackerDownloaders: 7,
        lastAnnounceAt: DateTime(2026, 1, 1),
        lastScrapeAt: DateTime(2026, 1, 2),
      );

      expect(status.enabled, isTrue);
      expect(status.isPartialSeed, isTrue);
      expect(status.completedPieces, equals(5));
      expect(status.totalPieces, equals(20));
      expect(status.trackerDownloaders, equals(7));
    });
  });
}
