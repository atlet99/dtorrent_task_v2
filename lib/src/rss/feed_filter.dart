import 'package:dtorrent_task_v2/src/rss/rss_parser.dart';

class FeedFilter {
  final Set<String> includeKeywords;
  final Set<String> excludeKeywords;
  final bool requireDownloadUrl;

  const FeedFilter({
    this.includeKeywords = const <String>{},
    this.excludeKeywords = const <String>{},
    this.requireDownloadUrl = true,
  });

  bool matches(RSSFeedItem item) {
    final haystack = '${item.title} ${item.link ?? ''}'.toLowerCase();

    if (requireDownloadUrl &&
        item.magnetUrl == null &&
        item.torrentUrl == null) {
      return false;
    }

    if (excludeKeywords
        .any((keyword) => haystack.contains(keyword.toLowerCase()))) {
      return false;
    }

    if (includeKeywords.isEmpty) {
      return true;
    }

    return includeKeywords
        .any((keyword) => haystack.contains(keyword.toLowerCase()));
  }
}
