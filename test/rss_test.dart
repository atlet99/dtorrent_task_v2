import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('RSS/Atom auto-download (5.4)', () {
    test('should parse RSS feed items', () {
      const xml = '''
<rss version="2.0">
  <channel>
    <item>
      <title>Ubuntu 26.04 ISO</title>
      <link>https://example.org/ubuntu.torrent</link>
      <guid>ubuntu-2604</guid>
    </item>
  </channel>
</rss>
''';
      final parser = RSSParser();
      final items = parser.parse(xml);

      expect(items, hasLength(1));
      expect(items.first.title, contains('Ubuntu'));
      expect(items.first.torrentUrl, 'https://example.org/ubuntu.torrent');
    });

    test('should parse Atom entries', () {
      const xml = '''
<feed xmlns="http://www.w3.org/2005/Atom">
  <entry>
    <title>Fedora Release</title>
    <id>fedora-1</id>
    <link href="magnet:?xt=urn:btih:abc" />
  </entry>
</feed>
''';
      final parser = RSSParser();
      final items = parser.parse(xml);

      expect(items, hasLength(1));
      expect(items.first.magnetUrl, startsWith('magnet:?'));
    });

    test('should filter and deduplicate items across polls', () async {
      const xml = '''
<rss version="2.0">
  <channel>
    <item>
      <title>Linux ISO</title>
      <link>https://example.org/linux.torrent</link>
      <guid>linux-1</guid>
    </item>
    <item>
      <title>Windows ISO</title>
      <link>https://example.org/windows.torrent</link>
      <guid>windows-1</guid>
    </item>
  </channel>
</rss>
''';

      final received = <RSSFeedItem>[];
      final manager = RSSManager(
        onItem: (item) async => received.add(item),
        fetcher: (_) async => xml,
      );
      manager.addSubscription(
        RSSSubscription(
          id: 'linux-only',
          url: Uri.parse('https://example.org/feed.xml'),
          filter: const FeedFilter(includeKeywords: {'linux'}),
        ),
      );

      await manager.pollNow();
      await manager.pollNow(); // duplicate poll should not re-add same guid

      expect(received, hasLength(1));
      expect(received.first.title, contains('Linux'));
      manager.dispose();
    });
  });
}
