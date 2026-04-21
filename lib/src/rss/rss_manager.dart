import 'dart:async';

import 'package:dtorrent_task_v2/src/rss/feed_filter.dart';
import 'package:dtorrent_task_v2/src/rss/rss_parser.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

typedef RSSItemHandler = Future<void> Function(RSSFeedItem item);

typedef RSSFetcher = Future<String> Function(Uri url);

class RSSSubscription {
  final String id;
  final Uri url;
  final Duration interval;
  final FeedFilter filter;

  const RSSSubscription({
    required this.id,
    required this.url,
    this.interval = const Duration(minutes: 30),
    this.filter = const FeedFilter(),
  });
}

class RSSManager {
  final RSSParser _parser;
  final RSSFetcher _fetcher;
  final Logger _log;
  final RSSItemHandler _onItem;

  final Map<String, RSSSubscription> _subscriptions = {};
  final Set<String> _seenItems = <String>{};
  final Map<String, Timer> _timers = {};

  RSSManager({
    required RSSItemHandler onItem,
    RSSParser parser = const RSSParser(),
    RSSFetcher? fetcher,
    Logger? logger,
  })  : _onItem = onItem,
        _parser = parser,
        _fetcher = fetcher ?? _defaultFetcher,
        _log = logger ?? Logger('RSSManager');

  List<RSSSubscription> get subscriptions =>
      List.unmodifiable(_subscriptions.values);

  void addSubscription(RSSSubscription subscription) {
    _subscriptions[subscription.id] = subscription;
    _restartTimer(subscription);
  }

  bool removeSubscription(String id) {
    final removed = _subscriptions.remove(id) != null;
    _cancelTimer(id);
    return removed;
  }

  void clearSubscriptions() {
    for (final id in _timers.keys.toList()) {
      _cancelTimer(id);
    }
    _timers.clear();
    _subscriptions.clear();
  }

  Future<void> pollNow([String? id]) async {
    if (id != null) {
      final sub = _subscriptions[id];
      if (sub != null) {
        await _pollSubscription(sub);
      }
      return;
    }

    for (final sub in _subscriptions.values) {
      await _pollSubscription(sub);
    }
  }

  void dispose() {
    clearSubscriptions();
    _seenItems.clear();
  }

  Future<void> _pollSubscription(RSSSubscription subscription) async {
    try {
      final body = await _fetcher(subscription.url);
      final items = _parser.parse(body);
      for (final item in items) {
        if (!subscription.filter.matches(item)) continue;
        if (!_seenItems.add(_dedupKey(subscription.id, item.dedupKey))) {
          continue;
        }
        await _onItem(item);
      }
    } catch (e, stackTrace) {
      _log.warning('RSS poll failed for ${subscription.url}', e, stackTrace);
    }
  }

  void _restartTimer(RSSSubscription subscription) {
    _cancelTimer(subscription.id);
    _timers[subscription.id] = Timer.periodic(
      subscription.interval,
      (_) => _pollSubscription(subscription),
    );
  }

  void _cancelTimer(String id) {
    _timers.remove(id)?.cancel();
  }

  String _dedupKey(String subscriptionId, String itemKey) =>
      '$subscriptionId:$itemKey';

  static Future<String> _defaultFetcher(Uri url) async {
    final response = await http.get(url);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StateError('RSS request failed with status ${response.statusCode}');
    }
    return response.body;
  }
}
