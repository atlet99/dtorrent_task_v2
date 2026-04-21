import 'tracker/tracker_base.dart';

abstract class TorrentAnnounceEvent {}

class AnnounceErrorEvent implements TorrentAnnounceEvent {
  final Tracker source;
  final Object? error;
  AnnounceErrorEvent(
    this.source,
    this.error,
  );
}

class AnnounceOverEvent implements TorrentAnnounceEvent {
  final Tracker source;
  final int time;
  AnnounceOverEvent(
    this.source,
    this.time,
  );
}

class AnnouncePeerEventEvent implements TorrentAnnounceEvent {
  final Tracker source;

  final PeerEvent? event;
  AnnouncePeerEventEvent(
    this.source,
    this.event,
  );
}

class AnnounceTrackerDisposedEvent implements TorrentAnnounceEvent {
  final Tracker source;

  final Object? reason;
  AnnounceTrackerDisposedEvent(
    this.source,
    this.reason,
  );
}

class AnnounceTrackerStartEvent implements TorrentAnnounceEvent {
  final Tracker source;

  AnnounceTrackerStartEvent(this.source);
}

class AnnounceRetryPolicyEvent implements TorrentAnnounceEvent {
  final Tracker source;
  final int? requestedRetryInSeconds;
  final int? effectiveRetryInSeconds;
  final bool neverRetry;
  final bool fromError;
  final bool clamped;
  final bool warningBased;
  final String? warning;

  AnnounceRetryPolicyEvent({
    required this.source,
    required this.requestedRetryInSeconds,
    required this.effectiveRetryInSeconds,
    required this.neverRetry,
    required this.fromError,
    required this.clamped,
    required this.warningBased,
    this.warning,
  });
}
