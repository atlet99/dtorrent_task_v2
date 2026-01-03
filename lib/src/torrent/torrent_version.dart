import 'dart:typed_data';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:crypto/crypto.dart';

/// BitTorrent protocol version
enum TorrentVersion {
  /// BitTorrent v1 (BEP 0003) - uses SHA-1, 20-byte info hash
  v1,

  /// BitTorrent v2 (BEP 52) - uses SHA-256, 32-byte info hash
  v2,

  /// Hybrid torrent - supports both v1 and v2
  hybrid,
}

/// Helper class for working with torrent versions
class TorrentVersionHelper {
  /// Determine torrent version from Torrent object
  static TorrentVersion detectVersion(Torrent torrent) {
    // Check if torrent has meta version field
    // This is a simplified check - in real implementation,
    // we'd need to check the actual bencoded info dict
    // For now, we'll check if it has both pieces and piece layers (hybrid)
    // or just piece layers (v2)

    // Note: dtorrent_parser might not expose meta version directly
    // We'll need to check the raw bencoded data or extend the parser

    // Default to v1 for now, will be enhanced when we can access meta version
    return TorrentVersion.v1;
  }

  /// Get info hash for a specific version
  static Uint8List? getInfoHashForVersion(
      Torrent torrent, TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return torrent.infoHashBuffer;
      case TorrentVersion.v2:
        // For v2, we need to calculate SHA-256 of the info dict
        // This would require access to the raw bencoded info dict
        // For now, return null - will be implemented when we have access
        return null;
      case TorrentVersion.hybrid:
        // Hybrid torrents can use either v1 or v2 info hash
        // Return v1 by default for compatibility
        return torrent.infoHashBuffer;
    }
  }

  /// Check if info hash is v2 (32 bytes)
  static bool isV2InfoHash(Uint8List infoHash) {
    return infoHash.length == 32;
  }

  /// Check if info hash is v1 (20 bytes)
  static bool isV1InfoHash(Uint8List infoHash) {
    return infoHash.length == 20;
  }

  /// Get piece hash length for a version
  static int getPieceHashLength(TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return 20; // SHA-1
      case TorrentVersion.v2:
        return 32; // SHA-256
      case TorrentVersion.hybrid:
        // Hybrid can use either, default to v1 for compatibility
        return 20;
    }
  }

  /// Get hash algorithm for a version
  static Hash getHashAlgorithm(TorrentVersion version) {
    switch (version) {
      case TorrentVersion.v1:
        return sha1;
      case TorrentVersion.v2:
        return sha256;
      case TorrentVersion.hybrid:
        // Hybrid can use either, default to v1 for compatibility
        return sha1;
    }
  }
}
