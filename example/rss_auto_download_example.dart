import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

Future<void> main(List<String> args) async {
  final feedUrl = args.isNotEmpty ? args.first : 'https://example.com/feed.xml';
  final queueManager = QueueManager(maxConcurrentDownloads: 2);
  queueManager.enableRssAutoDownload(defaultSavePath: './downloads');

  queueManager.rssManager?.addSubscription(
    RSSSubscription(
      id: 'linux-releases',
      url: Uri.parse(feedUrl),
      interval: const Duration(minutes: 30),
      filter: const FeedFilter(
        includeKeywords: {'linux', 'iso'},
        excludeKeywords: {'beta'},
      ),
    ),
  );
  print('RSS subscription added: $feedUrl');
  print('Tip: pass your real RSS URL as first argument.');

  await queueManager.rssManager?.pollNow();
  await queueManager.dispose();
}
