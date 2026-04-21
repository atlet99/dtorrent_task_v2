import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ipify/dart_ipify.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_model.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer_events.dart';
import 'package:dtorrent_task_v2/src/peer/swarm/peers_manager_events.dart';
import 'package:events_emitter2/events_emitter2.dart';
import 'package:logging/logging.dart';
import 'package:utp_protocol/utp_protocol.dart' show UTPSocket;

import '../protocol/peer.dart';
import '../extensions/pex.dart';
import '../extensions/holepunch.dart';
import '../peer_priority.dart';
import '../../torrent/torrent_version.dart';
import '../../filter/ip_filter.dart';
import '../../proxy/proxy_manager.dart';
import '../../ssl/ssl_config.dart';
import '../../encryption/protocol_encryption.dart';

const MAX_ACTIVE_PEERS = 50;

const MAX_WRITE_BUFFER_SIZE = 10 * 1024 * 1024;

const MAX_UPLOADED_NOTIFY_SIZE = 1024 * 1024 * 10; // 10 mb

var _log = Logger('PeersManager');

typedef _PendingUploadRequest = ({int pieceIndex, int begin, Peer peer});
typedef _PausedPieceRequest = ({Peer peer, int pieceIndex});
typedef _PausedRemoteRequest = ({
  Peer peer,
  int index,
  int begin,
  int length,
});

///
/// TODO:
/// - The external Suggest Piece/Fast Allow requests are not handled.
class PeersManager with Holepunch, PEX, EventsEmittable<PeerEvent> {
  final List<InternetAddress> IGNORE_IPS = [
    InternetAddress.tryParse('0.0.0.0')!,
    InternetAddress.tryParse('127.0.0.1')!
  ];

  bool _disposed = false;

  bool get isDisposed => _disposed;

  final Set<Peer> _activePeers = {};

  final Map<Peer, EventsListener<PeerEvent>> _peerListeners = {};

  final Set<CompactAddress> _peersAddress = {};

  final Set<InternetAddress> _incomingAddress = {};

  InternetAddress? localExternalIP;

  IPFilter? _ipFilter;

  ProxyManager? _proxyManager;
  SSLConfig? _sslConfig;
  ProtocolEncryptionConfig? _protocolEncryptionConfig;

  final TorrentModel _metaInfo;

  int _uploaded = 0;

  int _downloaded = 0;

  int? _startedTime;

  int? _endTime;

  int _uploadedNotifySize = 0;

  final List<_PendingUploadRequest> _remoteRequest = [];

  bool _paused = false;

  Timer? _keepAliveTimer;

  final List<_PausedPieceRequest> _pausedRequest = [];

  final Map<String, List<_PausedRemoteRequest>> _pausedRemoteRequest = {};

  final String _localPeerId;

  TorrentVersion? _torrentVersion;

  PeersManager(
    this._localPeerId,
    this._metaInfo, {
    IPFilter? ipFilter,
  }) {
    _ipFilter = ipFilter;
    _init();
    // Start pex interval
    startPEX();
  }

  /// Set torrent version for v2/hybrid support
  void setTorrentVersion(TorrentVersion version) {
    _torrentVersion = version;
    // Update existing peers
    for (var peer in _activePeers) {
      peer.setTorrentVersion(version);
    }
  }

  /// Set IP filter for blocking/allowing peers
  void setIPFilter(IPFilter? filter) {
    _ipFilter = filter;
    _log.info('IP filter ${filter != null ? "enabled" : "disabled"}');
  }

  /// Get current IP filter
  IPFilter? get ipFilter => _ipFilter;

  /// Set proxy manager for peer connections
  void setProxyManager(ProxyManager? manager) {
    _proxyManager = manager;
    _log.info('Proxy manager ${manager != null ? "enabled" : "disabled"}');
  }

  /// Get current proxy manager
  ProxyManager? get proxyManager => _proxyManager;

  /// Set SSL config for peer connections
  void setSSLConfig(SSLConfig? config) {
    _sslConfig = config;
    _log.info(
        'Peer TLS ${config?.enableForPeers == true ? "enabled" : "disabled"}');
  }

  /// Set protocol encryption config for peer connections
  void setProtocolEncryptionConfig(ProtocolEncryptionConfig? config) {
    _protocolEncryptionConfig = config;
    _log.info(
        'Protocol encryption ${config?.isEnabled == true ? "enabled" : "disabled"}');
  }

  Future<void> _init() async {
    try {
      localExternalIP = InternetAddress.tryParse(await Ipify.ipv4());
    } catch (e) {
      // Do nothing
    }
  }

  /// Task is paused
  bool get isPaused => _paused;

  /// All peers number. Include the connecting peer.
  int get peersNumber {
    if (_peersAddress.isEmpty) return 0;
    return _peersAddress.length;
  }

  /// All connected peers number. Include seeder.
  int get connectedPeersNumber {
    if (_activePeers.isEmpty) return 0;
    return _activePeers.length;
  }

  /// All seeder number
  int get seederNumber {
    if (_activePeers.isEmpty) return 0;
    var c = 0;
    return _activePeers.fold(c, (previousValue, element) {
      if (element.isSeeder) {
        return previousValue + 1;
      }
      return previousValue;
    });
  }

  /// Since first peer connected to end time ,
  ///
  /// The end time is current, but once `dispose` this class
  /// the end time is when manager was disposed.
  int get liveTime {
    if (_startedTime == null) return 0;
    var passed = DateTime.now().millisecondsSinceEpoch - _startedTime!;
    if (_endTime != null) {
      passed = _endTime! - _startedTime!;
    }
    return passed;
  }

  /// Average download speed , b/ms
  ///
  /// This speed calculation : `total download content bytes` / [liveTime]
  double get averageDownloadSpeed {
    var live = liveTime;
    if (live == 0) return 0.0;
    return _downloaded / live;
  }

  /// Average upload speed , b/ms
  ///
  /// This speed calculation : `total upload content bytes` / [liveTime]
  double get averageUploadSpeed {
    var live = liveTime;
    if (live == 0) return 0.0;
    return _uploaded / live;
  }

  /// Current download speed , b/ms
  ///
  /// This speed calculation: sum(`active peer download speed`)
  double get currentDownloadSpeed {
    if (_activePeers.isEmpty) return 0.0;
    return _activePeers.fold(
        0.0, (p, element) => p + element.currentDownloadSpeed);
  }

  /// Current upload speed , b/ms
  ///
  /// This speed calculation: sum(`active peer upload speed`)
  double get uploadSpeed {
    if (_activePeers.isEmpty) return 0.0;
    return _activePeers.fold(
        0.0, (p, element) => p + element.averageUploadSpeed);
  }

  /// Returns peers ordered by BEP 40 canonical priority for this torrent.
  ///
  /// Larger priority value means higher rank.
  List<Peer> getCanonicalPriorityPeers({Iterable<Peer>? peers}) {
    final source = (peers ?? _activePeers).where((p) => !p.isDisposed).toList();
    final clientIp = localExternalIP;
    if (clientIp == null || source.length <= 1) {
      return source;
    }

    source.sort((a, b) {
      final ap = PeerPriority.canonicalPriority(
        clientIp: clientIp,
        clientPort: 0,
        peerIp: a.address.address,
        peerPort: a.address.port,
      );
      final bp = PeerPriority.canonicalPriority(
        clientIp: clientIp,
        clientPort: 0,
        peerIp: b.address.address,
        peerPort: b.address.port,
      );
      return bp.compareTo(ap);
    });
    return source;
  }

  void _hookPeer(Peer peer) {
    if (peer.address.address == localExternalIP) return;
    if (_peerExist(peer)) return;
    _peerListeners[peer] = peer.createListener();
    // emit all peer events
    _peerListeners[peer]!.listen((event) => events.emit(event));
    _peerListeners[peer]!
      ..on<PeerDisposeEvent>(_processPeerDispose)
      ..on<PeerInterestedChanged>(_processInterestedChange)
      ..on<PeerConnected>(_peerConnected)
      ..on<PeerPieceEvent>(_processReceivePiece)
      ..on<PeerRequestEvent>(_processRemoteRequest)
      ..on<PeerSuggestPiece>(_processSuggestPiece)
      ..on<ExtendedEvent>((event) =>
          _processExtendedMessage(peer, event.eventName, event.data));
    _registerExtended(peer);
    peer.connect();
  }

  ///  Add supported extensions here
  void _registerExtended(Peer peer) {
    _log.fine('registering extensions for peer ${peer.address}');
    peer.registerExtend('ut_pex');
    peer.registerExtend('ut_holepunch');
    peer.registerExtend(EXTENSION_LT_DONTHAVE);
  }

  void _unHookPeer(Peer peer) {
    peer.events.dispose();
    _peerListeners[peer]?.dispose();
    _peerListeners.remove(peer);
  }

  bool _peerExist(Peer id) {
    return _activePeers.contains(id);
  }

  void _processExtendedMessage(Peer source, String name, Object? data) {
    _log.fine('Processing Extended Message $name');
    if (name == 'ut_holepunch') {
      if (data is List<int>) {
        parseHolepunchMessage(data);
      }
    }
    if (name == 'ut_pex') {
      if (data is List<int>) {
        parsePEXDatas(source, data);
      }
    }
    if (name == 'handshake') {
      if (data is! Map) {
        _log.fine('Ignoring invalid handshake payload from ${source.address}');
        return;
      }
      final yourIpRaw = data['yourip'];
      if (localExternalIP != null &&
          yourIpRaw is List<int> &&
          (yourIpRaw.length == 4 || yourIpRaw.length == 16)) {
        final yourIpBytes = Uint8List.fromList(yourIpRaw);
        InternetAddress myIp;
        try {
          myIp = InternetAddress.fromRawAddress(yourIpBytes);
        } catch (e) {
          return;
        }
        if (IGNORE_IPS.contains(myIp)) return;
        localExternalIP = InternetAddress.fromRawAddress(yourIpBytes);
      }
    }
  }

  /// Add a new peer [address] , the default [type] is `PeerType.TCP`,
  /// [socket] is null.
  ///
  /// Usually [socket] is null , unless this peer was incoming connection, but
  /// this type peer was managed by [TorrentTask] , user don't need to know that.
  void addNewPeerAddress(CompactAddress? address, PeerSource source,
      {PeerType? type, Object? socket}) {
    if (address == null) return;
    if (IGNORE_IPS.contains(address.address)) return;
    if (address.address == localExternalIP) return;

    // Check IP filter
    if (_ipFilter != null && _ipFilter!.isBlocked(address.address)) {
      _log.fine('Peer ${address.address} blocked by IP filter');
      return;
    }
    if (socket != null) {
      // Indicates that it is an actively connected peer, and currently, only one IP address is allowed to connect at a time.
      if (!_incomingAddress.add(address.address)) {
        _log.warning(
            'Incoming connection from ${address.address} is ignored, already connected, multiple connections from the same IP are not allowed.');
        return;
      }
    }
    // TODO: should we allow reconnects?
    // _activePeers.removeWhere((p) => p.address == address);
    // _peersAddress.remove(address);
    if (_peersAddress.add(address)) {
      Peer? peer;
      if (type == null || type == PeerType.TCP) {
        if (_metaInfo.pieces == null) {
          _log.warning(
              'Cannot create peer: torrent has no pieces (v2-only torrent?)');
          return;
        }
        peer = Peer.newTCPPeer(
          address,
          _metaInfo.infoHashBuffer,
          _metaInfo.pieces!.length,
          socket is Socket ? socket : null,
          source,
          proxyManager: _proxyManager,
          sslConfig: _sslConfig,
          protocolEncryptionConfig: _protocolEncryptionConfig,
        );
      }
      if (type == PeerType.UTP) {
        if (_metaInfo.pieces == null) {
          _log.warning(
              'Cannot create peer: torrent has no pieces (v2-only torrent?)');
          return;
        }
        peer = Peer.newUTPPeer(
            address,
            _metaInfo.infoHashBuffer,
            _metaInfo.pieces!.length,
            socket is UTPSocket ? socket : null,
            source,
            protocolEncryptionConfig: _protocolEncryptionConfig);
      }
      if (peer != null) {
        // Set torrent version for v2/hybrid support in handshake
        if (_torrentVersion != null) {
          peer.setTorrentVersion(_torrentVersion!);
        }
        _hookPeer(peer);
      }
    }
  }

  /// When read the resource content complete , invoke this method to notify
  /// this class to send it to related peer.
  ///
  /// [pieceIndex] is the index of the piece, [begin] is the byte index of the whole
  /// contents , [block] should be uint8 list, it's the sub-piece contents bytes.
  void readSubPieceComplete(int pieceIndex, int begin, List<int> block) {
    final requestIndex = _remoteRequest.indexWhere(
      (request) => request.pieceIndex == pieceIndex && request.begin == begin,
    );
    if (requestIndex >= 0) {
      final request = _remoteRequest.removeAt(requestIndex);
      final peer = request.peer;
      if (!peer.isDisposed && peer.sendPiece(pieceIndex, begin, block)) {
        _uploaded += block.length;
        _uploadedNotifySize += block.length;
      }
      if (_uploadedNotifySize >= MAX_UPLOADED_NOTIFY_SIZE) {
        _uploadedNotifySize = 0;
        events.emit(UpdateUploaded(_uploaded));
      }
    }
  }

  void _processSuggestPiece(PeerSuggestPiece event) {}

  void _processPeerDispose(PeerDisposeEvent disposeEvent) {
    _peerListeners.remove(disposeEvent.peer);
    var reconnect = true;
    if (disposeEvent.reason is BadException) {
      reconnect = false;
    }

    _peersAddress.remove(disposeEvent.peer.address);
    _incomingAddress.remove(disposeEvent.peer.address.address);
    _activePeers.remove(disposeEvent.peer);

    _pausedRemoteRequest.remove(disposeEvent.peer.id);
    _pausedRequest.removeWhere((request) => request.peer == disposeEvent.peer);

    if (disposeEvent.reason is TCPConnectException) {
      // print('TCPConnectException');
      // addNewPeerAddress(peer.address, PeerType.UTP);
      return;
    }

    if (reconnect) {
      if (_activePeers.length < MAX_ACTIVE_PEERS && !isDisposed) {
        addNewPeerAddress(
          disposeEvent.peer.address,
          disposeEvent.peer.source,
          type: disposeEvent.peer.type,
        );
      }
    } else {
      if (disposeEvent.peer.isSeeder && !isDisposed) {
        addNewPeerAddress(disposeEvent.peer.address, disposeEvent.peer.source,
            type: disposeEvent.peer.type);
      }
    }
  }

  void _peerConnected(PeerConnected event) {
    _startedTime ??= DateTime.now().millisecondsSinceEpoch;
    _endTime = null;
    _activePeers.add(event.peer);
    event.peer.sendHandShake(_localPeerId);
  }

  bool addPausedRequest(Peer peer, int pieceIndex) {
    if (isPaused) {
      _pausedRequest.add((peer: peer, pieceIndex: pieceIndex));
      return true;
    }
    return false;
  }

  void _processReceivePiece(PeerPieceEvent event) {
    _downloaded += event.block.length;
  }

  void _processRemoteRequest(PeerRequestEvent event) {
    if (isPaused) {
      _pausedRemoteRequest[event.peer.id] ??= [];
      final pausedRequest = _pausedRemoteRequest[event.peer.id];
      pausedRequest?.add((
        peer: event.peer,
        index: event.index,
        begin: event.begin,
        length: event.length,
      ));
      return;
    }
    _remoteRequest
        .add((pieceIndex: event.index, begin: event.begin, peer: event.peer));
  }

  void _processInterestedChange(PeerInterestedChanged event) {
    if (event.interested) {
      event.peer.sendChoke(false);
    } else {
      event.peer.sendChoke(true); // Choke it if not interested.
    }
  }

  void _sendKeepAliveToAll() {
    for (var peer in _activePeers) {
      Timer.run(() => _keepAlive(peer));
    }
  }

  void _keepAlive(Peer peer) {
    peer.sendKeepAlive();
  }

  void sendHaveToAll(int index) {
    for (var peer in _activePeers) {
      Timer.run(() => peer.sendHave(index));
    }
  }

  void sendDontHaveToAll(int index) {
    for (var peer in _activePeers) {
      Timer.run(() => peer.sendDontHave(index));
    }
  }

  /// Pause the task
  ///
  /// All the incoming request message will be received but they will be stored
  /// in buffer and no response to remote.
  ///
  /// All out message/incoming connection will be processed even task is paused.
  void pause() {
    if (_paused) return;
    _paused = true;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = Timer(Duration(seconds: 110), _sendKeepAliveToAll);
  }

  /// Resume the task
  void resume() {
    if (!_paused) return;
    _paused = false;
    _keepAliveTimer?.cancel();
    _keepAliveTimer = null;
    for (final element in _pausedRequest) {
      final peer = element.peer;
      final index = element.pieceIndex;
      if (!peer.isDisposed) {
        events.emit(PieceRequest(
          peer,
          index,
        ));
      }
    }
    _pausedRequest.clear();

    _pausedRemoteRequest.forEach((_, value) {
      for (final element in value) {
        final peer = element.peer;
        final index = element.index;
        final begin = element.begin;
        final length = element.length;
        if (!peer.isDisposed) {
          Timer.run(() => _processRemoteRequest(
              PeerRequestEvent(peer, index, begin, length)));
        }
      }
    });
    _pausedRemoteRequest.clear();
  }

  Future<void> disposeAllSeeder([Object? reason]) async {
    for (var peer in [..._activePeers]) {
      if (peer.isSeeder) {
        await peer.dispose(reason);
      }
    }
  }

  Future<void> dispose() async {
    if (isDisposed) return;
    _disposed = true;
    events.dispose();
    clearHolepunch();
    clearPEX();
    _endTime = DateTime.now().millisecondsSinceEpoch;

    _remoteRequest.clear();
    _pausedRequest.clear();
    _pausedRemoteRequest.clear();
    await _disposePeers(_activePeers);
  }

  //TODO: test

  @override
  void addPEXPeer(
      Peer source, CompactAddress address, Map<String, bool> options) {
    // addNewPeerAddress(address);
    // return;
    // if (options['reachable'] != null) {
    //   if (options['utp'] != null) {
    //     print('UTP/TCP reachable');
    //   }
    //   addNewPeerAddress(address);
    //   return;
    // }
    if ((options['utp'] == true || options['ut_holepunch'] == true) &&
        options['reachable'] != true) {
      final message = getRendezvousMessage(address);
      source.sendExtendMessage('ut_holepunch', message);
      return;
    }
    addNewPeerAddress(address, PeerSource.pex);
  }

  @override
  Iterable<Peer> get activePeers => _activePeers;

  @override
  void holePunchConnect(CompactAddress ip) {
    _log.info("holePunch connect $ip");
    addNewPeerAddress(ip, PeerSource.holepunch, type: PeerType.UTP);
  }

  int get utpPeerCount {
    return _activePeers.fold(0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += 1;
      }
      return previousValue;
    });
  }

  double get utpDownloadSpeed {
    return _activePeers.fold(0.0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += element.currentDownloadSpeed;
      }
      return previousValue;
    });
  }

  double get utpUploadSpeed {
    return _activePeers.fold(0.0, (previousValue, element) {
      if (element.type == PeerType.UTP) {
        previousValue += element.averageUploadSpeed;
      }
      return previousValue;
    });
  }

  @override
  void holePunchError(String err, CompactAddress ip) {
    _log.info('holepunch error - $err');
  }

  @override
  void holePunchRendezvous(CompactAddress ip) {
    // TODO: implement holePunchRendezvous
    _log.info('Received holePunch Rendezvous from $ip');
  }

  Future<void> _disposePeers(Set<Peer> peers) async {
    if (peers.isNotEmpty) {
      for (final peer in peers.toList()) {
        _unHookPeer(peer);
        await peer.dispose('Peer Manager disposed');
      }
    }
    peers.clear();
  }
}
