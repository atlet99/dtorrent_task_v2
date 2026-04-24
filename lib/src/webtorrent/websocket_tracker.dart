import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';

import '../standalone/dtorrent_tracker/tracker/peer_event.dart';
import '../standalone/dtorrent_tracker/tracker/tracker.dart';
import '../standalone/dtorrent_tracker/tracker/tracker_exception.dart';

final _log = Logger('WebSocketTracker');

/// WebSocket tracker announce client used by WebTorrent-compatible trackers.
///
/// This handles the tracker signalling layer. WebRTC peer transport is modeled
/// separately, so offer/answer/candidate payloads are exposed as tracker metadata.
class WebSocketTracker extends Tracker {
  WebSocket? _socket;
  String? _currentEvent;

  WebSocketTracker(
    Uri uri,
    Uint8List infoHashBuffer, {
    AnnounceOptionsProvider? provider,
  }) : super('${uri.scheme}:${uri.host}:${uri.port}${uri.path}', uri,
            infoHashBuffer,
            provider: provider);

  String? get currentEvent => _currentEvent;

  @override
  Future<PeerEvent?> announce(
    String eventType,
    Map<String, dynamic> options,
  ) async {
    _currentEvent = eventType;
    final socket = await WebSocket.connect(announceUrl.toString());
    _socket = socket;
    try {
      socket.add(jsonEncode(_announcePayload(eventType, options)));
      final response = await socket.first.timeout(const Duration(seconds: 15));
      return _parseResponse(response);
    } finally {
      await close();
    }
  }

  Map<String, Object?> _announcePayload(
    String eventType,
    Map<String, dynamic> options,
  ) {
    final peerId = (options['peerId'] ?? options['peer_id']) as String?;
    if (peerId == null || peerId.length != 20) {
      throw ArgumentError(
        'Missing or invalid peerId for WebSocket announce (must be 20 chars)',
      );
    }

    return <String, Object?>{
      'action': 'announce',
      'info_hash': String.fromCharCodes(infoHashBuffer),
      'peer_id': peerId,
      'downloaded': _asInt(options['downloaded']) ?? 0,
      'uploaded': _asInt(options['uploaded']) ?? 0,
      'left': _asInt(options['left']) ?? 0,
      'numwant': _asInt(options['numwant']) ?? 50,
      if (eventType != EVENT_UPDATE) 'event': eventType,
    };
  }

  PeerEvent _parseResponse(Object? response) {
    final decoded = switch (response) {
      String text => jsonDecode(text),
      List<int> bytes => jsonDecode(utf8.decode(bytes)),
      _ =>
        throw const FormatException('Unsupported WebSocket tracker response'),
    };
    if (decoded is! Map) {
      throw const FormatException('WebSocket tracker response is not a map');
    }

    final action = decoded['action'];
    if (action != null && action != 'announce') {
      throw FormatException('Unexpected WebSocket tracker action: $action');
    }

    final failure = decoded['failure reason'] ?? decoded['failure_reason'];
    if (failure != null) {
      throw TrackerException(id, failure);
    }

    final event = PeerEvent(
      infoHash,
      announceUrl,
      interval: _asInt(decoded['interval']),
      minInterval: _asInt(decoded['min interval'] ?? decoded['min_interval']),
      complete: _asInt(decoded['complete']),
      incomplete: _asInt(decoded['incomplete']),
      warning: _asString(decoded['warning message'] ?? decoded['warning']),
    );

    _copyMetadata(event, decoded, 'peer_id');
    _copyMetadata(event, decoded, 'offer');
    _copyMetadata(event, decoded, 'answer');
    _copyMetadata(event, decoded, 'offers');
    _copyMetadata(event, decoded, 'ice');
    _copyMetadata(event, decoded, 'to_peer_id');
    _copyMetadata(event, decoded, 'webtorrent_peers', fromKey: 'peers');
    return event;
  }

  void _copyMetadata(
    PeerEvent event,
    Map<Object?, Object?> decoded,
    String targetKey, {
    String? fromKey,
  }) {
    final sourceKey = fromKey ?? targetKey;
    if (decoded.containsKey(sourceKey)) {
      event.setInfo(targetKey, decoded[sourceKey]);
    }
  }

  int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  String? _asString(Object? value) {
    if (value == null) return null;
    if (value is String) return value;
    return value.toString();
  }

  @override
  Future<void> close() async {
    final socket = _socket;
    _socket = null;
    if (socket == null) return;
    try {
      await socket.close();
    } catch (e, st) {
      _log.fine('WebSocket tracker close failed', e, st);
    }
  }
}
