import 'dart:async';

/// Pub/Sub message envelope for BEP 50 inspired workflow.
class DHTPubSubMessage {
  final String network;
  final String topic;
  final List<int> payload;
  final String publisherId;
  final int sequenceNumber;
  final DateTime timestamp;

  const DHTPubSubMessage({
    required this.network,
    required this.topic,
    required this.payload,
    required this.publisherId,
    required this.sequenceNumber,
    required this.timestamp,
  });
}

/// In-memory topic manager for push-based updates over DHT-like topics.
class DHTPubSub {
  final DateTime Function() _clock;
  final Map<String, StreamController<DHTPubSubMessage>> _controllers = {};
  final Map<String, int> _sequenceByTopic = {};
  final Set<String> _knownTopics = {};
  bool _closed = false;

  DHTPubSub({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  Set<String> get topics => Set<String>.from(_knownTopics);

  Stream<DHTPubSubMessage> subscribe({
    required String topic,
    String network = 'default',
  }) {
    _ensureOpen();
    final key = _topicKey(network: network, topic: topic);
    _knownTopics.add(key);
    final controller = _controllers.putIfAbsent(
      key,
      () => StreamController<DHTPubSubMessage>.broadcast(),
    );
    return controller.stream;
  }

  DHTPubSubMessage publish({
    required String topic,
    required List<int> payload,
    String network = 'default',
    String publisherId = 'local-node',
  }) {
    _ensureOpen();
    if (topic.trim().isEmpty) {
      throw ArgumentError.value(topic, 'topic', 'must not be empty');
    }

    final key = _topicKey(network: network, topic: topic);
    final nextSeq = (_sequenceByTopic[key] ?? 0) + 1;
    _sequenceByTopic[key] = nextSeq;
    _knownTopics.add(key);

    final message = DHTPubSubMessage(
      network: network,
      topic: topic,
      payload: List<int>.from(payload),
      publisherId: publisherId,
      sequenceNumber: nextSeq,
      timestamp: _clock(),
    );

    final controller = _controllers[key];
    if (controller != null && !controller.isClosed) {
      controller.add(message);
    }
    return message;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final controller in _controllers.values) {
      await controller.close();
    }
    _controllers.clear();
    _sequenceByTopic.clear();
    _knownTopics.clear();
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('DHTPubSub is closed');
    }
  }

  static String _topicKey({
    required String network,
    required String topic,
  }) =>
      '$network::$topic';
}
