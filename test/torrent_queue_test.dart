import 'package:dtorrent_task_v2/src/queue/torrent_queue.dart';
import 'package:dtorrent_task_v2/src/queue/torrent_queue_item.dart';
import 'package:test/test.dart';
import 'test_helpers.dart';

void main() {
  group('TorrentQueueItem', () {
    test('Creates item with default values', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
      );

      expect(item.metaInfo, equals(torrent));
      expect(item.savePath, equals('/tmp/test'));
      expect(item.priority, equals(QueuePriority.normal));
      expect(item.stream, isFalse);
      expect(item.id, isNotEmpty);
      expect(item.addedAt, isA<DateTime>());
    });

    test('Creates item with custom priority', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
        priority: QueuePriority.high,
      );

      expect(item.priority, equals(QueuePriority.high));
      expect(item.priorityValue, equals(3));
    });

    test('Priority values are correct', () async {
      final torrent = await createTestTorrent();
      final highItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/high',
        priority: QueuePriority.high,
      );
      final normalItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/normal',
        priority: QueuePriority.normal,
      );
      final lowItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/low',
        priority: QueuePriority.low,
      );

      expect(highItem.priorityValue, equals(3));
      expect(normalItem.priorityValue, equals(2));
      expect(lowItem.priorityValue, equals(1));
    });

    test('copyWith creates new item with modified fields', () async {
      final torrent1 = await createTestTorrent();
      final torrent2 = await createTestTorrent();
      final item1 = TorrentQueueItem(
        metaInfo: torrent1,
        savePath: '/tmp/test1',
        priority: QueuePriority.normal,
      );

      final item2 = item1.copyWith(
        metaInfo: torrent2,
        priority: QueuePriority.high,
      );

      expect(item2.metaInfo, equals(torrent2));
      expect(item2.priority, equals(QueuePriority.high));
      expect(item2.savePath, equals(item1.savePath));
      expect(item2.id, equals(item1.id)); // ID is preserved
    });

    test('Equality is based on ID', () async {
      final torrent = await createTestTorrent();
      final item1 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
        id: 'test-id',
      );
      final item2 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
        id: 'test-id',
      );
      final item3 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
        id: 'different-id',
      );

      expect(item1, equals(item2));
      expect(item1, isNot(equals(item3)));
      expect(item1.hashCode, equals(item2.hashCode));
    });
  });

  group('TorrentQueue', () {
    late TorrentQueue queue;

    setUp(() {
      queue = TorrentQueue();
    });

    test('Starts empty', () {
      expect(queue.isEmpty, isTrue);
      expect(queue.length, equals(0));
    });

    test('Adds items to queue', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
      );

      queue.add(item);

      expect(queue.length, equals(1));
      expect(queue.isEmpty, isFalse);
      expect(queue.contains(item.id), isTrue);
    });

    test('Sorts items by priority', () async {
      final torrent = await createTestTorrent();
      final lowItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/low',
        priority: QueuePriority.low,
      );
      final normalItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/normal',
        priority: QueuePriority.normal,
      );
      final highItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/high',
        priority: QueuePriority.high,
      );

      queue.add(lowItem);
      queue.add(normalItem);
      queue.add(highItem);

      expect(queue.length, equals(3));
      final items = queue.items;
      expect(items[0].priority, equals(QueuePriority.high));
      expect(items[1].priority, equals(QueuePriority.normal));
      expect(items[2].priority, equals(QueuePriority.low));
    });

    test('Peek returns first item without removing', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
      );

      queue.add(item);
      final peeked = queue.peek();

      expect(peeked, equals(item));
      expect(queue.length, equals(1)); // Still in queue
    });

    test('Pop returns and removes first item', () async {
      final torrent = await createTestTorrent();
      final item1 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test1',
        priority: QueuePriority.high,
      );
      final item2 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test2',
        priority: QueuePriority.normal,
      );

      queue.add(item1);
      queue.add(item2);

      final popped = queue.pop();

      expect(popped, equals(item1));
      expect(queue.length, equals(1));
      expect(queue.peek(), equals(item2));
    });

    test('Remove removes item by ID', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
      );

      queue.add(item);
      final removed = queue.remove(item.id);

      expect(removed, isTrue);
      expect(queue.length, equals(0));
      expect(queue.contains(item.id), isFalse);
    });

    test('UpdatePriority updates item priority', () async {
      final torrent = await createTestTorrent();
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test',
        priority: QueuePriority.normal,
      );

      queue.add(item);
      final updated = queue.updatePriority(item.id, QueuePriority.high);

      expect(updated, isTrue);
      final updatedItem = queue.getById(item.id);
      expect(updatedItem?.priority, equals(QueuePriority.high));
    });

    test('GetByPriority returns items with specific priority', () async {
      final torrent = await createTestTorrent();
      final highItem1 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/high1',
        priority: QueuePriority.high,
      );
      final highItem2 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/high2',
        priority: QueuePriority.high,
      );
      final normalItem = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/normal',
        priority: QueuePriority.normal,
      );

      queue.add(highItem1);
      queue.add(normalItem);
      queue.add(highItem2);

      final highItems = queue.getByPriority(QueuePriority.high);
      expect(highItems.length, equals(2));
      expect(highItems, contains(highItem1));
      expect(highItems, contains(highItem2));
    });

    test('Clear removes all items', () async {
      final torrent = await createTestTorrent();
      final item1 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test1',
      );
      final item2 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test2',
      );

      queue.add(item1);
      queue.add(item2);
      queue.clear();

      expect(queue.length, equals(0));
      expect(queue.isEmpty, isTrue);
    });

    test('Items with same priority are sorted by addedAt (FIFO)', () async {
      final torrent = await createTestTorrent();
      final item1 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test1',
        priority: QueuePriority.normal,
      );
      await Future.delayed(const Duration(milliseconds: 10));
      final item2 = TorrentQueueItem(
        metaInfo: torrent,
        savePath: '/tmp/test2',
        priority: QueuePriority.normal,
      );

      queue.add(item1);
      queue.add(item2);

      final items = queue.items;
      expect(items[0].id, equals(item1.id));
      expect(items[1].id, equals(item2.id));
    });
  });
}
