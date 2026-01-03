import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_version.dart';
import 'package:dtorrent_task_v2/src/piece/piece.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('BitTorrent v2 Protocol Tests', () {
    test('TorrentVersionHelper detects v1 info hash', () {
      final v1Hash = Uint8List(20);
      expect(TorrentVersionHelper.isV1InfoHash(v1Hash), isTrue);
      expect(TorrentVersionHelper.isV2InfoHash(v1Hash), isFalse);
    });

    test('TorrentVersionHelper detects v2 info hash', () {
      final v2Hash = Uint8List(32);
      expect(TorrentVersionHelper.isV2InfoHash(v2Hash), isTrue);
      expect(TorrentVersionHelper.isV1InfoHash(v2Hash), isFalse);
    });

    test('TorrentVersionHelper returns correct piece hash length for v1', () {
      expect(TorrentVersionHelper.getPieceHashLength(TorrentVersion.v1),
          equals(20));
    });

    test('TorrentVersionHelper returns correct piece hash length for v2', () {
      expect(TorrentVersionHelper.getPieceHashLength(TorrentVersion.v2),
          equals(32));
    });

    test('TorrentVersionHelper returns correct hash algorithm for v1', () {
      final algo = TorrentVersionHelper.getHashAlgorithm(TorrentVersion.v1);
      expect(algo, equals(sha1));
    });

    test('TorrentVersionHelper returns correct hash algorithm for v2', () {
      final algo = TorrentVersionHelper.getHashAlgorithm(TorrentVersion.v2);
      expect(algo, equals(sha256));
    });

    test('Piece validates with SHA-1 for v1 torrent', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = sha1.convert(testData).toString();
      final piece =
          Piece(hash, 0, testData.length, 0, version: TorrentVersion.v1);

      // Simulate piece download
      piece.init();
      piece.subPieceReceived(0, testData);

      expect(piece.validatePiece(), isTrue);
    });

    test('Piece validates with SHA-256 for v2 torrent', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = sha256.convert(testData).toString();
      final piece =
          Piece(hash, 0, testData.length, 0, version: TorrentVersion.v2);

      // Simulate piece download
      piece.init();
      piece.subPieceReceived(0, testData);

      expect(piece.validatePiece(), isTrue);
    });

    test('Piece rejects invalid hash for v1 torrent', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final wrongHash = 'invalid_hash_string';
      final piece =
          Piece(wrongHash, 0, testData.length, 0, version: TorrentVersion.v1);

      // Simulate piece download
      piece.init();
      piece.subPieceReceived(0, testData);

      expect(piece.validatePiece(), isFalse);
    });

    test('Piece rejects invalid hash for v2 torrent', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final wrongHash = 'invalid_hash_string';
      final piece =
          Piece(wrongHash, 0, testData.length, 0, version: TorrentVersion.v2);

      // Simulate piece download
      piece.init();
      piece.subPieceReceived(0, testData);

      expect(piece.validatePiece(), isFalse);
    });

    test('Hybrid torrent defaults to v1 hash algorithm', () {
      final algo = TorrentVersionHelper.getHashAlgorithm(TorrentVersion.hybrid);
      expect(algo, equals(sha1));
    });
  });
}
