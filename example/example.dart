import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

void main() {
  print('dtorrent_task_v2 quick example');
  print('----------------------------');

  // 1) Parse a magnet URI.
  const magnetUri =
      'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567'
      '&dn=Example%20Torrent'
      '&tr=udp%3A%2F%2Ftracker.opentrackr.org%3A1337%2Fannounce';

  final magnet = MagnetParser.parse(magnetUri);
  if (magnet == null) {
    print('Invalid magnet URI');
    return;
  }

  final downloader = MetadataDownloader.fromMagnet(magnetUri);
  print('Magnet parsed successfully');
  print('Info hash: ${magnet.infoHashString}');
  print('Display name: ${magnet.displayName}');
  print('Trackers: ${magnet.trackers.length}');
  print('Initial progress: ${downloader.progress}%');

  // 2) Build optional UX automation configs (no network calls required).
  final autoMove = AutoMoveConfig(
    defaultDestinationDirectory: './downloads/completed',
    rules: const [
      AutoMoveRule(
        extensions: {'mkv', 'mp4'},
        destinationDirectory: './downloads/video',
      ),
    ],
  );

  final schedule = ScheduleWindow(
    id: 'night-limit',
    weekdays: const {1, 2, 3, 4, 5, 6, 7},
    start: const Duration(hours: 1),
    end: const Duration(hours: 8),
    maxDownloadRate: 1 * 1024 * 1024,
    maxUploadRate: 256 * 1024,
  );

  print('Auto-move rules configured: ${autoMove.rules.length}');
  print('Schedule window configured: ${schedule.id}');

  print('');
  print('Next steps for a real session:');
  print('1. Download metadata: await downloader.startDownload();');
  print('2. Build TorrentTask from parsed torrent metadata/file.');
  print('3. Apply task.configureAutoMove(autoMove);');
  print('4. Apply task.addScheduleWindow(schedule); task.startScheduling();');
}
