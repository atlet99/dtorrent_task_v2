///
/// When tracker get the error from server , it will send this exception to client
class TrackerException implements Exception {
  final dynamic failureReason;
  final String id;
  final int? retryIn;
  final bool neverRetry;

  TrackerException(this.id, this.failureReason,
      {this.retryIn, this.neverRetry = false});

  @override
  String toString() {
    if (failureReason == null) {
      return 'TrackerException($id) - Unknown track error';
    }
    var suffix = '';
    if (neverRetry) {
      suffix = ' (retry in: never)';
    } else if (retryIn != null) {
      suffix = ' (retry in: ${retryIn}s)';
    }
    return 'TrackerException($id) - $failureReason$suffix';
  }
}
