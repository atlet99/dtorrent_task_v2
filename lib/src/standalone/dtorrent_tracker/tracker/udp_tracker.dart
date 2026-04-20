import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:logging/logging.dart';

import 'peer_event.dart';

import 'udp_tracker_base.dart';
import '../utils.dart';

import 'tracker.dart';

var _log = Logger('UDPTracker');

const _bep41OptionEndOfOptions = 0;
const _bep41OptionUrlData = 2;

/// UDP Tracker
class UDPTracker extends Tracker with UDPTrackerBase {
  String? _currentEvent;
  UDPTracker(Uri uri, Uint8List infoHashBuffer,
      {AnnounceOptionsProvider? provider})
      : super('udp:${uri.host}:${uri.port}', uri, infoHashBuffer,
            provider: provider);
  String? get currentEvent {
    return _currentEvent;
  }

  @override
  Future<List<CompactAddress>?> get addresses async {
    try {
      var ips = await InternetAddress.lookup(announceUrl.host);
      var l = <CompactAddress>[];
      for (var element in ips) {
        try {
          l.add(CompactAddress(element, announceUrl.port));
        } catch (e) {
          //
        }
      }
      return l;
    } catch (e) {
      return null;
    }
  }

  @override
  Future<PeerEvent?> announce(String eventType, Map<String, dynamic> options) {
    _currentEvent = eventType;
    return contactAnnouncer<PeerEvent>(options);
  }

  @override
  Uint8List generateSecondTouchMessage(Uint8List connectionId, Map options) {
    final list = <int>[];
    list.addAll(connectionId);

    list.addAll(
        ACTION_ANNOUNCE); // The type of Action is currently 'announce', which is represented as 1.
    list.addAll(transcationId!); // Session id
    list.addAll(infoHashBuffer);
    final peerId = (options['peerId'] ?? options['peer_id']) as String?;
    if (peerId == null || peerId.length != 20) {
      throw ArgumentError(
          'Missing or invalid peerId for UDP announce (must be 20 chars)');
    }
    list.addAll(utf8.encode(peerId));
    list.addAll(num2Uint64List(options['downloaded']));
    list.addAll(num2Uint64List(options['left']));
    list.addAll(num2Uint64List(options['uploaded']));
    var event = EVENTS[currentEvent];
    event ??= 0;
    list.addAll(num2Uint32List(event)); // This is the event type.
    list.addAll(
        num2Uint32List(_announceIpv4FromOption(options['ip']))); // default is 0
    list.addAll(
        num2Uint32List(options['key'] ?? 0)); // de-facto compatibility field
    list.addAll(num2Uint32List(options['numwant'] ??
        0xFFFFFFFF)); // default value of -1 in the wire format.
    list.addAll(num2Uint16List(options['port'])); // This is the TCP port.

    // BEP 41: append URLData options so UDP trackers can route by original
    // announce path/query (for example passkeys and custom endpoints).
    _appendBep41UrlDataOptions(list);
    list.add(_bep41OptionEndOfOptions);

    return Uint8List.fromList(list);
  }

  @override
  dynamic processResponseData(
      Uint8List data, int action, Iterable<CompactAddress> addresses) {
    if (data.length < 20) {
      // The data is incorrect
      throw Exception('announce data is wrong');
    }
    var view = ByteData.view(data.buffer);
    var event = PeerEvent(infoHash, announceUrl,
        interval: view.getUint32(8),
        incomplete: view.getUint32(16),
        complete: view.getUint32(12));
    final payload = data.sublist(20);
    final add = addresses.elementAt(0);
    final addressType = add.address.type;
    final splitPayload = _splitPeerPayloadAndOptions(
      payload,
      addressType == InternetAddressType.IPv4 ? 6 : 18,
    );
    final ips = splitPayload.peerPayload;
    try {
      if (addressType == InternetAddressType.IPv4) {
        var list = CompactAddress.parseIPv4Addresses(ips);
        for (var c in list) {
          event.addPeer(c);
        }
      } else if (addressType == InternetAddressType.IPv6) {
        var list = CompactAddress.parseIPv6Addresses(ips);
        for (var c in list) {
          event.addPeer(c);
        }
      }
    } catch (e) {
      // Error tolerance
      _log.warning('Error parsing peer IP : $ips , ${ips.length}', e);
    }
    if (splitPayload.options.isNotEmpty) {
      event.setInfo('udp_options', splitPayload.options);
    }
    if (splitPayload.hasExtensionFrame) {
      event.setInfo('udp_extensions_supported', true);
    }
    return event;
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
  void handleSocketDone() {
    dispose('Remote/Local close the socket');
  }

  @override
  void handleSocketError(e) {
    dispose(e);
  }

  int _announceIpv4FromOption(dynamic ipOption) {
    if (ipOption == null) return 0;
    try {
      final ip = ipOption is InternetAddress
          ? ipOption
          : InternetAddress.tryParse(ipOption.toString());
      if (ip == null || ip.type != InternetAddressType.IPv4) return 0;
      final bytes = ip.rawAddress;
      if (bytes.length != 4) return 0;
      return ByteData.sublistView(Uint8List.fromList(bytes)).getUint32(0);
    } catch (_) {
      return 0;
    }
  }

  void _appendBep41UrlDataOptions(List<int> out) {
    final path = announceUrl.path;
    final query = announceUrl.hasQuery ? '?${announceUrl.query}' : '';
    final pathAndQuery = '$path$query';
    if (pathAndQuery.isEmpty || pathAndQuery == '/') return;
    final raw = utf8.encode(pathAndQuery);
    var offset = 0;
    while (offset < raw.length) {
      final chunkSize =
          (raw.length - offset) > 255 ? 255 : (raw.length - offset);
      out.add(_bep41OptionUrlData);
      out.add(chunkSize);
      out.addAll(raw.sublist(offset, offset + chunkSize));
      offset += chunkSize;
    }
  }

  _PeerAndOptionsPayload _splitPeerPayloadAndOptions(
      Uint8List payload, int peerStride) {
    if (payload.isEmpty) {
      return _PeerAndOptionsPayload(
        peerPayload: Uint8List(0),
        options: <int, List<List<int>>>{},
        hasExtensionFrame: false,
      );
    }
    if (payload.length % peerStride == 0) {
      return _PeerAndOptionsPayload(
        peerPayload: payload,
        options: const {},
        hasExtensionFrame: false,
      );
    }
    for (var peerBytesLen = payload.length; peerBytesLen >= 0; peerBytesLen--) {
      if (peerBytesLen % peerStride != 0) continue;
      final optionBytes = payload.sublist(peerBytesLen);
      final parsed = _parseBep41Options(optionBytes);
      if (parsed != null &&
          (parsed.options.isNotEmpty || parsed.hasEndOfOptions)) {
        return _PeerAndOptionsPayload(
          peerPayload: payload.sublist(0, peerBytesLen),
          options: parsed.options,
          hasExtensionFrame: true,
        );
      }
    }
    return _PeerAndOptionsPayload(
      peerPayload: payload,
      options: const {},
      hasExtensionFrame: false,
    );
  }

  _ParsedBep41Options? _parseBep41Options(Uint8List bytes) {
    final options = <int, List<List<int>>>{};
    var hasEndOfOptions = false;
    var i = 0;
    while (i < bytes.length) {
      final type = bytes[i];
      i += 1;
      if (type == _bep41OptionEndOfOptions) {
        hasEndOfOptions = true;
        break;
      }
      if (i >= bytes.length) return null;
      final len = bytes[i];
      i += 1;
      if (i + len > bytes.length) return null;
      final data = bytes.sublist(i, i + len);
      i += len;
      options.putIfAbsent(type, () => <List<int>>[]).add(data);
    }
    return _ParsedBep41Options(
      options: options,
      hasEndOfOptions: hasEndOfOptions,
    );
  }
}

class _PeerAndOptionsPayload {
  final Uint8List peerPayload;
  final Map<int, List<List<int>>> options;
  final bool hasExtensionFrame;

  const _PeerAndOptionsPayload({
    required this.peerPayload,
    required this.options,
    required this.hasExtensionFrame,
  });
}

class _ParsedBep41Options {
  final Map<int, List<List<int>>> options;
  final bool hasEndOfOptions;

  const _ParsedBep41Options({
    required this.options,
    required this.hasEndOfOptions,
  });
}
