import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Helper utility to ensure test torrent file exists
///
/// Checks if test torrent exists, and creates it if it doesn't
/// Returns the path to the torrent file
Future<String> ensureTestTorrentExists([String? customPath]) async {
  final torrentPath = customPath ?? path.join('tmp', 'test.torrent');
  final torrentFile = File(torrentPath);

  // If torrent already exists, return its path
  if (await torrentFile.exists()) {
    return torrentPath;
  }

  // Create tmp directory if it doesn't exist
  final tmpDir = Directory(path.dirname(torrentPath));
  if (!await tmpDir.exists()) {
    await tmpDir.create(recursive: true);
  }

  // Create a simple test file
  final testFileDir = Directory(path.join(tmpDir.path, 'test_data'));
  if (!await testFileDir.exists()) {
    await testFileDir.create(recursive: true);
  }

  final testFile = File(path.join(testFileDir.path, 'test_file.txt'));
  if (!await testFile.exists()) {
    // Create a test file with some content (about 1MB)
    final content =
        List.generate(1000, (i) => 'This is test file line $i. ' * 10)
            .join('\n');
    await testFile.writeAsString(content);
  }

  // Create torrent
  final torrent = await TorrentCreator.createTorrent(
    testFileDir.path,
    TorrentCreationOptions(
      pieceLength: 256 * 1024, // 256KB
      trackers: [
        Uri.parse('udp://tracker.openbittorrent.com:6969/announce'),
        Uri.parse('udp://tracker.leechers-paradise.org:6969/announce'),
      ],
      comment: 'Test torrent for dtorrent_task examples',
      createdBy: 'dtorrent_task_v2',
    ),
  );

  // Save torrent to file
  final torrentMap = <String, dynamic>{
    'info': {
      'name': torrent.name,
      'piece length': torrent.pieceLength,
      'pieces': torrent.pieces,
      if (torrent.files.length == 1)
        'length': torrent.length
      else
        'files': torrent.files
            .map((f) => {
                  'length': f.length,
                  'path': f.name.split('/'),
                })
            .toList(),
    },
    'announce-list': torrent.announces.map((a) => [a.toString()]).toList(),
    if (torrent.announces.isNotEmpty)
      'announce': torrent.announces.first.toString(),
    'comment': 'Test torrent for dtorrent_task examples',
    'created by': 'dtorrent_task_v2',
    'creation date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'encoding': 'UTF-8',
  };

  await TorrentCreator.saveTorrent(torrentMap, torrentPath);

  return torrentPath;
}
