import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/lsd/lsd.dart';
import 'package:path/path.dart' as path;
import 'test_torrent_helper.dart';

var scriptDir = path.dirname(Platform.script.path);
var torrentsPath =
    path.canonicalize(path.join(scriptDir, '..', '..', '..', 'torrents'));

void main(List<String> args) async {
  print(await getTorrentTaskVersion());
  // Try to use big-buck-bunny.torrent, fallback to test torrent
  var torrentFile = path.join(torrentsPath, 'big-buck-bunny.torrent');
  if (!await File(torrentFile).exists()) {
    print('big-buck-bunny.torrent not found, creating test torrent...');
    torrentFile = await ensureTestTorrentExists();
    print('Using test torrent: $torrentFile');
  }
  var model = await TorrentModel.parse(torrentFile);
  var infoHash = model.infoHash;
  var lsd = LSD(infoHash, 'daa231dfa');
  lsd.port = 61111;
  lsd.start();
}
