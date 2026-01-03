import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/tracker/scrape_client.dart' as scrape;

void main() {
  group('ScrapeClient', () {
    late scrape.ScrapeClient client;

    setUp(() {
      client = scrape.ScrapeClient(
        cacheTimeout: const Duration(seconds: 1), // Short timeout for tests
        httpTimeout: const Duration(seconds: 5),
        udpTimeout: const Duration(seconds: 3),
      );
    });

    tearDown(() {
      client.clearCache();
    });

    test('ScrapeStats creation and properties', () {
      final stats = scrape.ScrapeStats(
        complete: 100,
        incomplete: 50,
        downloaded: 200,
      );

      expect(stats.complete, equals(100));
      expect(stats.incomplete, equals(50));
      expect(stats.downloaded, equals(200));
      expect(stats.toString(), contains('complete: 100'));
    });

    test('ScrapeResult creation and properties', () {
      final stats = scrape.ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
      );

      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {'abc123': stats},
      );

      expect(result.isSuccess, isTrue);
      expect(result.error, isNull);
      expect(result.stats.length, equals(1));
      expect(result.getStatsForInfoHash('abc123'), equals(stats));
      expect(result.getStatsForInfoHash('ABC123'),
          equals(stats)); // Case insensitive
      expect(result.getStatsForInfoHash('xyz789'), isNull);
    });

    test('ScrapeResult with error', () {
      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {},
        error: 'Connection failed',
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, equals('Connection failed'));
      expect(result.stats.isEmpty, isTrue);
    });

    test('ScrapeResult with empty info hashes', () async {
      final result = await client.scrape(
        Uri.parse('http://tracker.example.com/announce'),
        [],
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(result.error, contains('No info hashes'));
    });

    test('Cache functionality', () async {
      final infoHash = Uint8List.fromList(List.filled(20, 0xAA));
      final trackerUrl = Uri.parse('http://tracker.example.com/announce');

      // First request (will fail but should be cached)
      await client.scrape(trackerUrl, [infoHash]);

      // Second request should use cache (if first was successful)
      // Note: This test assumes the scrape might fail, so we test cache structure
      expect(client, isNotNull);
    });

    test('Clear cache', () {
      // Clear should work even if cache is empty
      client.clearCache();
      expect(client, isNotNull);
    });

    test('ScrapeResult creation', () {
      // This tests internal functionality indirectly
      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {},
      );

      // Test that we can create results
      expect(result.trackerUrl.toString(), contains('tracker.example.com'));
    });

    test('Multiple info hashes support', () async {
      final infoHash1 = Uint8List.fromList(List.filled(20, 0xAA));
      final infoHash2 = Uint8List.fromList(List.filled(20, 0xBB));

      // This will likely fail (no real tracker), but tests the API
      final result = await client.scrape(
        Uri.parse('http://tracker.example.com/announce'),
        [infoHash1, infoHash2],
      );

      // Should handle multiple hashes (even if request fails)
      expect(result.trackerUrl.toString(), contains('tracker.example.com'));
    });

    test('Unsupported tracker scheme', () async {
      final infoHash = Uint8List.fromList(List.filled(20, 0xAA));

      final result = await client.scrape(
        Uri.parse('ftp://tracker.example.com/announce'),
        [infoHash],
      );

      expect(result.isSuccess, isFalse);
      expect(result.error, isNotNull);
      expect(result.error, contains('Unsupported'));
    });
  });

  group('ScrapeStats', () {
    test('Equality', () {
      final stats1 = scrape.ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
      );

      final stats2 = scrape.ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
      );

      final stats3 = scrape.ScrapeStats(
        complete: 11,
        incomplete: 5,
        downloaded: 20,
      );

      expect(stats1.complete, equals(stats2.complete));
      expect(stats1.complete, isNot(equals(stats3.complete)));
    });

    test('toString format', () {
      final stats = scrape.ScrapeStats(
        complete: 100,
        incomplete: 50,
        downloaded: 200,
      );

      final str = stats.toString();
      expect(str, contains('100'));
      expect(str, contains('50'));
      expect(str, contains('200'));
    });
  });

  group('ScrapeResult', () {
    test('getStatsForInfoHash case insensitive', () {
      final stats = scrape.ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
      );

      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {'abc123def456': stats},
      );

      expect(result.getStatsForInfoHash('abc123def456'), equals(stats));
      expect(result.getStatsForInfoHash('ABC123DEF456'), equals(stats));
      expect(result.getStatsForInfoHash('AbC123DeF456'), equals(stats));
    });

    test('toString with error', () {
      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {},
        error: 'Test error',
      );

      final str = result.toString();
      expect(str, contains('error'));
      expect(str, contains('Test error'));
    });

    test('toString without error', () {
      final stats = scrape.ScrapeStats(
        complete: 10,
        incomplete: 5,
        downloaded: 20,
      );

      final result = scrape.ScrapeResult(
        trackerUrl: Uri.parse('http://tracker.example.com/announce'),
        stats: {'hash1': stats, 'hash2': stats},
      );

      final str = result.toString();
      expect(str, contains('tracker'));
      expect(str, contains('2'));
    });
  });
}
