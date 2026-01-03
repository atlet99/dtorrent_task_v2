import 'package:logging/logging.dart';
import '../peer/protocol/peer.dart';

var _log = Logger('SuperSeeder');

/// SuperSeeder implements BEP 16 Superseeding algorithm.
///
/// When enabled, the seeder masquerades as a normal peer with no data.
/// It then informs connecting clients that it received a piece - a piece that
/// was never sent, or if all pieces were already sent, is very rare.
/// This induces the client to attempt to download only that piece.
///
/// The seeder will not inform the client of any other pieces until it has seen
/// the piece it had sent previously present on at least one other client.
///
/// This method results in much higher seeding efficiencies by:
/// - Inducing peers into taking only the rarest data
/// - Reducing the amount of redundant data sent
/// - Limiting the amount of data sent to peers which do not contribute to the swarm
///
/// **Important**: Superseeding is NOT recommended for general use. It should only
/// be used for initial seeding when you are the only or primary seeder.
class SuperSeeder {
  /// Total number of pieces in the torrent
  final int totalPieces;

  /// Map of piece index to its rarity (number of peers that have this piece)
  final Map<int, int> _pieceRarity = {};

  /// Set of pieces that have been offered to peers
  final Set<int> _offeredPieces = {};

  /// Map of piece index to set of peers that have this piece
  final Map<int, Set<Peer>> _pieceDistribution = {};

  /// Map of peer to the piece index that was offered to this peer
  final Map<Peer, int?> _peerOfferedPiece = {};

  /// Whether superseeding is currently enabled
  bool _enabled = false;

  bool get enabled => _enabled;

  /// Statistics: number of pieces offered
  int _piecesOffered = 0;

  /// Statistics: number of pieces that appeared on other peers
  int _piecesDistributed = 0;

  SuperSeeder(this.totalPieces) {
    // Initialize rarity for all pieces to 0 (only we have them)
    for (var i = 0; i < totalPieces; i++) {
      _pieceRarity[i] = 0;
      _pieceDistribution[i] = {};
    }
  }

  /// Enable superseeding mode
  void enable() {
    if (_enabled) return;
    _enabled = true;
    _log.info('Superseeding enabled');
  }

  /// Disable superseeding mode
  void disable() {
    if (!_enabled) return;
    _enabled = false;
    _log.info('Superseeding disabled');
    // Clear all tracking when disabled
    _offeredPieces.clear();
    _peerOfferedPiece.clear();
  }

  /// Check if we should send bitfield (returns false in superseeding mode)
  bool shouldSendBitfield() {
    return !_enabled;
  }

  /// Select a piece to offer to a peer
  ///
  /// Returns the piece index to offer, or null if no piece should be offered yet.
  int? selectPieceToOffer(Peer peer) {
    if (!_enabled) return null;

    // If we already offered a piece to this peer, don't offer another one yet
    final alreadyOffered = _peerOfferedPiece[peer];
    if (alreadyOffered != null) {
      // Check if this piece has been distributed (seen on another peer)
      if (_pieceRarity[alreadyOffered]! > 0) {
        // Piece has been distributed, we can offer a new one
        _peerOfferedPiece.remove(peer);
      } else {
        // Still waiting for this piece to be distributed
        return null;
      }
    }

    // Find the rarest piece that hasn't been offered yet
    int? rarestPiece;
    int minRarity = 999999;

    // First, try to find a piece that hasn't been offered at all
    for (var i = 0; i < totalPieces; i++) {
      if (!_offeredPieces.contains(i)) {
        final rarity = _pieceRarity[i] ?? 0;
        if (rarity < minRarity) {
          minRarity = rarity;
          rarestPiece = i;
        }
      }
    }

    // If all pieces have been offered, find the rarest one overall
    if (rarestPiece == null) {
      for (var i = 0; i < totalPieces; i++) {
        final rarity = _pieceRarity[i] ?? 0;
        if (rarity < minRarity) {
          minRarity = rarity;
          rarestPiece = i;
        }
      }
    }

    if (rarestPiece != null) {
      _offeredPieces.add(rarestPiece);
      _peerOfferedPiece[peer] = rarestPiece;
      _piecesOffered++;
      _log.fine(
          'Offering piece $rarestPiece to peer ${peer.address} (rarity: $minRarity)');
    }

    return rarestPiece;
  }

  /// Get the list of pieces to announce to a peer via HAVE messages
  ///
  /// In superseeding mode, this returns only one piece (the one offered to this peer).
  /// Returns empty list if no piece should be announced yet.
  List<int> getPiecesToAnnounce(Peer peer) {
    if (!_enabled) return [];

    final offeredPiece = _peerOfferedPiece[peer];
    if (offeredPiece != null) {
      return [offeredPiece];
    }

    // Try to select a new piece to offer
    final pieceToOffer = selectPieceToOffer(peer);
    if (pieceToOffer != null) {
      return [pieceToOffer];
    }

    return [];
  }

  /// Handle when a peer sends a HAVE message for a piece
  ///
  /// This is used to track piece distribution - when we see a piece on another peer,
  /// we know it has been distributed and can offer the next piece.
  void onPeerHave(Peer peer, int pieceIndex) {
    if (!_enabled) return;
    if (pieceIndex < 0 || pieceIndex >= totalPieces) return;

    // Add peer to the distribution set for this piece
    _pieceDistribution[pieceIndex]?.add(peer);

    // Update rarity (number of peers with this piece)
    _pieceRarity[pieceIndex] = _pieceDistribution[pieceIndex]?.length ?? 0;

    // Check if this piece was offered to this peer
    final offeredPiece = _peerOfferedPiece[peer];
    if (offeredPiece == pieceIndex) {
      // This is the piece we offered to this peer
      // Now that it's on the peer, we can offer a new piece when they connect again
      // But we wait until we see it on ANOTHER peer (rarity > 0 means someone else has it)
      if (_pieceRarity[pieceIndex]! > 0) {
        _log.fine(
            'Piece $pieceIndex offered to peer ${peer.address} has been distributed (rarity: ${_pieceRarity[pieceIndex]})');
        _piecesDistributed++;
      }
    }

    _log.fine(
        'Peer ${peer.address} has piece $pieceIndex (rarity: ${_pieceRarity[pieceIndex]})');
  }

  /// Handle when a peer disconnects
  ///
  /// Cleans up tracking for this peer.
  void onPeerDisconnected(Peer peer) {
    if (!_enabled) return;

    // Remove peer from piece distribution
    for (var pieceIndex in _pieceDistribution.keys) {
      _pieceDistribution[pieceIndex]?.remove(peer);
      _pieceRarity[pieceIndex] = _pieceDistribution[pieceIndex]?.length ?? 0;
    }

    // Remove peer from offered pieces tracking
    _peerOfferedPiece.remove(peer);

    _log.fine('Cleaned up tracking for disconnected peer ${peer.address}');
  }

  /// Get statistics about superseeding performance
  Map<String, dynamic> getStatistics() {
    return {
      'enabled': _enabled,
      'piecesOffered': _piecesOffered,
      'piecesDistributed': _piecesDistributed,
      'totalPieces': totalPieces,
      'offeredPiecesCount': _offeredPieces.length,
      'averageRarity': _pieceRarity.values.isEmpty
          ? 0.0
          : _pieceRarity.values.reduce((a, b) => a + b) / _pieceRarity.length,
    };
  }

  /// Get rarity of a specific piece
  int getPieceRarity(int pieceIndex) {
    return _pieceRarity[pieceIndex] ?? 0;
  }

  /// Check if a piece has been offered
  bool hasBeenOffered(int pieceIndex) {
    return _offeredPieces.contains(pieceIndex);
  }
}
