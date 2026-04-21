import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'torrent_announce_events.dart';
import 'tracker/peer_event.dart';
import 'package:events_emitter2/events_emitter2.dart';

import 'tracker/tracker.dart';
import 'tracker/tracker_events.dart';
import 'tracker/tracker_exception.dart';
import 'tracker_generator.dart';

class TrackerRetryState {
  final int? requestedRetryInSeconds;
  final int? effectiveRetryInSeconds;
  final bool neverRetry;
  final bool fromError;
  final bool warningBased;
  final bool clamped;
  final String? warning;
  final DateTime updatedAt;

  const TrackerRetryState({
    required this.requestedRetryInSeconds,
    required this.effectiveRetryInSeconds,
    required this.neverRetry,
    required this.fromError,
    required this.warningBased,
    required this.clamped,
    required this.updatedAt,
    this.warning,
  });
}

class _RetrySchedule {
  final int? requested;
  final int? effective;
  final bool clamped;

  const _RetrySchedule({
    required this.requested,
    required this.effective,
    required this.clamped,
  });
}

/// Torrent announce tracker.
///
/// Create announce trackers from torrent model. This class can start/stop
/// trackers , and send track response event or track exception to client.
///
///
class TorrentAnnounceTracker with EventsEmittable<TorrentAnnounceEvent> {
  static final Logger _log = Logger('TorrentAnnounceTracker');
  final Map<Uri, Tracker> _trackers = {};
  final Map<Tracker, EventsListener<TrackerEvent>> trackerEventListeners = {};
  final Map<Uri, InternetAddress> _externalIpByTracker = {};
  final Map<Uri, TrackerRetryState> _retryStateByTracker = {};
  final Map<Tracker, ({Timer timer, int retryTimes})> _announceRetryTimers = {};

  TrackerGenerator? trackerGenerator;

  AnnounceOptionsProvider provider;

  final int maxRetryTime;

  final int _retryAfter = 5;
  final int minRetryDelaySeconds;
  final int maxRetryDelaySeconds;
  final double retryJitterRatio;
  final Random _random;
  int _retryDirectiveCount = 0;
  int _retryNeverCount = 0;
  int _retrySuppressedCount = 0;
  int _retryClampedCount = 0;

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
      {this.trackerGenerator,
      this.maxRetryTime = 3,
      this.minRetryDelaySeconds = 1,
      this.maxRetryDelaySeconds = 24 * 60 * 60,
      this.retryJitterRatio = 0.1,
      Random? random})
      : _random = random ?? Random() {
    trackerGenerator ??= TrackerGenerator.base();
  }

  int get trackersNum => _trackers.length;
  InternetAddress? get externalIp {
    if (_externalIpByTracker.isEmpty) return null;
    return _externalIpByTracker.values.last;
  }

  Map<Uri, InternetAddress> get externalIpByTracker =>
      Map.unmodifiable(_externalIpByTracker);
  Map<Uri, TrackerRetryState> get retryStateByTracker =>
      Map.unmodifiable(_retryStateByTracker);
  int get retryDirectiveCount => _retryDirectiveCount;
  int get retryNeverCount => _retryNeverCount;
  int get retrySuppressedCount => _retrySuppressedCount;
  int get retryClampedCount => _retryClampedCount;

  Future<List<bool>> restartAll() {
    var list = <Future<bool>>[];
    _trackers.forEach((url, tracker) {
      list.add(tracker.restart());
    });
    return Stream.fromFutures(list).toList();
  }

  void removeTracker(Uri url) {
    var tracker = _trackers.remove(url);
    _externalIpByTracker.remove(url);
    _retryStateByTracker.remove(url);
    tracker?.dispose();
  }

  /// Close stream controller
  void _cleanup() {
    events.dispose();
    _trackers.clear();
    _externalIpByTracker.clear();
    _retryStateByTracker.clear();
    _announceRetryTimers.forEach((key, record) {
      record.timer.cancel();
    });
    _announceRetryTimers.clear();
  }

  _RetrySchedule _normalizeRetryDelay(int requestedSeconds) {
    var effective = requestedSeconds;
    var clamped = false;
    if (effective < minRetryDelaySeconds) {
      effective = minRetryDelaySeconds;
      clamped = true;
    }
    if (effective > maxRetryDelaySeconds) {
      effective = maxRetryDelaySeconds;
      clamped = true;
    }

    if (effective > 0 && retryJitterRatio > 0) {
      final maxJitter = (effective * retryJitterRatio).round();
      if (maxJitter > 0) {
        final shift = _random.nextInt(maxJitter * 2 + 1) - maxJitter;
        effective += shift;
      }
      if (effective < minRetryDelaySeconds) {
        effective = minRetryDelaySeconds;
        clamped = true;
      }
      if (effective > maxRetryDelaySeconds) {
        effective = maxRetryDelaySeconds;
        clamped = true;
      }
    }

    if (clamped) _retryClampedCount++;
    return _RetrySchedule(
      requested: requestedSeconds,
      effective: effective,
      clamped: clamped,
    );
  }

  void _emitRetryPolicyEvent(
    Tracker tracker, {
    required int? requestedRetryInSeconds,
    required int? effectiveRetryInSeconds,
    required bool neverRetry,
    required bool fromError,
    required bool warningBased,
    required bool clamped,
    String? warning,
  }) {
    _retryDirectiveCount++;
    if (neverRetry) _retryNeverCount++;
    final uri = tracker.announceUrl;
    _retryStateByTracker[uri] = TrackerRetryState(
      requestedRetryInSeconds: requestedRetryInSeconds,
      effectiveRetryInSeconds: effectiveRetryInSeconds,
      neverRetry: neverRetry,
      fromError: fromError,
      warningBased: warningBased,
      clamped: clamped,
      warning: warning,
      updatedAt: DateTime.now(),
    );
    events.emit(AnnounceRetryPolicyEvent(
      source: tracker,
      requestedRetryInSeconds: requestedRetryInSeconds,
      effectiveRetryInSeconds: effectiveRetryInSeconds,
      neverRetry: neverRetry,
      fromError: fromError,
      clamped: clamped,
      warningBased: warningBased,
      warning: warning,
    ));
  }

  void _scheduleTrackerRetry(
    Tracker tracker, {
    required int seconds,
    required int retryTimes,
  }) {
    final timer = Timer(Duration(seconds: seconds), () {
      if (tracker.isDisposed || isDisposed) return;
      _unHookTracker(tracker);
      final url = tracker.announceUrl;
      final infoHash = tracker.infoHashBuffer;
      _trackers.remove(url);
      tracker.dispose();
      runTracker(url, infoHash);
    });
    _announceRetryTimers[tracker] = (timer: timer, retryTimes: retryTimes);
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
      record.timer.cancel();
      times = record.retryTimes;
    }
    if (times >= maxRetryTime) {
      event.source.dispose('NO MORE RETRY ($times/$maxRetryTime)');
      return;
    }

    int? retryIn;
    if (event.error is TrackerException) {
      final trackerError = event.error as TrackerException;
      if (trackerError.neverRetry) {
        _log.warning(
          'Tracker ${event.source.announceUrl} requested no retry (retry in = never)',
        );
        _emitRetryPolicyEvent(
          event.source,
          requestedRetryInSeconds: null,
          effectiveRetryInSeconds: null,
          neverRetry: true,
          fromError: true,
          warningBased: false,
          clamped: false,
        );
        _retrySuppressedCount++;
        event.source.dispose('Tracker requested no retry (retry in = never)');
        return;
      }
      retryIn = trackerError.retryIn;
      if (retryIn == 0) {
        _log.warning(
          'Tracker ${event.source.announceUrl} requested no retry (retry in = 0)',
        );
        _emitRetryPolicyEvent(
          event.source,
          requestedRetryInSeconds: 0,
          effectiveRetryInSeconds: 0,
          neverRetry: false,
          fromError: true,
          warningBased: false,
          clamped: false,
        );
        _retrySuppressedCount++;
        event.source.dispose('Tracker requested no retry (retry in = 0)');
        return;
      }
    }

    final requested = retryIn ?? (_retryAfter * pow(2, times) as int);
    final schedule = _normalizeRetryDelay(requested);
    final reTime = schedule.effective!;
    _emitRetryPolicyEvent(
      event.source,
      requestedRetryInSeconds: schedule.requested,
      effectiveRetryInSeconds: schedule.effective,
      neverRetry: false,
      fromError: true,
      warningBased: false,
      clamped: schedule.clamped,
    );
    if (retryIn != null) {
      _log.info(
        'Tracker ${event.source.announceUrl} requested retry in ${retryIn}s, '
        'effective ${reTime}s '
        '(attempt ${times + 1}/$maxRetryTime)',
      );
    } else {
      _log.fine(
        'Tracker ${event.source.announceUrl} uses exponential retry ${reTime}s '
        '(attempt ${times + 1}/$maxRetryTime)',
      );
    }
    times++;
    _scheduleTrackerRetry(event.source, seconds: reTime, retryTimes: times);
    events.emit(AnnounceErrorEvent(event.source, event.error));
  }

  void _fireAnnounceOver(TrackerAnnounceOverEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record.timer.cancel();
    }
    events.emit(AnnounceOverEvent(event.source, event.intervalTime));
  }

  void _firePeerEvent(TrackerPeerEventEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record.timer.cancel();
    }
    final externalIp = event.peerEvent.externalIp;
    if (externalIp != null) {
      _externalIpByTracker[event.source.announceUrl] = externalIp;
    }
    if (event.peerEvent.warning != null &&
        (event.peerEvent.retryIn != null || event.peerEvent.neverRetry)) {
      if (event.peerEvent.neverRetry) {
        _emitRetryPolicyEvent(
          event.source,
          requestedRetryInSeconds: null,
          effectiveRetryInSeconds: null,
          neverRetry: true,
          fromError: false,
          warningBased: true,
          clamped: false,
          warning: event.peerEvent.warning,
        );
        _retrySuppressedCount++;
        event.source.stopIntervalAnnounce();
      } else {
        final schedule = _normalizeRetryDelay(event.peerEvent.retryIn!);
        _emitRetryPolicyEvent(
          event.source,
          requestedRetryInSeconds: schedule.requested,
          effectiveRetryInSeconds: schedule.effective,
          neverRetry: false,
          fromError: false,
          warningBased: true,
          clamped: schedule.clamped,
          warning: event.peerEvent.warning,
        );
        event.source.stopIntervalAnnounce();
        _scheduleTrackerRetry(
          event.source,
          seconds: schedule.effective!,
          retryTimes: 0,
        );
      }
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerComplete(TrackerCompleteEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record.timer.cancel();
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerStop(TrackerStopEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record.timer.cancel();
    }
    events.emit(AnnouncePeerEventEvent(event.source, event.peerEvent));
  }

  void _fireTrackerDisposed(TrackerDisposedEvent event) {
    var record = _announceRetryTimers.remove(event.source);
    if (record != null) {
      record.timer.cancel();
    }
    _externalIpByTracker.remove(event.source.announceUrl);
    _retryStateByTracker.remove(event.source.announceUrl);
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
