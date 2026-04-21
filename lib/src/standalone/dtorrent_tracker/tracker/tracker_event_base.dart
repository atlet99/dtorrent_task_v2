/// The tracker base event.
class TrackerEventBase {
  final Map<Object, Object?> _others = {};

  Map<Object, Object?> get otherInfomationsMap {
    return _others;
  }

  void setInfo(Object key, Object? value) {
    _others[key] = value;
  }

  Object? removeInfo(Object key) {
    return _others.remove(key);
  }
}
