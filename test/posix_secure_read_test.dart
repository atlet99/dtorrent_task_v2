import 'dart:io';
import 'dart:async';
import 'dart:isolate';

import 'package:dtorrent_task_v2/src/file/posix_secure_read.dart';
import 'package:test/test.dart';

Future<void> swapDirectory(List<Object> args) async {
  final root = args[0] as String;
  final outside = args[1] as String;
  final port = args[2] as SendPort;
  port.send('ready');
  for (var i = 0; i < 500; i++) {
    await Directory('$root/dir').rename('$root/held');
    await Link('$root/dir').create(outside);
    await Link('$root/dir').delete();
    await Directory('$root/held').rename('$root/dir');
  }
  port.send('done');
}

void main() {
  test('unlink stays beneath root and never follows parent symlinks', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final root = await Directory.systemTemp.createTemp('secure_unlink_');
    final outside = await Directory.systemTemp.createTemp('secure_outside_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await Directory('${root.path}/dir').create();
    await File('${root.path}/dir/data').writeAsString('inside');
    await File('${outside.path}/data').writeAsString('outside');
    await Link('${root.path}/link').create(outside.path);
    expect(() => unlinkBeneath(root.path, 'link/data'),
        throwsA(isA<FileSystemException>()));
    expect(await File('${outside.path}/data').readAsString(), 'outside');
    await Link('${root.path}/leaf').create('${outside.path}/data');
    unlinkBeneath(root.path, 'leaf');
    expect(await Link('${root.path}/leaf').exists(), isFalse);
    expect(await File('${outside.path}/data').readAsString(), 'outside');
    unlinkBeneath(root.path, 'dir/data');
    expect(await File('${root.path}/dir/data').exists(), isFalse);
    expect(() => unlinkBeneath(root.path, '../data'), throwsFormatException);
  });

  test('unsupported platforms fail closed', () {
    if (Platform.isWindows) {
      expect(() => readBeneath('.', 'file', 0, 1), throwsUnsupportedError);
    }
  });

  test('read beneath rejects links, traversal and non-regular files', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final root = await Directory.systemTemp.createTemp('secure_read_');
    final outside = await Directory.systemTemp.createTemp('secure_outside_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await Directory('${root.path}/dir').create();
    await File('${root.path}/dir/data').writeAsString('abcdef');
    await File('${outside.path}/secret').writeAsString('secret');
    await Link('${root.path}/final').create('${outside.path}/secret');
    await Link('${root.path}/middle').create(outside.path);
    expect(readBeneath(root.path, 'dir/data', 2, 3), [99, 100, 101]);
    expect(() => readBeneath(root.path, 'final', 0, 6),
        throwsA(isA<FileSystemException>()));
    expect(() => readBeneath(root.path, 'middle/secret', 0, 6),
        throwsA(isA<FileSystemException>()));
    expect(
        () => readBeneath(root.path, '../secret', 0, 6), throwsFormatException);
    expect(
        () => readBeneath(root.path, '/secret', 0, 6), throwsFormatException);
    final result = await Process.run('mkfifo', ['${root.path}/pipe']);
    expect(result.exitCode, 0);
    expect(() => readBeneath(root.path, 'pipe', 0, 6),
        throwsA(isA<FileSystemException>()));
  });

  test('concurrent directory swaps cannot redirect a read', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final root = await Directory.systemTemp.createTemp('secure_race_');
    final outside = await Directory.systemTemp.createTemp('secure_outside_');
    final port = ReceivePort();
    final done = Completer<void>();
    final ready = Completer<void>();
    port.listen((message) {
      if (message == 'ready') ready.complete();
      if (message == 'done') done.complete();
    });
    await Directory('${root.path}/dir').create();
    await File('${root.path}/dir/data').writeAsString('inside');
    await File('${outside.path}/data').writeAsString('secret');
    await File('${root.path}/dir/deletable').writeAsString('inside');
    await File('${outside.path}/deletable').writeAsString('outside');
    final isolate = await Isolate.spawn(
        swapDirectory, [root.path, outside.path, port.sendPort]);
    try {
      await ready.future;
      for (var i = 0; i < 2000; i++) {
        try {
          expect(readBeneath(root.path, 'dir/data', 0, 6), 'inside'.codeUnits);
        } on FileSystemException {
          // A path temporarily absent or replaced by a link must fail closed.
        }
        try {
          unlinkBeneath(root.path, 'dir/deletable');
        } on FileSystemException {
          // It may already be deleted, absent, or replaced by a link.
        }
      }
      await done.future.timeout(const Duration(seconds: 20));
      expect(await File('${outside.path}/deletable').readAsString(), 'outside');
    } finally {
      isolate.kill();
      port.close();
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    }
  });
}
