/// The tracker base event.
class TrackerEventBase {
  final Map<dynamic, dynamic> _others = {};

  Map<dynamic, dynamic> get otherInfomationsMap {
    return _others;
  }

  void setInfo(dynamic key, dynamic value) {
    _others[key] = value;
  }

  dynamic removeInfo(dynamic key) {
    return _others.remove(key);
  }
}
