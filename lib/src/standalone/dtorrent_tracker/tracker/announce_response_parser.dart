import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:logging/logging.dart';

import 'peer_event.dart';
import 'tracker_exception.dart';

class AnnounceParseResult {
  final PeerEvent event;
  final String? trackerId;

  const AnnounceParseResult({
    required this.event,
    this.trackerId,
  });
}

class _RetryDirective {
  final int? retryInSeconds;
  final bool neverRetry;

  const _RetryDirective({
    this.retryInSeconds,
    this.neverRetry = false,
  });
}

class AnnounceResponseParser {
  static AnnounceParseResult parseHttpAnnounce({
    required Uint8List data,
    required String infoHash,
    required Uri trackerUrl,
    required String trackerId,
    required Logger logger,
  }) {
    final result = decode(data) as Map;
    final retryDirective = _extractRetryDirective(result);

    if (result['failure reason'] != null) {
      final failure = result['failure reason'];
      final failureText = failure is List<int>
          ? String.fromCharCodes(failure)
          : failure.toString();
      throw TrackerException(
        trackerId,
        failureText,
        retryIn: retryDirective.retryInSeconds,
        neverRetry: retryDirective.neverRetry,
      );
    }

    final trackerIdValue = result['tracker id'];
    final parsedTrackerId = trackerIdValue is List<int>
        ? String.fromCharCodes(trackerIdValue)
        : trackerIdValue?.toString();

    final event = PeerEvent(infoHash, trackerUrl);
    event.retryIn = retryDirective.retryInSeconds;
    event.neverRetry = retryDirective.neverRetry;

    result.forEach((key, value) {
      if (key == 'min interval') {
        event.minInterval = _toInt(value);
        return;
      }
      if (key == 'interval') {
        event.interval = _toInt(value);
        return;
      }
      if (key == 'warning message' && value != null) {
        event.warning =
            value is List<int> ? String.fromCharCodes(value) : '$value';
        return;
      }
      if (key == 'complete') {
        event.complete = _toInt(value);
        return;
      }
      if (key == 'incomplete') {
        event.incomplete = _toInt(value);
        return;
      }
      if (key == 'downloaded') {
        event.downloaded = _toInt(value);
        return;
      }
      if (key == 'retry in' || key == 'retry_in') {
        // already parsed once in _extractRetryDirective() with explicit
        // precedence for "retry in" over "retry_in"
        return;
      }
      if (key == 'external ip' || key == 'external_ip') {
        final external = _parseExternalIp(value);
        if (external != null) {
          event.externalIp = external;
        }
        return;
      }
      if (key == 'peers' && value != null) {
        _fillPeers(event, value, logger, InternetAddressType.IPv4);
        return;
      }
      if (key == 'peers6' && value != null) {
        _fillPeers(event, value, logger, InternetAddressType.IPv6);
        return;
      }
      event.setInfo(key, value);
    });

    return AnnounceParseResult(event: event, trackerId: parsedTrackerId);
  }

  static int? _toInt(dynamic value) {
    if (value is int) return value;
    if (value is BigInt) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  static _RetryDirective _extractRetryDirective(Map result) {
    if (result.containsKey('retry in')) {
      return _parseRetryDirective('retry in', result['retry in']);
    }
    if (result.containsKey('retry_in')) {
      return _parseRetryDirective('retry_in', result['retry_in']);
    }
    return const _RetryDirective();
  }

  static _RetryDirective _parseRetryDirective(String key, dynamic value) {
    if (value == null) return const _RetryDirective();

    if (value is List<int>) {
      return _parseRetryDirective(key, String.fromCharCodes(value));
    }

    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized == 'never') {
        return const _RetryDirective(neverRetry: true);
      }
      final parsed = int.tryParse(normalized);
      if (parsed == null || parsed < 0) return const _RetryDirective();
      // BEP 31 defines "retry in" in minutes.
      if (key == 'retry in') {
        return _RetryDirective(retryInSeconds: parsed * 60);
      }
      // Compatibility mode for de-facto "retry_in" fields in seconds.
      return _RetryDirective(retryInSeconds: parsed);
    }

    if (value is int || value is BigInt) {
      final parsed = _toInt(value);
      if (parsed == null || parsed < 0) return const _RetryDirective();
      if (key == 'retry in') {
        return _RetryDirective(retryInSeconds: parsed * 60);
      }
      return _RetryDirective(retryInSeconds: parsed);
    }

    return const _RetryDirective();
  }

  static InternetAddress? _parseExternalIp(dynamic value) {
    if (value == null) return null;
    if (value is String) return InternetAddress.tryParse(value);
    if (value is Uint8List && (value.length == 4 || value.length == 16)) {
      try {
        return InternetAddress.fromRawAddress(value);
      } catch (_) {
        return null;
      }
    }
    if (value is List<int> && (value.length == 4 || value.length == 16)) {
      try {
        return InternetAddress.fromRawAddress(Uint8List.fromList(value));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  static void _fillPeers(
    PeerEvent event,
    dynamic value,
    Logger logger,
    InternetAddressType type,
  ) {
    final compactPayload = _asCompactPayload(value);
    if (compactPayload != null) {
      _fillCompactPeers(event, compactPayload, logger, type);
      return;
    }

    if (value is List) {
      for (final peer in value) {
        if (peer is! Map) continue;
        final ipRaw = peer['ip'];
        final portRaw = peer['port'];
        InternetAddress? ip;
        if (ipRaw is String) {
          ip = InternetAddress.tryParse(ipRaw);
        } else if (ipRaw is List<int>) {
          ip = InternetAddress.tryParse(String.fromCharCodes(ipRaw));
        }
        final port = _toInt(portRaw);
        if (ip == null || port == null) continue;
        try {
          event.addPeer(CompactAddress(ip, port));
        } catch (e, st) {
          logger.warning('Failed to parse peer map entry: $peer', e, st);
        }
      }
    }
  }

  static Uint8List? _asCompactPayload(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    return null;
  }

  static void _fillCompactPeers(
    PeerEvent event,
    Uint8List payload,
    Logger logger,
    InternetAddressType type,
  ) {
    final stride = type == InternetAddressType.IPv6 ? 18 : 6;
    final ipLen = type == InternetAddressType.IPv6 ? 16 : 4;
    final aligned = payload.length - (payload.length % stride);
    if (aligned <= 0) return;

    try {
      final view = ByteData.sublistView(payload, 0, aligned);
      for (var i = 0; i < aligned; i += stride) {
        final rawIp = Uint8List.sublistView(payload, i, i + ipLen);
        final ip = InternetAddress.fromRawAddress(rawIp, type: type);
        final port = view.getUint16(i + ipLen);
        event.addPeer(CompactAddress(ip, port));
      }
    } catch (e, st) {
      logger.warning(
        'Failed to parse compact peers for ${event.serverHost}',
        e,
        st,
      );
    }
  }
}
