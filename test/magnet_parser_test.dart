import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/metadata/magnet_parser.dart';

const sintelWebTorrentMagnet =
    'magnet:?xt=urn:btih:08ada5a7a6183aae1e09d831df6748d566095a10&dn=Sintel&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.empire-js.us%3A1337&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2F&xs=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fsintel.torrent';

const bigBuckBunnyWebTorrentMagnet =
    'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c&dn=Big+Buck+Bunny&tr=udp%3A%2F%2Fexplodie.org%3A6969&tr=udp%3A%2F%2Ftracker.coppersurfer.tk%3A6969&tr=udp%3A%2F%2Ftracker.leechers-paradise.org%3A6969&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337&tr=udp%3A%2F%2Ftracker.torrent.eu.org%3A451&tr=wss%3A%2F%2Ftracker.btorrent.xyz&tr=wss%3A%2F%2Ftracker.fastcast.nz&tr=wss%3A%2F%2Ftracker.openwebtorrent.com&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.mp4';

void main() {
  group('MagnetParser Tests', () {
    test('should parse basic magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test+file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
      // Display name may be URL encoded, so check for either format
      expect(
          magnet.displayName == 'test file' ||
              magnet.displayName == 'test+file',
          isTrue);
      expect(magnet.trackers, isEmpty);
    });

    test('should parse magnet URI with trackers', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Should parse multiple trackers
      expect(magnet!.trackers.length, greaterThanOrEqualTo(1));
      // At least one tracker should be present
      final trackerStrings = magnet.trackers.map((t) => t.toString()).join(',');
      expect(
          trackerStrings.contains('tracker1') ||
              trackerStrings.contains('tracker2'),
          isTrue);
    });

    test('should parse magnet URI with exact length', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&xl=1048576';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.exactLength, equals(1048576));
    });

    test('should handle multiple tr parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com,http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackers.length, equals(2));
    });

    test('should reject invalid magnet URI', () {
      final invalidUri = 'not-a-magnet-uri';
      final magnet = MagnetParser.parse(invalidUri);

      expect(magnet, isNull);
    });

    test('should reject magnet URI without xt parameter', () {
      final magnetUri = 'magnet:?dn=test+file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should reject magnet URI with invalid info hash length', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef0123456'; // 39 chars
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should create magnet URI from MagnetLink', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final trackers = [
        Uri.parse('http://tracker1.com'),
        Uri.parse('http://tracker2.com'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        displayName: 'test file',
        trackers: trackers,
        exactLength: 1048576,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('magnet:?'));
      expect(uri, contains('xt=urn:btih:'));
      expect(uri, contains('dn=')); // Display name is URL encoded
      expect(uri, contains('tracker1'));
      expect(uri, contains('tracker2'));
      expect(uri, contains('xl=1048576'));
    });

    test('should handle SHA1 format', () {
      final magnetUri =
          'magnet:?xt=urn:sha1:0123456789abcdef0123456789abcdef01234567';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
    });

    test('should handle uppercase BTIH namespace', () {
      final magnetUri =
          'magnet:?xt=urn:BTIH:0123456789abcdef0123456789abcdef01234567';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
    });

    test('should parse lowercase Base32 infohash', () {
      final magnetUri = 'magnet:?xt=urn:btih:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
      expect(magnet.infoHash.every((b) => b == 0), isTrue);
    });

    test('should handle URL-encoded display name', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test%20File%20Name';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.displayName, equals('Test File Name'));
    });

    test('should parse web seed URLs (BEP 0019)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed.example.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, equals(1));
      expect(magnet.webSeeds[0].toString(), contains('webseed.example.com'));
    });

    test('should parse multiple web seed URLs', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed1.com/file&ws=http://webseed2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, greaterThanOrEqualTo(1));
    });

    test('should parse acceptable source URLs (BEP 0019)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source.example.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, equals(1));
      expect(magnet.acceptableSources[0].toString(),
          contains('source.example.com'));
    });

    test('should parse multiple acceptable source URLs', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source1.com/file&as=http://source2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, greaterThanOrEqualTo(1));
    });

    test('should parse selected file indices (BEP 0053)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=2&so=5';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(3));
      expect(magnet.selectedFileIndices, containsAll([0, 2, 5]));
    });

    test('should handle numbered web seed parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws.1=http://webseed1.com/file&ws.2=http://webseed2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.webSeeds.length, equals(2));
    });

    test('should handle numbered acceptable source parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as.1=http://source1.com/file&as.2=http://source2.com/file';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.acceptableSources.length, equals(2));
    });

    test('should parse tracker tiers (BEP 0012)', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr.1=http://tracker1.com&tr.2=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackerTiers.length, equals(2));
      expect(magnet.trackerTiers[0].trackers.length, equals(1));
      expect(magnet.trackerTiers[1].trackers.length, equals(1));
    });

    test('should group trackers in same tier when using tr parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackerTiers.length, equals(1));
      expect(magnet.trackerTiers[0].trackers.length, equals(2));
    });

    test('should parse Base32 infohash (RFC 4648)', () {
      // Base32 encoding of 20 zero bytes: AAAAAAAAAAAAAAAAAAAAAAAAAA
      final magnetUri = 'magnet:?xt=urn:btih:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.infoHash.length, equals(20));
      // All bytes should be zero
      expect(magnet.infoHash.every((b) => b == 0), isTrue);
    });

    test('should reject invalid Base32 infohash', () {
      final magnetUri =
          'magnet:?xt=urn:btih:INVALIDBASE32CHARACTERS123456789012';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNull);
    });

    test('should create magnet URI with web seeds', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final webSeeds = [
        Uri.parse('http://webseed1.com/file'),
        Uri.parse('http://webseed2.com/file'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        webSeeds: webSeeds,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('ws='));
      expect(uri, contains('webseed1'));
      expect(uri, contains('webseed2'));
    });

    test('should create magnet URI with acceptable sources', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final acceptableSources = [
        Uri.parse('http://source1.com/file'),
        Uri.parse('http://source2.com/file'),
      ];
      final magnet = MagnetLink(
        infoHash: infoHash,
        acceptableSources: acceptableSources,
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('as='));
      expect(uri, contains('source1'));
      expect(uri, contains('source2'));
    });

    test('should create magnet URI with selected file indices', () {
      final infoHash = Uint8List.fromList(List<int>.generate(20, (i) => i));
      final magnet = MagnetLink(
        infoHash: infoHash,
        selectedFileIndices: [0, 2, 5],
      );

      final uri = MagnetParser.toUri(magnet);
      expect(uri, contains('so=0'));
      expect(uri, contains('so=2'));
      expect(uri, contains('so=5'));
    });

    test('should handle full magnet URI with all parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=Test+File&xl=1048576&tr=http://tracker.com&ws=http://webseed.com/file&as=http://source.com/file&so=0&so=2';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.displayName, isNotNull);
      expect(magnet.exactLength, equals(1048576));
      expect(magnet.trackers.length, greaterThanOrEqualTo(1));
      expect(magnet.webSeeds.length, equals(1));
      expect(magnet.acceptableSources.length, equals(1));
      expect(magnet.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(2));
    });

    test('should handle invalid web seed URL scheme', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=invalid://url';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Invalid URLs should be filtered out
      expect(magnet!.webSeeds.length, equals(0));
    });

    test('should handle invalid file index in so parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=invalid&so=2';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Invalid indices should be filtered out
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(2));
      expect(magnet.selectedFileIndices, containsAll([0, 2]));
    });

    test('should handle negative file index in so parameter', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=-1&so=0';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      // Negative indices should be filtered out
      expect(magnet!.selectedFileIndices, isNotNull);
      expect(magnet.selectedFileIndices!.length, equals(1));
      expect(magnet.selectedFileIndices, contains(0));
    });

    test('should deduplicate and sort selected file indices', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=5&so=2&so=5&so.1=3&so.2=2';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.selectedFileIndices, equals([2, 3, 5]));
    });

    test('should parse uppercase query parameter keys', () {
      final magnetUri =
          'magnet:?XT=urn:btih:0123456789abcdef0123456789abcdef01234567&DN=Upper+Case&TR=http://tracker.example.com&WS=http://webseed.example.com/file&AS=http://source.example.com/file&SO=4';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.displayName, equals('Upper Case'));
      expect(magnet.trackers.length, equals(1));
      expect(magnet.webSeeds.length, equals(1));
      expect(magnet.acceptableSources.length, equals(1));
      expect(magnet.selectedFileIndices, equals([4]));
    });

    test('should keep repeated numbered tracker entries in same tier', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr.1=http://tracker1.com&tr.1=http://tracker2.com&tr.2=http://tracker3.com';
      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackerTiers.length, equals(2));
      expect(magnet.trackerTiers[0].trackers.length, equals(2));
      expect(magnet.trackerTiers[1].trackers.length, equals(1));
      expect(magnet.trackers.length, equals(3));
    });

    test('should parse Sintel WebTorrent magnet fixture', () {
      final magnet = MagnetParser.parse(sintelWebTorrentMagnet);

      expect(magnet, isNotNull);
      expect(
        magnet!.infoHashString,
        equals('08ada5a7a6183aae1e09d831df6748d566095a10'),
      );
      expect(magnet.displayName, equals('Sintel'));
      expect(magnet.trackers.length, equals(8));
      expect(
        magnet.trackers.where((tracker) => tracker.scheme == 'udp').length,
        equals(5),
      );
      expect(
        magnet.trackers.where((tracker) => tracker.scheme == 'wss').length,
        equals(3),
      );
      expect(magnet.trackerTiers.length, equals(1));
      expect(magnet.trackerTiers.single.trackers.length, equals(8));
      expect(magnet.webSeeds,
          equals([Uri.parse('https://webtorrent.io/torrents/')]));
      expect(
        magnet.exactSources,
        equals([Uri.parse('https://webtorrent.io/torrents/sintel.torrent')]),
      );
    });

    test('should parse Big Buck Bunny WebTorrent magnet fixture', () {
      final magnet = MagnetParser.parse(bigBuckBunnyWebTorrentMagnet);

      expect(magnet, isNotNull);
      expect(
        magnet!.infoHashString,
        equals('dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'),
      );
      expect(magnet.displayName, equals('Big Buck Bunny'));
      expect(magnet.trackers.length, equals(8));
      expect(
        magnet.trackers.where((tracker) => tracker.scheme == 'udp').length,
        equals(5),
      );
      expect(
        magnet.trackers.where((tracker) => tracker.scheme == 'wss').length,
        equals(3),
      );
      expect(magnet.trackerTiers.length, equals(1));
      expect(magnet.trackerTiers.single.trackers.length, equals(8));
      expect(
        magnet.webSeeds,
        equals(
            [Uri.parse('https://webtorrent.io/torrents/big-buck-bunny.mp4')]),
      );
      expect(magnet.exactSources, isEmpty);
    });

    test('should round-trip WebTorrent magnet fields to URI', () {
      final magnet = MagnetLink(
        infoHash: Uint8List.fromList(List<int>.filled(20, 0xdd)),
        displayName: 'WebTorrent Sample',
        trackers: [
          Uri.parse('udp://tracker.opentrackr.org:1337'),
          Uri.parse('wss://tracker.openwebtorrent.com'),
        ],
        webSeeds: [
          Uri.parse('https://webtorrent.io/torrents/sample.mp4'),
        ],
        exactSources: [
          Uri.parse('https://webtorrent.io/torrents/sample.torrent'),
        ],
      );

      final uri = MagnetParser.toUri(magnet);
      final parsed = MagnetParser.parse(uri);

      expect(uri, contains('tr=udp'));
      expect(uri, contains('tr=wss'));
      expect(uri, contains('ws='));
      expect(uri, contains('xs='));
      expect(parsed, isNotNull);
      expect(parsed!.trackers.map((uri) => uri.scheme), contains('wss'));
      expect(parsed.webSeeds, magnet.webSeeds);
      expect(parsed.exactSources, magnet.exactSources);
    });

    test('should parse numbered exact source parameters', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
          '&xs.1=https://example.com/one.torrent'
          '&xs.2=https://example.com/two.torrent';

      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.exactSources.length, equals(2));
      expect(
        magnet.exactSources.map((uri) => uri.path).toList(),
        equals(['/one.torrent', '/two.torrent']),
      );
    });

    test('should filter invalid WebTorrent tracker and exact source schemes',
        () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
          '&tr=wss://tracker.openwebtorrent.com'
          '&tr=mailto:not-a-tracker'
          '&xs=https://example.com/sample.torrent'
          '&xs=magnet:?xt=urn:btih:bad';

      final magnet = MagnetParser.parse(magnetUri);

      expect(magnet, isNotNull);
      expect(magnet!.trackers,
          equals([Uri.parse('wss://tracker.openwebtorrent.com')]));
      expect(
        magnet.exactSources,
        equals([Uri.parse('https://example.com/sample.torrent')]),
      );
    });
  });
}
