import 'dart:convert';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:http/http.dart' as http;
import 'package:logging/logging.dart';

/// Result of BEP 21 paused announce.
class PausedAnnounceResult {
  final Uri trackerUrl;
  final bool isSuccess;
  final String? error;
  final int? interval;
  final int? complete;
  final int? incomplete;
  final int? downloaders;

  const PausedAnnounceResult({
    required this.trackerUrl,
    required this.isSuccess,
    this.error,
    this.interval,
    this.complete,
    this.incomplete,
    this.downloaders,
  });
}

/// Lightweight client for BEP 21 paused announce (`event=paused`).
///
/// Notes:
/// - HTTP/HTTPS trackers only.
/// - UDP trackers do not support custom event strings like `paused`.
class TrackerClient {
  static final _log = Logger('TrackerClient');

  final Duration timeout;
  final http.Client _httpClient;

  TrackerClient({
    this.timeout = const Duration(seconds: 10),
    http.Client? httpClient,
  }) : _httpClient = httpClient ?? http.Client();

  /// Build paused announce URL for HTTP/HTTPS tracker.
  Uri? buildPausedAnnounceUri({
    required Uri trackerUrl,
    required Uint8List infoHash,
    required Map<String, dynamic> options,
  }) {
    if (trackerUrl.scheme != 'http' && trackerUrl.scheme != 'https') {
      return null;
    }

    final queryParts = <String>[];

    void add(String key, dynamic value) {
      if (value == null) return;
      queryParts.add(
          '${Uri.encodeQueryComponent(key)}=${Uri.encodeQueryComponent(value.toString())}');
    }

    add('compact', options['compact'] ?? 1);
    add('downloaded', options['downloaded'] ?? 0);
    add('uploaded', options['uploaded'] ?? 0);
    add('left', options['left'] ?? 0);
    add('numwant', options['numwant'] ?? 50);
    add('port', options['port'] ?? 0);
    add('peer_id', options['peerId'] ?? options['peer_id'] ?? '');
    add('event', 'paused');

    final encodedInfoHash = Uri.encodeQueryComponent(
      String.fromCharCodes(infoHash),
      encoding: latin1,
    );
    queryParts.add('info_hash=$encodedInfoHash');

    return trackerUrl.replace(query: queryParts.join('&'));
  }

  /// Send paused announce to tracker.
  Future<PausedAnnounceResult> announcePaused({
    required Uri trackerUrl,
    required Uint8List infoHash,
    required Map<String, dynamic> options,
  }) async {
    final uri = buildPausedAnnounceUri(
      trackerUrl: trackerUrl,
      infoHash: infoHash,
      options: options,
    );

    if (uri == null) {
      return PausedAnnounceResult(
        trackerUrl: trackerUrl,
        isSuccess: false,
        error:
            'Unsupported tracker scheme for paused announce: ${trackerUrl.scheme}',
      );
    }

    try {
      final response = await _httpClient.get(uri,
          headers: {'User-Agent': 'dtorrent_task_v2/1.0'}).timeout(timeout);

      if (response.statusCode != 200) {
        return PausedAnnounceResult(
          trackerUrl: trackerUrl,
          isSuccess: false,
          error: 'HTTP ${response.statusCode}: ${response.reasonPhrase}',
        );
      }

      final decoded = decode(response.bodyBytes);
      if (decoded is! Map) {
        return PausedAnnounceResult(
          trackerUrl: trackerUrl,
          isSuccess: false,
          error: 'Invalid tracker response format',
        );
      }

      if (decoded.containsKey('failure reason')) {
        final failure = decoded['failure reason'];
        return PausedAnnounceResult(
          trackerUrl: trackerUrl,
          isSuccess: false,
          error: failure is String ? failure : '$failure',
        );
      }

      int? getInt(dynamic key) {
        final value = decoded[key];
        if (value is int) return value;
        if (value is BigInt) return value.toInt();
        return null;
      }

      return PausedAnnounceResult(
        trackerUrl: trackerUrl,
        isSuccess: true,
        interval: getInt('interval'),
        complete: getInt('complete'),
        incomplete: getInt('incomplete'),
        downloaders: getInt('downloaders'),
      );
    } catch (e, st) {
      _log.warning('Paused announce failed for $trackerUrl', e, st);
      return PausedAnnounceResult(
        trackerUrl: trackerUrl,
        isSuccess: false,
        error: e.toString(),
      );
    }
  }
}
