import 'dart:async';
import 'dart:collection';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:logging/logging.dart';
import 'proxy_config.dart';

var _log = Logger('Socks5Client');

/// Error thrown when a SOCKS5 proxy returns an invalid or rejected response.
class Socks5Exception implements Exception {
  final String message;

  const Socks5Exception(this.message);

  @override
  String toString() => 'Socks5Exception: $message';
}

/// SOCKS5 proxy client for peer connections
class Socks5Client {
  final ProxyConfig config;

  Socks5Client(this.config) {
    if (config.type != ProxyType.socks5) {
      throw ArgumentError('Socks5Client only supports SOCKS5 proxies');
    }
  }

  /// Connect to target through SOCKS5 proxy
  ///
  /// [targetAddress] - Target IP address
  /// [targetPort] - Target port
  /// [timeout] - Connection timeout
  ///
  /// Returns connected socket ready for data transfer
  Future<Socket> connect(
    InternetAddress targetAddress,
    int targetPort, {
    Duration? timeout,
  }) async {
    try {
      _log.fine(
          'Connecting to $targetAddress:$targetPort via SOCKS5 proxy ${config.host}:${config.port}');

      // Connect to proxy server
      final proxySocket = await Socket.connect(
        config.host,
        config.port,
        timeout: timeout ?? const Duration(seconds: 30),
      );

      try {
        final reader = _Socks5SocketReader(proxySocket);

        // Step 1: Authentication negotiation
        await _negotiateAuth(proxySocket, reader);

        // Step 2: Connect to target
        await _connectToTarget(proxySocket, reader, targetAddress, targetPort);

        return _Socks5Socket(proxySocket, reader.releaseStream());
      } catch (e) {
        await proxySocket.close();
        rethrow;
      }
    } catch (e, stackTrace) {
      _log.warning('SOCKS5 connection failed: $targetAddress:$targetPort', e,
          stackTrace);
      rethrow;
    }
  }

  /// Negotiate authentication method (SOCKS5 handshake)
  Future<void> _negotiateAuth(
    Socket socket,
    _Socks5SocketReader reader,
  ) async {
    // Build authentication request
    final authMethods = <int>[];

    if (config.requiresAuth) {
      // Username/Password authentication (method 0x02)
      authMethods.add(0x02);
    }

    // No authentication (method 0x00)
    authMethods.add(0x00);

    final request = Uint8List(2 + authMethods.length);
    request[0] = 0x05; // SOCKS version 5
    request[1] = authMethods.length; // Number of methods
    for (var i = 0; i < authMethods.length; i++) {
      request[2 + i] = authMethods[i];
    }

    // Send authentication request
    socket.add(request);
    await socket.flush();

    // Receive server response
    final response = await reader.read(2);
    if (response[0] != 0x05) {
      throw Socks5Exception(
        'Invalid SOCKS5 version in response: ${response[0]}',
      );
    }

    final selectedMethod = response[1];

    // Handle authentication based on selected method
    if (selectedMethod == 0x02) {
      // Username/Password authentication
      await _authenticateUsernamePassword(socket, reader);
    } else if (selectedMethod == 0x00) {
      // No authentication required
      _log.fine('SOCKS5: No authentication required');
    } else if (selectedMethod == 0xFF) {
      throw const Socks5Exception(
          'SOCKS5: No acceptable authentication method');
    } else {
      throw Socks5Exception(
        'SOCKS5: Unknown authentication method: $selectedMethod',
      );
    }
  }

  /// Authenticate using username/password
  Future<void> _authenticateUsernamePassword(
    Socket socket,
    _Socks5SocketReader reader,
  ) async {
    if (!config.requiresAuth) {
      throw const Socks5Exception(
        'SOCKS5: Username/password required but not provided',
      );
    }

    final username = utf8.encode(config.username ?? '');
    final password = utf8.encode(config.password ?? '');

    if (username.length > 255 || password.length > 255) {
      throw const Socks5Exception('SOCKS5: Username or password too long');
    }

    final request = Uint8List(3 + username.length + password.length);
    request[0] = 0x01; // Username/Password version
    request[1] = username.length;
    request.setRange(2, 2 + username.length, username);
    request[2 + username.length] = password.length;
    request.setRange(
        3 + username.length, 3 + username.length + password.length, password);

    socket.add(request);
    await socket.flush();

    final response = await reader.read(2);
    if (response[0] != 0x01) {
      throw Socks5Exception(
        'Invalid username/password version: ${response[0]}',
      );
    }

    if (response[1] != 0x00) {
      throw const Socks5Exception('SOCKS5: Authentication failed');
    }

    _log.fine('SOCKS5: Username/password authentication successful');
  }

  /// Connect to target address through proxy
  Future<void> _connectToTarget(
    Socket socket,
    _Socks5SocketReader reader,
    InternetAddress targetAddress,
    int targetPort,
  ) async {
    // Build CONNECT request
    Uint8List request;

    if (targetAddress.type == InternetAddressType.IPv4) {
      // IPv4 address (type 0x01)
      final addrBytes = targetAddress.rawAddress;
      request = Uint8List(4 + 2 + addrBytes.length);
      request[0] = 0x05; // SOCKS version
      request[1] = 0x01; // CONNECT command
      request[2] = 0x00; // Reserved
      request[3] = 0x01; // IPv4 address type
      request.setRange(4, 4 + addrBytes.length, addrBytes);
      final portOffset = 4 + addrBytes.length;
      request[portOffset] = (targetPort >> 8) & 0xFF;
      request[portOffset + 1] = targetPort & 0xFF;
    } else if (targetAddress.type == InternetAddressType.IPv6) {
      // IPv6 address (type 0x04)
      final addrBytes = targetAddress.rawAddress;
      request = Uint8List(4 + 2 + addrBytes.length);
      request[0] = 0x05; // SOCKS version
      request[1] = 0x01; // CONNECT command
      request[2] = 0x00; // Reserved
      request[3] = 0x04; // IPv6 address type
      request.setRange(4, 4 + addrBytes.length, addrBytes);
      final portOffset = 4 + addrBytes.length;
      request[portOffset] = (targetPort >> 8) & 0xFF;
      request[portOffset + 1] = targetPort & 0xFF;
    } else {
      throw Socks5Exception('Unsupported address type: ${targetAddress.type}');
    }

    // Send CONNECT request
    socket.add(request);
    await socket.flush();

    // Receive response
    final response = await reader.read(4);
    if (response[0] != 0x05) {
      throw Socks5Exception(
        'Invalid SOCKS5 version in response: ${response[0]}',
      );
    }

    final reply = response[1];
    if (reply != 0x00) {
      final errorMsg = _getSocks5Error(reply);
      throw Socks5Exception(
        'SOCKS5 connection failed: $errorMsg (code: $reply)',
      );
    }

    final addressType = response[3];

    // Read bound address (we don't need it, but must read it)
    if (addressType == 0x01) {
      // IPv4
      await reader.read(4);
    } else if (addressType == 0x03) {
      // Domain name
      final nameLen = (await reader.read(1))[0];
      await reader.read(nameLen);
    } else if (addressType == 0x04) {
      // IPv6
      await reader.read(16);
    }

    // Read bound port (we don't need it, but must read it)
    await reader.read(2);

    _log.fine('SOCKS5: Connected to $targetAddress:$targetPort');
  }

  /// Get SOCKS5 error message
  String _getSocks5Error(int code) {
    switch (code) {
      case 0x01:
        return 'General SOCKS server failure';
      case 0x02:
        return 'Connection not allowed by ruleset';
      case 0x03:
        return 'Network unreachable';
      case 0x04:
        return 'Host unreachable';
      case 0x05:
        return 'Connection refused';
      case 0x06:
        return 'TTL expired';
      case 0x07:
        return 'Command not supported';
      case 0x08:
        return 'Address type not supported';
      default:
        return 'Unknown error (code: $code)';
    }
  }
}

final class _Socks5SocketReader {
  final Socket _socket;
  final List<int> _buffer = <int>[];
  final Queue<_PendingSocks5Read> _pendingReads = Queue<_PendingSocks5Read>();
  final StreamController<Uint8List> _releasedStreamController =
      StreamController<Uint8List>();
  bool _released = false;

  _Socks5SocketReader(this._socket) {
    _socket.listen(
      _handleData,
      onError: _handleError,
      onDone: _handleDone,
      cancelOnError: true,
    );
  }

  Future<Uint8List> read(int count) async {
    if (_released) {
      throw StateError('SOCKS5 handshake reader has already been released');
    }

    if (_buffer.length >= count) {
      return _takeBytes(count);
    }

    final pendingRead = _PendingSocks5Read(count);
    _pendingReads.add(pendingRead);
    return pendingRead.completer.future;
  }

  Stream<Uint8List> releaseStream() {
    if (_released) return _releasedStreamController.stream;
    _released = true;

    if (_buffer.isNotEmpty) {
      _releasedStreamController.add(Uint8List.fromList(_buffer));
      _buffer.clear();
    }

    return _releasedStreamController.stream;
  }

  void _handleData(Uint8List data) {
    if (_released) {
      _releasedStreamController.add(data);
      return;
    }

    _buffer.addAll(data);
    _flushPendingReads();
  }

  void _flushPendingReads() {
    while (_pendingReads.isNotEmpty &&
        _buffer.length >= _pendingReads.first.count) {
      final pendingRead = _pendingReads.removeFirst();
      pendingRead.completer.complete(_takeBytes(pendingRead.count));
    }
  }

  Uint8List _takeBytes(int count) {
    final bytes = Uint8List.fromList(_buffer.take(count).toList());
    _buffer.removeRange(0, count);
    return bytes;
  }

  void _handleError(Object error, StackTrace stackTrace) {
    while (_pendingReads.isNotEmpty) {
      _pendingReads.removeFirst().completer.completeError(error, stackTrace);
    }
    if (_released) {
      _releasedStreamController.addError(error, stackTrace);
    }
  }

  void _handleDone() {
    const error = Socks5Exception(
      'SOCKS5 socket closed before enough data was received',
    );
    while (_pendingReads.isNotEmpty) {
      _pendingReads.removeFirst().completer.completeError(error);
    }
    _releasedStreamController.close();
  }
}

final class _PendingSocks5Read {
  final int count;
  final Completer<Uint8List> completer = Completer<Uint8List>();

  _PendingSocks5Read(this.count);
}

final class _Socks5Socket extends StreamView<Uint8List> implements Socket {
  final Socket _socket;

  _Socks5Socket(this._socket, Stream<Uint8List> stream) : super(stream);

  @override
  InternetAddress get address => _socket.address;

  @override
  void add(List<int> data) => _socket.add(data);

  @override
  void addError(Object error, [StackTrace? stackTrace]) =>
      _socket.addError(error, stackTrace);

  @override
  Future<void> addStream(Stream<List<int>> stream) => _socket.addStream(stream);

  @override
  Future<void> close() => _socket.close();

  @override
  Future<void> get done => _socket.done;

  @override
  void destroy() => _socket.destroy();

  @override
  Encoding get encoding => _socket.encoding;

  @override
  set encoding(Encoding encoding) => _socket.encoding = encoding;

  @override
  Future<void> flush() => _socket.flush();

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      _socket.getRawOption(option);

  @override
  int get port => _socket.port;

  @override
  InternetAddress get remoteAddress => _socket.remoteAddress;

  @override
  int get remotePort => _socket.remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) =>
      _socket.setOption(option, enabled);

  @override
  void setRawOption(RawSocketOption option) => _socket.setRawOption(option);

  @override
  void write(Object? object) => _socket.write(object);

  @override
  void writeAll(Iterable<dynamic> objects, [String separator = '']) =>
      _socket.writeAll(objects, separator);

  @override
  void writeCharCode(int charCode) => _socket.writeCharCode(charCode);

  @override
  void writeln([Object? object = '']) => _socket.writeln(object);
}
