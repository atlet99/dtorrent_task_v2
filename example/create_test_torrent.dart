import 'dart:io';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:path/path.dart' as path;

/// Utility script to create a test torrent file for examples
///
/// Creates a simple test file and generates a torrent for it
/// Usage: dart run example/create_test_torrent.dart [output_path]
void main(List<String> args) async {
  final outputPath =
      args.isNotEmpty ? args[0] : path.join('tmp', 'test.torrent');

  // Create tmp directory if it doesn't exist
  final tmpDir = Directory(path.dirname(outputPath));
  if (!await tmpDir.exists()) {
    await tmpDir.create(recursive: true);
  }

  // Check if torrent already exists
  if (await File(outputPath).exists()) {
    print('Test torrent already exists: $outputPath');
    print('Skipping creation. Delete the file to recreate it.');
    return;
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
    print('Created test file: ${testFile.path}');
    print(
        'File size: ${(await testFile.length() / 1024).toStringAsFixed(2)} KB');
  }

  print('Creating test torrent...');
  print('Output path: $outputPath');

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

  await TorrentCreator.saveTorrent(torrentMap, outputPath);

  print('');
  print('✓ Test torrent created successfully!');
  print('  Path: $outputPath');
  print('  Name: ${torrent.name}');
  print('  Size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
  print('  Pieces: ${torrent.pieces.length}');
  print('  Files: ${torrent.files.length}');
}
