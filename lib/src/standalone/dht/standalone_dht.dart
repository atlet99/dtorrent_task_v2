import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:events_emitter2/events_emitter2.dart';

/// Base event type for standalone DHT facade.
abstract class StandaloneDHTEvent {}

/// Emitted when DHT discovers a new peer for an info-hash.
class StandaloneDHTNewPeerEvent implements StandaloneDHTEvent {
  final Object address;
  final String infoHash;

  const StandaloneDHTNewPeerEvent({
    required this.address,
    required this.infoHash,
  });
}

/// Emitted when retry policy is applied.
class StandaloneDHTRetryEvent implements StandaloneDHTEvent {
  final String operation;
  final int attempt;
  final Duration delay;
  final Object error;

  const StandaloneDHTRetryEvent({
    required this.operation,
    required this.attempt,
    required this.delay,
    required this.error,
  });
}

/// Emitted when DHT implementation reports an error.
class StandaloneDHTErrorEvent implements StandaloneDHTEvent {
  final String message;

  const StandaloneDHTErrorEvent(this.message);
}

/// Emitted when read-only mode is toggled (BEP 43).
class StandaloneDHTReadOnlyChangedEvent implements StandaloneDHTEvent {
  final bool readOnly;

  const StandaloneDHTReadOnlyChangedEvent(this.readOnly);
}

enum StandaloneDHTAddressFamilyMode {
  ipv4Only,
  ipv6Only,
  dualStackPreferIPv4,
  dualStackPreferIPv6,
}

/// Emitted when DHT address-family mode is changed (BEP 7 / BEP 32).
class StandaloneDHTAddressFamilyChangedEvent implements StandaloneDHTEvent {
  final StandaloneDHTAddressFamilyMode mode;

  const StandaloneDHTAddressFamilyChangedEvent(this.mode);
}

abstract class StandaloneDHTDriverEvent {}

class StandaloneDHTDriverNewPeerEvent implements StandaloneDHTDriverEvent {
  final Object address;
  final String infoHash;

  StandaloneDHTDriverNewPeerEvent({
    required this.address,
    required this.infoHash,
  });
}

class StandaloneDHTDriverErrorEvent implements StandaloneDHTDriverEvent {
  final String message;

  StandaloneDHTDriverErrorEvent(this.message);
}

abstract class StandaloneDHTDriver {
  Stream<StandaloneDHTDriverEvent> get events;

  bool get readOnly;
  set readOnly(bool value);
  StandaloneDHTAddressFamilyMode get addressFamilyMode;
  set addressFamilyMode(StandaloneDHTAddressFamilyMode value);

  Future<int?> bootstrap({int port});

  void announce(String infoHash, int port);

  void requestPeers(String infoHash);

  Future<void> addBootstrapNode(Uri url);

  Future<void> stop();
}

class _PendingQuery {
  final String kind;
  final CompactAddress node;
  final String? infoHash;

  _PendingQuery({
    required this.kind,
    required this.node,
    this.infoHash,
  });
}

/// In-repo minimal Mainline-DHT driver (UDP + KRPC).
///
/// Scope:
/// - bootstrap via router nodes
/// - find_node -> maintain node table
/// - get_peers -> emit discovered peers
/// - announce_peer when token is available
class InRepoStandaloneDHTDriver implements StandaloneDHTDriver {
  static final List<Uri> _defaultBootstrapNodes = [
    Uri.parse('udp://router.bittorrent.com:6881'),
    Uri.parse('udp://router.utorrent.com:6881'),
    Uri.parse('udp://dht.transmissionbt.com:6881'),
  ];

  final StreamController<StandaloneDHTDriverEvent> _controller =
      StreamController<StandaloneDHTDriverEvent>.broadcast();
  final Map<String, CompactAddress> _nodes = {};
  final Map<String, _PendingQuery> _pendingQueries = {};
  final Map<String, Map<String, List<int>>> _tokensByNodeAndInfoHash = {};
  final Map<String, int> _announcePorts = {};
  final Set<Uri> _bootstrapNodes = {};

  RawDatagramSocket? _socketV4;
  RawDatagramSocket? _socketV6;
  StreamSubscription<RawSocketEvent>? _socketSubV4;
  StreamSubscription<RawSocketEvent>? _socketSubV6;
  bool _stopped = false;
  bool _readOnly = false;
  StandaloneDHTAddressFamilyMode _addressFamilyMode =
      StandaloneDHTAddressFamilyMode.dualStackPreferIPv4;
  int _tidCounter = 0;
  late final List<int> _nodeId;

  InRepoStandaloneDHTDriver() {
    _nodeId = randomBytes(20, true);
    _bootstrapNodes.addAll(_defaultBootstrapNodes);
  }

  @override
  Stream<StandaloneDHTDriverEvent> get events => _controller.stream;

  @override
  bool get readOnly => _readOnly;

  @override
  set readOnly(bool value) {
    _readOnly = value;
  }

  @override
  StandaloneDHTAddressFamilyMode get addressFamilyMode => _addressFamilyMode;

  @override
  set addressFamilyMode(StandaloneDHTAddressFamilyMode value) {
    _addressFamilyMode = value;
  }

  @override
  Future<int?> bootstrap({int port = 0}) async {
    _stopped = false;
    if (_hasAnySocket) return _preferredSocket()?.port;

    if (_isFamilyEnabled(InternetAddressType.IPv4)) {
      try {
        _socketV4 = await RawDatagramSocket.bind(InternetAddress.anyIPv4, port);
        _socketSubV4 = _socketV4!.listen(
          (event) => _handleSocketEvent(_socketV4!, event),
          onError: (Object e) => _emitError('IPv4 socket error: $e'),
        );
      } catch (e) {
        _emitError('IPv4 bootstrap bind failed: $e');
        if (_addressFamilyMode == StandaloneDHTAddressFamilyMode.ipv4Only) {
          rethrow;
        }
      }
    }
    if (_isFamilyEnabled(InternetAddressType.IPv6)) {
      try {
        _socketV6 = await RawDatagramSocket.bind(InternetAddress.anyIPv6, port);
        _socketSubV6 = _socketV6!.listen(
          (event) => _handleSocketEvent(_socketV6!, event),
          onError: (Object e) => _emitError('IPv6 socket error: $e'),
        );
      } catch (e) {
        _emitError('IPv6 bootstrap bind failed: $e');
        if (_addressFamilyMode == StandaloneDHTAddressFamilyMode.ipv6Only) {
          rethrow;
        }
      }
    }
    if (!_hasAnySocket) {
      throw StateError('DHT bootstrap failed: no UDP sockets available');
    }

    for (final uri in _bootstrapNodes) {
      await _bootstrapViaNode(uri);
    }
    return _preferredSocket()?.port;
  }

  bool get _hasAnySocket => _socketV4 != null || _socketV6 != null;

  RawDatagramSocket? _preferredSocket() {
    if (_addressFamilyMode == StandaloneDHTAddressFamilyMode.ipv6Only) {
      return _socketV6;
    }
    if (_addressFamilyMode == StandaloneDHTAddressFamilyMode.ipv4Only) {
      return _socketV4;
    }
    if (_addressFamilyMode ==
        StandaloneDHTAddressFamilyMode.dualStackPreferIPv6) {
      return _socketV6 ?? _socketV4;
    }
    return _socketV4 ?? _socketV6;
  }

  bool _isFamilyEnabled(InternetAddressType type) {
    switch (_addressFamilyMode) {
      case StandaloneDHTAddressFamilyMode.ipv4Only:
        return type == InternetAddressType.IPv4;
      case StandaloneDHTAddressFamilyMode.ipv6Only:
        return type == InternetAddressType.IPv6;
      case StandaloneDHTAddressFamilyMode.dualStackPreferIPv4:
      case StandaloneDHTAddressFamilyMode.dualStackPreferIPv6:
        return true;
    }
  }

  void _handleSocketEvent(RawDatagramSocket socket, RawSocketEvent event) {
    if (_stopped || event != RawSocketEvent.read) return;

    try {
      Datagram? d;
      while ((d = socket.receive()) != null) {
        _handleDatagram(d!);
      }
    } catch (e) {
      _emitError('datagram receive failed: $e');
    }
  }

  void _handleDatagram(Datagram datagram) {
    Object? message;
    try {
      message = decode(datagram.data);
    } catch (e) {
      _emitError('decode failed from ${datagram.address}:${datagram.port}: $e');
      return;
    }

    if (message is! Map) return;
    if (message['y'] != 'r') return;

    final tidBytes = _asBytes(message['t']);
    if (tidBytes == null || tidBytes.isEmpty) return;
    final tid = String.fromCharCodes(tidBytes);
    final pending = _pendingQueries.remove(tid);

    final response = message['r'];
    if (response is! Map) return;

    final nodesData = _asBytes(response['nodes']);
    if (nodesData != null && nodesData.isNotEmpty) {
      _addNodesFromCompact(nodesData, false);
    }

    final nodes6Data = _asBytes(response['nodes6']);
    if (nodes6Data != null && nodes6Data.isNotEmpty) {
      _addNodesFromCompact(nodes6Data, true);
    }

    if (pending == null ||
        pending.kind != 'get_peers' ||
        pending.infoHash == null) {
      return;
    }

    final infoHash = pending.infoHash!;

    final values = response['values'];
    if (values is List) {
      for (final value in values) {
        final compact = _asBytes(value);
        if (compact == null) continue;
        final peers = _parseCompactPeers(compact);
        for (final peer in peers) {
          _controller.add(
            StandaloneDHTDriverNewPeerEvent(
              address: peer,
              infoHash: infoHash,
            ),
          );
        }
      }
    }

    final token = _asBytes(response['token']);
    if (token != null && token.isNotEmpty) {
      final endpoint = _endpoint(pending.node);
      _tokensByNodeAndInfoHash.putIfAbsent(endpoint, () => {});
      _tokensByNodeAndInfoHash[endpoint]![infoHash] = token;

      final announcePort = _announcePorts[infoHash];
      if (!_readOnly && announcePort != null) {
        _sendAnnouncePeer(
          node: pending.node,
          infoHash: infoHash,
          port: announcePort,
          token: token,
        );
      }
    }
  }

  void _addNodesFromCompact(List<int> nodesData, bool ipv6) {
    final stride = ipv6 ? 38 : 26;
    for (var offset = 0;
        offset + stride <= nodesData.length;
        offset += stride) {
      final addrOffset = offset + 20;
      final address = ipv6
          ? CompactAddress.parseIPv6Address(nodesData, addrOffset)
          : CompactAddress.parseIPv4Address(nodesData, addrOffset);
      if (address == null) continue;
      _nodes.putIfAbsent(_endpoint(address), () => address);
    }
  }

  List<CompactAddress> _parseCompactPeers(List<int> bytes) {
    if (bytes.length == 6) {
      final a = CompactAddress.parseIPv4Address(bytes, 0);
      return a == null ? const [] : [a];
    }
    if (bytes.length == 18) {
      final a = CompactAddress.parseIPv6Address(bytes, 0);
      return a == null ? const [] : [a];
    }
    if (bytes.length % 6 == 0) {
      return CompactAddress.parseIPv4Addresses(bytes);
    }
    if (bytes.length % 18 == 0) {
      return CompactAddress.parseIPv6Addresses(bytes);
    }
    return const [];
  }

  @override
  void announce(String infoHash, int port) {
    if (_stopped || !_hasAnySocket) return;
    if (_readOnly) {
      _emitError('announce ignored: read-only mode enabled (BEP 43)');
      return;
    }
    if (infoHash.length != 20) {
      throw ArgumentError.value(infoHash, 'infoHash', 'must be 20-byte string');
    }
    _announcePorts[infoHash] = port;
    requestPeers(infoHash);
  }

  @override
  void requestPeers(String infoHash) {
    if (_stopped || !_hasAnySocket) return;
    if (infoHash.length != 20) {
      throw ArgumentError.value(infoHash, 'infoHash', 'must be 20-byte string');
    }

    final nodes = _nodes.values.toList()
      ..sort((a, b) => _addressPriority(a.address.type)
          .compareTo(_addressPriority(b.address.type)));
    for (final node in nodes) {
      _sendGetPeers(node: node, infoHash: infoHash);
    }
  }

  @override
  Future<void> addBootstrapNode(Uri url) async {
    _bootstrapNodes.add(url);
    if (_hasAnySocket && !_stopped) {
      await _bootstrapViaNode(url);
    }
  }

  Future<void> _bootstrapViaNode(Uri url) async {
    final host = url.host;
    final port = url.hasPort ? url.port : 6881;

    try {
      final ip = InternetAddress.tryParse(host);
      if (ip != null) {
        if (_isFamilyEnabled(ip.type)) {
          _sendFindNode(CompactAddress(ip, port));
        }
        return;
      }

      final ips = await InternetAddress.lookup(host);
      for (final resolved in ips) {
        if (_isFamilyEnabled(resolved.type)) {
          _sendFindNode(CompactAddress(resolved, port));
        }
      }
    } catch (e) {
      _emitError('bootstrap lookup failed for $url: $e');
    }
  }

  void _sendFindNode(CompactAddress node) {
    _nodes.putIfAbsent(_endpoint(node), () => node);
    final target = randomBytes(20, true);
    _sendQuery(
      node: node,
      query: 'find_node',
      args: {
        'id': _nodeId,
        'target': target,
      },
      pending: _PendingQuery(kind: 'find_node', node: node),
    );
  }

  void _sendGetPeers({required CompactAddress node, required String infoHash}) {
    final infoHashBytes = infoHash.codeUnits;
    _sendQuery(
      node: node,
      query: 'get_peers',
      args: {
        'id': _nodeId,
        'info_hash': infoHashBytes,
      },
      pending: _PendingQuery(kind: 'get_peers', node: node, infoHash: infoHash),
    );
  }

  void _sendAnnouncePeer({
    required CompactAddress node,
    required String infoHash,
    required int port,
    required List<int> token,
  }) {
    _sendQuery(
      node: node,
      query: 'announce_peer',
      args: {
        'id': _nodeId,
        'info_hash': infoHash.codeUnits,
        'port': port,
        'token': token,
        'implied_port': 0,
      },
      pending:
          _PendingQuery(kind: 'announce_peer', node: node, infoHash: infoHash),
    );
  }

  void _sendQuery({
    required CompactAddress node,
    required String query,
    required Map<String, dynamic> args,
    required _PendingQuery pending,
  }) {
    final socket = _socketForAddress(node.address.type);
    if (_stopped || socket == null) return;

    final tid = _nextTid();
    _pendingQueries[tid] = pending;

    final packet = {
      't': tid.codeUnits,
      'y': 'q',
      'q': query,
      'a': args,
      if (_readOnly) 'ro': 1,
    };

    try {
      final encoded = encode(packet);
      socket.send(encoded, node.address, node.port);
    } catch (e) {
      _pendingQueries.remove(tid);
      _emitError('send $query failed to $node: $e');
    }
  }

  RawDatagramSocket? _socketForAddress(InternetAddressType type) {
    if (type == InternetAddressType.IPv6) {
      return _socketV6 ??
          (_isFamilyEnabled(InternetAddressType.IPv4) ? _socketV4 : null);
    }
    return _socketV4 ??
        (_isFamilyEnabled(InternetAddressType.IPv6) ? _socketV6 : null);
  }

  int _addressPriority(InternetAddressType type) {
    if (_addressFamilyMode ==
        StandaloneDHTAddressFamilyMode.dualStackPreferIPv6) {
      return type == InternetAddressType.IPv6 ? 0 : 1;
    }
    if (_addressFamilyMode ==
        StandaloneDHTAddressFamilyMode.dualStackPreferIPv4) {
      return type == InternetAddressType.IPv4 ? 0 : 1;
    }
    return 0;
  }

  String _nextTid() {
    _tidCounter++;
    if (_tidCounter > 0xffff) _tidCounter = 1;
    final hi = (_tidCounter >> 8) & 0xff;
    final lo = _tidCounter & 0xff;
    return String.fromCharCodes([hi, lo]);
  }

  List<int>? _asBytes(Object? value) {
    if (value is List<int>) return value;
    if (value is String) return value.codeUnits;
    return null;
  }

  String _endpoint(CompactAddress a) => '${a.address.address}:${a.port}';

  void _emitError(String message) {
    if (_controller.isClosed) return;
    _controller.add(StandaloneDHTDriverErrorEvent(message));
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _socketSubV4?.cancel();
    await _socketSubV6?.cancel();
    _socketSubV4 = null;
    _socketSubV6 = null;
    _socketV4?.close();
    _socketV6?.close();
    _socketV4 = null;
    _socketV6 = null;
    _nodes.clear();
    _pendingQueries.clear();
    _tokensByNodeAndInfoHash.clear();
    _announcePorts.clear();
    if (!_controller.isClosed) {
      await _controller.close();
    }
  }
}

/// Stable in-repo facade for DHT operations.
abstract class StandaloneDHT with EventsEmittable<StandaloneDHTEvent> {
  StandaloneDHT._();

  factory StandaloneDHT() = BittorrentDHTAdapter;

  bool get readOnly;
  StandaloneDHTAddressFamilyMode get addressFamilyMode;

  void setReadOnly(bool value);
  void setAddressFamilyMode(StandaloneDHTAddressFamilyMode value);

  Future<int?> bootstrap({int port});

  void announce(String infoHash, int port);

  void requestPeers(String infoHash);

  Future<void> addBootstrapNode(Uri url);

  Future<void> stop();
}

/// Adapter for DHT driver with retry/backoff policy.
class BittorrentDHTAdapter extends StandaloneDHT {
  final StandaloneDHTDriver _driver;
  final int _bootstrapMaxAttempts;
  final int _operationMaxAttempts;
  final Duration _retryBaseDelay;
  final Duration _retryMaxDelay;
  final double _retryJitterRatio;
  final Random _random;

  StreamSubscription<StandaloneDHTDriverEvent>? _eventsSub;
  bool _stopped = false;

  BittorrentDHTAdapter({
    StandaloneDHTDriver? driver,
    int bootstrapMaxAttempts = 3,
    int operationMaxAttempts = 2,
    Duration retryBaseDelay = const Duration(milliseconds: 150),
    Duration retryMaxDelay = const Duration(seconds: 2),
    double retryJitterRatio = 0.1,
    Random? random,
  })  : _driver = driver ?? InRepoStandaloneDHTDriver(),
        _bootstrapMaxAttempts = bootstrapMaxAttempts,
        _operationMaxAttempts = operationMaxAttempts,
        _retryBaseDelay = retryBaseDelay,
        _retryMaxDelay = retryMaxDelay,
        _retryJitterRatio = retryJitterRatio,
        _random = random ?? Random(),
        super._() {
    _eventsSub = _driver.events.listen(_handleDriverEvent);
  }

  void _handleDriverEvent(StandaloneDHTDriverEvent event) {
    if (event is StandaloneDHTDriverNewPeerEvent) {
      events.emit(
        StandaloneDHTNewPeerEvent(
          address: event.address,
          infoHash: event.infoHash,
        ),
      );
      return;
    }
    if (event is StandaloneDHTDriverErrorEvent) {
      events.emit(StandaloneDHTErrorEvent(event.message));
    }
  }

  Duration _retryDelay(int attempt) {
    final exp = 1 << (attempt - 1);
    final baseMs = _retryBaseDelay.inMilliseconds;
    final maxMs = _retryMaxDelay.inMilliseconds;
    var delayMs = baseMs * exp;
    if (delayMs > maxMs) delayMs = maxMs;
    if (_retryJitterRatio > 0) {
      final jitter = (delayMs * _retryJitterRatio).round();
      final offset = _random.nextInt(jitter * 2 + 1) - jitter;
      delayMs += offset;
      if (delayMs < 0) delayMs = 0;
    }
    return Duration(milliseconds: delayMs);
  }

  @override
  bool get readOnly => _driver.readOnly;

  @override
  StandaloneDHTAddressFamilyMode get addressFamilyMode =>
      _driver.addressFamilyMode;

  @override
  void setReadOnly(bool value) {
    if (_driver.readOnly == value) return;
    _driver.readOnly = value;
    events.emit(StandaloneDHTReadOnlyChangedEvent(value));
  }

  @override
  void setAddressFamilyMode(StandaloneDHTAddressFamilyMode value) {
    if (_driver.addressFamilyMode == value) return;
    _driver.addressFamilyMode = value;
    events.emit(StandaloneDHTAddressFamilyChangedEvent(value));
  }

  @override
  Future<int?> bootstrap({int port = 0}) async {
    _stopped = false;
    Object? lastError;
    for (var attempt = 1; attempt <= _bootstrapMaxAttempts; attempt++) {
      if (_stopped) return null;
      try {
        final result = await _driver.bootstrap(port: port);
        if (result != null) return result;
        throw StateError('DHT bootstrap returned null port');
      } catch (e) {
        lastError = e;
        if (attempt >= _bootstrapMaxAttempts) break;
        final delay = _retryDelay(attempt);
        events.emit(StandaloneDHTRetryEvent(
          operation: 'bootstrap',
          attempt: attempt + 1,
          delay: delay,
          error: e,
        ));
        await Future.delayed(delay);
      }
    }
    if (lastError != null) {
      events.emit(StandaloneDHTErrorEvent('bootstrap failed: $lastError'));
    }
    return null;
  }

  Future<void> _retryVoidOperation({
    required String operation,
    required void Function() run,
    required Object initialError,
  }) async {
    var lastError = initialError;
    for (var attempt = 2; attempt <= _operationMaxAttempts; attempt++) {
      if (_stopped) return;
      final delay = _retryDelay(attempt - 1);
      events.emit(StandaloneDHTRetryEvent(
        operation: operation,
        attempt: attempt,
        delay: delay,
        error: lastError,
      ));
      await Future.delayed(delay);
      try {
        run();
        return;
      } catch (e) {
        lastError = e;
      }
    }
    events.emit(StandaloneDHTErrorEvent('$operation failed: $lastError'));
  }

  @override
  void announce(String infoHash, int port) {
    if (_stopped) return;
    if (_driver.readOnly) {
      events.emit(
        const StandaloneDHTErrorEvent(
          'announce ignored: read-only mode enabled (BEP 43)',
        ),
      );
      return;
    }
    try {
      _driver.announce(infoHash, port);
    } catch (e) {
      unawaited(
        _retryVoidOperation(
          operation: 'announce',
          run: () => _driver.announce(infoHash, port),
          initialError: e,
        ),
      );
    }
  }

  @override
  void requestPeers(String infoHash) {
    if (_stopped) return;
    try {
      _driver.requestPeers(infoHash);
    } catch (e) {
      unawaited(
        _retryVoidOperation(
          operation: 'requestPeers',
          run: () => _driver.requestPeers(infoHash),
          initialError: e,
        ),
      );
    }
  }

  @override
  Future<void> addBootstrapNode(Uri url) {
    return _driver.addBootstrapNode(url);
  }

  @override
  Future<void> stop() async {
    _stopped = true;
    await _driver.stop();
    await _eventsSub?.cancel();
    _eventsSub = null;
  }
}
