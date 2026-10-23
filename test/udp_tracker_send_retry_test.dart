import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker/tracker/udp_tracker_base.dart';
import 'package:test/test.dart';

void main() {
  test('a datagram send succeeds only for a positive byte count', () {
    expect(udpDatagramSent(null), isFalse);
    expect(udpDatagramSent(0), isFalse);
    expect(udpDatagramSent(1), isTrue);
  });

  test('a successful announce keeps the tracker reusable', () async {
    final server =
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
    var received = 0;
    server.listen((event) {
      if (event != RawSocketEvent.read) return;
      final datagram = server.receive();
      if (datagram == null) return;
      received++;
      final view = ByteData.sublistView(datagram.data);
      final action = view.getUint32(8);
      final transactionId = view.getUint32(12);
      final response = Uint8List(20);
      final responseView = ByteData.sublistView(response);
      responseView.setUint32(0, action);
      responseView.setUint32(4, transactionId);
      if (action == 1) {
        responseView.setUint32(8, 1800); // interval
      }
      server.send(response, datagram.address, datagram.port);
    });

    final tracker = UDPTracker(
      Uri.parse('udp://127.0.0.1:${server.port}/announce'),
      Uint8List(20),
    );
    addTearDown(() async {
      await tracker.close();
      server.close();
    });
    final options = <String, dynamic>{
      'peerId': '-DT0201-123456789012',
      'downloaded': 0,
      'left': 0,
      'uploaded': 0,
      'port': 6881,
    };

    final first = await tracker
        .announce('started', options)
        .timeout(const Duration(seconds: 5));
    final second = await tracker
        .announce('started', options)
        .timeout(const Duration(seconds: 5));

    expect(first, isNotNull);
    expect(second, isNotNull);
    expect(received, 4); // connect + announce for each of the two rounds
  });

  test('failed sends emit one error and stop retrying', () async {
    // The socket is bound to IPv4, so sending to ::1 fails instead of being
    // silently dropped by a remote tracker.
    final tracker = UDPTracker(
      Uri.parse('udp://[::1]:6969/announce'),
      Uint8List(20),
    )
      ..maxSendRetryTimes = 2
      ..sendRetryDelay = Duration.zero;
    final errors = <Object?>[];
    tracker.events.on<TrackerAnnounceErrorEvent>(
      (event) => errors.add(event.error),
    );

    final started = await tracker.start().timeout(const Duration(seconds: 5));
    await pumpEventQueue();

    expect(started, isFalse);
    expect(errors, hasLength(1));
    expect(errors.single, isA<SocketException>());
  });
}
