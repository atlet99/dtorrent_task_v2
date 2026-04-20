import 'package:dtorrent_task_v2/src/standalone/dtorrent_common.dart';

enum DHTAddressConnectivity {
  unknown,
  reachable,
  unreachable,
}

class DHTNodeAddressState {
  final CompactAddress address;
  final DHTAddressConnectivity connectivity;
  final int score;
  final int successfulChecks;
  final int failedChecks;
  final DateTime firstSeenAt;
  final DateTime lastUpdatedAt;

  const DHTNodeAddressState({
    required this.address,
    required this.connectivity,
    required this.score,
    required this.successfulChecks,
    required this.failedChecks,
    required this.firstSeenAt,
    required this.lastUpdatedAt,
  });
}

class _MutableAddressState {
  final CompactAddress address;
  DHTAddressConnectivity connectivity = DHTAddressConnectivity.unknown;
  int score = 0;
  int successfulChecks = 0;
  int failedChecks = 0;
  final DateTime firstSeenAt;
  DateTime lastUpdatedAt;

  _MutableAddressState(this.address, DateTime now)
      : firstSeenAt = now,
        lastUpdatedAt = now;

  DHTNodeAddressState snapshot() => DHTNodeAddressState(
        address: address,
        connectivity: connectivity,
        score: score,
        successfulChecks: successfulChecks,
        failedChecks: failedChecks,
        firstSeenAt: firstSeenAt,
        lastUpdatedAt: lastUpdatedAt,
      );
}

/// BEP 45 helper: keeps a shared node table with multiple addresses per node.
class DHTMultipleAddressTable {
  final DateTime Function() _clock;
  final Map<String, Map<String, _MutableAddressState>> _nodeAddresses = {};

  DHTMultipleAddressTable({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  int get nodeCount => _nodeAddresses.length;

  int get addressCount =>
      _nodeAddresses.values.fold(0, (sum, addresses) => sum + addresses.length);

  void addAddress({
    required String nodeId,
    required CompactAddress address,
  }) {
    final addresses = _nodeAddresses.putIfAbsent(nodeId, () => {});
    final key = _addressKey(address);
    addresses.putIfAbsent(key, () => _MutableAddressState(address, _clock()));
  }

  void markReachable({
    required String nodeId,
    required CompactAddress address,
  }) {
    final entry = _requireEntry(nodeId, address);
    entry.successfulChecks++;
    entry.score += 2;
    entry.connectivity = DHTAddressConnectivity.reachable;
    entry.lastUpdatedAt = _clock();
  }

  void markUnreachable({
    required String nodeId,
    required CompactAddress address,
  }) {
    final entry = _requireEntry(nodeId, address);
    entry.failedChecks++;
    entry.score -= 2;
    entry.connectivity = DHTAddressConnectivity.unreachable;
    entry.lastUpdatedAt = _clock();
  }

  List<DHTNodeAddressState> getAddresses(String nodeId) {
    final entries = _nodeAddresses[nodeId];
    if (entries == null) return const [];
    return entries.values.map((entry) => entry.snapshot()).toList();
  }

  /// Returns addresses ordered by connectivity + score (best first).
  List<CompactAddress> getPrioritizedAddresses(String nodeId) {
    final entries = _nodeAddresses[nodeId];
    if (entries == null) return const [];
    final states = entries.values.map((entry) => entry.snapshot()).toList()
      ..sort((a, b) {
        final byConnectivity = _connectivityWeight(b.connectivity) -
            _connectivityWeight(a.connectivity);
        if (byConnectivity != 0) return byConnectivity;
        final byScore = b.score - a.score;
        if (byScore != 0) return byScore;
        return a.address.address.address.compareTo(b.address.address.address);
      });
    return states.map((state) => state.address).toList();
  }

  _MutableAddressState _requireEntry(String nodeId, CompactAddress address) {
    addAddress(nodeId: nodeId, address: address);
    final addresses = _nodeAddresses[nodeId]!;
    return addresses[_addressKey(address)]!;
  }

  static int _connectivityWeight(DHTAddressConnectivity connectivity) {
    switch (connectivity) {
      case DHTAddressConnectivity.reachable:
        return 2;
      case DHTAddressConnectivity.unknown:
        return 1;
      case DHTAddressConnectivity.unreachable:
        return 0;
    }
  }

  static String _addressKey(CompactAddress address) =>
      '${address.address.address}:${address.port}';
}
