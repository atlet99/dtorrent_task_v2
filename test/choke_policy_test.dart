import 'dart:math';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';
import 'test_helpers.dart';

ChokeCandidate _peer(
  String id, {
  bool interested = true,
  bool disposed = false,
  bool unchoked = false,
  double download = 0,
  double upload = 0,
}) {
  return ChokeCandidate(
    id: id,
    interested: interested,
    disposed: disposed,
    unchoked: unchoked,
    downloadScore: download,
    uploadScore: upload,
  );
}

List<String> _ids(List<ChokeCandidate> winners) {
  return winners.map((w) => w.id as String).toList();
}

void main() {
  group('selectUnchokedCandidates (tit-for-tat)', () {
    test('picks fastest peers by download speed while leeching', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('a', download: 10),
          _peer('b', download: 50),
          _peer('c', download: 30),
          _peer('d', download: 20),
          _peer('e', download: 5),
        ],
        slots: 4,
        seeding: false,
      );

      // One slot is reserved for the optimistic peer.
      expect(_ids(winners), equals(['b', 'c', 'd']));
    });

    test('includes the optimistic peer beyond regular slots', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('a', download: 50),
          _peer('b', download: 40),
          _peer('c', download: 30),
          _peer('d', download: 10),
        ],
        slots: 4,
        seeding: false,
        optimisticId: 'd',
      );

      expect(_ids(winners), equals(['a', 'b', 'c', 'd']));
    });

    test('ignores stale optimistic ids and caps at slots', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('a', download: 50),
          _peer('b', download: 40),
        ],
        slots: 4,
        seeding: false,
        optimisticId: 'gone',
      );

      expect(_ids(winners), equals(['a', 'b']));
    });

    test('excludes uninterested and disposed peers', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('fast-but-bored', download: 1000, interested: false),
          _peer('fast-but-dead', download: 1000, disposed: true),
          _peer('slow', download: 1),
        ],
        slots: 4,
        seeding: false,
      );

      expect(_ids(winners), equals(['slow']));
    });

    test('ranks by upload speed while seeding', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('a', download: 100, upload: 10),
          _peer('b', download: 10, upload: 100),
          _peer('c', download: 50, upload: 50),
        ],
        slots: 3,
        seeding: true,
      );

      expect(_ids(winners), equals(['b', 'c']));
    });

    test('breaks speed ties by reciprocal direction, then incumbency', () {
      final winners = selectUnchokedCandidates(
        candidates: [
          _peer('new', download: 10, upload: 20),
          _peer('incumbent', download: 10, upload: 20, unchoked: true),
          _peer('better-upload', download: 10, upload: 30),
        ],
        slots: 4,
        seeding: false,
        random: Random(1),
      );

      expect(_ids(winners), equals(['better-upload', 'incumbent', 'new']));
    });

    test('breaks fully tied peers randomly, reproducibly per seed', () {
      List<String> withSeed(int seed) => _ids(selectUnchokedCandidates(
            candidates: [_peer('a'), _peer('b'), _peer('c'), _peer('d')],
            slots: 4,
            seeding: false,
            random: Random(seed),
          ));

      expect(withSeed(7), equals(withSeed(7)));
      expect(
        {for (var seed = 0; seed < 50; seed++) withSeed(seed).first}.length,
        greaterThan(1),
      );
    });
  });

  group('pickOptimisticCandidateId (round-robin)', () {
    test('rotates through choked interested peers', () {
      final pool = [_peer('a'), _peer('b'), _peer('c')];

      expect(pickOptimisticCandidateId(chokedInterested: pool, cursor: 0), 'a');
      expect(pickOptimisticCandidateId(chokedInterested: pool, cursor: 1), 'b');
      expect(pickOptimisticCandidateId(chokedInterested: pool, cursor: 3), 'a');
    });

    test('returns null for an empty pool', () {
      expect(
          pickOptimisticCandidateId(chokedInterested: [], cursor: 0), isNull);
    });
  });

  group('PeersManager choke wiring', () {
    test('runs empty cycles, clamps slots, disposes cleanly', () async {
      final torrent = await createTestTorrent();
      final manager = PeersManager('test-peer-id', torrent,
          maxUploadSlots: 0, seeding: true);

      expect(manager.maxUploadSlots, equals(1));
      expect(manager.seeding, isTrue);

      manager.maxUploadSlots = 8;
      expect(manager.maxUploadSlots, equals(8));
      manager.seeding = false;
      expect(manager.seeding, isFalse);

      // No peers: cycles are no-ops, must not throw.
      manager.runUnchokeCycle();
      manager.rotateOptimisticUnchoke();
      await manager.dispose();
      await manager.dispose();

      // Cycles after dispose are no-ops.
      manager.runUnchokeCycle();
      manager.rotateOptimisticUnchoke();
    });
  });
}
