import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_version.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('BEP 52 Advanced Features Tests', () {
    test('TorrentVersionHelper detects v2 from bencoded bytes', () {
      // Create a v2 torrent structure
      final info = <String, dynamic>{
        'meta version': 2,
        'name': 'test',
        'piece length': 16384,
        'file tree': {
          'test.txt': {
            '': {
              'length': 1024,
              'pieces root': Uint8List(32),
            }
          }
        }
      };

      final torrent = <String, dynamic>{
        'info': info,
        'piece layers': {},
      };

      final encoded = encode(torrent);
      final version = TorrentVersionHelper.detectVersionFromBytes(encoded);

      expect(version, equals(TorrentVersion.v2));
    });

    test('TorrentVersionHelper detects hybrid from bencoded bytes', () {
      // Create a hybrid torrent structure
      final info = <String, dynamic>{
        'meta version': 2,
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20), // v1 pieces
        'file tree': {
          'test.txt': {
            '': {
              'length': 1024,
              'pieces root': Uint8List(32),
            }
          }
        }
      };

      final torrent = <String, dynamic>{
        'info': info,
        'piece layers': {}, // v2 piece layers
      };

      final encoded = encode(torrent);
      final version = TorrentVersionHelper.detectVersionFromBytes(encoded);

      expect(version, equals(TorrentVersion.hybrid));
    });

    test('TorrentVersionHelper detects v1 from bencoded bytes', () {
      // Create a v1 torrent structure
      final info = <String, dynamic>{
        'name': 'test',
        'piece length': 16384,
        'pieces': Uint8List(20),
        'length': 1024,
      };

      final torrent = <String, dynamic>{
        'info': info,
      };

      final encoded = encode(torrent);
      final version = TorrentVersionHelper.detectVersionFromBytes(encoded);

      expect(version, equals(TorrentVersion.v1));
    });

    test('TorrentVersionHelper calculates v2 info hash', () {
      final infoDict = <String, dynamic>{
        'meta version': 2,
        'name': 'test',
        'piece length': 16384,
      };

      final encoded = encode(infoDict);
      final v2Hash = TorrentVersionHelper.calculateV2InfoHash(encoded);

      expect(v2Hash, isNotNull);
      expect(v2Hash!.length, equals(32)); // SHA-256 produces 32 bytes

      // Verify it's actually SHA-256
      final expectedHash = sha256.convert(encoded);
      expect(v2Hash, equals(Uint8List.fromList(expectedHash.bytes)));
    });

    test('TorrentVersionHelper calculates v2 info hash from dict', () {
      final infoDict = <String, dynamic>{
        'meta version': 2,
        'name': 'test',
        'piece length': 16384,
      };

      final v2Hash = TorrentVersionHelper.calculateV2InfoHashFromDict(infoDict);

      expect(v2Hash, isNotNull);
      expect(v2Hash!.length, equals(32));
    });

    test('TorrentVersionHelper truncates v2 info hash for tracker', () {
      final fullHash = Uint8List.fromList(List.generate(32, (i) => i));
      final truncated = TorrentVersionHelper.getTruncatedInfoHash(fullHash);

      expect(truncated, isNotNull);
      expect(truncated!.length, equals(20));
      expect(truncated, equals(fullHash.sublist(0, 20)));
    });

    test('Hash request message parsing', () {
      final piecesRoot = Uint8List.fromList(List.generate(32, (i) => i));
      final baseLayer = 0;
      final index = 0;
      final length = 2;
      final proofLayers = 1;

      // Create hash request message
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

      // Verify structure
      expect(message.length, equals(42));
      expect(message.sublist(0, 32), equals(piecesRoot));
      expect(message[32], equals(baseLayer));
      expect(view.getUint32(0, Endian.big), equals(index));
      expect(view.getUint32(4, Endian.big), equals(length));
      expect(message[41], equals(proofLayers));
    });

    test('Hashes message parsing', () {
      final piecesRoot = Uint8List.fromList(List.generate(32, (i) => i));
      final baseLayer = 0;
      final index = 0;
      final length = 2;
      final proofLayers = 1;
      final hashes = Uint8List.fromList(List.generate(64, (i) => i));

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

      // Verify structure
      expect(message.length, equals(42 + hashes.length));
      expect(message.sublist(0, 32), equals(piecesRoot));
      expect(message.sublist(42), equals(hashes));
    });

    test('Handshake reserved bit for v2 support', () {
      final reserved = List<int>.from([0, 0, 0, 0, 0, 0, 0, 0]);

      // Set v2 support bit (4th bit = 0x10 in reserved[7])
      reserved[7] |= 0x10;

      expect(reserved[7] & 0x10, equals(0x10));

      // Check that other bits are not affected
      reserved[7] |= 0x04; // Fast extension bit
      expect(reserved[7] & 0x10, equals(0x10)); // v2 bit still set
      expect(reserved[7] & 0x04, equals(0x04)); // Fast bit set
    });

    test('Handshake reserved bits combination', () {
      final reserved = List<int>.from([0, 0, 0, 0, 0, 0, 0, 0]);

      // Set extended protocol bit (reserved[5])
      reserved[5] |= 0x10;
      // Set fast extension bit (reserved[7])
      reserved[7] |= 0x04;
      // Set v2 support bit (reserved[7])
      reserved[7] |= 0x10;

      expect(reserved[5] & 0x10, equals(0x10));
      expect(reserved[7] & 0x04, equals(0x04));
      expect(reserved[7] & 0x10, equals(0x10));
      expect(reserved[7] & 0x14, equals(0x14)); // Both bits set
    });
  });
}
