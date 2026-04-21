import 'dart:async';

/// Debouncer for events - delays event emission until a period of inactivity
class Debouncer<T> {
  final Duration delay;
  final void Function(T) callback;
  Timer? _timer;
  late T _lastValue;
  bool _hasPendingValue = false;

  Debouncer(this.delay, this.callback);

  void call(T value) {
    _lastValue = value;
    _hasPendingValue = true;
    _timer?.cancel();
    _timer = Timer(delay, _emitPendingValue);
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _hasPendingValue = false;
  }

  /// Immediately emit the last value if any
  void flush() {
    _timer?.cancel();
    _emitPendingValue();
  }

  void _emitPendingValue() {
    if (!_hasPendingValue) return;
    callback(_lastValue);
    _hasPendingValue = false;
  }
}
