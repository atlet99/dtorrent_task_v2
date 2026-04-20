/// Indexed torrent metadata entry for BEP 51 style lookup.
class DHTIndexedTorrent {
  final String infoHash;
  final String name;
  final Set<String> keywords;
  final Map<String, Object?> metadata;
  final DateTime indexedAt;

  const DHTIndexedTorrent({
    required this.infoHash,
    required this.name,
    required this.keywords,
    required this.metadata,
    required this.indexedAt,
  });
}

/// In-memory infohash index with keyword lookup and metadata integration.
class DHTInfohashIndexer {
  final DateTime Function() _clock;
  final Map<String, DHTIndexedTorrent> _byInfoHash = {};
  final Map<String, Set<String>> _keywordToInfoHashes = {};

  DHTInfohashIndexer({DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  int get length => _byInfoHash.length;

  void index({
    required String infoHash,
    required String name,
    Iterable<String> keywords = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (infoHash.trim().isEmpty) {
      throw ArgumentError.value(infoHash, 'infoHash', 'must not be empty');
    }
    if (name.trim().isEmpty) {
      throw ArgumentError.value(name, 'name', 'must not be empty');
    }

    final normalizedKeywords = _normalizeKeywords(
      [...keywords, ...name.split(RegExp(r'\s+'))],
    );

    final existing = _byInfoHash[infoHash];
    if (existing != null) {
      _removeKeywordLinks(infoHash, existing.keywords);
    }

    final entry = DHTIndexedTorrent(
      infoHash: infoHash,
      name: name,
      keywords: normalizedKeywords,
      metadata: Map<String, Object?>.from(metadata),
      indexedAt: _clock(),
    );
    _byInfoHash[infoHash] = entry;
    for (final keyword in normalizedKeywords) {
      _keywordToInfoHashes.putIfAbsent(keyword, () => {}).add(infoHash);
    }
  }

  void indexFromMetadata({
    required String infoHash,
    required Map<String, Object?> metadata,
  }) {
    final name = (metadata['name'] as String?)?.trim();
    if (name == null || name.isEmpty) {
      throw ArgumentError.value(
          metadata, 'metadata', 'must include non-empty "name"');
    }

    final rawKeywords = metadata['keywords'];
    final keywords = <String>[];
    if (rawKeywords is Iterable) {
      for (final keyword in rawKeywords) {
        if (keyword is String) {
          keywords.add(keyword);
        }
      }
    }

    index(
      infoHash: infoHash,
      name: name,
      keywords: keywords,
      metadata: metadata,
    );
  }

  DHTIndexedTorrent? byInfoHash(String infoHash) => _byInfoHash[infoHash];

  List<DHTIndexedTorrent> search(String keyword) {
    final normalized = _normalizeKeyword(keyword);
    if (normalized.isEmpty) return const [];
    final ids = _keywordToInfoHashes[normalized];
    if (ids == null || ids.isEmpty) return const [];
    return ids
        .map((id) => _byInfoHash[id])
        .whereType<DHTIndexedTorrent>()
        .toList();
  }

  List<DHTIndexedTorrent> searchAll(Iterable<String> keywords) {
    final normalized = _normalizeKeywords(keywords);
    if (normalized.isEmpty) return const [];
    Set<String>? intersection;
    for (final keyword in normalized) {
      final ids = _keywordToInfoHashes[keyword] ?? const <String>{};
      if (intersection == null) {
        intersection = Set<String>.from(ids);
      } else {
        intersection = intersection.intersection(ids);
      }
      if (intersection.isEmpty) {
        return const [];
      }
    }
    return intersection!
        .map((id) => _byInfoHash[id])
        .whereType<DHTIndexedTorrent>()
        .toList();
  }

  bool remove(String infoHash) {
    final existing = _byInfoHash.remove(infoHash);
    if (existing == null) return false;
    _removeKeywordLinks(infoHash, existing.keywords);
    return true;
  }

  Set<String> _normalizeKeywords(Iterable<String> keywords) {
    final result = <String>{};
    for (final keyword in keywords) {
      final normalized = _normalizeKeyword(keyword);
      if (normalized.isNotEmpty) {
        result.add(normalized);
      }
    }
    return result;
  }

  static String _normalizeKeyword(String keyword) =>
      keyword.trim().toLowerCase();

  void _removeKeywordLinks(String infoHash, Set<String> keywords) {
    for (final keyword in keywords) {
      final ids = _keywordToInfoHashes[keyword];
      if (ids == null) continue;
      ids.remove(infoHash);
      if (ids.isEmpty) {
        _keywordToInfoHashes.remove(keyword);
      }
    }
  }
}
