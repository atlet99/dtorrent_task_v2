import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/torrent/piece_layers.dart';

void main() {
  group('PieceLayersHelper', () {
    test('Parse piece layers with single file', () {
      final piecesRoot1 = Uint8List.fromList(List.filled(32, 0xAA));
      final hashes1 = Uint8List.fromList(List.filled(64, 0xBB)); // 2 hashes

      final pieceLayersData = {
        piecesRoot1: hashes1,
      };

      final pieceLayers = PieceLayersHelper.parsePieceLayers(pieceLayersData);
      expect(pieceLayers, isNotNull);
      expect(pieceLayers!.length, equals(1));
      expect(pieceLayers.containsKey(piecesRoot1), isTrue);
      expect(pieceLayers[piecesRoot1], equals(hashes1));
    });

    test('Parse piece layers with multiple files', () {
      final piecesRoot1 = Uint8List.fromList(List.filled(32, 0xAA));
      final piecesRoot2 = Uint8List.fromList(List.filled(32, 0xBB));
      final hashes1 = Uint8List.fromList(List.filled(96, 0xCC)); // 3 hashes
      final hashes2 = Uint8List.fromList(List.filled(32, 0xDD)); // 1 hash

      final pieceLayersData = {
        piecesRoot1: hashes1,
        piecesRoot2: hashes2,
      };

      final pieceLayers = PieceLayersHelper.parsePieceLayers(pieceLayersData);
      expect(pieceLayers, isNotNull);
      expect(pieceLayers!.length, equals(2));
      expect(pieceLayers[piecesRoot1], equals(hashes1));
      expect(pieceLayers[piecesRoot2], equals(hashes2));
    });

    test('Get piece hashes for file', () {
      final piecesRoot = Uint8List.fromList(List.filled(32, 0xAA));
      final hashes = Uint8List.fromList(List.filled(96, 0xBB)); // 3 hashes

      final pieceLayers = {
        piecesRoot: hashes,
      };

      final fileHashes =
          PieceLayersHelper.getPieceHashesForFile(pieceLayers, piecesRoot);
      expect(fileHashes, isNotNull);
      expect(fileHashes, equals(hashes));
    });

    test('Get piece hash by index', () {
      final hash1 = Uint8List.fromList(List.filled(32, 0xAA));
      final hash2 = Uint8List.fromList(List.filled(32, 0xBB));
      final hash3 = Uint8List.fromList(List.filled(32, 0xCC));

      final concatenated = Uint8List(96);
      concatenated.setRange(0, 32, hash1);
      concatenated.setRange(32, 64, hash2);
      concatenated.setRange(64, 96, hash3);

      final pieceHash0 = PieceLayersHelper.getPieceHash(concatenated, 0, 32);
      expect(pieceHash0, isNotNull);
      expect(pieceHash0, equals(hash1));

      final pieceHash1 = PieceLayersHelper.getPieceHash(concatenated, 1, 32);
      expect(pieceHash1, isNotNull);
      expect(pieceHash1, equals(hash2));

      final pieceHash2 = PieceLayersHelper.getPieceHash(concatenated, 2, 32);
      expect(pieceHash2, isNotNull);
      expect(pieceHash2, equals(hash3));
    });

    test('Get all piece hashes', () {
      final hash1 = Uint8List.fromList(List.filled(32, 0xAA));
      final hash2 = Uint8List.fromList(List.filled(32, 0xBB));
      final hash3 = Uint8List.fromList(List.filled(32, 0xCC));

      final concatenated = Uint8List(96);
      concatenated.setRange(0, 32, hash1);
      concatenated.setRange(32, 64, hash2);
      concatenated.setRange(64, 96, hash3);

      final allHashes = PieceLayersHelper.getAllPieceHashes(concatenated, 32);
      expect(allHashes.length, equals(3));
      expect(allHashes[0], equals(hash1));
      expect(allHashes[1], equals(hash2));
      expect(allHashes[2], equals(hash3));
    });

    test('Validate piece layers structure', () {
      final piecesRoot1 = Uint8List.fromList(List.filled(32, 0xAA));
      final piecesRoot2 = Uint8List.fromList(List.filled(32, 0xBB));
      final hashes1 = Uint8List.fromList(List.filled(96, 0xCC)); // Valid
      final hashes2 = Uint8List.fromList(List.filled(33, 0xDD)); // Invalid

      final pieceLayers = {
        piecesRoot1: hashes1,
        piecesRoot2: hashes2,
      };

      final isValid = PieceLayersHelper.validatePieceLayers(pieceLayers);
      expect(isValid, isFalse); // hashes2 is not multiple of 32
    });

    test('Validate valid piece layers', () {
      final piecesRoot = Uint8List.fromList(List.filled(32, 0xAA));
      final hashes = Uint8List.fromList(List.filled(64, 0xBB)); // Valid

      final pieceLayers = {
        piecesRoot: hashes,
      };

      final isValid = PieceLayersHelper.validatePieceLayers(pieceLayers);
      expect(isValid, isTrue);
    });

    test('Parse piece layers with invalid pieces root length', () {
      final invalidRoot =
          Uint8List.fromList(List.filled(20, 0xAA)); // Wrong length
      final hashes = Uint8List.fromList(List.filled(32, 0xBB));

      final pieceLayersData = {
        invalidRoot: hashes,
      };

      final pieceLayers = PieceLayersHelper.parsePieceLayers(pieceLayersData);
      // Invalid entry is skipped, so result is empty map which returns null
      expect(pieceLayers, isNull);
    });

    test('Parse empty piece layers returns null', () {
      final pieceLayers = PieceLayersHelper.parsePieceLayers({});
      expect(pieceLayers, isNull);
    });

    test('Parse invalid piece layers returns null', () {
      final pieceLayers = PieceLayersHelper.parsePieceLayers('not a map');
      expect(pieceLayers, isNull);
    });

    test('Get piece hash with out of bounds index returns null', () {
      final hashes = Uint8List.fromList(List.filled(32, 0xAA));
      final pieceHash = PieceLayersHelper.getPieceHash(hashes, 1, 32);
      expect(pieceHash, isNull);
    });
  });
}
