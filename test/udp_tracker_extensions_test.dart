import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';
import 'package:dtorrent_task_v2/src/standalone/dtorrent_tracker.dart';
import 'package:test/test.dart';

void main() {
  group('UDP tracker BEP 41 extensions', () {
    test('appends URLData option with path and query', () {
      final tracker = UDPTracker(
        Uri.parse('udp://tracker.example.org:6969/announce/passkey?foo=bar'),
        Uint8List(20),
      );
      final message = tracker.generateSecondTouchMessage(
        Uint8List.fromList(List<int>.filled(8, 1)),
        <String, dynamic>{
          'peerId': '-DT0201-123456789012',
          'downloaded': 0,
          'left': 0,
          'uploaded': 0,
          'port': 6881,
          'numwant': 10,
          'key': 123,
        },
      );

      const fixedAnnounceLen = 98;
      expect(message.length, greaterThan(fixedAnnounceLen));
      final options = message.sublist(fixedAnnounceLen);
      expect(options.last, 0); // EndOfOptions marker.
      expect(options.first, 2); // URLData option type.

      final len = options[1];
      final urlData = utf8.decode(options.sublist(2, 2 + len));
      expect(urlData, '/announce/passkey?foo=bar');
    });

    test('splits long URLData into multiple chunks', () {
      final longPath = '/announce/${'a' * 320}?token=abc';
      final tracker = UDPTracker(
        Uri.parse('udp://tracker.example.org:6969$longPath'),
        Uint8List(20),
      );
      final message = tracker.generateSecondTouchMessage(
        Uint8List.fromList(List<int>.filled(8, 2)),
        <String, dynamic>{
          'peerId': '-DT0201-123456789012',
          'downloaded': 0,
          'left': 0,
          'uploaded': 0,
          'port': 6881,
        },
      );

      const fixedAnnounceLen = 98;
      final options = message.sublist(fixedAnnounceLen);
      var i = 0;
      var chunks = 0;
      final merged = <int>[];
      while (i < options.length) {
        final type = options[i++];
        if (type == 0) break;
        expect(type, 2);
        final len = options[i++];
        expect(len, inInclusiveRange(1, 255));
        merged.addAll(options.sublist(i, i + len));
        i += len;
        chunks++;
      }

      expect(chunks, greaterThan(1));
      expect(utf8.decode(merged), longPath);
    });

    test('parses peers and extension payload from response', () {
      final tracker = UDPTracker(
        Uri.parse('udp://tracker.example.org:6969/announce'),
        Uint8List(20),
      );

      final header = ByteData(20)
        ..setUint32(8, 1800) // interval
        ..setUint32(12, 3) // complete
        ..setUint32(16, 7); // incomplete

      final response = Uint8List.fromList(<int>[
        ...header.buffer.asUint8List(),
        1, 2, 3, 4, 0x1A, 0xE1, // compact peer: 1.2.3.4:6881
        3, 2, 0xAA, 0xBB, // extension option type 3 with payload
        0, // EndOfOptions
      ]);

      final event = tracker.processResponseData(
        response,
        1,
        <CompactAddress>[
          CompactAddress(InternetAddress.loopbackIPv4, 6969),
        ],
      );

      expect(event.peers.length, 1);
      final peer = event.peers.first;
      expect(peer.address.address, '1.2.3.4');
      expect(peer.port, 6881);

      final options =
          event.otherInfomationsMap['udp_options'] as Map<int, List<List<int>>>;
      expect(options.containsKey(3), isTrue);
      expect(options[3]!.single, <int>[0xAA, 0xBB]);
      expect(event.otherInfomationsMap['udp_extensions_supported'], isTrue);
    });
  });
}
