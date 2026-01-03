import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/src/torrent/merkle_tree.dart';

void main() {
  group('MerkleTreeHelper', () {
    test('Calculate root for empty file', () {
      final emptyData = Uint8List(0);
      final root = MerkleTreeHelper.calculateRoot(emptyData);
      expect(root.length, equals(32));
      // Empty file should have zero root
      expect(root.every((byte) => byte == 0), isTrue);
    });

    test('Calculate root for small file (single block)', () {
      final fileData = Uint8List.fromList(List.filled(1024, 0xAA));
      final root = MerkleTreeHelper.calculateRoot(fileData);
      expect(root.length, equals(32));

      // Root should be SHA-256 of the single block
      final expectedHash = sha256.convert(fileData);
      expect(root, equals(Uint8List.fromList(expectedHash.bytes)));
    });

    test('Calculate root for file with multiple blocks', () {
      // Create file with 2 blocks (32KB total)
      final fileData = Uint8List.fromList(List.filled(32 * 1024, 0xBB));
      final root = MerkleTreeHelper.calculateRoot(fileData);
      expect(root.length, equals(32));

      // Should have valid root
      expect(root.any((byte) => byte != 0), isTrue);
    });

    test('Validate file with correct pieces root', () {
      final fileData = Uint8List.fromList(List.filled(1024, 0xAA));
      final calculatedRoot = MerkleTreeHelper.calculateRoot(fileData);

      final isValid = MerkleTreeHelper.validateFile(fileData, calculatedRoot);
      expect(isValid, isTrue);
    });

    test('Validate file with incorrect pieces root', () {
      final fileData = Uint8List.fromList(List.filled(1024, 0xAA));
      final wrongRoot = Uint8List.fromList(List.filled(32, 0xFF));

      final isValid = MerkleTreeHelper.validateFile(fileData, wrongRoot);
      expect(isValid, isFalse);
    });

    test('Validate piece with correct hash', () {
      final pieceData = Uint8List.fromList(List.filled(16 * 1024, 0xCC));
      final expectedHash = sha256.convert(pieceData);
      final hashBytes = Uint8List.fromList(expectedHash.bytes);

      final isValid = MerkleTreeHelper.validatePiece(pieceData, hashBytes);
      expect(isValid, isTrue);
    });

    test('Validate piece with incorrect hash', () {
      final pieceData = Uint8List.fromList(List.filled(16 * 1024, 0xCC));
      final wrongHash = Uint8List.fromList(List.filled(32, 0xFF));

      final isValid = MerkleTreeHelper.validatePiece(pieceData, wrongHash);
      expect(isValid, isFalse);
    });

    test('Calculate layer hashes for leaf layer', () {
      final fileData = Uint8List.fromList(List.filled(32 * 1024, 0xDD));
      final layerHashes = MerkleTreeHelper.calculateLayerHashes(fileData, 0);

      expect(layerHashes, isNotNull);
      expect(layerHashes!.length, equals(2)); // 2 blocks of 16KB each
      expect(layerHashes[0].length, equals(32));
      expect(layerHashes[1].length, equals(32));
    });

    test('Calculate layer hashes for parent layer', () {
      final fileData = Uint8List.fromList(List.filled(32 * 1024, 0xEE));
      final layerHashes = MerkleTreeHelper.calculateLayerHashes(fileData, 1);

      expect(layerHashes, isNotNull);
      expect(layerHashes!.length, equals(1)); // Parent of 2 leaf nodes
      expect(layerHashes[0].length, equals(32));
    });

    test('Get layer number for piece size', () {
      // 16KB piece size = leaf layer (0)
      expect(MerkleTreeHelper.getLayerForPieceSize(16 * 1024), equals(0));

      // 32KB piece size = layer 1
      expect(MerkleTreeHelper.getLayerForPieceSize(32 * 1024), equals(1));

      // 64KB piece size = layer 2
      expect(MerkleTreeHelper.getLayerForPieceSize(64 * 1024), equals(2));

      // 128KB piece size = layer 3
      expect(MerkleTreeHelper.getLayerForPieceSize(128 * 1024), equals(3));
    });

    test('Validate file with invalid pieces root length', () {
      final fileData = Uint8List.fromList(List.filled(1024, 0xAA));
      final invalidRoot = Uint8List(20); // Wrong length

      final isValid = MerkleTreeHelper.validateFile(fileData, invalidRoot);
      expect(isValid, isFalse);
    });

    test('Validate piece with invalid hash length', () {
      final pieceData = Uint8List.fromList(List.filled(16 * 1024, 0xCC));
      final invalidHash = Uint8List(20); // Wrong length

      final isValid = MerkleTreeHelper.validatePiece(pieceData, invalidHash);
      expect(isValid, isFalse);
    });

    test('Calculate root with custom block size', () {
      final fileData = Uint8List.fromList(List.filled(8192, 0xFF));
      final root = MerkleTreeHelper.calculateRoot(fileData, blockSize: 4096);
      expect(root.length, equals(32));

      // Should have 2 blocks
      final layerHashes =
          MerkleTreeHelper.calculateLayerHashes(fileData, 0, blockSize: 4096);
      expect(layerHashes, isNotNull);
      expect(layerHashes!.length, equals(2));
    });

    test('Calculate root for file with odd number of blocks', () {
      // 3 blocks (48KB)
      final fileData = Uint8List.fromList(List.filled(48 * 1024, 0x11));
      final root = MerkleTreeHelper.calculateRoot(fileData);
      expect(root.length, equals(32));

      // Should handle odd number correctly
      final layerHashes = MerkleTreeHelper.calculateLayerHashes(fileData, 0);
      expect(layerHashes, isNotNull);
      expect(layerHashes!.length, equals(3));
    });
  });
}
