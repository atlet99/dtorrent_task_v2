import 'dart:math';

/// Token-bucket rate limiter in bytes per second.
///
/// [reserve] immediately takes the requested budget, possibly going into
/// debt, and returns how long the caller must wait before sending. Callers
/// must honor the returned delay; retrying [reserve] would double-charge.
class RateLimiter {
  RateLimiter(this.bytesPerSecond, {DateTime Function()? clock})
      : assert(bytesPerSecond > 0),
        _tokens = bytesPerSecond.toDouble(),
        _clock = clock ?? DateTime.now,
        _lastRefill = (clock ?? DateTime.now)();

  /// Allowed throughput in bytes per second; always > 0.
  final int bytesPerSecond;

  final DateTime Function() _clock;

  /// One second of burst capacity; may go negative after reservations.
  double _tokens;

  DateTime _lastRefill;

  /// Reserve [bytes] and return the delay before they may be sent.
  Duration reserve(int bytes) {
    if (bytes <= 0) return Duration.zero;
    _refill();
    _tokens -= bytes;
    if (_tokens >= 0) return Duration.zero;
    return Duration(
      microseconds:
          (-_tokens / bytesPerSecond * Duration.microsecondsPerSecond).ceil(),
    );
  }

  void _refill() {
    final now = _clock();
    final elapsed = now.difference(_lastRefill).inMicroseconds;
    if (elapsed <= 0) return;
    _lastRefill = now;
    _tokens = min(
      bytesPerSecond.toDouble(),
      _tokens + elapsed * bytesPerSecond / Duration.microsecondsPerSecond,
    );
  }
}
