/// Session-wide limits applied to a torrent task.
///
/// Defaults mirror libretorrent. A value of `0` means "unlimited" for
/// connection and rate limits; [maxUploadsPerTorrent] must be at least 1.
///
/// Without a [connectionBudget], [maxConnections] is an upper bound for this
/// task alongside [maxConnectionsPerTorrent]. Pass a shared
/// [SessionConnectionBudget] to enforce it across several tasks in a session.
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

  /// Optional shared budget for cross-task [maxConnections] enforcement.
  final SessionConnectionBudget? connectionBudget;

  const SessionSettings({
    this.maxConnections = defaultMaxConnections,
    this.maxConnectionsPerTorrent = defaultMaxConnectionsPerTorrent,
    this.maxIncomingConnectionsPerTorrent =
        defaultMaxIncomingConnectionsPerTorrent,
    this.maxUploadsPerTorrent = defaultMaxUploadsPerTorrent,
    this.downloadRateLimit = 0,
    this.uploadRateLimit = 0,
    this.connectionBudget,
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
    SessionConnectionBudget? connectionBudget,
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
      connectionBudget: connectionBudget ?? this.connectionBudget,
    );
  }
}

/// Opt-in shared connection budget for several tasks in one session.
///
/// Pass the same instance as [SessionSettings.connectionBudget] to each task
/// (with the same [SessionSettings.maxConnections]) to cap known peer
/// addresses across them. Without it, limits stay per task.
///
/// The budget is checked when peers are added. Lowering a cap makes each
/// task that re-applies the settings disconnect its own excess peers; tasks
/// already above the shared cap stop admitting new peers until they drain.
class SessionConnectionBudget {
  final Map<Object, int> _counts = {};

  /// Total known peer addresses across all registered tasks.
  int get total => _counts.values.fold(0, (sum, count) => sum + count);

  /// Report the current known-peer count of [owner].
  void updateCount(Object owner, int count) {
    _counts[owner] = count;
  }

  /// Stop counting peers for [owner].
  void removeOwner(Object owner) {
    _counts.remove(owner);
  }
}
