import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/torrent/torrent_version.dart';
import 'package:dtorrent_task_v2/src/piece/piece.dart';
import 'package:crypto/crypto.dart';

void main() {
  group('Hybrid Torrent Tests', () {
    test('Hybrid torrent can use v1 piece validation', () {
      final testData = Uint8List.fromList([1, 2, 3, 4, 5]);
      final hash = sha1.convert(testData).toString();
      final piece =
          Piece(hash, 0, testData.length, 0, version: TorrentVersion.hybrid);

      // Simulate piece download
      piece.init();
      piece.subPieceReceived(0, testData);

      expect(piece.validatePiece(), isTrue);
    });

    test('Hybrid torrent piece hash length defaults to v1', () {
      expect(TorrentVersionHelper.getPieceHashLength(TorrentVersion.hybrid),
          equals(20));
    });

    test('Hybrid torrent hash algorithm defaults to v1', () {
      final algo = TorrentVersionHelper.getHashAlgorithm(TorrentVersion.hybrid);
      expect(algo, equals(sha1));
    });

    test('Info hash detection works for both v1 and v2 lengths', () {
      final v1Hash = Uint8List(20);
      final v2Hash = Uint8List(32);

      expect(TorrentVersionHelper.isV1InfoHash(v1Hash), isTrue);
      expect(TorrentVersionHelper.isV2InfoHash(v1Hash), isFalse);

      expect(TorrentVersionHelper.isV2InfoHash(v2Hash), isTrue);
      expect(TorrentVersionHelper.isV1InfoHash(v2Hash), isFalse);
    });

    test('Hybrid torrent pieces can be created with explicit version', () {
      final hash = sha1.convert([1, 2, 3]).toString();
      final piece = Piece(hash, 0, 3, 0, version: TorrentVersion.hybrid);

      expect(piece.version, equals(TorrentVersion.hybrid));
    });
  });
}
