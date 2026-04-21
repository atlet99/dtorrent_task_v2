import 'dart:async';

import 'package:logging/logging.dart';

class ScheduleWindow {
  final String id;
  final Set<int> weekdays;
  final Duration start;
  final Duration end;
  final int? maxDownloadRate;
  final int? maxUploadRate;
  final bool pauseOutsideWindow;

  const ScheduleWindow({
    required this.id,
    required this.weekdays,
    required this.start,
    required this.end,
    this.maxDownloadRate,
    this.maxUploadRate,
    this.pauseOutsideWindow = true,
  });

  bool isActive(DateTime now) {
    if (!weekdays.contains(now.weekday)) return false;
    final nowDuration = Duration(hours: now.hour, minutes: now.minute);
    if (end >= start) {
      return nowDuration >= start && nowDuration <= end;
    }
    return nowDuration >= start || nowDuration <= end;
  }
}

abstract class SchedulerDelegate {
  void pauseTask();
  void resumeTask();
  void applySpeedLimits({int? maxDownloadRate, int? maxUploadRate});
  void clearSpeedLimits();
}

class TaskScheduler {
  final SchedulerDelegate _delegate;
  final DateTime Function() _clock;
  final Logger _log;
  final List<ScheduleWindow> _windows = <ScheduleWindow>[];
  Timer? _timer;

  TaskScheduler({
    required SchedulerDelegate delegate,
    DateTime Function()? clock,
    Logger? logger,
  })  : _delegate = delegate,
        _clock = clock ?? DateTime.now,
        _log = logger ?? Logger('TaskScheduler');

  List<ScheduleWindow> get windows => List.unmodifiable(_windows);

  void addWindow(ScheduleWindow window) {
    _windows.removeWhere((w) => w.id == window.id);
    _windows.add(window);
    _log.info('Added schedule window: ${window.id}');
    _evaluateNow();
  }

  bool removeWindow(String id) {
    final before = _windows.length;
    _windows.removeWhere((w) => w.id == id);
    final removed = _windows.length != before;
    if (removed) {
      _log.info('Removed schedule window: $id');
      _evaluateNow();
    }
    return removed;
  }

  void clear() {
    _windows.clear();
    _delegate.clearSpeedLimits();
    _log.info('Cleared all schedule windows');
  }

  void start({Duration tick = const Duration(seconds: 30)}) {
    _timer?.cancel();
    _timer = Timer.periodic(tick, (_) => _evaluateNow());
    _evaluateNow();
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stop();
    clear();
  }

  void _evaluateNow() {
    if (_windows.isEmpty) {
      _delegate.clearSpeedLimits();
      return;
    }

    final now = _clock();
    final active = _windows.where((w) => w.isActive(now)).toList();
    if (active.isEmpty) {
      final shouldPause = _windows.any((w) => w.pauseOutsideWindow);
      if (shouldPause) {
        _delegate.pauseTask();
      }
      _delegate.clearSpeedLimits();
      return;
    }

    // Prefer the most restrictive limits among active windows.
    int? maxDownload;
    int? maxUpload;
    for (final window in active) {
      if (window.maxDownloadRate != null) {
        maxDownload = maxDownload == null
            ? window.maxDownloadRate
            : (window.maxDownloadRate! < maxDownload
                ? window.maxDownloadRate
                : maxDownload);
      }
      if (window.maxUploadRate != null) {
        maxUpload = maxUpload == null
            ? window.maxUploadRate
            : (window.maxUploadRate! < maxUpload
                ? window.maxUploadRate
                : maxUpload);
      }
    }

    _delegate.resumeTask();
    if (maxDownload != null || maxUpload != null) {
      _delegate.applySpeedLimits(
        maxDownloadRate: maxDownload,
        maxUploadRate: maxUpload,
      );
    } else {
      _delegate.clearSpeedLimits();
    }
  }
}
