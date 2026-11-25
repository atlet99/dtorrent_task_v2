import 'dart:io';

import 'package:dtorrent_task_v2/src/file/posix_secure_read.dart';
import 'package:test/test.dart';

void main() {
  test('secure operations stay beneath the root', () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('secure_win_');
    final outside = await Directory.systemTemp.createTemp('secure_win_out_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    final writer = openSecureWriter(root.path, 'dir/data', 8);
    writer.write(2, [1, 2, 3], 0, 3);
    writer.flush();
    writer.close();
    expect(await File('${root.path}/dir/data').readAsBytes(),
        [0, 0, 1, 2, 3, 0, 0, 0]);
    final existing = openSecureWriter(root.path, 'dir/data', 1);
    existing.close();
    expect(await File('${root.path}/dir/data').length(), 8);
    expect(readBeneath(root.path, 'dir/data', 2, 3), [1, 2, 3]);
    moveBeneath(root.path, 'dir/data', outside.path, 'moved');
    expect(await File('${outside.path}/moved').readAsBytes(),
        [0, 0, 1, 2, 3, 0, 0, 0]);
    expect(await File('${root.path}/dir/data').exists(), isFalse);
    unlinkBeneath(outside.path, 'moved');
    expect(await File('${outside.path}/moved').exists(), isFalse);
    expect(
        () => openSecureWriter(root.path, '../data', 8), throwsFormatException);
  });

  test('secure operations reject junction escapes', () async {
    if (!Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp('secure_win_link_');
    final outside =
        await Directory.systemTemp.createTemp('secure_win_link_out_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await File('${outside.path}/data').writeAsString('secret');
    final junction = await Process.run(
        'cmd', ['/c', 'mklink', '/J', '${root.path}\\junction', outside.path]);
    if (junction.exitCode != 0) return;
    expect(() => readBeneath(root.path, 'junction/data', 0, 6),
        throwsA(isA<FileSystemException>()));
    expect(() => openSecureWriter(root.path, 'junction/data', 6),
        throwsA(isA<FileSystemException>()));
    expect(() => unlinkBeneath(root.path, 'junction/data'),
        throwsA(isA<FileSystemException>()));
    expect(() => moveBeneath(root.path, 'junction/data', root.path, 'x'),
        throwsA(isA<FileSystemException>()));
    expect(await File('${outside.path}/data').readAsString(), 'secret');
  });
}
