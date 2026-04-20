import 'dart:convert';

import 'package:crypto/crypto.dart';

/// BEP 44 get query payload.
class DHTGetQuery {
  final List<int> target;
  final int? seq;

  const DHTGetQuery({
    required this.target,
    this.seq,
  });

  Map<String, Object> toMap() {
    final map = <String, Object>{'target': target};
    if (seq != null) {
      map['seq'] = seq!;
    }
    return map;
  }
}

/// BEP 44 immutable put query payload.
class DHTPutImmutableQuery {
  final List<int> token;
  final List<int> value;

  const DHTPutImmutableQuery({
    required this.token,
    required this.value,
  });

  Map<String, Object> toMap() => {
        'token': token,
        'v': value,
      };
}

/// BEP 44 mutable put query payload.
class DHTPutMutableQuery {
  final List<int> token;
  final List<int> value;
  final List<int> publicKey;
  final List<int> signature;
  final int sequenceNumber;
  final List<int>? salt;
  final int? compareAndSwapSequence;

  const DHTPutMutableQuery({
    required this.token,
    required this.value,
    required this.publicKey,
    required this.signature,
    required this.sequenceNumber,
    this.salt,
    this.compareAndSwapSequence,
  });

  Map<String, Object> toMap() {
    final map = <String, Object>{
      'token': token,
      'v': value,
      'k': publicKey,
      'sig': signature,
      'seq': sequenceNumber,
    };
    if (salt != null && salt!.isNotEmpty) {
      map['salt'] = salt!;
    }
    if (compareAndSwapSequence != null) {
      map['cas'] = compareAndSwapSequence!;
    }
    return map;
  }
}

typedef DHTMutableSignatureVerifier = bool Function({
  required List<int> publicKey,
  required List<int> salt,
  required int sequenceNumber,
  required List<int> value,
  required List<int> signature,
});

/// Read model returned from [DHTStorage.get].
class DHTStoredValue {
  final List<int> target;
  final List<int> value;
  final bool mutable;
  final int? sequenceNumber;
  final List<int>? publicKey;
  final List<int>? signature;
  final List<int>? salt;
  final DateTime storedAt;
  final DateTime expiresAt;

  const DHTStoredValue({
    required this.target,
    required this.value,
    required this.mutable,
    required this.sequenceNumber,
    required this.publicKey,
    required this.signature,
    required this.salt,
    required this.storedAt,
    required this.expiresAt,
  });
}

class _StoredEntry {
  final DHTStoredValue value;

  const _StoredEntry(this.value);
}

/// In-memory BEP 44 storage for immutable and mutable DHT values.
class DHTStorage {
  final Duration defaultTtl;
  final DateTime Function() _clock;
  final DHTMutableSignatureVerifier? _signatureVerifier;
  final Map<String, _StoredEntry> _entries = {};

  DHTStorage({
    this.defaultTtl = const Duration(hours: 1),
    DateTime Function()? clock,
    DHTMutableSignatureVerifier? signatureVerifier,
  })  : _clock = clock ?? DateTime.now,
        _signatureVerifier = signatureVerifier;

  int get size {
    _purgeExpired();
    return _entries.length;
  }

  List<int> putImmutable(
    List<int> value, {
    Duration? ttl,
  }) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }

    final target = _immutableTarget(value);
    final now = _clock();
    final expiresAt = now.add(ttl ?? defaultTtl);
    final key = _targetKey(target);
    final existing = _entries[key]?.value;
    if (existing != null && existing.mutable) {
      throw StateError('target already used by mutable entry');
    }

    _entries[key] = _StoredEntry(
      DHTStoredValue(
        target: target,
        value: List<int>.from(value),
        mutable: false,
        sequenceNumber: null,
        publicKey: null,
        signature: null,
        salt: null,
        storedAt: now,
        expiresAt: expiresAt,
      ),
    );
    return target;
  }

  List<int> putMutable({
    required List<int> value,
    required List<int> publicKey,
    required List<int> signature,
    required int sequenceNumber,
    List<int>? salt,
    int? compareAndSwapSequence,
    Duration? ttl,
  }) {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'must not be empty');
    }
    if (publicKey.length != 32) {
      throw ArgumentError.value(publicKey, 'publicKey', 'must be 32 bytes');
    }
    if (signature.length != 64) {
      throw ArgumentError.value(signature, 'signature', 'must be 64 bytes');
    }
    if (sequenceNumber < 0) {
      throw ArgumentError.value(
          sequenceNumber, 'sequenceNumber', 'must be >= 0');
    }
    final normalizedSalt = List<int>.from(salt ?? const <int>[]);
    if (normalizedSalt.length > 64) {
      throw ArgumentError.value(normalizedSalt, 'salt', 'must be <= 64 bytes');
    }
    if (_signatureVerifier != null) {
      final isValid = _signatureVerifier!(
        publicKey: publicKey,
        salt: normalizedSalt,
        sequenceNumber: sequenceNumber,
        value: value,
        signature: signature,
      );
      if (!isValid) {
        throw StateError('invalid mutable signature');
      }
    }

    final target = _mutableTarget(publicKey, normalizedSalt);
    final key = _targetKey(target);
    final now = _clock();
    final expiresAt = now.add(ttl ?? defaultTtl);
    final existing = _entries[key]?.value;

    if (existing != null) {
      if (!existing.mutable) {
        throw StateError('target already used by immutable entry');
      }
      final existingSeq = existing.sequenceNumber ?? -1;
      if (compareAndSwapSequence != null &&
          existingSeq != compareAndSwapSequence) {
        throw StateError(
          'CAS mismatch: expected seq=$compareAndSwapSequence actual=$existingSeq',
        );
      }
      if (sequenceNumber <= existingSeq) {
        throw StateError(
          'invalid mutable sequence update: $sequenceNumber <= $existingSeq',
        );
      }
    } else if (compareAndSwapSequence != null) {
      throw StateError('CAS mismatch: mutable entry does not exist');
    }

    _entries[key] = _StoredEntry(
      DHTStoredValue(
        target: target,
        value: List<int>.from(value),
        mutable: true,
        sequenceNumber: sequenceNumber,
        publicKey: List<int>.from(publicKey),
        signature: List<int>.from(signature),
        salt: normalizedSalt.isEmpty ? null : normalizedSalt,
        storedAt: now,
        expiresAt: expiresAt,
      ),
    );
    return target;
  }

  DHTStoredValue? get(List<int> target) {
    if (target.isEmpty) return null;
    _purgeExpired();
    final entry = _entries[_targetKey(target)]?.value;
    if (entry == null) {
      return null;
    }
    return DHTStoredValue(
      target: List<int>.from(entry.target),
      value: List<int>.from(entry.value),
      mutable: entry.mutable,
      sequenceNumber: entry.sequenceNumber,
      publicKey:
          entry.publicKey == null ? null : List<int>.from(entry.publicKey!),
      signature:
          entry.signature == null ? null : List<int>.from(entry.signature!),
      salt: entry.salt == null ? null : List<int>.from(entry.salt!),
      storedAt: entry.storedAt,
      expiresAt: entry.expiresAt,
    );
  }

  void remove(List<int> target) {
    _entries.remove(_targetKey(target));
  }

  void clear() {
    _entries.clear();
  }

  List<int> immutableTargetForValue(List<int> value) => _immutableTarget(value);

  List<int> mutableTargetForKey(List<int> publicKey, {List<int>? salt}) =>
      _mutableTarget(publicKey, List<int>.from(salt ?? const <int>[]));

  void _purgeExpired() {
    final now = _clock();
    _entries.removeWhere((_, entry) => now.isAfter(entry.value.expiresAt));
  }

  static List<int> _immutableTarget(List<int> value) =>
      sha1.convert(value).bytes;

  static List<int> _mutableTarget(List<int> publicKey, List<int> salt) {
    final payload = List<int>.from(publicKey)..addAll(salt);
    return sha1.convert(payload).bytes;
  }

  static String _targetKey(List<int> target) => base64.encode(target);
}
