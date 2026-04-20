import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'announce_response_parser.dart';
import 'peer_event.dart';
import 'http_tracker_base.dart';
import 'tracker.dart';

var _log = Logger('HttpTracker');

/// Torrent http/https tracker implement.
///
/// Torrent http tracker protocol specification :
/// [HTTP/HTTPS Tracker Protocol](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_HTTP.2FHTTPS_Protocol).
///
class HttpTracker extends Tracker with HttpTrackerBase {
  String? _trackerId;
  String? _currentEvent;
  HttpTracker(Uri uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super('http:${uri.host}:${uri.port}${uri.path}', uri, infoHashBuffer,
            provider: provider);

  String? get currentTrackerId {
    return _trackerId;
  }

  String? get currentEvent {
    return _currentEvent;
  }

  @override
  Future<PeerEvent?> stop([bool force = false]) async {
    await close();
    var f = super.stop(force);
    return f;
  }

  @override
  Future<PeerEvent?> complete() async {
    await close();
    var f = super.complete();
    return f;
  }

  @override
  Future dispose([dynamic reason]) async {
    await close();
    return super.dispose(reason);
  }

  @override
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent =
        eventType; // save the current event, stop and complete will also call this method, so the current event type should be recorded here
    return httpGet<PeerEvent>(options);
  }

  ///
  /// Create an access URL string for 'announce'.
  /// For more information, visit [HTTP/HTTPS Tracker Request Parameters](https://wiki.theory.org/index.php/BitTorrentSpecification#Tracker_Request_Parameters)
  ///
  /// Regarding the query parameters for access:
  /// - compact: I keep setting bit 1.
  /// - downloaded: The number of bytes downloaded.
  /// - uploaded: The number of bytes uploaded.
  /// - left: The number of bytes left to download.
  /// - numwant: Optional. The default value here is 50, it's better not to set it to -1 as some addresses may consider it an illegal number.
  /// - info_hash: Required. Comes from the torrent file. Note that we don't use Uri's urlencode to obtain it because this class uses UTF-8 encoding when generating the query string, which causes issues with correctly encoding some special characters in the info_hash. So here, we handle it manually.
  /// - port: Required. TCP listening port.
  /// - peer_id: Required. A randomly generated string of 20 characters. It should be query string encoded, but currently, I use only digits and alphabets, so I directly use it.
  /// - event: Must be one of "stopped," "started," or "completed." According to the protocol, the first visit must be "started." If not specified, the other party will consider it a regular announce visit.
  /// - trackerid: Optional. If the previous request contained a trackerid, it should be set. Some responses may include a tracker ID, and if so, I will set this field.
  /// - ip: Optional.
  /// - key: Optional.
  /// - no_peer_id: If compact is specified, this field will be ignored. I always set compact to 1 here, so I don't set this value.
  ///
  @override
  Map<String, String> generateQueryParameters(Map<String, dynamic> options) {
    final params = <String, String>{};
    params['compact'] = (options['compact'] ?? 1).toString();
    params['downloaded'] = _requireOption(options, 'downloaded').toString();
    params['uploaded'] = _requireOption(options, 'uploaded').toString();
    params['left'] = _requireOption(options, 'left').toString();
    params['numwant'] = (options['numwant'] ?? 50).toString();
    // infohash value usually can not be decode by utf8, because some special character,
    // so I transform them with String.fromCharCodes , when transform them to the query component, use latin1 encoding
    params['info_hash'] = Uri.encodeQueryComponent(
        String.fromCharCodes(infoHashBuffer),
        encoding: latin1);
    params['port'] = _requireOption(options, 'port').toString();
    params['peer_id'] =
        _requireOption(options, 'peerId', fallbackKey: 'peer_id').toString();
    var event = currentEvent;
    if (event != null) {
      params['event'] = event;
    } else {
      params['event'] = EVENT_STARTED;
    }

    // De-facto compatibility fields used by real trackers.
    final trackerIdFromOptions = options['trackerid'];
    if (trackerIdFromOptions != null) {
      params['trackerid'] = trackerIdFromOptions.toString();
    } else if (currentTrackerId != null) {
      params['trackerid'] = currentTrackerId!;
    }
    if (options['key'] != null) {
      params['key'] = options['key'].toString();
    }
    if (options['no_peer_id'] != null) {
      params['no_peer_id'] = options['no_peer_id'].toString();
    }
    if (options['ip'] != null) {
      params['ip'] = options['ip'].toString();
    }

    // BEP 7 explicitly discourages &ipv4= / &ipv6= on announce due to abuse
    // potential. Keep compatibility by ignoring such values.
    if (options.containsKey('ipv4') || options.containsKey('ipv6')) {
      _log.warning('Ignoring discouraged announce params: ipv4/ipv6');
    }

    return params;
  }

  dynamic _requireOption(Map<String, dynamic> options, String key,
      {String? fallbackKey}) {
    final value =
        options[key] ?? (fallbackKey != null ? options[fallbackKey] : null);
    if (value == null) {
      throw ArgumentError('Missing required announce option: $key');
    }
    return value;
  }

  ///
  /// Decode the return bytebuffer with bencoder.
  ///
  /// - Get the 'interval' value , and make sure the return Map contains it(or null), because the Tracker
  /// will check the return Map , if it has 'interval' value , Tracker will update the interval timer.
  /// - If it has 'tracker id' , need to store it , use it next time.
  /// - parse 'peers' informations. the peers usually is a `List<int>`, need to parse it to 'n.n.n.n:p' formate
  /// ip address.
  /// - Sometimes , the remote will return 'failer reason', then need to throw a exception
  @override
  PeerEvent processResponseData(Uint8List data) {
    final parsed = AnnounceResponseParser.parseHttpAnnounce(
      data: data,
      infoHash: infoHash,
      trackerUrl: url,
      trackerId: id,
      logger: _log,
    );
    if (parsed.trackerId != null) {
      _trackerId = parsed.trackerId;
    }
    return parsed.event;
  }

  @override
  Uri get url => announceUrl;
}
