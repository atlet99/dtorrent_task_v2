import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha1;
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_downloader.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_downloader_events.dart';
import 'package:dtorrent_task_v2/src/metadata/magnet_parser.dart';

void main() {
  group('MetadataDownloader Tests', () {
    test('should create from info hash string', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
      expect(downloader.metaDataSize, isNull);
    });

    test('should throw for invalid info hash length in constructor', () {
      expect(
        () => MetadataDownloader('0123456789abcdef'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should throw for non-hex info hash in constructor', () {
      expect(
        () => MetadataDownloader('zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should create from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&dn=test+file&tr=http://tracker.example.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should throw error for invalid magnet URI', () {
      expect(
        () => MetadataDownloader.fromMagnet('invalid-uri'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('should track download progress', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.progress, equals(0));
      expect(downloader.bytesDownloaded, equals(0));
    });

    test('should have active peers getter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.activePeers, isNotNull);
      expect(downloader.activePeers.length, equals(0));
    });

    test('should create with trackers from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr=http://tracker1.com&tr=http://tracker2.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with tracker tiers from magnet URI', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&tr.1=http://tracker1.com&tr.2=http://tracker2.com';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with trackers parameter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final trackers = [
        Uri.parse('http://tracker1.com'),
        Uri.parse('http://tracker2.com'),
      ];

      final downloader = MetadataDownloader(infoHash, trackers: trackers);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should create with tracker tiers parameter', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final trackerTiers = [
        TrackerTier([Uri.parse('http://tracker1.com')]),
        TrackerTier([Uri.parse('http://tracker2.com')]),
      ];

      final downloader =
          MetadataDownloader(infoHash, trackerTiers: trackerTiers);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });

    test('should have DHT instance', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.dht, isNotNull);
    });

    test('should track metadata size when set', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.metaDataSize, isNull);
      // metadata size is set during handshake, which we can't easily test without peers
    });

    test('should calculate bytes downloaded correctly', () {
      final infoHash = '0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader(infoHash);

      expect(downloader.bytesDownloaded, equals(0));
      // bytesDownloaded is calculated based on completed pieces
    });

    test('should handle magnet URI with web seeds', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&ws=http://webseed.example.com/file';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      // Web seeds are parsed but not used in MetadataDownloader
      // They should be passed to TorrentTask instead
    });

    test('should handle magnet URI with acceptable sources', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&as=http://source.example.com/file';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
    });

    test('should handle magnet URI with selected file indices', () {
      final magnetUri =
          'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567&so=0&so=2';

      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      // Selected file indices are parsed but not used in MetadataDownloader
      // They should be passed to TorrentTask instead
    });

    test('should return null when metadata cache file is missing', () async {
      final cacheDir =
          await Directory.systemTemp.createTemp('metadata_cache_missing_');
      addTearDown(() async {
        MetadataDownloader.setCacheDirectory(null);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      });

      MetadataDownloader.setCacheDirectory(cacheDir.path);
      final loaded = await MetadataDownloader.loadFromCache(
        '0123456789abcdef0123456789abcdef01234567',
      );
      expect(loaded, isNull);
    });

    test('should load metadata bytes from cache', () async {
      final cacheDir =
          await Directory.systemTemp.createTemp('metadata_cache_load_');
      addTearDown(() async {
        MetadataDownloader.setCacheDirectory(null);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      });

      const infoHash = '0123456789abcdef0123456789abcdef01234567';
      final expectedData = List<int>.generate(256, (i) => i % 256);
      final cacheFile = File('${cacheDir.path}/$infoHash.torrent');
      await cacheFile.writeAsBytes(expectedData);

      MetadataDownloader.setCacheDirectory(cacheDir.path);
      final loaded = await MetadataDownloader.loadFromCache(infoHash);

      expect(loaded, isNotNull);
      expect(loaded, equals(expectedData));
    });

    test('should emit complete event from cache without network download',
        () async {
      final cacheDir =
          await Directory.systemTemp.createTemp('metadata_cache_start_');
      addTearDown(() async {
        MetadataDownloader.setCacheDirectory(null);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      });

      final cachedData = List<int>.generate(128, (i) => (255 - i) % 256);
      final infoHash = sha1.convert(cachedData).toString();
      await File('${cacheDir.path}/$infoHash.torrent').writeAsBytes(cachedData);
      MetadataDownloader.setCacheDirectory(cacheDir.path);

      final downloader = MetadataDownloader(infoHash);
      final listener = downloader.createListener();
      final completeCompleter = Completer<List<int>>();

      listener.on<MetaDataDownloadComplete>((event) {
        if (!completeCompleter.isCompleted) {
          completeCompleter.complete(event.data);
        }
      });

      await downloader.startDownload();

      final result = await completeCompleter.future.timeout(
        const Duration(seconds: 2),
      );
      expect(result, equals(cachedData));
      expect(downloader.progress, equals(0));

      listener.dispose();
      await downloader.stop();
    });

    test('should ignore corrupted cache with mismatched hash', () async {
      final cacheDir =
          await Directory.systemTemp.createTemp('metadata_cache_corrupt_');
      addTearDown(() async {
        MetadataDownloader.setCacheDirectory(null);
        if (await cacheDir.exists()) {
          await cacheDir.delete(recursive: true);
        }
      });

      const infoHash = '0123456789abcdef0123456789abcdef01234567';
      final corruptedData = List<int>.generate(64, (i) => i);
      await File('${cacheDir.path}/$infoHash.torrent')
          .writeAsBytes(corruptedData);
      MetadataDownloader.setCacheDirectory(cacheDir.path);

      final downloader = MetadataDownloader(infoHash);
      final listener = downloader.createListener();
      final completeCompleter = Completer<List<int>>();

      listener.on<MetaDataDownloadComplete>((event) {
        if (!completeCompleter.isCompleted) {
          completeCompleter.complete(event.data);
        }
      });

      await downloader.startDownload();

      await expectLater(
        completeCompleter.future.timeout(const Duration(milliseconds: 300)),
        throwsA(isA<TimeoutException>()),
      );

      listener.dispose();
      await downloader.stop();
    });

    test('should create from magnet URI with uppercase BTIH namespace', () {
      final magnetUri =
          'magnet:?xt=urn:BTIH:0123456789abcdef0123456789abcdef01234567';
      final downloader = MetadataDownloader.fromMagnet(magnetUri);

      expect(downloader, isNotNull);
      expect(downloader.progress, equals(0));
    });
  });
}
