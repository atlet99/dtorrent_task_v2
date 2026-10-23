/// Session-wide limits applied to a torrent task.
///
/// Defaults mirror libretorrent. A value of `0` means "unlimited" for
/// connection and rate limits; [maxUploadsPerTorrent] must be at least 1.
///
/// `dtorrent_task_v2` runs one task per process/session, so
/// [maxConnections] is treated as an upper bound for this task alongside
/// [maxConnectionsPerTorrent].
class SessionSettings {
  /// Libretorrent `DEFAULT_CONNECTIONS_LIMIT`.
  static const defaultMaxConnections = 200;

  /// Libretorrent `DEFAULT_CONNECTIONS_LIMIT_PER_TORRENT`.
  static const defaultMaxConnectionsPerTorrent = 50;

  /// Default incoming connection cap per task.
  static const defaultMaxIncomingConnectionsPerTorrent = 10;

  /// Libretorrent `DEFAULT_UPLOADS_LIMIT_PER_TORRENT`.
  static const defaultMaxUploadsPerTorrent = 4;

  /// Session connection cap; 0 = unlimited.
  final int maxConnections;

  /// Per-task connection cap; 0 = unlimited.
  final int maxConnectionsPerTorrent;

  /// Incoming connection cap per task; 0 = unlimited.
  final int maxIncomingConnectionsPerTorrent;

  /// Maximum simultaneously unchoked peers, optimistic slot included.
  final int maxUploadsPerTorrent;

  /// Download cap in bytes per second; 0 = unlimited.
  final int downloadRateLimit;

  /// Upload cap in bytes per second; 0 = unlimited.
  final int uploadRateLimit;

  const SessionSettings({
    this.maxConnections = defaultMaxConnections,
    this.maxConnectionsPerTorrent = defaultMaxConnectionsPerTorrent,
    this.maxIncomingConnectionsPerTorrent =
        defaultMaxIncomingConnectionsPerTorrent,
    this.maxUploadsPerTorrent = defaultMaxUploadsPerTorrent,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
  })  : assert(maxConnections >= 0),
        assert(maxConnectionsPerTorrent >= 0),
        assert(maxIncomingConnectionsPerTorrent >= 0),
        assert(maxUploadsPerTorrent >= 1),
        assert(downloadRateLimit >= 0),
        assert(uploadRateLimit >= 0);

  /// Most restrictive connection cap; 0 means unlimited.
  int get effectiveMaxConnectionsPerTorrent {
    if (maxConnections <= 0) return maxConnectionsPerTorrent;
    if (maxConnectionsPerTorrent <= 0) return maxConnections;
    return maxConnections < maxConnectionsPerTorrent
        ? maxConnections
        : maxConnectionsPerTorrent;
  }

  SessionSettings copyWith({
    int? maxConnections,
    int? maxConnectionsPerTorrent,
    int? maxIncomingConnectionsPerTorrent,
    int? maxUploadsPerTorrent,
    int? downloadRateLimit,
    int? uploadRateLimit,
  }) {
    return SessionSettings(
      maxConnections: maxConnections ?? this.maxConnections,
      maxConnectionsPerTorrent:
          maxConnectionsPerTorrent ?? this.maxConnectionsPerTorrent,
      maxIncomingConnectionsPerTorrent: maxIncomingConnectionsPerTorrent ??
          this.maxIncomingConnectionsPerTorrent,
      maxUploadsPerTorrent: maxUploadsPerTorrent ?? this.maxUploadsPerTorrent,
      downloadRateLimit: downloadRateLimit ?? this.downloadRateLimit,
      uploadRateLimit: uploadRateLimit ?? this.uploadRateLimit,
    );
  }
}
