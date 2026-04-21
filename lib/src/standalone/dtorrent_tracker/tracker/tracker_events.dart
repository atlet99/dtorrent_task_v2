import 'tracker_base.dart';

abstract class TrackerEvent {}

class TrackerAnnounceStartEvent implements TrackerEvent {
  final Tracker source;

  TrackerAnnounceStartEvent(this.source);
}

class TrackerPeerEventEvent implements TrackerEvent {
  final Tracker source;
  final PeerEvent peerEvent;

  TrackerPeerEventEvent(this.source, this.peerEvent);
}

class TrackerStopEvent implements TrackerEvent {
  final Tracker source;
  final PeerEvent? peerEvent;

  TrackerStopEvent(this.source, this.peerEvent);
}

class TrackerCompleteEvent implements TrackerEvent {
  final Tracker source;
  final PeerEvent? peerEvent;

  TrackerCompleteEvent(this.source, this.peerEvent);
}

class TrackerAnnounceErrorEvent implements TrackerEvent {
  final Tracker source;
  final Object? error;

  TrackerAnnounceErrorEvent(this.source, this.error);
}

class TrackerAnnounceOverEvent implements TrackerEvent {
  final Tracker source;
  final int intervalTime;

  TrackerAnnounceOverEvent(this.source, this.intervalTime);
}

class TrackerDisposedEvent implements TrackerEvent {
  final Tracker source;
  final Object? reason;

  TrackerDisposedEvent(this.source, this.reason);
}
