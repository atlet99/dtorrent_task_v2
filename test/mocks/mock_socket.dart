import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Mock Socket implementation for deterministic testing
///
/// Provides synchronous data delivery between paired sockets without
/// any real network I/O. Used for testing peer communication logic.
class MockSocket extends Stream<Uint8List> implements Socket {
  final StreamController<Uint8List> _controller = StreamController<Uint8List>();
  MockSocket? _peer;
  bool _closed = false;

  final InternetAddress _address;
  final int _port;
  final InternetAddress _remoteAddress;
  final int _remotePort;

  MockSocket._(
    this._address,
    this._port,
    this._remoteAddress,
    this._remotePort,
  );

  /// Public factory to create unpaired socket
  factory MockSocket.create(
    InternetAddress address,
    int port,
    InternetAddress remoteAddress,
    int remotePort,
  ) {
    return MockSocket._(address, port, remoteAddress, remotePort);
  }

  /// Create a pair of connected sockets
  static (MockSocket, MockSocket) createPair({
    InternetAddress? clientAddress,
    int? clientPort,
    InternetAddress? serverAddress,
    int? serverPort,
  }) {
    final clientAddr = clientAddress ?? InternetAddress.loopbackIPv4;
    final serverAddr = serverAddress ?? InternetAddress.loopbackIPv4;
    final cPort = clientPort ?? 50000;
    final sPort = serverPort ?? 12345;

    final client = MockSocket._(clientAddr, cPort, serverAddr, sPort);
    final server = MockSocket._(serverAddr, sPort, clientAddr, cPort);

    client._peer = server;
    server._peer = client;

    return (client, server);
  }

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('Socket is closed');
    // Synchronously deliver to peer's stream
    _peer?._controller.add(Uint8List.fromList(data));
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {
    if (_closed) return;
    _peer?._controller.addError(error, stackTrace);
  }

  @override
  Future addStream(Stream<List<int>> stream) {
    return stream.listen(add).asFuture();
  }

  @override
  Future close() async {
    if (_closed) return;
    _closed = true;
    await _controller.close();
  }

  @override
  Future get done => _controller.done;

  @override
  void destroy() {
    _closed = true;
    _controller.close();
  }

  @override
  Future flush() async {
    // No-op for mock
  }

  @override
  InternetAddress get address => _address;

  @override
  int get port => _port;

  @override
  InternetAddress get remoteAddress => _remoteAddress;

  @override
  int get remotePort => _remotePort;

  @override
  bool setOption(SocketOption option, bool enabled) => true;

  @override
  Uint8List getRawOption(RawSocketOption option) =>
      throw UnimplementedError('getRawOption not needed for mocks');

  @override
  void setRawOption(RawSocketOption option) {}

  @override
  void write(Object? object) {
    add(object.toString().codeUnits);
  }

  @override
  void writeAll(Iterable objects, [String separator = ""]) {
    write(objects.join(separator));
  }

  @override
  void writeCharCode(int charCode) {
    add([charCode]);
  }

  @override
  void writeln([Object? object = ""]) {
    write('$object\n');
  }

  @override
  Encoding get encoding => utf8;

  @override
  set encoding(Encoding value) {
    // No-op for mock
  }

  // Stream implementation - delegate everything to _controller.stream
  @override
  StreamSubscription<Uint8List> listen(
    void Function(Uint8List event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _controller.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  Future<bool> any(bool Function(Uint8List element) test) =>
      _controller.stream.any(test);

  @override
  Stream<Uint8List> asBroadcastStream({
    void Function(StreamSubscription<Uint8List> subscription)? onListen,
    void Function(StreamSubscription<Uint8List> subscription)? onCancel,
  }) =>
      _controller.stream.asBroadcastStream(onListen: onListen, onCancel: onCancel);

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Uint8List event) convert) =>
      _controller.stream.asyncExpand(convert);

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Uint8List event) convert) =>
      _controller.stream.asyncMap(convert);

  @override
  Stream<R> cast<R>() => _controller.stream.cast<R>();

  @override
  Future<bool> contains(Object? needle) => _controller.stream.contains(needle);

  @override
  Stream<Uint8List> distinct([bool Function(Uint8List previous, Uint8List next)? equals]) =>
      _controller.stream.distinct(equals);

  @override
  Future<E> drain<E>([E? futureValue]) => _controller.stream.drain(futureValue);

  @override
  Future<Uint8List> elementAt(int index) => _controller.stream.elementAt(index);

  @override
  Future<bool> every(bool Function(Uint8List element) test) => _controller.stream.every(test);

  @override
  Stream<S> expand<S>(Iterable<S> Function(Uint8List element) convert) =>
      _controller.stream.expand(convert);

  @override
  Future<Uint8List> get first => _controller.stream.first;

  @override
  Future<Uint8List> firstWhere(bool Function(Uint8List element) test, {Uint8List Function()? orElse}) =>
      _controller.stream.firstWhere(test, orElse: orElse);

  @override
  Future<S> fold<S>(S initialValue, S Function(S previous, Uint8List element) combine) =>
      _controller.stream.fold(initialValue, combine);

  @override
  Future forEach(void Function(Uint8List element) action) => _controller.stream.forEach(action);

  @override
  Stream<Uint8List> handleError(Function onError, {bool Function(dynamic error)? test}) =>
      _controller.stream.handleError(onError, test: test);

  @override
  bool get isBroadcast => _controller.stream.isBroadcast;

  @override
  Future<bool> get isEmpty => _controller.stream.isEmpty;

  @override
  Future<String> join([String separator = ""]) => _controller.stream.join(separator);

  @override
  Future<Uint8List> get last => _controller.stream.last;

  @override
  Future<Uint8List> lastWhere(bool Function(Uint8List element) test, {Uint8List Function()? orElse}) =>
      _controller.stream.lastWhere(test, orElse: orElse);

  @override
  Future<int> get length => _controller.stream.length;

  @override
  Stream<S> map<S>(S Function(Uint8List event) convert) => _controller.stream.map(convert);

  @override
  Future pipe(StreamConsumer<Uint8List> streamConsumer) => _controller.stream.pipe(streamConsumer);

  @override
  Future<Uint8List> reduce(Uint8List Function(Uint8List previous, Uint8List element) combine) =>
      _controller.stream.reduce(combine);

  @override
  Future<Uint8List> get single => _controller.stream.single;

  @override
  Future<Uint8List> singleWhere(bool Function(Uint8List element) test, {Uint8List Function()? orElse}) =>
      _controller.stream.singleWhere(test, orElse: orElse);

  @override
  Stream<Uint8List> skip(int count) => _controller.stream.skip(count);

  @override
  Stream<Uint8List> skipWhile(bool Function(Uint8List element) test) =>
      _controller.stream.skipWhile(test);

  @override
  Stream<Uint8List> take(int count) => _controller.stream.take(count);

  @override
  Stream<Uint8List> takeWhile(bool Function(Uint8List element) test) =>
      _controller.stream.takeWhile(test);

  @override
  Stream<Uint8List> timeout(Duration timeLimit, {void Function(EventSink<Uint8List> sink)? onTimeout}) =>
      _controller.stream.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Uint8List>> toList() => _controller.stream.toList();

  @override
  Future<Set<Uint8List>> toSet() => _controller.stream.toSet();

  @override
  Stream<S> transform<S>(StreamTransformer<Uint8List, S> streamTransformer) =>
      _controller.stream.transform(streamTransformer);

  @override
  Stream<Uint8List> where(bool Function(Uint8List event) test) => _controller.stream.where(test);
}

/// Mock ServerSocket implementation for testing
class MockServerSocket extends Stream<Socket> implements ServerSocket {
  final StreamController<Socket> _connectionController = StreamController<Socket>();
  final int _port;
  final InternetAddress _address;
  bool _closed = false;

  MockServerSocket._(this._address, this._port);

  /// Bind to an address and port (returns immediately)
  static Future<MockServerSocket> bind(
    dynamic address,
    int port, {
    int backlog = 0,
    bool v6Only = false,
    bool shared = false,
  }) async {
    final addr = address is String ? InternetAddress(address) : address as InternetAddress;
    return MockServerSocket._(addr, port);
  }

  /// Accept a connection from a client
  void acceptConnection(MockSocket clientSocket) {
    if (_closed) throw StateError('Server socket is closed');

    final serverSocket = MockSocket._(
      _address,
      _port,
      clientSocket.address,
      clientSocket.port,
    );

    clientSocket._peer = serverSocket;
    serverSocket._peer = clientSocket;

    _connectionController.add(serverSocket);
  }

  @override
  InternetAddress get address => _address;

  @override
  int get port => _port;

  @override
  Future<ServerSocket> close() async {
    if (_closed) return this;
    _closed = true;
    await _connectionController.close();
    return this;
  }

  // Stream implementation
  @override
  StreamSubscription<Socket> listen(
    void Function(Socket event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _connectionController.stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  // Delegate all Stream methods
  @override
  Future<bool> any(bool Function(Socket element) test) => _connectionController.stream.any(test);

  @override
  Stream<Socket> asBroadcastStream({
    void Function(StreamSubscription<Socket> subscription)? onListen,
    void Function(StreamSubscription<Socket> subscription)? onCancel,
  }) =>
      _connectionController.stream.asBroadcastStream(onListen: onListen, onCancel: onCancel);

  @override
  Stream<E> asyncExpand<E>(Stream<E>? Function(Socket event) convert) =>
      _connectionController.stream.asyncExpand(convert);

  @override
  Stream<E> asyncMap<E>(FutureOr<E> Function(Socket event) convert) =>
      _connectionController.stream.asyncMap(convert);

  @override
  Stream<R> cast<R>() => _connectionController.stream.cast<R>();

  @override
  Future<bool> contains(Object? needle) => _connectionController.stream.contains(needle);

  @override
  Stream<Socket> distinct([bool Function(Socket previous, Socket next)? equals]) =>
      _connectionController.stream.distinct(equals);

  @override
  Future<E> drain<E>([E? futureValue]) => _connectionController.stream.drain(futureValue);

  @override
  Future<Socket> elementAt(int index) => _connectionController.stream.elementAt(index);

  @override
  Future<bool> every(bool Function(Socket element) test) => _connectionController.stream.every(test);

  @override
  Stream<S> expand<S>(Iterable<S> Function(Socket element) convert) =>
      _connectionController.stream.expand(convert);

  @override
  Future<Socket> get first => _connectionController.stream.first;

  @override
  Future<Socket> firstWhere(bool Function(Socket element) test, {Socket Function()? orElse}) =>
      _connectionController.stream.firstWhere(test, orElse: orElse);

  @override
  Future<S> fold<S>(S initialValue, S Function(S previous, Socket element) combine) =>
      _connectionController.stream.fold(initialValue, combine);

  @override
  Future forEach(void Function(Socket element) action) => _connectionController.stream.forEach(action);

  @override
  Stream<Socket> handleError(Function onError, {bool Function(dynamic error)? test}) =>
      _connectionController.stream.handleError(onError, test: test);

  @override
  bool get isBroadcast => _connectionController.stream.isBroadcast;

  @override
  Future<bool> get isEmpty => _connectionController.stream.isEmpty;

  @override
  Future<String> join([String separator = ""]) => _connectionController.stream.join(separator);

  @override
  Future<Socket> get last => _connectionController.stream.last;

  @override
  Future<Socket> lastWhere(bool Function(Socket element) test, {Socket Function()? orElse}) =>
      _connectionController.stream.lastWhere(test, orElse: orElse);

  @override
  Future<int> get length => _connectionController.stream.length;

  @override
  Stream<S> map<S>(S Function(Socket event) convert) => _connectionController.stream.map(convert);

  @override
  Future pipe(StreamConsumer<Socket> streamConsumer) => _connectionController.stream.pipe(streamConsumer);

  @override
  Future<Socket> reduce(Socket Function(Socket previous, Socket element) combine) =>
      _connectionController.stream.reduce(combine);

  @override
  Future<Socket> get single => _connectionController.stream.single;

  @override
  Future<Socket> singleWhere(bool Function(Socket element) test, {Socket Function()? orElse}) =>
      _connectionController.stream.singleWhere(test, orElse: orElse);

  @override
  Stream<Socket> skip(int count) => _connectionController.stream.skip(count);

  @override
  Stream<Socket> skipWhile(bool Function(Socket element) test) =>
      _connectionController.stream.skipWhile(test);

  @override
  Stream<Socket> take(int count) => _connectionController.stream.take(count);

  @override
  Stream<Socket> takeWhile(bool Function(Socket element) test) =>
      _connectionController.stream.takeWhile(test);

  @override
  Stream<Socket> timeout(Duration timeLimit, {void Function(EventSink<Socket> sink)? onTimeout}) =>
      _connectionController.stream.timeout(timeLimit, onTimeout: onTimeout);

  @override
  Future<List<Socket>> toList() => _connectionController.stream.toList();

  @override
  Future<Set<Socket>> toSet() => _connectionController.stream.toSet();

  @override
  Stream<S> transform<S>(StreamTransformer<Socket, S> streamTransformer) =>
      _connectionController.stream.transform(streamTransformer);

  @override
  Stream<Socket> where(bool Function(Socket event) test) => _connectionController.stream.where(test);
}
