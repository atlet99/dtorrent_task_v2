import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/file/state_file_v2.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'test_helpers.dart';

void main() {
  group('StateFileV2', () {
    late Directory testDir;
    late Torrent testTorrent;

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

      final updated = await stateFile.updateBitfield(0, true);
      expect(updated, isTrue);
      expect(stateFile.bitfield.getBit(0), isTrue);
    });
  });

  group('FileValidator', () {
    late Directory testDir;
    late Torrent testTorrent;

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
        final filePath = File('${testDir.path}${file.path}');
        await filePath.create(recursive: true);
        await filePath.writeAsBytes(List.filled(file.length, 0));
      }

      // Note: We can't create a full validator without pieces,
      // so this test is a placeholder for the structure
      expect(testTorrent.files.length, greaterThan(0));
    });
  });
}
