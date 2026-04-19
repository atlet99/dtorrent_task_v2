import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker.dart';
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

void main() {
  group('Standalone Tracker Migration', () {
    test('BaseTrackerGenerator creates HTTP and UDP trackers', () {
      final generator = TrackerGenerator.base();
      final provider = _StubAnnounceOptionsProvider();
      final infoHash = Uint8List(20);

      final http = generator.createTracker(
        Uri.parse('http://tracker.example.org/announce'),
        infoHash,
        provider,
      );
      final udp = generator.createTracker(
        Uri.parse('udp://tracker.example.org:6969/announce'),
        infoHash,
        provider,
      );
      final unsupported = generator.createTracker(
        Uri.parse('ws://tracker.example.org/announce'),
        infoHash,
        provider,
      );

      expect(http, isA<HttpTracker>());
      expect(udp, isA<UDPTracker>());
      expect(unsupported, isNull);
    });

    test('TorrentAnnounceTracker ignores invalid infohash length', () {
      final tracker = TorrentAnnounceTracker(_StubAnnounceOptionsProvider());
      final invalidInfoHash = Uint8List(19);

      tracker.runTracker(
        Uri.parse('http://tracker.example.org/announce'),
        invalidInfoHash,
      );

      expect(tracker.trackersNum, 0);
      tracker.dispose();
    });

    test('BaseScraperGenerator converts announce URL to scrape URL', () {
      final scraperGenerator = ScraperGenerator.base();
      final scraper = scraperGenerator.createScrape(
        Uri.parse('http://tracker.example.org/announce'),
      );

      expect(scraper, isNotNull);
      expect(
          scraper!.scrapeUrl.toString(), 'http://tracker.example.org/scrape');
    });
  });
}
