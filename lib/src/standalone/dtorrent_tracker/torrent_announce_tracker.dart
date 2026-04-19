import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'torrent_announce_events.dart';
import 'tracker/peer_event.dart';
import 'package:events_emitter2/events_emitter2.dart';

import 'tracker/tracker.dart';
import 'tracker/tracker_events.dart';
import 'tracker_generator.dart';

/// Torrent announce tracker.
///
/// Create announce trackers from torrent model. This class can start/stop
/// trackers , and send track response event or track exception to client.
///
///
class TorrentAnnounceTracker with EventsEmittable<TorrentAnnounceEvent> {
  final Map<Uri, Tracker> _trackers = {};
  final Map<Tracker, EventsListener<TrackerEvent>> trackerEventListeners = {};

  TrackerGenerator? trackerGenerator;

  AnnounceOptionsProvider provider;

  final Map<Tracker, List<dynamic>> _announceRetryTimers = {};

  final int maxRetryTime;

  final int _retryAfter = 5;

  // final Set<String> _announceOverTrackers = {};

  ///
  /// [provider] is announce options value provider , it should return a `Future<Map>` and the `Map`
  /// should contains `downloaded`,`uploaded`,`numwant`,`compact`,`left` ,`peerId`,`port` property values, these datas
  /// will be used when tracker to access remote , this class will get `AnnounceOptionProvider`'s `options`
  /// when it ready to acceess remove. I suggest that client implement `AnnounceOptionProvider` to get the options
  /// data lazyly :
  /// ```dart
  /// class MyAnnounceOptionsProvider implements AnnounceOptionProvider{
  ///     ....
  ///     Torrent torrent;
  ///     /// the file has been downloaded....
  ///     File downloadedFile;
  ///
  ///     Future getOptions(Uri uri,String infoHash) async{
  ///         // It can determine the required parameters to return based on the
  ///         // URI and infoHash. In other words, this provider can be used
  ///         // together with multiple TorrentTrackers.
  ///         var someport;
  ///         if(infoHash..... ){
  ///             someport = ... // port depends infohash or uri...
  ///         }
  ///         /// maybe need to await some IO operations...
  ///         return {
  ///           'port' : someport,
  ///           'downloaded' : downloadedFile.length,
  ///           'left' : torrent.length - file.length,
  ///           ....
  ///         };
  ///     }
  /// }
  /// ```
  ///
  /// [trackerGenerator] is a class which implements `TrackerGenerator`.
  /// Actually client dosn't need to care about it if client dont want to extends some other schema tracker,
  /// `BaseTrackerGenerator` has implemented for creating `https` `http` `udp` schema tracker, this parameter's default value
  /// is a `BaseTrackerGenerator` instance.
  ///
  /// However, if client has implemented other schema trackers , such as `ws`(web socket), it can create a new tracker generator
  /// base on `BaseTrackerGenerator`:
  ///
  /// ```dart
  /// class MyTrackerGenerator extends BaseTrackerGenerator{
  ///   .....
  ///   @override
  ///   Tracker createTracker(
  ///    Uri announce, Uint8List infoHashBuffer, AnnounceOptionsProvider provider) {
  ///     if (announce.isScheme('ws')) {
  ///        return MyWebSocketTracker(announce, infoHashBuffer, provider: provider);
  ///     }
  ///     return super.createTracker(announce,infoHashBuffer,provider);
  ///   }
  /// }
  /// ```
  TorrentAnnounceTracker(this.provider,
      {this.trackerGenerator, this.maxRetryTime = 3}) {
    trackerGenerator ??= TrackerGenerator.base();
  }

  int get trackersNum => _trackers.length;

  Future<List<bool>> restartAll() {
    var list = <Future<bool>>[];
    _trackers.forEach((url, tracker) {
      list.add(tracker.restart());
    });
    return Stream.fromFutures(list).toList();
  }

  void removeTracker(Uri url) {
    var tracker = _trackers.remove(url);
    tracker?.dispose();
  }

  /// Close stream controller
  void _cleanup() {
    events.dispose();
    _trackers.clear();
    _announceRetryTimers.forEach((key, record) {
      record[0].cancel();
    });
    _announceRetryTimers.clear();
  }

  Tracker? _createTracker(Uri announce, Uint8List infohash) {
    if (trackerGenerator == null) return null;
    if (infohash.length != 20) return null;
    if (announce.port > 65535 || announce.port < 0) return null;
    var tracker = trackerGenerator!.createTracker(announce, infohash, provider);
    return tracker;
  }

  ///
  /// Create and run a tracker via [announce] url
  ///
  /// This class will generate a tracker via [announce] , duplicate [announce]
  /// will be ignore.
  void runTracker(Uri url, Uint8List infoHash,
      {String event = EVENT_STARTED, bool force = false}) {
    if (isDisposed) return;
    var tracker = _trackers[url];
    if (tracker == null) {
      tracker = _createTracker(url, infoHash);
      if (tracker == null) return;
      _hookTracker(tracker);
      _trackers[url] = tracker;
    }
    if (tracker.isDisposed) return;
    if (event == EVENT_STARTED) {
      tracker.start();
    }
    if (event == EVENT_STOPPED) {
      tracker.stop(force);
    }
    if (event == EVENT_COMPLETED) {
      tracker.complete();
    }
  }

  /// Create and run a tracker via the its url.
  ///
  /// [infoHash] is the bytes of the torrent infohash.
  void runTrackers(Iterable<Uri> announces, Uint8List infoHash,
      {String event = EVENT_STARTED,
      bool forceStop = false,
      int maxRetryTimes = 3}) {
    if (isDisposed) return;

    for (var announce in announces) {
      runTracker(announce, infoHash, event: event, force: forceStop);
    }
  }

  /// Restart all trackers(which is record with this class instance , some of the trackers
  /// was removed because it can not access)
  bool restartTracker(Uri url) {
    var tracker = _trackers[url];
    tracker?.restart();
    return tracker != null;
  }

  void _fireAnnounceError(TrackerAnnounceErrorEvent event) {
    if (isDisposed) return;
    var record = _announceRetryTimers.remove(event.source);
    if (event.source.isDisposed) return;
    var times = 0;
    if (record != null) {
      (record[0] as Timer).cancel();
      times = record[1];
    }
    if (times >= maxRetryTime) {
      event.source.dispose('NO MORE RETRY ($times/$maxRetryTime)');
      return;
    }
    var reTime = (_retryAfter * pow(2, times) as int);
    var timer = Timer(Duration(seconds: reTime), () {
      if (event.source.isDisposed || isDisposed) return;
      _unHookTracker(event.source);
      var url = event.source.announceUrl;
      var infoHash = event.source.infoHashBuffer;
      _trackers.remove(url);
      event.source.dispose();
      runTracker(url, infoHash);
    });
    times++;
    _announceRetryTimers[event.source] = [timer, times];
    events.emit(AnnounceErrorEvent(event.source, event.error));
  }

  void _fireAnnounceOver(TrackerAnnounceOverEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record[0].cancel();
    }
    events.emit(AnnounceOverEvent(event.source, event.intervalTime));
  }

  void _firePeerEvent(TrackerPeerEventEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record[0].cancel();
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerComplete(TrackerCompleteEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record[0].cancel();
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerStop(TrackerStopEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record[0].cancel();
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerDisposed(TrackerDisposedEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record[0].cancel();
    }
    _trackers.remove(event.source.announceUrl);
    events.emit(AnnounceTrackerDisposedEvent(event.source, event.reason));
  }

  void _fireAnnounceStart(TrackerAnnounceStartEvent event) {
    events.emit(AnnounceTrackerStartEvent(event.source));
  }

  void _hookTracker(Tracker tracker) {
    var trackerListener = tracker.createListener();
    trackerEventListeners[tracker] = trackerListener;
    trackerListener
      ..on<TrackerAnnounceStartEvent>(_fireAnnounceStart)
      ..on<TrackerAnnounceErrorEvent>(_fireAnnounceError)
      ..on<TrackerAnnounceOverEvent>(_fireAnnounceOver)
      ..on<TrackerPeerEventEvent>(_firePeerEvent)
      ..on<TrackerDisposedEvent>(_fireTrackerDisposed)
      ..on<TrackerCompleteEvent>(_fireTrackerComplete)
      ..on<TrackerStopEvent>(_fireTrackerStop);
  }

  void _unHookTracker(Tracker tracker) {
    var trackerListener = trackerEventListeners.remove(tracker);
    if (trackerListener != null) {
      trackerListener.dispose();
    }
  }

  Future<List<PeerEvent?>>? stop([bool force = false]) {
    if (isDisposed) return null;
    var l = <Future<PeerEvent?>>[];
    _trackers.forEach((url, element) {
      l.add(element.stop(force));
    });
    return Stream.fromFutures(l).toList();
  }

  Future<List<PeerEvent?>>? complete() {
    if (isDisposed) return null;
    var l = <Future<PeerEvent?>>[];
    _trackers.forEach((url, element) {
      l.add(element.complete());
    });
    return Stream.fromFutures(l).toList();
  }

  bool _disposed = false;

  bool get isDisposed => _disposed;

  Future dispose() async {
    if (isDisposed) return;
    _disposed = true;
    var f = <Future>[];
    _trackers.forEach((url, element) {
      _unHookTracker(element);
      f.add(element.dispose());
    });
    _cleanup();
    return Stream.fromFutures(f).toList();
  }
}
