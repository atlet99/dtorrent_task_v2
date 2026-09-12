import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';
import 'test_helpers.dart';

bool _isPortConflict(dynamic e) {
  if (e is SocketException) {
    return e.message.contains('Address already in use') ||
        e.osError?.errorCode == 48;
  }
  final str = e.toString();
  return str.contains('Address already in use') ||
      str.contains('errno = 48') ||
      str.contains('port = 6771') ||
      str.contains('Failed to create datagram socket');
}

Future<void> _writeTorrentData(TorrentModel torrent, Directory dir) async {
  for (final file in torrent.files) {
    final f = File(
        '${dir.path}${Platform.pathSeparator}${file.path.replaceAll('/', Platform.pathSeparator)}');
    await f.create(recursive: true);
    await f.writeAsBytes(List<int>.filled(file.length, 0));
  }
}

Future<void> _persistPartialState(
    TorrentModel torrent, Directory dir, int completedPieces) async {
  final stateFile = await StateFileV2.getStateFile(dir.path, torrent);
  for (var i = 0; i < completedPieces; i++) {
    await stateFile.updateBitfield(i);
  }
  await stateFile.close();
}

void main() {
  group('Multi-file torrent progress regression', () {
    test('single-file torrent reports totalSize equal to length', () async {
      final torrent = await createTestTorrent();

      expect(torrent.length, isNotNull);
      expect(torrent.totalSize, equals(torrent.length));
    });

    test('multi-file torrent totalSize falls back to sum of files', () async {
      final torrent = await createTestMultiFileTorrent();
      final sum = torrent.files.fold<int>(0, (sum, f) => sum + f.length);

      expect(torrent.length, isNull);
      expect(torrent.files, hasLength(3));
      expect(torrent.totalSize, equals(sum));
      expect(torrent.totalSize, greaterThan(0));
    });

    test('multi-file torrent progress reflects downloaded bytes', () async {
      final torrent = await createTestMultiFileTorrent();
      const completedPieces = 5;
      final testDir = await getTestDownloadDirectory();
      await _writeTorrentData(torrent, testDir);
      await _persistPartialState(torrent, testDir, completedPieces);

      final task = TorrentTask.newTask(torrent, testDir.path);
      try {
        try {
          await task.start();
        } catch (e) {
          if (_isPortConflict(e)) {
            return;
          }
          rethrow;
        }

        expect(task.metaInfo.length, isNull);
        expect(task.downloaded, equals(completedPieces * torrent.pieceLength));

        final expectedProgress =
            (completedPieces * torrent.pieceLength) / torrent.totalSize;
        expect(task.progress, closeTo(expectedProgress, 0.001));

        await task.stop();
      } finally {
        await task.dispose();
        await cleanupTestDirectory(testDir);
      }
    });

    test('single-file torrent progress still uses length when completed',
        () async {
      final torrent = await createTestTorrent();
      final testDir = await getTestDownloadDirectory();
      await _writeTorrentData(torrent, testDir);
      await _persistPartialState(torrent, testDir, 3);

      final task = TorrentTask.newTask(torrent, testDir.path);
      try {
        try {
          await task.start();
        } catch (e) {
          if (_isPortConflict(e)) {
            return;
          }
          rethrow;
        }

        expect(task.metaInfo.length, isNotNull);
        expect(task.downloaded, equals(3 * torrent.pieceLength));

        final expectedProgress = (3 * torrent.pieceLength) / torrent.length!;
        expect(task.progress, closeTo(expectedProgress, 0.001));

        await task.stop();
      } finally {
        await task.dispose();
        await cleanupTestDirectory(testDir);
      }
    });
  });
}
