import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('DHTInfohashIndexer (BEP 51)', () {
    test('indexes and searches torrents by keyword', () {
      final indexer = DHTInfohashIndexer();
      indexer.index(
        infoHash: 'hash-1',
        name: 'Ubuntu ISO',
        keywords: const ['linux', 'distribution'],
      );

      final linux = indexer.search('linux');
      final ubuntu = indexer.search('ubuntu');

      expect(linux, hasLength(1));
      expect(ubuntu, hasLength(1));
      expect(linux.first.infoHash, 'hash-1');
    });

    test('supports search by multiple keywords', () {
      final indexer = DHTInfohashIndexer();
      indexer.index(
        infoHash: 'hash-1',
        name: 'Movie Pack',
        keywords: const ['movie', 'pack', '4k'],
      );
      indexer.index(
        infoHash: 'hash-2',
        name: 'Movie Trailer',
        keywords: const ['movie', 'hd'],
      );

      final result = indexer.searchAll(const ['movie', 'pack']);
      expect(result, hasLength(1));
      expect(result.first.infoHash, 'hash-1');
    });

    test('integrates metadata map indexing', () {
      final indexer = DHTInfohashIndexer();
      indexer.indexFromMetadata(
        infoHash: 'hash-3',
        metadata: const {
          'name': 'Music Album',
          'keywords': ['audio', 'flac'],
          'size': 12345,
        },
      );

      final album = indexer.byInfoHash('hash-3');
      expect(album, isNotNull);
      expect(album!.name, 'Music Album');
      expect(album.metadata['size'], 12345);
      expect(indexer.search('flac'), hasLength(1));
    });

    test('updates existing entry and removes stale keyword links', () {
      final indexer = DHTInfohashIndexer();
      indexer.index(
        infoHash: 'hash-4',
        name: 'Old Name',
        keywords: const ['old'],
      );
      indexer.index(
        infoHash: 'hash-4',
        name: 'New Name',
        keywords: const ['new'],
      );

      expect(indexer.search('old'), isEmpty);
      expect(indexer.search('new'), hasLength(1));
      expect(indexer.search('name'), hasLength(1));
    });
  });
}
