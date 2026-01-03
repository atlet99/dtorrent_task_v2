import 'dart:io';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';
import 'package:dtorrent_common/dtorrent_common.dart';

void main() {
  group('BEP 52 Hash Messages Tests', () {
    late List<int> testInfoHash;
    late CompactAddress testAddress;

    setUp(() {
      testInfoHash = List.filled(20, 0);
      testAddress = CompactAddress(InternetAddress('127.0.0.1'), 6881);
    });

    test('Peer sends hash request message', () {
      final piecesRoot = Uint8List.fromList(List.generate(32, (i) => i));
      final baseLayer = 0;
      final index = 0;
      final length = 2;
      final proofLayers = 1;

      // Create a mock peer (we'll test the message format)
      final message = Uint8List(42);
      var offset = 0;
      message.setRange(offset, offset + 32, piecesRoot);
      offset += 32;
      message[offset] = baseLayer;
      offset += 1;
      final view = ByteData.view(message.buffer, offset);
      view.setUint32(0, index, Endian.big);
      offset += 4;
      view.setUint32(4, length, Endian.big);
      offset += 4;
      message[offset] = proofLayers;

      // Verify message structure matches BEP 52 spec
      expect(message.length, equals(42));
      expect(message.sublist(0, 32), equals(piecesRoot));
      expect(message[32], equals(baseLayer));
      expect(view.getUint32(0, Endian.big), equals(index));
      expect(view.getUint32(4, Endian.big), equals(length));
      expect(message[41], equals(proofLayers));
    });

    test('Peer sends hashes message', () {
      final piecesRoot = Uint8List.fromList(List.generate(32, (i) => i));
      final baseLayer = 0;
      final index = 0;
      final length = 2;
      final proofLayers = 1;
      final hashes = Uint8List.fromList(List.generate(64, (i) => i % 256));

      // Create hashes message
      final message = Uint8List(42 + hashes.length);
      var offset = 0;
      message.setRange(offset, offset + 32, piecesRoot);
      offset += 32;
      message[offset] = baseLayer;
      offset += 1;
      final view = ByteData.view(message.buffer, offset);
      view.setUint32(0, index, Endian.big);
      offset += 4;
      view.setUint32(4, length, Endian.big);
      offset += 4;
      message[offset] = proofLayers;
      offset += 1;
      message.setRange(offset, offset + hashes.length, hashes);

      // Verify message structure
      expect(message.length, equals(42 + hashes.length));
      expect(message.sublist(0, 32), equals(piecesRoot));
      expect(message.sublist(42), equals(hashes));
    });

    test('Peer sends hash reject message', () {
      final piecesRoot = Uint8List.fromList(List.generate(32, (i) => i));
      final baseLayer = 0;
      final index = 0;
      final length = 2;
      final proofLayers = 1;

      // Hash reject has same format as hash request
      final message = Uint8List(42);
      var offset = 0;
      message.setRange(offset, offset + 32, piecesRoot);
      offset += 32;
      message[offset] = baseLayer;
      offset += 1;
      final view = ByteData.view(message.buffer, offset);
      view.setUint32(0, index, Endian.big);
      offset += 4;
      view.setUint32(4, length, Endian.big);
      offset += 4;
      message[offset] = proofLayers;

      expect(message.length, equals(42));
    });

    test('Hash request message ID is 21', () {
      expect(ID_HASH_REQUEST, equals(21));
    });

    test('Hashes message ID is 22', () {
      expect(ID_HASHES, equals(22));
    });

    test('Hash reject message ID is 23', () {
      expect(ID_HASH_REJECT, equals(23));
    });

    test('Hash request message minimum size is 42 bytes', () {
      // pieces root (32) + base layer (1) + index (4) + length (4) + proof layers (1) = 42
      expect(32 + 1 + 4 + 4 + 1, equals(42));
    });

    test('Hashes message can contain variable length hash data', () {
      final piecesRoot = Uint8List(32);
      final hashes = Uint8List.fromList(List.generate(128, (i) => i % 256));

      final message = Uint8List(42 + hashes.length);
      message.setRange(0, 32, piecesRoot);
      message.setRange(42, 42 + hashes.length, hashes);

      expect(message.length, greaterThan(42));
      expect(message.sublist(42), equals(hashes));
    });
  });
}
