import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../torrent/safe_torrent_path.dart';

final _libc = DynamicLibrary.process();
final _open = _libc.lookupFunction<
    Int32 Function(Pointer<Utf8>, Int32, VarArgs<()>),
    int Function(Pointer<Utf8>, int)>('open');
final _openAt = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Utf8>, Int32, VarArgs<()>),
    int Function(int, Pointer<Utf8>, int)>('openat');
final _fstat = _libc.lookupFunction<Int32 Function(Int32, Pointer<Void>),
    int Function(int, Pointer<Void>)>(
  Abi.current() == Abi.macosX64 ? r'fstat$INODE64' : 'fstat',
);
final _pread = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
    int Function(int, Pointer<Uint8>, int, int)>('pread');
final _close =
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('close');
final _unlinkAt = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Utf8>, Int32),
    int Function(int, Pointer<Utf8>, int)>('unlinkat');

/// Unlinks one entry relative to no-follow directory descriptors.
void unlinkBeneath(String root, String relative) {
  final abi = Abi.current();
  final apple =
      abi == Abi.macosArm64 || abi == Abi.macosX64 || abi == Abi.iosArm64;
  final android = abi == Abi.androidArm64;
  final arm64 = abi == Abi.linuxArm64 || android;
  if (!apple && !arm64 && abi != Abi.linuxX64) {
    throw UnsupportedError('Secure file deletion is unavailable on $abi');
  }
  final parts = relative.split('/');
  for (final part in parts) {
    validateTorrentPathComponent(part);
  }
  final directory = apple ? 0x100000 : (arm64 ? 0x4000 : 0x10000);
  final nofollow = apple ? 0x100 : (arm64 ? 0x8000 : 0x20000);
  final cloexec = apple ? 0x1000000 : 0x80000;
  using((arena) {
    final errno = _libc
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            apple ? '__error' : (android ? '__errno' : '__errno_location'));
    Never fail(String message) => throw FileSystemException(
        message, relative, OSError('', errno().value));
    var fd = _open(root.toNativeUtf8(allocator: arena), directory | cloexec);
    if (fd < 0) fail('Cannot open download root');
    try {
      for (final part in parts.take(parts.length - 1)) {
        final next = _openAt(fd, part.toNativeUtf8(allocator: arena),
            directory | nofollow | cloexec);
        if (next < 0) fail('Cannot open torrent directory');
        _close(fd);
        fd = next;
      }
      if (_unlinkAt(fd, parts.last.toNativeUtf8(allocator: arena), 0) != 0) {
        fail('Cannot delete torrent file');
      }
    } finally {
      _close(fd);
    }
  });
}

/// Reads a range through no-follow directory descriptors on supported POSIX ABIs.
Uint8List readBeneath(String root, String relative, int offset, int length) {
  final abi = Abi.current();
  final apple =
      abi == Abi.macosArm64 || abi == Abi.macosX64 || abi == Abi.iosArm64;
  final linuxX64 = abi == Abi.linuxX64;
  final androidArm64 = abi == Abi.androidArm64;
  final linuxArm64 = abi == Abi.linuxArm64 || androidArm64;
  if (!apple && !linuxX64 && !linuxArm64) {
    throw UnsupportedError('Secure file reads are unavailable on $abi');
  }
  if (offset < 0 || length < 0) throw ArgumentError('Invalid read range');
  final parts = relative.split('/');
  for (final part in parts) {
    validateTorrentPathComponent(part);
  }

  final directory = apple ? 0x100000 : (linuxArm64 ? 0x4000 : 0x10000);
  final nofollow = apple ? 0x100 : (linuxArm64 ? 0x8000 : 0x20000);
  final cloexec = apple ? 0x1000000 : 0x80000;
  final nonblock = apple ? 0x4 : 0x800;
  return using((arena) {
    final errno = _libc.lookupFunction<Pointer<Int32> Function(),
            Pointer<Int32> Function()>(
        apple ? '__error' : (androidArm64 ? '__errno' : '__errno_location'));
    Never fail(String message) => throw FileSystemException(
        message, relative, OSError('', errno().value));

    var fd = _open(root.toNativeUtf8(allocator: arena), directory | cloexec);
    if (fd < 0) fail('Cannot open download root');
    try {
      for (var i = 0; i < parts.length; i++) {
        final last = i == parts.length - 1;
        final next = _openAt(fd, parts[i].toNativeUtf8(allocator: arena),
            nofollow | cloexec | (last ? nonblock : directory));
        if (next < 0) fail('Cannot open torrent path');
        _close(fd);
        fd = next;
      }
      final stat = arena<Uint8>(512);
      if (_fstat(fd, stat.cast()) != 0) fail('Cannot stat torrent file');
      // Darwin, Linux x86-64 and Linux AArch64 have different struct stat layouts.
      final modeOffset = apple ? 4 : (linuxX64 ? 24 : 16);
      final mode = apple
          ? (stat + modeOffset).cast<Uint16>().value
          : (stat + modeOffset).cast<Uint32>().value;
      if (mode & 0xf000 != 0x8000) {
        throw FileSystemException(
            'Torrent path is not a regular file', relative);
      }
      final buffer = arena<Uint8>(length == 0 ? 1 : length);
      var total = 0;
      while (total < length) {
        final count =
            _pread(fd, buffer + total, length - total, offset + total);
        if (count < 0) {
          if (errno().value == 4) continue;
          fail('Cannot read torrent file');
        }
        if (count == 0) break;
        total += count;
      }
      return Uint8List.fromList(buffer.asTypedList(total));
    } finally {
      _close(fd);
    }
  });
}
