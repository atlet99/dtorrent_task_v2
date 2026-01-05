import 'dart:async';
import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';

var _log = Logger('TorrentQueueExample');

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.message}');
  });

  final parser = ArgParser()
    ..addOption('max-concurrent',
        abbr: 'm',
        defaultsTo: '3',
        help: 'Maximum number of concurrent downloads')
    ..addMultiOption('torrent',
        abbr: 't', help: 'Path to torrent file(s) to add to queue')
    ..addOption('save-path',
        abbr: 's', defaultsTo: 'tmp', help: 'Path where torrents will be saved')
    ..addOption('priority',
        abbr: 'p',
        allowed: ['high', 'normal', 'low'],
        defaultsTo: 'normal',
        help: 'Priority for added torrents')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print('Error parsing arguments: $e');
    print(parser.usage);
    exit(1);
  }

  if (results['help']) {
    print('Torrent Queue Example');
    print('');
    print('Usage: dart run example/torrent_queue_example.dart [options]');
    print('');
    print(parser.usage);
    exit(0);
  }

  final maxConcurrent = int.tryParse(results['max-concurrent'] as String) ?? 3;
  final torrentFiles = results['torrent'] as List<String>;
  final savePath = results['save-path'] as String;
  final priorityStr = results['priority'] as String;

  if (torrentFiles.isEmpty) {
    print('Error: At least one torrent file is required');
    print('Use --torrent or -t to specify torrent file(s)');
    print('');
    print(parser.usage);
    exit(1);
  }

  // Parse priority
  QueuePriority priority;
  switch (priorityStr) {
    case 'high':
      priority = QueuePriority.high;
      break;
    case 'low':
      priority = QueuePriority.low;
      break;
    default:
      priority = QueuePriority.normal;
  }

  // Create queue manager
  final queueManager = QueueManager(maxConcurrentDownloads: maxConcurrent);
  _log.info(
      'Queue manager created with max concurrent downloads: $maxConcurrent');

  // Set up event listeners
  queueManager.events.listen((event) {
    if (event is QueueItemAdded) {
      _log.info(
          'Item added to queue: ${event.item.metaInfo.name} (ID: ${event.item.id})');
    } else if (event is QueueItemStarted) {
      _log.info('Download started: ${event.queueItemId}');
    } else if (event is QueueItemCompleted) {
      _log.info('Download completed: ${event.queueItemId}');
    } else if (event is QueueItemFailed) {
      _log.warning('Download failed: ${event.queueItemId} - ${event.error}');
    } else if (event is QueueItemStopped) {
      _log.info('Download stopped: ${event.queueItemId}');
    }
  });

  // Ensure save directory exists
  final saveDir = Directory(savePath);
  if (!await saveDir.exists()) {
    await saveDir.create(recursive: true);
    _log.info('Created save directory: $savePath');
  }

  // Parse and add torrents to queue
  final queueItemIds = <String>[];
  for (final torrentFile in torrentFiles) {
    final file = File(torrentFile);
    if (!await file.exists()) {
      _log.warning('Torrent file not found: $torrentFile');
      continue;
    }

    try {
      final torrent = await TorrentModel.parse(torrentFile);
      final item = TorrentQueueItem(
        metaInfo: torrent,
        savePath: savePath,
        priority: priority,
      );
      final id = queueManager.addToQueue(item);
      queueItemIds.add(id);
      _log.info('Added torrent to queue: ${torrent.name} (ID: $id)');
    } catch (e, stackTrace) {
      _log.severe('Failed to parse torrent: $torrentFile', e, stackTrace);
    }
  }

  if (queueItemIds.isEmpty) {
    _log.warning('No torrents were added to the queue');
    await queueManager.dispose();
    exit(1);
  }

  _log.info('Added ${queueItemIds.length} torrent(s) to queue');
  _log.info(
      'Queue will automatically start downloads up to the concurrent limit');

  // Monitor queue status
  Timer.periodic(const Duration(seconds: 5), (timer) {
    final activeCount = queueManager.activeDownloadsCount;
    final queueLength = queueManager.queue.length;
    _log.info(
        'Queue status: $activeCount active, $queueLength queued, ${queueItemIds.length} total');

    // Show active downloads
    if (activeCount > 0) {
      _log.info('Active downloads:');
      for (final entry in queueManager.activeTasks.entries) {
        final task = entry.value;
        _log.info(
            '  - ${entry.key}: ${task.name} (${(task.progress * 100).toStringAsFixed(1)}%)');
      }
    }

    // Check if all downloads are complete
    if (activeCount == 0 && queueLength == 0) {
      _log.info('All downloads complete!');
      timer.cancel();
      queueManager.dispose().then((_) {
        _log.info('Queue manager disposed');
        exit(0);
      });
    }
  });

  // Wait for user interrupt or completion
  print('');
  print('Queue is running. Press Ctrl+C to stop all downloads and exit.');
  print('');

  // Handle interrupt
  ProcessSignal.sigint.watch().listen((signal) {
    _log.info('Received interrupt signal, stopping all downloads...');
    queueManager.stopAll().then((_) {
      queueManager.dispose().then((_) {
        _log.info('Queue manager disposed');
        exit(0);
      });
    });
  });

  // Keep the program running
  await Future.delayed(const Duration(days: 1));
}
