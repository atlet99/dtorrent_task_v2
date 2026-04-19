import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

void main() {
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
  print('Info hash: ${magnet.infoHashString}');
  print('Display name: ${magnet.displayName}');
  print('Trackers: ${magnet.trackers.length}');
  print('Initial progress: ${downloader.progress}%');

  // For a real download flow, subscribe to downloader events and call:
  // await downloader.startDownload();
}
