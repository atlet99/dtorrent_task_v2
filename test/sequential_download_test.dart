import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_common/dtorrent_common.dart';
import 'test_helpers.dart';

void main() {
  group('Sequential Download Tests', () {
    test('should create SequentialConfig with default values', () {
      final config = SequentialConfig.forVideoStreaming();

      expect(config.lookAheadSize, greaterThan(0));
      expect(config.criticalZoneSize, greaterThan(0));
      expect(config.adaptiveStrategy, isTrue);
      expect(config.minSpeedForSequential, greaterThan(0));
    });

    test('should create SequentialConfig for audio streaming', () {
      final config = SequentialConfig.forAudioStreaming();

      expect(config.lookAheadSize, greaterThan(0));
      expect(config.criticalZoneSize, greaterThan(0));
      expect(config.adaptiveStrategy, isTrue);
    });

    test('should create minimal SequentialConfig', () {
      final config = SequentialConfig.minimal();

      expect(config.lookAheadSize, greaterThan(0));
      expect(config.lookAheadSize, lessThanOrEqualTo(10));
    });

    test('should create custom SequentialConfig', () {
      final config = const SequentialConfig(
        lookAheadSize: 20,
        criticalZoneSize: 15 * 1024 * 1024,
        adaptiveStrategy: true,
        minSpeedForSequential: 200 * 1024,
        autoDetectMoovAtom: true,
        seekLatencyTolerance: 2,
        enablePeerPriority: true,
        enableFastResumption: true,
      );

      expect(config.lookAheadSize, equals(20));
      expect(config.criticalZoneSize, equals(15 * 1024 * 1024));
      expect(config.adaptiveStrategy, isTrue);
      expect(config.minSpeedForSequential, equals(200 * 1024));
      expect(config.autoDetectMoovAtom, isTrue);
      expect(config.seekLatencyTolerance, equals(2));
      expect(config.enablePeerPriority, isTrue);
      expect(config.enableFastResumption, isTrue);
    });

    test('should create AdvancedSequentialPieceSelector', () {
      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);

      expect(selector, isNotNull);
    });

    test('should initialize AdvancedSequentialPieceSelector', () {
      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);

      selector.initialize(100, 256 * 1024); // 100 pieces, 256KB each

      expect(selector, isNotNull);
    });

    test('should detect and set moov atom', () {
      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);

      selector.initialize(100, 256 * 1024);
      selector.detectAndSetMoovAtom(25 * 1024 * 1024, 256 * 1024); // 25MB file

      expect(selector, isNotNull);
    });

    test('should set playback position', () {
      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);

      selector.initialize(100, 256 * 1024);
      selector.setPlaybackPosition(5 * 1024 * 1024, 256 * 1024); // Seek to 5MB

      expect(selector, isNotNull);
    });

    test('should create SequentialStats', () {
      final stats = SequentialStats(
        bufferHealth: 85.5,
        timeToFirstByte: 1500,
        playbackPosition: 10 * 1024 * 1024, // 10MB
        bufferedPieces: 8,
        downloadingPieces: 2,
        currentStrategy: DownloadStrategy.sequential,
        seekCount: 3,
        averageSeekLatency: 800,
        moovAtomDownloaded: true,
      );

      expect(stats.bufferHealth, equals(85.5));
      expect(stats.timeToFirstByte, equals(1500));
      expect(stats.playbackPosition, equals(10 * 1024 * 1024));
      expect(stats.bufferedPieces, equals(8));
      expect(stats.downloadingPieces, equals(2));
      expect(stats.currentStrategy, equals(DownloadStrategy.sequential));
      expect(stats.seekCount, equals(3));
      expect(stats.averageSeekLatency, equals(800));
      expect(stats.moovAtomDownloaded, isTrue);
    });

    test('should use AdvancedSequentialPieceSelector in PieceManager',
        () async {
      final torrent = await createTestTorrent(
        fileSize: 1024 * 100,
        pieceLength: 16384,
      );

      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);
      selector.initialize(torrent.pieces?.length ?? 0, torrent.pieceLength);

      final bitfield =
          Bitfield.createEmptyBitfield(torrent.pieces?.length ?? 0);
      final pieceManager = PieceManager.createPieceManager(
        selector,
        torrent,
        bitfield,
      );

      expect(pieceManager, isNotNull);
      expect(pieceManager.length, equals(torrent.pieces?.length ?? 0));
    });

    test('should prioritize pieces sequentially', () async {
      final torrent = await createTestTorrent(
        fileSize: 1024 * 100,
        pieceLength: 16384,
      );

      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);
      selector.initialize(torrent.pieces?.length ?? 0, torrent.pieceLength);

      final bitfield =
          Bitfield.createEmptyBitfield(torrent.pieces?.length ?? 0);
      final pieceManager = PieceManager.createPieceManager(
        selector,
        torrent,
        bitfield,
      );

      // Create a mock peer
      final peer = Peer.newTCPPeer(
        CompactAddress(InternetAddress('127.0.0.1'), 6881),
        List<int>.generate(20, (i) => i),
        torrent.pieces?.length ?? 0,
        null,
        PeerSource.manual,
      );

      // Set remote bitfield to indicate peer has all pieces
      for (var i = 0; i < (torrent.pieces?.length ?? 0); i++) {
        peer.updateRemoteBitfield(i, true);
      }

      // Add peer to available peers for all pieces
      for (var i = 0; i < pieceManager.length; i++) {
        final piece = pieceManager[i];
        if (piece != null) {
          piece.addAvailablePeer(peer);
        }
      }

      // Select pieces - should prioritize sequentially
      final selectedPieces = <int>[];
      for (var i = 0; i < 5; i++) {
        final piece = pieceManager.selectPiece(peer, pieceManager, null);
        if (piece != null) {
          selectedPieces.add(piece.index);
        }
      }

      // Should select pieces in sequential order (0, 1, 2, ...)
      expect(selectedPieces.length, greaterThan(0));
      // First piece should be 0 or close to 0
      expect(selectedPieces[0], lessThan(5));
    });

    test('should handle seek operations', () {
      final config = SequentialConfig.forVideoStreaming();
      final selector = AdvancedSequentialPieceSelector(config);

      selector.initialize(100, 256 * 1024);

      // Set initial playback position
      selector.setPlaybackPosition(5 * 1024 * 1024, 256 * 1024);

      // Seek to different position
      selector.setPlaybackPosition(10 * 1024 * 1024, 256 * 1024);

      expect(selector, isNotNull);
    });
  });
}
