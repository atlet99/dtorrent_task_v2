import 'tracker/tracker_base.dart';

abstract class TorrentAnnounceEvent {}

class AnnounceErrorEvent implements TorrentAnnounceEvent {
  Tracker source;
  dynamic error;
  AnnounceErrorEvent(
    this.source,
    this.error,
  );
}

class AnnounceOverEvent implements TorrentAnnounceEvent {
  Tracker source;
  int time;
  AnnounceOverEvent(
    this.source,
    this.time,
  );
}

class AnnouncePeerEventEvent implements TorrentAnnounceEvent {
  Tracker source;

  PeerEvent? event;
  AnnouncePeerEventEvent(
    this.source,
    this.event,
  );
}

class AnnounceTrackerDisposedEvent implements TorrentAnnounceEvent {
  Tracker source;

  dynamic reason;
  AnnounceTrackerDisposedEvent(
    this.source,
    this.reason,
  );
}

class AnnounceTrackerStartEvent implements TorrentAnnounceEvent {
  final Tracker source;

  AnnounceTrackerStartEvent(this.source);
}
