import 'dart:convert';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

Future<void> main() async {
  print('dtorrent_task_v2 feature tour');
  print('=============================');
  print('');

  _printSection('1) Magnet and metadata bootstrap');
  const magnetUri =
      'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
      '&dn=Example%20Torrent'
      '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce';

  final magnet = MagnetParser.parse(magnetUri);
  if (magnet == null) {
    print('Invalid magnet URI');
    return;
  }

  final downloader = MetadataDownloader.fromMagnet(magnetUri);
  print('Magnet parsed: yes');
  print('Info hash: ${magnet.infoHashString}');
  print('Display name: ${magnet.displayName}');
  print('Trackers: ${magnet.trackers.length}');
  print('Initial progress: ${downloader.progress}%');
  print('Next step in real usage: await downloader.startDownload();');
  print('');

  _printSection('2) WebTorrent-style magnet compatibility');
  const webTorrentMagnet =
      'magnet:?xt=urn:btih:dd8255ecdc7ca55fb0bbf81323d87062db1f6d1c'
      '&dn=Big+Buck+Bunny'
      '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337'
      '&tr=wss%3A%2F%2Ftracker.openwebtorrent.com'
      '&ws=https%3A%2F%2Fwebtorrent.io%2Ftorrents%2Fbig-buck-bunny.mp4';

  final webTorrent = MagnetParser.parse(webTorrentMagnet);
  if (webTorrent == null) {
    print('WebTorrent magnet parsed: no');
  } else {
    final websocketTrackers = webTorrent.trackers
        .where((tracker) => tracker.scheme == 'ws' || tracker.scheme == 'wss')
        .toList(growable: false);

    print('WebTorrent magnet parsed: yes');
    print('Display name: ${webTorrent.displayName}');
    print('UDP/WSS trackers: ${webTorrent.trackers.length}');
    print('WebSocket trackers: ${websocketTrackers.length}');
    print('Web seeds: ${webTorrent.webSeeds.length}');
    print('Exact sources: ${webTorrent.exactSources.length}');
    print('First WebSocket tracker: '
        '${websocketTrackers.isNotEmpty ? websocketTrackers.first : 'none'}');
    print('Note: WebSocketTracker handles tracker signalling; browser WebRTC '
        'peer transport is a separate future layer.');
  }
  print('');

  _printSection('3) Download UX automation');
  final autoMove = AutoMoveConfig(
    defaultDestinationDirectory: './downloads/completed',
    rules: const [
      AutoMoveRule(
        extensions: {'mkv', 'mp4'},
        destinationDirectory: './downloads/video',
      ),
    ],
  );

  final scheduleWindow = ScheduleWindow(
    id: 'night-limit',
    weekdays: const {1, 2, 3, 4, 5, 6, 7},
    start: const Duration(hours: 1),
    end: const Duration(hours: 8),
    maxDownloadRate: 1 * 1024 * 1024,
    maxUploadRate: 256 * 1024,
  );

  print('Auto-move rules configured: ${autoMove.rules.length}');
  print('Schedule window configured: ${scheduleWindow.id}');
  print('');

  _printSection('4) Queue, RSS and filtering');
  final queueManager = QueueManager(maxConcurrentDownloads: 2);
  queueManager.enableRssAutoDownload(defaultSavePath: './downloads');
  queueManager.rssManager?.addSubscription(
    RSSSubscription(
      id: 'linux',
      url: Uri.parse('https://example.com/feed.xml'),
      filter: const FeedFilter(
        includeKeywords: {'linux', 'iso'},
        excludeKeywords: {'beta'},
      ),
    ),
  );
  print('Queue manager ready, RSS subscriptions: '
      '${queueManager.rssManager?.subscriptions.length ?? 0}');

  final rssParser = const RSSParser();
  final parsedItems = rssParser.parse('''
<rss><channel>
  <item>
    <title>Linux ISO release</title>
    <enclosure url="https://example.com/linux.torrent" type="application/x-bittorrent"/>
    <guid>linux-1</guid>
  </item>
</channel></rss>
''');
  print('RSS parser sanity items: ${parsedItems.length}');
  print('');

  _printSection('5) Network and security configs');
  final proxy = ProxyConfig.socks5(
    host: '127.0.0.1',
    port: 1080,
    useForTrackers: true,
    useForPeers: true,
  );
  print('Proxy configured: ${proxy.uri}');

  final ipFilter = IPFilter();
  ipFilter.addCIDRFromString('10.0.0.0/8');
  ipFilter.addIPFromString('192.168.1.10');
  print('IP filter rules total: ${ipFilter.totalRules}');

  const encryptionConfig = ProtocolEncryptionConfig(
    level: EncryptionLevel.prefer,
    enableStreamEncryption: true,
    enableMessageObfuscation: true,
  );
  final encryptionSession = ProtocolEncryptionSession.fromSharedSecret(
    config: encryptionConfig,
    sharedSecret: utf8.encode('shared-secret-demo'),
  );
  final encrypted = encryptionSession
      .encryptOutbound(Uint8List.fromList(utf8.encode('ping')));
  final decrypted = encryptionSession.decryptInbound(encrypted);
  print(
      'Protocol encryption roundtrip ok: ${utf8.decode(decrypted) == 'ping'}');
  print('');

  _printSection('6) DHT modules');
  final dhtStorage = DHTStorage();
  final immutableTarget = dhtStorage.putImmutable(utf8.encode('hello dht'));
  final stored = dhtStorage.get(immutableTarget);
  print('DHT storage entries: ${dhtStorage.size}, value bytes: '
      '${stored?.value.length ?? 0}');

  final pubSub = DHTPubSub();
  final sub = pubSub.subscribe(topic: 'releases');
  final received = <DHTPubSubMessage>[];
  final subCancel = sub.listen(received.add);
  pubSub.publish(topic: 'releases', payload: utf8.encode('v1.0'));
  await Future<void>.delayed(const Duration(milliseconds: 5));
  print('DHT pub/sub messages received: ${received.length}');

  final indexer = DHTInfohashIndexer();
  indexer.index(
    infoHash: magnet.infoHashString,
    name: magnet.displayName ?? 'Example Torrent',
    keywords: const {'linux', 'release'},
    metadata: const {'source': 'example'},
  );
  final matches = indexer.search('linux');
  print('DHT index search("linux"): ${matches.length} result(s)');
  print('');

  _printSection('7) Streaming/sequential presets');
  final videoStreaming = SequentialConfig.forVideoStreaming();
  print('Sequential video preset lookAhead: ${videoStreaming.lookAheadSize}');
  print('');

  print('Feature tour completed.');

  await subCancel.cancel();
  await pubSub.close();
  await queueManager.dispose();
}

void _printSection(String title) {
  print(title);
  print('-' * title.length);
}
