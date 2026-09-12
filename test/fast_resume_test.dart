import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'test_helpers.dart';

void main() {
  group('StateFileV2', () {
    late Directory testDir;
    late TorrentModel testTorrent;

    setUp(() async {
      testDir = await getTestDownloadDirectory();
      testTorrent = await createTestTorrent();
    });

    tearDown(() async {
      await cleanupTestDirectory(testDir);
    });

    test('Creates new state file with v2 format', () async {
      final stateFile =
          await StateFileV2.getStateFile(testDir.path, testTorrent);

      expect(stateFile.version, equals(2));
      expect(stateFile.isValid, isTrue);
      expect(stateFile.lastModified, isNotNull);
    });

    test('Validates state file integrity', () async {
      final stateFile =
          await StateFileV2.getStateFile(testDir.path, testTorrent);
      final isValid = await stateFile.validate();

      expect(isValid, isTrue);
    });

    test('Updates bitfield correctly', () async {
      final stateFile =
          await StateFileV2.getStateFile(testDir.path, testTorrent);

      try {
        final updated = await stateFile.updateBitfield(0, true);
        expect(updated, isTrue);
        expect(stateFile.bitfield.getBit(0), isTrue);
      } finally {
        await stateFile.close();
      }
    });
  });

  group('StateFileV2 batched persists', () {
    late Directory testDir;
    late TorrentModel testTorrent;

    setUp(() async {
      testDir = await getTestDownloadDirectory();
      testTorrent = await createTestTorrent();
    });

    tearDown(() async {
      await cleanupTestDirectory(testDir);
    });

    test('N piece updates persist in one batch pass', () async {
      final stateFile =
          await StateFileV2.getStateFile(testDir.path, testTorrent);
      List<int> completed;
      try {
        final piecesNum = stateFile.bitfield.piecesNum;
        for (var i = 0; i < piecesNum; i++) {
          expect(await stateFile.updateBitfield(i, true), isTrue);
        }
        // All changes are still in memory: no header/footer/flush yet.
        expect(stateFile.hasPendingChanges, isTrue);
        expect(stateFile.persistCount, equals(0));

        await stateFile.saveResumeData();
        expect(stateFile.hasPendingChanges, isFalse);
        expect(stateFile.persistCount, equals(1));
        expect(await stateFile.validate(), isTrue);

        // A second save with no changes is a no-op.
        await stateFile.saveResumeData();
        expect(stateFile.persistCount, equals(1));

        completed = List<int>.from(stateFile.bitfield.completedPieces);
      } finally {
        await stateFile.close();
      }

      // Reload from disk: every bit survived the single batch pass.
      final reloaded =
          await StateFileV2.getStateFile(testDir.path, testTorrent);
      try {
        expect(reloaded.bitfield.completedPieces, equals(completed));
        expect(reloaded.bitfield.completedPieces,
            hasLength(testTorrent.pieces!.length));
      } finally {
        await reloaded.close();
      }
    });

    test('auto-persists pending changes on timer', () async {
      final stateFile = StateFileV2(testTorrent,
          persistInterval: const Duration(milliseconds: 50));
      await stateFile.init(testDir.path, testTorrent);
      try {
        expect(await stateFile.updateBitfield(0, true), isTrue);
        expect(stateFile.hasPendingChanges, isTrue);

        await Future.delayed(const Duration(milliseconds: 500));

        expect(stateFile.hasPendingChanges, isFalse);
        expect(stateFile.persistCount, equals(1));
        expect(await stateFile.validate(), isTrue);
      } finally {
        await stateFile.close();
      }
    });

    test('close() flushes pending changes', () async {
      final stateFile =
          await StateFileV2.getStateFile(testDir.path, testTorrent);
      final piecesNum = stateFile.bitfield.piecesNum;
      expect(await stateFile.updateBitfield(0, true), isTrue);
      expect(await stateFile.updateBitfield(piecesNum - 1, true), isTrue);
      expect(stateFile.persistCount, equals(0));
      await stateFile.close();

      final reloaded =
          await StateFileV2.getStateFile(testDir.path, testTorrent);
      try {
        expect(reloaded.bitfield.getBit(0), isTrue);
        expect(reloaded.bitfield.getBit(piecesNum - 1), isTrue);
      } finally {
        await reloaded.close();
      }
    });
  });

  group('FileValidator', () {
    late Directory testDir;
    late TorrentModel testTorrent;

    setUp(() async {
      testDir = await getTestDownloadDirectory();
      testTorrent = await createTestTorrent();
    });

    tearDown(() async {
      await cleanupTestDirectory(testDir);
    });

    test('Quick validation checks file existence and sizes', () async {
      // Create empty files
      for (var file in testTorrent.files) {
        final filePath = File('${testDir.path}${Platform.pathSeparator}'
            '${file.path.replaceAll('/', Platform.pathSeparator)}');
        await filePath.create(recursive: true);
        await filePath.writeAsBytes(List.filled(file.length, 0));
      }

      final validator = FileValidator(testTorrent, const [], testDir.path);

      expect(await validator.quickValidate(), isTrue);
    });
  });
}
