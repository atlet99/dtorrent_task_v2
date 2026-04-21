import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/peer/peer_base.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:events_emitter2/events_emitter2.dart';

mixin ExtendedProcessor on EventsEmittable<PeerEvent> {
  // Remote map of id to extension name
  final Map<int, String> _extendedEventMap = {};
  int _id = 1;

  // The raw `m` dictionary returned from the remote peer
  final Map<String, int> _rawMap = <String, int>{};
  final Map<int, String> _localExtended = <int, String>{};

  Map<String, int> get localExtended {
    final map = <String, int>{};
    _localExtended.forEach((key, value) {
      map[value] = key;
    });
    return map;
  }

  /// Called to register an extension
  /// the id is auto incremented and starts with 1
  void registerExtend(String name) {
    _localExtended[_id] = name;
    _id++;
  }

  int? getExtendedEventId(String name) {
    return _rawMap[name];
  }

  String? getExtendedEventNameById(int id) {
    return _extendedEventMap[id] ?? _localExtended[id];
  }

  void processExtendMessage(int id, Uint8List message) {
    if (id == 0) {
      // this is a handshake extended message
      final data = decode(message);
      processExtendHandshake(data);
    } else {
      final name = getExtendedEventNameById(id);
      if (name != null) {
        final peer = _tryGetPeer();
        if (peer != null) {
          events.emit(ExtendedEvent(peer, name, message));
        }
      }
    }
  }

  void processExtendHandshake(Object? data) {
    if (data is! Map || !data.containsKey('m')) {
      // this is not a handshake message
      return;
    }
    final extMapDynamic = data['m'];
    if (extMapDynamic is! Map) return;

    _rawMap.clear();
    _extendedEventMap.clear();
    extMapDynamic.forEach((key, value) {
      if (key is! String || value is! int || value == 0) return;
      _rawMap[key] = value;
      _extendedEventMap[value] = key;
    });

    final peer = _tryGetPeer();
    if (peer != null) {
      events.emit(ExtendedEvent(peer, 'handshake', data));
    }
  }

  void clearExtendedProcessors() {
    _extendedEventMap.clear();
    _rawMap.clear();
    _localExtended.clear();
    _id = 1;
  }

  Peer? _tryGetPeer() {
    final self = this;
    if (self is Peer) return self;
    return null;
  }
}
