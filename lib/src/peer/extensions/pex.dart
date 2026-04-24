import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';

import '../protocol/peer.dart';

const pexFlagPrefersEncryption = 0x01;

const pexFlagUploadOnly = 0x02;

const pexFlagSupportsUtp = 0x04;

const pexFlagSupportsHolepunch = 0x08;

const pexFlagReachable = 0x10;

mixin PEX {
  Timer? _timer;

  final Set<CompactAddress> _lastUTPEX = <CompactAddress>{};

  void startPEX() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: 60), (timer) {
      sendUtPexPeers();
    });
  }

  Iterable<Peer> get activePeers;

  void sendUtPexPeers() {
    final dropped = <CompactAddress>[];
    final added = <CompactAddress>[];
    for (final p in activePeers) {
      if (!_lastUTPEX.remove(p.address)) {
        added.add(p.address);
      }
    }
    for (final element in _lastUTPEX) {
      dropped.add(element);
    }
    _lastUTPEX.clear();

    final data = <String, List<int>>{};
    data['added'] = <int>[];
    for (final element in added) {
      _lastUTPEX.add(element);
      data['added']!.addAll(element.toBytes());
    }
    data['dropped'] = <int>[];
    for (final element in dropped) {
      data['dropped']!.addAll(element.toBytes());
    }
    if (data['added']!.isEmpty && data['dropped']!.isEmpty) return;
    final message = encode(data);
    for (final peer in activePeers) {
      peer.sendExtendMessage('ut_pex', message);
    }
  }

  void parsePEXDatas(Peer source, List<int> message) {
    final datas = decode(Uint8List.fromList(message));
    if (datas is! Map) return;
    _parseAdded(source, datas);
    _parseAdded(source, datas, 'added6', InternetAddressType.IPv6);
  }

  void _parseAdded(
    Peer source,
    Map<dynamic, dynamic> datas, [
    String keyStr = 'added',
    InternetAddressType type = InternetAddressType.IPv4,
  ]) {
    final added = _toByteList(datas[keyStr]);
    if (added == null || added.isEmpty) return;

    final ips = _parseCompactAddresses(added, type);
    if (ips.isEmpty) return;

    final flags = _toByteList(datas['$keyStr.f']);
    if (flags == null || flags.isEmpty) return;

    for (var i = 0; i < ips.length; i++) {
      if (i > flags.length - 1) {
        // Some messages can be malformed (flags count != ips count).
        continue;
      }
      final f = flags[i];
      final opts = _decodePexFlags(f);
      final address = ips[i];
      Timer.run(() => addPEXPeer(source, address, opts));
    }
  }

  void addPEXPeer(
    Peer source,
    CompactAddress address,
    Map<String, bool> options,
  );

  List<int>? _toByteList(dynamic value) {
    if (value is! List || value.isEmpty) return null;
    final intList = <int>[];
    for (var i = 0; i < value.length; i++) {
      final n = value[i];
      if (n is int && n >= 0 && n < 256) {
        intList.add(n);
      } else {
        return null;
      }
    }
    return intList;
  }

  List<CompactAddress> _parseCompactAddresses(
    List<int> bytes,
    InternetAddressType type,
  ) {
    try {
      if (type == InternetAddressType.IPv6) {
        return CompactAddress.parseIPv6Addresses(bytes);
      }
      return CompactAddress.parseIPv4Addresses(bytes);
    } catch (_) {
      return <CompactAddress>[];
    }
  }

  Map<String, bool> _decodePexFlags(int f) {
    final opts = <String, bool>{};
    if (f & pexFlagPrefersEncryption == pexFlagPrefersEncryption) {
      opts['e'] = true;
    }
    if (f & pexFlagUploadOnly == pexFlagUploadOnly) {
      opts['uploadonly'] = true;
    }
    if (f & pexFlagSupportsUtp == pexFlagSupportsUtp) {
      opts['utp'] = true;
    }
    if (f & pexFlagSupportsHolepunch == pexFlagSupportsHolepunch) {
      opts['holepunch'] = true;
    }
    if (f & pexFlagReachable == pexFlagReachable) {
      opts['reachable'] = true;
    }
    return opts;
  }

  void clearPEX() {
    _timer?.cancel();
    _lastUTPEX.clear();
  }
}
