import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/torrent/torrent_file_model.dart';
import 'package:logging/logging.dart';
import 'package:mime/mime.dart';

var _log = Logger('StreamingIsolate');

/// Messages sent to the streaming isolate
abstract class StreamingIsolateMessage {}

/// Request to get playlist data
class GetPlaylistMessage implements StreamingIsolateMessage {
  final List<TorrentFileModel> files;
  final InternetAddress address;
  final int port;

  GetPlaylistMessage(this.files, this.address, this.port);
}

/// Request to get JSON metadata
class GetJsonMetadataMessage implements StreamingIsolateMessage {
  final List<TorrentFileModel> files;
  final int totalLength;
  final int downloaded;
  final double downloadSpeed;
  final double uploadSpeed;
  final int totalPeers;
  final int activePeers;

  GetJsonMetadataMessage(
    this.files,
    this.totalLength,
    this.downloaded,
    this.downloadSpeed,
    this.uploadSpeed,
    this.totalPeers,
    this.activePeers,
  );
}

/// Response from isolate
abstract class StreamingIsolateResponse {}

class PlaylistResponse implements StreamingIsolateResponse {
  final Uint8List data;
  PlaylistResponse(this.data);
}

class JsonMetadataResponse implements StreamingIsolateResponse {
  final Uint8List data;
  JsonMetadataResponse(this.data);
}

class _IsolateRequest {
  final int requestId;
  final StreamingIsolateMessage payload;

  const _IsolateRequest(this.requestId, this.payload);
}

class _IsolateResponse {
  final int requestId;
  final StreamingIsolateResponse payload;

  const _IsolateResponse(this.requestId, this.payload);
}

/// Streaming isolate entry point
void _streamingIsolateEntry(SendPort sendPort) {
  final receivePort = ReceivePort();
  sendPort.send(receivePort.sendPort);

  receivePort.listen((message) {
    if (message is! _IsolateRequest) {
      return;
    }

    final requestId = message.requestId;
    final payload = message.payload;

    if (payload is GetPlaylistMessage) {
      try {
        final playlist =
            _createPlaylist(payload.files, payload.address, payload.port);
        sendPort.send(_IsolateResponse(
          requestId,
          PlaylistResponse(Uint8List.fromList(playlist.codeUnits)),
        ));
      } catch (e, stackTrace) {
        _log.warning('Error creating playlist in isolate', e, stackTrace);
        sendPort.send(
          _IsolateResponse(requestId, PlaylistResponse(Uint8List(0))),
        );
      }
    } else if (payload is GetJsonMetadataMessage) {
      try {
        final json = _createJsonMetadata(
          payload.files,
          payload.totalLength,
          payload.downloaded,
          payload.downloadSpeed,
          payload.uploadSpeed,
          payload.totalPeers,
          payload.activePeers,
        );
        sendPort.send(_IsolateResponse(
          requestId,
          JsonMetadataResponse(Uint8List.fromList(json.codeUnits)),
        ));
      } catch (e, stackTrace) {
        _log.warning('Error creating JSON metadata in isolate', e, stackTrace);
        sendPort.send(
          _IsolateResponse(requestId, JsonMetadataResponse(Uint8List(0))),
        );
      }
    }
  });
}

String _createPlaylist(
    List<TorrentFileModel> files, InternetAddress address, int port) {
  final videoFiles = files.where((element) {
    final mimeType = lookupMimeType(element.name);
    return mimeType?.startsWith('video') ??
        mimeType?.startsWith('audio') ??
        false;
  });

  final entries = videoFiles.map((file) =>
      '#EXTINF:-1,${file.path}\nhttp://${address.host}:$port/${file.path}');
  return '#EXTM3U\n${entries.join('\n')}';
}

String _createJsonMetadata(
  List<TorrentFileModel> files,
  int totalLength,
  int downloaded,
  double downloadSpeed,
  double uploadSpeed,
  int totalPeers,
  int activePeers,
) {
  final jsonEntries = files
      .map((file) => {
            'name': file.name,
            'url': 'http://localhost:9090/${file.path}',
            'length': file.length
          })
      .toList();

  final json = {
    'totalLength': totalLength,
    'downloaded': downloaded,
    'downloadSpeed': downloadSpeed,
    'uploadSpeed': uploadSpeed,
    'totalPeers': totalPeers,
    'activePeers': activePeers,
    'files': jsonEntries,
  };

  return const JsonEncoder.withIndent('  ').convert(json);
}

/// Manager for streaming isolate
class StreamingIsolateManager {
  Isolate? _isolate;
  SendPort? _sendPort;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _responseSubscription;
  bool _initialized = false;
  int _requestCounter = 0;
  Completer<void>? _initializationCompleter;
  final Map<int, Completer<Uint8List>> _pendingRequests = {};

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializationCompleter != null) {
      await _initializationCompleter!.future;
      return;
    }

    _initializationCompleter = Completer<void>();
    _receivePort = ReceivePort();
    _responseSubscription = _receivePort!.listen(_handleIsolateMessage);
    _isolate = await Isolate.spawn(
      _streamingIsolateEntry,
      _receivePort!.sendPort,
      debugName: 'StreamingIsolate',
    );

    await _initializationCompleter!.future;
    _initialized = true;
    _initializationCompleter = null;
    _log.info('Streaming isolate initialized');
  }

  Future<Uint8List> getPlaylist(
    List<TorrentFileModel> files,
    InternetAddress address,
    int port,
  ) async {
    if (!_initialized) await initialize();
    return _sendRequest(
      GetPlaylistMessage(files, address, port),
      timeoutWarning: 'Playlist request timeout',
    );
  }

  Future<Uint8List> getJsonMetadata(
    List<TorrentFileModel> files,
    int totalLength,
    int downloaded,
    double downloadSpeed,
    double uploadSpeed,
    int totalPeers,
    int activePeers,
  ) async {
    if (!_initialized) await initialize();
    return _sendRequest(
      GetJsonMetadataMessage(
        files,
        totalLength,
        downloaded,
        downloadSpeed,
        uploadSpeed,
        totalPeers,
        activePeers,
      ),
      timeoutWarning: 'JSON metadata request timeout',
    );
  }

  Future<void> dispose() async {
    if (!_initialized) return;

    await _responseSubscription?.cancel();
    _responseSubscription = null;
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.complete(Uint8List(0));
      }
    }
    _pendingRequests.clear();
    _isolate?.kill(priority: Isolate.immediate);
    _receivePort?.close();
    _isolate = null;
    _sendPort = null;
    _receivePort = null;
    _initialized = false;
    _requestCounter = 0;
    _initializationCompleter = null;
    _log.info('Streaming isolate disposed');
  }

  Future<Uint8List> _sendRequest(
    StreamingIsolateMessage payload, {
    required String timeoutWarning,
  }) async {
    final sendPort = _sendPort;
    if (sendPort == null) {
      _log.warning('Streaming isolate send port is not initialized');
      return Uint8List(0);
    }

    final requestId = ++_requestCounter;
    final completer = Completer<Uint8List>();
    _pendingRequests[requestId] = completer;
    sendPort.send(_IsolateRequest(requestId, payload));

    return completer.future.timeout(
      const Duration(seconds: 5),
      onTimeout: () {
        _pendingRequests.remove(requestId);
        _log.warning(timeoutWarning);
        return Uint8List(0);
      },
    );
  }

  void _handleIsolateMessage(dynamic message) {
    if (message is SendPort) {
      _sendPort = message;
      _initializationCompleter?.complete();
      return;
    }

    if (message is! _IsolateResponse) return;
    final completer = _pendingRequests.remove(message.requestId);
    if (completer == null || completer.isCompleted) return;

    switch (message.payload) {
      case PlaylistResponse(:final data):
        completer.complete(data);
      case JsonMetadataResponse(:final data):
        completer.complete(data);
    }
  }
}
