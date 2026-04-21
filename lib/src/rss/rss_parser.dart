import 'package:xml/xml.dart';

class RSSFeedItem {
  final String title;
  final String? link;
  final String? guid;
  final DateTime? publishedAt;
  final String? magnetUrl;
  final String? torrentUrl;

  const RSSFeedItem({
    required this.title,
    this.link,
    this.guid,
    this.publishedAt,
    this.magnetUrl,
    this.torrentUrl,
  });

  String get dedupKey => guid ?? link ?? title;
}

class RSSParser {
  const RSSParser();

  List<RSSFeedItem> parse(String xml) {
    final doc = XmlDocument.parse(xml);
    final root = doc.rootElement;
    if (root.name.local.toLowerCase() == 'rss') {
      return _parseRss(root);
    }
    if (root.name.local.toLowerCase() == 'feed') {
      return _parseAtom(root);
    }
    return const <RSSFeedItem>[];
  }

  List<RSSFeedItem> _parseRss(XmlElement root) {
    final channel = root.getElement('channel');
    if (channel == null) return const <RSSFeedItem>[];
    final items = <RSSFeedItem>[];
    for (final item in channel.findElements('item')) {
      final title = item.getElement('title')?.innerText.trim();
      if (title == null || title.isEmpty) continue;
      final link = item.getElement('link')?.innerText.trim();
      final guid = item.getElement('guid')?.innerText.trim();
      final pubDateRaw = item.getElement('pubDate')?.innerText.trim();
      final pubDate = pubDateRaw == null ? null : DateTime.tryParse(pubDateRaw);
      final enclosureUrl =
          item.getElement('enclosure')?.getAttribute('url')?.trim();
      final torrentUrl = _pickTorrentUrl(link, enclosureUrl);
      final magnetUrl = _pickMagnetUrl(link, enclosureUrl);

      items.add(RSSFeedItem(
        title: title,
        link: link,
        guid: guid,
        publishedAt: pubDate,
        magnetUrl: magnetUrl,
        torrentUrl: torrentUrl,
      ));
    }
    return items;
  }

  List<RSSFeedItem> _parseAtom(XmlElement root) {
    final entries = <RSSFeedItem>[];
    for (final entry in root.findElements('entry')) {
      final title = entry.getElement('title')?.innerText.trim();
      if (title == null || title.isEmpty) continue;

      String? link;
      String? enclosure;
      for (final linkElement in entry.findElements('link')) {
        final href = linkElement.getAttribute('href')?.trim();
        if (href == null || href.isEmpty) continue;
        final rel = linkElement.getAttribute('rel')?.trim().toLowerCase();
        if (rel == 'enclosure') {
          enclosure = href;
        } else {
          link ??= href;
        }
      }

      final id = entry.getElement('id')?.innerText.trim();
      final updatedRaw = entry.getElement('updated')?.innerText.trim() ??
          entry.getElement('published')?.innerText.trim();
      final publishedAt =
          updatedRaw == null ? null : DateTime.tryParse(updatedRaw);
      final torrentUrl = _pickTorrentUrl(link, enclosure);
      final magnetUrl = _pickMagnetUrl(link, enclosure);

      entries.add(RSSFeedItem(
        title: title,
        link: link,
        guid: id,
        publishedAt: publishedAt,
        magnetUrl: magnetUrl,
        torrentUrl: torrentUrl,
      ));
    }
    return entries;
  }

  String? _pickMagnetUrl(String? a, String? b) {
    if (a != null && a.startsWith('magnet:?')) return a;
    if (b != null && b.startsWith('magnet:?')) return b;
    return null;
  }

  String? _pickTorrentUrl(String? a, String? b) {
    if (_isTorrentUrl(a)) return a;
    if (_isTorrentUrl(b)) return b;
    return null;
  }

  bool _isTorrentUrl(String? value) {
    if (value == null || value.isEmpty) return false;
    final lower = value.toLowerCase();
    return lower.endsWith('.torrent') || lower.contains('torrent');
  }
}
