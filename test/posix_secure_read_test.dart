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
    final held = '$root/held$i';
    try {
      await Directory('$root/dir').rename(held);
    } on FileSystemException {
      continue;
    }
    try {
      await Link('$root/dir').create(outside);
      await Link('$root/dir').delete();
    } on FileSystemException {
      // A concurrent writer may legitimately recreate the directory.
    }
    try {
      await Directory(held).rename('$root/dir');
    } on FileSystemException {
      // Keep the parked copy; the writer owns the recreated directory now.
    }
  }
  port.send('done');
}

void main() {
  test('secure writer creates and updates without following links', () async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    final root = await Directory.systemTemp.createTemp('secure_write_');
    final outside = await Directory.systemTemp.createTemp('secure_outside_');
    addTearDown(() async {
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    });
    await File('${outside.path}/data').writeAsString('outside');
    final writer = PosixSecureWriter.open(root.path, 'dir/data', 8);
    writer.write(2, [1, 2, 3], 0, 3);
    writer.flush();
    writer.close();
    expect(await File('${root.path}/dir/data').readAsBytes(),
        [0, 0, 1, 2, 3, 0, 0, 0]);
    final existing = PosixSecureWriter.open(root.path, 'dir/data', 1);
    existing.close();
    expect(await File('${root.path}/dir/data').length(), 8);
    final held = PosixSecureWriter.open(root.path, 'dir/data', 8);
    await File('${root.path}/dir/data').rename('${root.path}/dir/original');
    await Link('${root.path}/dir/data').create('${outside.path}/data');
    held.write(0, [7], 0, 1);
    held.flush();
    held.close();
    expect((await File('${root.path}/dir/original').readAsBytes()).first, 7);
    expect(await File('${outside.path}/data').readAsString(), 'outside');
    await Link('${root.path}/link').create(outside.path);
    expect(() => PosixSecureWriter.open(root.path, 'link/data', 8),
        throwsA(isA<FileSystemException>()));
    expect(await File('${outside.path}/data').readAsString(), 'outside');
    await Link('${root.path}/leaf').create('${outside.path}/data');
    expect(() => PosixSecureWriter.open(root.path, 'leaf', 8),
        throwsA(isA<FileSystemException>()));
    expect(() => PosixSecureWriter.open(root.path, '../data', 8),
        throwsFormatException);
    final fifo = await Process.run('mkfifo', ['${root.path}/pipe']);
    expect(fifo.exitCode, 0);
    expect(() => PosixSecureWriter.open(root.path, 'pipe', 8),
        throwsA(isA<FileSystemException>()));
  });

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
      expect(
          () => PosixSecureWriter.open('.', 'file', 1), throwsUnsupportedError);
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
        if (i < 40) {
          try {
            final writer = PosixSecureWriter.open(root.path, 'dir/data', 6);
            try {
              writer.write(0, 'inside'.codeUnits, 0, 6);
              writer.flush();
            } finally {
              writer.close();
            }
          } on FileSystemException {
            // A path temporarily absent or replaced by a link must fail closed.
          }
        }
      }
      await done.future.timeout(const Duration(seconds: 20));
      expect(await File('${outside.path}/deletable').readAsString(), 'outside');
      expect(await File('${outside.path}/data').readAsString(), 'secret');
    } finally {
      isolate.kill();
      port.close();
      await root.delete(recursive: true);
      await outside.delete(recursive: true);
    }
  });
}
