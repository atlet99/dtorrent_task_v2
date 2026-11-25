import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

Map<String, dynamic> v1(List<String> path) => {
      'info': {
        'name': 'root',
        'piece length': 4,
        'pieces': Uint8List(20),
        'files': [
          {'length': 4, 'path': path}
        ],
      }
    };

Map<String, dynamic> v2(String name) => {
      'info': {
        'name': 'root',
        'piece length': 4,
        'meta version': 2,
        'file tree': {
          name: {
            '': {'length': 4}
          }
        },
      }
    };

void main() {
  test('rejects unsafe v1 and v2 path components', () {
    for (final component in [
      '..',
      '.',
      '/tmp',
      r'C:\escape',
      'a/b',
      '.. ',
      'CON.txt',
      'a\u0000b'
    ]) {
      expect(() => TorrentParser.parseFromMap(v1([component])),
          throwsFormatException);
      expect(() => TorrentParser.parseFromMap(v2(component)),
          throwsFormatException);
    }
    expect(TorrentParser.parseFromMap(v1(['日本語.txt'])).files.single.path,
        'root/日本語.txt');
    final unicode = v1(['placeholder']);
    final unicodeFiles = (unicode['info'] as Map)['files'] as List;
    (unicodeFiles.single as Map)['path'] = [
      Uint8List.fromList(utf8.encode('日本語.txt'))
    ];
    expect(TorrentParser.parseBytes(encode(unicode)).files.single.path,
        'root/日本語.txt');
    final badName = v1(['file']);
    (badName['info'] as Map)['name'] = '../escape';
    expect(() => TorrentParser.parseFromMap(badName), throwsFormatException);
    final badLink = v1(['link']);
    final files = (badLink['info'] as Map)['files'] as List;
    (files.single as Map)['symlink path'] = ['..', 'outside'];
    expect(() => TorrentParser.parseFromMap(badLink), throwsFormatException);
  });

  test('rejects existing symlink in download path', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('torrent_path_');
    final outside = await Directory.systemTemp.createTemp('torrent_outside_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await Link('${root.path}/root').create(outside.path);
    final torrent = TorrentParser.parseFromMap(v1(['data.bin']));
    final state = await StateFileV2.getStateFile(root.path, torrent);
    addTearDown(state.close);
    await expectLater(
      DownloadFileManager.createFileManager(
          torrent, root.path, state, [Piece('00' * 20, 0, 4, 0)]),
      throwsA(isA<FileSystemException>()),
    );
    expect(await File('${outside.path}/data.bin').exists(), isFalse);
  });

  test('rejects symlink introduced after manager initialization', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('torrent_path_late_');
    final outside = await Directory.systemTemp.createTemp('torrent_outside_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    final torrent = TorrentParser.parseFromMap(v1(['data.bin']));
    final state = await StateFileV2.getStateFile(root.path, torrent);
    final manager = await DownloadFileManager.createFileManager(
        torrent, root.path, state, [Piece('00' * 20, 0, 4, 0)]);
    addTearDown(manager.close);
    await Link('${root.path}/root').create(outside.path);
    await expectLater(manager.writeFile(0, 0, [1, 2, 3, 4]),
        throwsA(isA<FileSystemException>()));
    expect(await File('${outside.path}/data.bin').exists(), isFalse);
  });
}
