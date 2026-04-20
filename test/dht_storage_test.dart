import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('DHTStorage (BEP 44)', () {
    test('stores and reads immutable values by target', () {
      final storage = DHTStorage();
      final value = 'immutable-payload'.codeUnits;

      final target = storage.putImmutable(value);
      final readBack = storage.get(target);

      expect(readBack, isNotNull);
      expect(readBack!.mutable, isFalse);
      expect(readBack.sequenceNumber, isNull);
      expect(readBack.value, value);
    });

    test('stores mutable value and updates with increasing sequence number',
        () {
      final storage = DHTStorage(
        signatureVerifier: ({
          required publicKey,
          required salt,
          required sequenceNumber,
          required value,
          required signature,
        }) =>
            signature.every((b) => b == 7),
      );
      final publicKey = List<int>.filled(32, 3);
      final signature = List<int>.filled(64, 7);

      final target = storage.putMutable(
        value: 'v1'.codeUnits,
        publicKey: publicKey,
        signature: signature,
        sequenceNumber: 1,
      );
      storage.putMutable(
        value: 'v2'.codeUnits,
        publicKey: publicKey,
        signature: signature,
        sequenceNumber: 2,
      );

      final readBack = storage.get(target);
      expect(readBack, isNotNull);
      expect(readBack!.mutable, isTrue);
      expect(readBack.sequenceNumber, 2);
      expect(readBack.value, 'v2'.codeUnits);
    });

    test('rejects mutable updates with non-increasing sequence number', () {
      final storage = DHTStorage(
        signatureVerifier: ({
          required publicKey,
          required salt,
          required sequenceNumber,
          required value,
          required signature,
        }) =>
            true,
      );
      final publicKey = List<int>.filled(32, 9);
      final signature = List<int>.filled(64, 1);

      storage.putMutable(
        value: 'v1'.codeUnits,
        publicKey: publicKey,
        signature: signature,
        sequenceNumber: 4,
      );

      expect(
        () => storage.putMutable(
          value: 'v0'.codeUnits,
          publicKey: publicKey,
          signature: signature,
          sequenceNumber: 4,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('rejects mutable put with invalid signature', () {
      final storage = DHTStorage(
        signatureVerifier: ({
          required publicKey,
          required salt,
          required sequenceNumber,
          required value,
          required signature,
        }) =>
            false,
      );

      expect(
        () => storage.putMutable(
          value: 'value'.codeUnits,
          publicKey: List<int>.filled(32, 1),
          signature: List<int>.filled(64, 2),
          sequenceNumber: 0,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('supports compare-and-swap validation for mutable updates', () {
      final storage = DHTStorage(
        signatureVerifier: ({
          required publicKey,
          required salt,
          required sequenceNumber,
          required value,
          required signature,
        }) =>
            true,
      );
      final publicKey = List<int>.filled(32, 5);
      final signature = List<int>.filled(64, 6);

      storage.putMutable(
        value: 'v1'.codeUnits,
        publicKey: publicKey,
        signature: signature,
        sequenceNumber: 1,
      );

      expect(
        () => storage.putMutable(
          value: 'v2'.codeUnits,
          publicKey: publicKey,
          signature: signature,
          sequenceNumber: 2,
          compareAndSwapSequence: 3,
        ),
        throwsA(isA<StateError>()),
      );

      storage.putMutable(
        value: 'v2'.codeUnits,
        publicKey: publicKey,
        signature: signature,
        sequenceNumber: 2,
        compareAndSwapSequence: 1,
      );
    });

    test('builds BEP44 query payloads for get and put', () {
      final get = DHTGetQuery(target: List<int>.filled(20, 1), seq: 10);
      final putImmutable = DHTPutImmutableQuery(
        token: 'token'.codeUnits,
        value: 'value'.codeUnits,
      );
      final putMutable = DHTPutMutableQuery(
        token: 'token'.codeUnits,
        value: 'value'.codeUnits,
        publicKey: List<int>.filled(32, 7),
        signature: List<int>.filled(64, 8),
        sequenceNumber: 10,
        salt: 'salt'.codeUnits,
        compareAndSwapSequence: 9,
      );

      expect(get.toMap()['target'], hasLength(20));
      expect(get.toMap()['seq'], 10);
      expect(putImmutable.toMap()['token'], 'token'.codeUnits);
      expect(putImmutable.toMap()['v'], 'value'.codeUnits);
      expect(putMutable.toMap()['k'], hasLength(32));
      expect(putMutable.toMap()['sig'], hasLength(64));
      expect(putMutable.toMap()['seq'], 10);
      expect(putMutable.toMap()['cas'], 9);
      expect(putMutable.toMap()['salt'], 'salt'.codeUnits);
    });
  });
}
