import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/metadata/metadata_messenger.dart';
import 'package:test/test.dart';

class _TestMessenger with MetaDataMessenger {}

void main() {
  group('MetaDataMessenger Tests', () {
    late _TestMessenger messenger;

    setUp(() {
      messenger = _TestMessenger();
    });

    test('createRequestMessage encodes msg_type=0 and piece', () {
      final encoded = messenger.createRequestMessage(7);
      final decoded = decode(Uint8List.fromList(encoded)) as Map;

      expect(decoded['msg_type'], equals(0));
      expect(decoded['piece'], equals(7));
    });

    test('createRejectMessage encodes msg_type=2 and piece', () {
      final encoded = messenger.createRejectMessage(3);
      final decoded = decode(Uint8List.fromList(encoded)) as Map;

      expect(decoded['msg_type'], equals(2));
      expect(decoded['piece'], equals(3));
    });

    test('createDataMessage encodes msg_type=1, piece and total_size', () {
      final encoded = messenger.createDataMessage(5, [1, 2, 3, 4]);
      final decoded = decode(Uint8List.fromList(encoded)) as Map;

      expect(decoded['msg_type'], equals(1));
      expect(decoded['piece'], equals(5));
      expect(decoded['total_size'], equals(4));
    });
  });
}
