import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('Auto-move downloaded files (5.2)', () {
    test('should select destination by extension rule', () async {
      String? movedTorrentPath;
      String? movedAbsolutePath;

      final manager = AutoMoveManager(
        moveAction: (torrentFilePath, newAbsolutePath) async {
          movedTorrentPath = torrentFilePath;
          movedAbsolutePath = newAbsolutePath;
          return true;
        },
        config: const AutoMoveConfig(
          defaultDestinationDirectory: '/downloads/misc',
          rules: [
            AutoMoveRule(
              extensions: {'mp4'},
              destinationDirectory: '/downloads/video',
            ),
          ],
        ),
      );

      final file = DownloadFile(
        '/tmp/a.mp4',
        0,
        100,
        'movies/a.mp4',
        [],
      );

      final result = await manager.moveCompletedFile(file);

      expect(result, isNotNull);
      expect(result!.success, isTrue);
      expect(movedTorrentPath, 'movies/a.mp4');
      expect(movedAbsolutePath, '/downloads/video/a.mp4');
    });

    test('should reject external disk when disabled', () async {
      final manager = AutoMoveManager(
        moveAction: (_, __) async => true,
        config: const AutoMoveConfig(
          defaultDestinationDirectory: '/Volumes/USB/downloads',
          allowExternalDisks: false,
        ),
      );

      final file = DownloadFile(
        '/tmp/music.flac',
        0,
        100,
        'music/music.flac',
        [],
      );

      final result = await manager.moveCompletedFile(file);
      expect(result, isNotNull);
      expect(result!.success, isFalse);
      expect(result.error, contains('External disk'));
    });
  });
}
