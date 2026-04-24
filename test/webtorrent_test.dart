import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker/tracker/tracker_exception.dart';
import 'package:test/test.dart';

class _StubAnnounceOptionsProvider implements AnnounceOptionsProvider {
  @override
  Future<Map<String, dynamic>> getOptions(Uri uri, String infoHash) async {
    return <String, dynamic>{
      'downloaded': 12,
      'uploaded': 3,
      'left': 42,
      'numwant': 1,
      'port': 6881,
      'peerId': '-DT0201-123456789012',
    };
  }
}

Future<({HttpServer server, Uri uri, Future<Map<String, dynamic>> request})>
    _startTrackerServer(
  Map<String, dynamic> response, {
  bool binaryResponse = false,
}) async {
  final requestCompleter = Completer<Map<String, dynamic>>();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.transform(WebSocketTransformer()).listen((socket) {
    socket.listen((message) {
      final decoded = jsonDecode(message as String) as Map<String, dynamic>;
      if (!requestCompleter.isCompleted) {
        requestCompleter.complete(decoded);
      }
      final encoded = jsonEncode(response);
      if (binaryResponse) {
        socket.add(utf8.encode(encoded));
      } else {
        socket.add(encoded);
      }
    });
  });

  return (
    server: server,
    uri: Uri.parse('ws://${server.address.address}:${server.port}/announce'),
    request: requestCompleter.future,
  );
}

void main() {
  group('WebTorrent WebSocket tracker', () {
    test('announces over WebSocket and parses signalling metadata', () async {
      final fixture = await _startTrackerServer(<String, dynamic>{
        'action': 'announce',
        'interval': 120,
        'complete': 4,
        'incomplete': 2,
        'warning message': 'busy but accepted',
        'offer': <String, dynamic>{'type': 'offer', 'sdp': 'fake-sdp'},
        'peer_id': '-WW0001-abcdefghijkl',
      });
      addTearDown(() async => fixture.server.close(force: true));

      final tracker = WebSocketTracker(
        fixture.uri,
        Uint8List.fromList(List<int>.generate(20, (index) => index)),
        provider: _StubAnnounceOptionsProvider(),
      );

      final event = await tracker.announce(
        eventStarted,
        await _StubAnnounceOptionsProvider().getOptions(fixture.uri, ''),
      );
      final request = await fixture.request;

      expect(request['action'], 'announce');
      expect(request['event'], eventStarted);
      expect((request['info_hash'] as String).codeUnits, hasLength(20));
      expect(request['peer_id'], '-DT0201-123456789012');
      expect(request['downloaded'], 12);
      expect(request['uploaded'], 3);
      expect(request['left'], 42);

      expect(event, isNotNull);
      expect(event!.interval, 120);
      expect(event.complete, 4);
      expect(event.incomplete, 2);
      expect(event.warning, 'busy but accepted');
      expect(event.otherInfomationsMap['offer'], isA<Map>());
      expect(event.otherInfomationsMap['peer_id'], '-WW0001-abcdefghijkl');
    });

    test('throws tracker exception on failure response', () async {
      final fixture = await _startTrackerServer(<String, dynamic>{
        'action': 'announce',
        'failure reason': 'tracker rejected announce',
      });
      addTearDown(() async => fixture.server.close(force: true));

      final tracker = WebSocketTracker(
        fixture.uri,
        Uint8List(20),
        provider: _StubAnnounceOptionsProvider(),
      );

      expect(
        tracker.announce(
          eventStarted,
          await _StubAnnounceOptionsProvider().getOptions(fixture.uri, ''),
        ),
        throwsA(isA<TrackerException>()),
      );
    });

    test('omits event for update announces and parses binary response',
        () async {
      final fixture = await _startTrackerServer(
        <String, dynamic>{
          'action': 'announce',
          'interval': '180',
          'min_interval': 60,
          'complete': 8,
          'incomplete': 1,
        },
        binaryResponse: true,
      );
      addTearDown(() async => fixture.server.close(force: true));

      final tracker = WebSocketTracker(
        fixture.uri,
        Uint8List(20),
        provider: _StubAnnounceOptionsProvider(),
      );

      final event = await tracker.announce(
        eventUpdate,
        await _StubAnnounceOptionsProvider().getOptions(fixture.uri, ''),
      );
      final request = await fixture.request;

      expect(request, isNot(contains('event')));
      expect(event, isNotNull);
      expect(event!.interval, 180);
      expect(event.minInterval, 60);
      expect(event.complete, 8);
      expect(event.incomplete, 1);
    });

    test('preserves WebTorrent signalling payload variants', () async {
      final fixture = await _startTrackerServer(<String, dynamic>{
        'action': 'announce',
        'answer': <String, dynamic>{'type': 'answer', 'sdp': 'answer-sdp'},
        'offers': [
          <String, dynamic>{
            'offer_id': 'offer-1',
            'offer': <String, dynamic>{'type': 'offer'},
          },
        ],
        'ice': <String, dynamic>{'candidate': 'candidate:1'},
        'to_peer_id': '-WW0001-targetpeer1',
        'peers': [
          <String, dynamic>{'peer_id': '-WW0001-peer000001'},
        ],
      });
      addTearDown(() async => fixture.server.close(force: true));

      final tracker = WebSocketTracker(
        fixture.uri,
        Uint8List(20),
        provider: _StubAnnounceOptionsProvider(),
      );

      final event = await tracker.announce(
        eventStarted,
        await _StubAnnounceOptionsProvider().getOptions(fixture.uri, ''),
      );

      expect(event, isNotNull);
      expect(event!.otherInfomationsMap['answer'], isA<Map>());
      expect(event.otherInfomationsMap['offers'], isA<List>());
      expect(event.otherInfomationsMap['ice'], isA<Map>());
      expect(event.otherInfomationsMap['to_peer_id'], '-WW0001-targetpeer1');
      expect(event.otherInfomationsMap['webtorrent_peers'], isA<List>());
    });

    test('rejects missing or invalid peer id before sending announce',
        () async {
      final fixture = await _startTrackerServer(<String, dynamic>{
        'action': 'announce',
      });
      addTearDown(() async => fixture.server.close(force: true));

      final tracker = WebSocketTracker(
        fixture.uri,
        Uint8List(20),
        provider: _StubAnnounceOptionsProvider(),
      );

      expect(
        tracker.announce(eventStarted, <String, dynamic>{
          'peerId': 'too-short',
        }),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
