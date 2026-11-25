import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../torrent/safe_torrent_path.dart';
import 'secure_file_writer.dart';
import 'win_secure_file.dart';

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
final _renameAt = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Utf8>, Int32, Pointer<Utf8>),
    int Function(int, Pointer<Utf8>, int, Pointer<Utf8>)>('renameat');
final _openAtCreate = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Utf8>, Int32, VarArgs<(Uint32,)>),
    int Function(int, Pointer<Utf8>, int, int)>('openat');
final _mkdirAt = _libc.lookupFunction<
    Int32 Function(Int32, Pointer<Utf8>, Uint32),
    int Function(int, Pointer<Utf8>, int)>('mkdirat');
final _truncate =
    _libc.lookupFunction<Int32 Function(Int32, Int64), int Function(int, int)>(
        'ftruncate');
final _pwrite = _libc.lookupFunction<
    IntPtr Function(Int32, Pointer<Uint8>, IntPtr, Int64),
    int Function(int, Pointer<Uint8>, int, int)>('pwrite');
final _fsync =
    _libc.lookupFunction<Int32 Function(Int32), int Function(int)>('fsync');

/// A regular file opened without following links beneath a trusted directory.
final class PosixSecureWriter implements SecureFileWriter {
  PosixSecureWriter._(this._fd, this._parentFd, this.path, this._errno);

  int _fd;
  int _parentFd;
  final String path;
  final Pointer<Int32> Function() _errno;

  static PosixSecureWriter open(String root, String relative, int length) {
    final abi = Abi.current();
    final apple =
        abi == Abi.macosArm64 || abi == Abi.macosX64 || abi == Abi.iosArm64;
    final android = abi == Abi.androidArm64;
    final arm64 = abi == Abi.linuxArm64 || android;
    if (!apple && !arm64 && abi != Abi.linuxX64) {
      throw UnsupportedError('Secure file writes are unavailable on $abi');
    }
    if (length < 0) throw ArgumentError.value(length, 'length');
    final parts = relative.split('/');
    for (final part in parts) {
      validateTorrentPathComponent(part);
    }
    final directory = apple ? 0x100000 : (arm64 ? 0x4000 : 0x10000);
    final nofollow = apple ? 0x100 : (arm64 ? 0x8000 : 0x20000);
    final cloexec = apple ? 0x1000000 : 0x80000;
    final nonblock = apple ? 0x4 : 0x800;
    final create = apple ? 0x200 : 0x40;
    final exclusive = apple ? 0x800 : 0x80;
    return using((arena) {
      final errno = _libc
          .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
              apple ? '__error' : (android ? '__errno' : '__errno_location'));
      Never fail(String message) => throw FileSystemException(
          message, relative, OSError('', errno().value));
      var parent =
          _open(root.toNativeUtf8(allocator: arena), directory | cloexec);
      if (parent < 0) fail('Cannot open download root');
      try {
        for (final part in parts.take(parts.length - 1)) {
          final name = part.toNativeUtf8(allocator: arena);
          var next = _openAt(parent, name, directory | nofollow | cloexec);
          if (next < 0 && errno().value == 2) {
            final result = _mkdirAt(parent, name, 493);
            if (result != 0) {
              if (errno().value != 17) fail('Cannot create torrent directory');
            } else if (_fsync(parent) != 0) {
              fail('Cannot sync parent directory');
            }
            next = _openAt(parent, name, directory | nofollow | cloexec);
          }
          if (next < 0) fail('Cannot open torrent directory');
          _close(parent);
          parent = next;
        }
        final name = parts.last.toNativeUtf8(allocator: arena);
        final flags = 2 | nofollow | cloexec | nonblock;
        var fd = _openAtCreate(parent, name, flags | create | exclusive, 420);
        final created = fd >= 0;
        if (fd < 0 && errno().value == 17) fd = _openAt(parent, name, flags);
        if (fd < 0) fail('Cannot open torrent file for writing');
        try {
          final stat = arena<Uint8>(512);
          if (_fstat(fd, stat.cast()) != 0) fail('Cannot stat torrent file');
          final modeOffset = apple ? 4 : (abi == Abi.linuxX64 ? 24 : 16);
          final mode = apple
              ? (stat + modeOffset).cast<Uint16>().value
              : (stat + modeOffset).cast<Uint32>().value;
          if (mode & 0xf000 != 0x8000) {
            throw FileSystemException(
                'Torrent path is not a regular file', relative);
          }
          if (created && _truncate(fd, length) != 0) {
            fail('Cannot allocate torrent file');
          }
          final writer = PosixSecureWriter._(fd, parent, relative, errno);
          parent = -1;
          return writer;
        } catch (_) {
          _close(fd);
          rethrow;
        }
      } finally {
        if (parent >= 0) _close(parent);
      }
    });
  }

  @override
  void write(int offset, List<int> data, int start, int end) {
    if (_fd < 0) throw StateError('File is closed');
    if (offset < 0 || start < 0 || end < start || end > data.length) {
      throw RangeError('Invalid write range');
    }
    using((arena) {
      final count = end - start;
      final buffer = arena<Uint8>(count == 0 ? 1 : count);
      buffer.asTypedList(count).setAll(0, data.skip(start).take(count));
      var written = 0;
      while (written < count) {
        final result =
            _pwrite(_fd, buffer + written, count - written, offset + written);
        if (result < 0 && _errno().value == 4) continue;
        if (result <= 0) {
          throw FileSystemException(
              'Cannot write torrent file', path, OSError('', _errno().value));
        }
        written += result;
      }
    });
  }

  @override
  void flush() {
    if (_fd < 0) throw StateError('File is closed');
    if (_fsync(_fd) != 0) {
      throw FileSystemException(
          'Cannot flush torrent file', path, OSError('', _errno().value));
    }
    if (_fsync(_parentFd) != 0) {
      throw FileSystemException(
          'Cannot sync torrent directory', path, OSError('', _errno().value));
    }
  }

  @override
  void close() {
    if (_fd < 0) return;
    final fd = _fd;
    final parentFd = _parentFd;
    _fd = -1;
    _parentFd = -1;
    final result = _close(fd);
    final error = result == 0 ? 0 : _errno().value;
    final parentResult = _close(parentFd);
    if (result != 0 || parentResult != 0) {
      throw FileSystemException('Cannot close torrent file', path,
          OSError('', result != 0 ? error : _errno().value));
    }
  }
}

/// Unlinks one entry relative to no-follow directory descriptors.
void unlinkBeneath(String root, String relative) {
  if (Platform.isWindows) {
    windowsUnlinkBeneath(root, relative);
    return;
  }
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

/// Moves one entry between no-follow directory descriptors.
void moveBeneath(String sourceRoot, String sourceRelative,
    String destinationRoot, String destinationRelative) {
  if (Platform.isWindows) {
    windowsMoveBeneath(
        sourceRoot, sourceRelative, destinationRoot, destinationRelative);
    return;
  }
  final abi = Abi.current();
  final apple =
      abi == Abi.macosArm64 || abi == Abi.macosX64 || abi == Abi.iosArm64;
  final android = abi == Abi.androidArm64;
  final arm64 = abi == Abi.linuxArm64 || android;
  if (!apple && !arm64 && abi != Abi.linuxX64) {
    throw UnsupportedError('Secure file moves are unavailable on $abi');
  }
  final sourceParts = sourceRelative.split('/');
  final destinationParts = destinationRelative.split('/');
  for (final part in [...sourceParts, ...destinationParts]) {
    validateTorrentPathComponent(part);
  }
  final directory = apple ? 0x100000 : (arm64 ? 0x4000 : 0x10000);
  final nofollow = apple ? 0x100 : (arm64 ? 0x8000 : 0x20000);
  final cloexec = apple ? 0x1000000 : 0x80000;
  final nonblock = apple ? 0x4 : 0x800;
  final create = apple ? 0x200 : 0x40;
  final truncate = apple ? 0x400 : 0x200;
  using((arena) {
    final errno = _libc
        .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
            apple ? '__error' : (android ? '__errno' : '__errno_location'));
    Never fail(String message) => throw FileSystemException(
        message, sourceRelative, OSError('', errno().value));
    int openParent(String root, List<String> parts) {
      var fd = _open(root.toNativeUtf8(allocator: arena), directory | cloexec);
      if (fd < 0) fail('Cannot open download directory');
      try {
        for (final part in parts.take(parts.length - 1)) {
          final next = _openAt(fd, part.toNativeUtf8(allocator: arena),
              directory | nofollow | cloexec);
          if (next < 0) fail('Cannot open torrent directory');
          _close(fd);
          fd = next;
        }
        return fd;
      } catch (_) {
        _close(fd);
        rethrow;
      }
    }

    void syncDirectories(int sourceParent, int destinationParent) {
      if (_fsync(sourceParent) != 0) fail('Cannot sync source directory');
      if (_fsync(destinationParent) != 0) {
        fail('Cannot sync destination directory');
      }
    }

    void copyFile(int sourceParent, Pointer<Utf8> sourceName,
        int destinationParent, Pointer<Utf8> destinationName) {
      final source =
          _openAt(sourceParent, sourceName, 2 | nofollow | cloexec | nonblock);
      if (source < 0) fail('Cannot open torrent file');
      var destination = -1;
      try {
        final stat = arena<Uint8>(512);
        if (_fstat(source, stat.cast()) != 0) fail('Cannot stat torrent file');
        final modeOffset = apple ? 4 : (abi == Abi.linuxX64 ? 24 : 16);
        final mode = apple
            ? (stat + modeOffset).cast<Uint16>().value
            : (stat + modeOffset).cast<Uint32>().value;
        if (mode & 0xf000 != 0x8000) {
          throw FileSystemException(
              'Torrent path is not a regular file', sourceRelative);
        }
        destination = _openAtCreate(destinationParent, destinationName,
            1 | create | truncate | nofollow | cloexec, 420);
        if (destination < 0) fail('Cannot create destination file');
        final buffer = arena<Uint8>(65536);
        var offset = 0;
        while (true) {
          final count = _pread(source, buffer, 65536, offset);
          if (count < 0) {
            if (errno().value == 4) continue;
            fail('Cannot read torrent file');
          }
          if (count == 0) break;
          var written = 0;
          while (written < count) {
            final result = _pwrite(destination, buffer + written,
                count - written, offset + written);
            if (result < 0 && errno().value == 4) continue;
            if (result <= 0) fail('Cannot write destination file');
            written += result;
          }
          offset += count;
        }
        if (_fsync(destination) != 0) fail('Cannot sync destination file');
      } catch (_) {
        if (destination >= 0) {
          _unlinkAt(destinationParent, destinationName, 0);
        }
        rethrow;
      } finally {
        _close(source);
        if (destination >= 0) _close(destination);
      }
    }

    final sourceParent = openParent(sourceRoot, sourceParts);
    var destinationParent = -1;
    try {
      destinationParent = openParent(destinationRoot, destinationParts);
      final sourceName = sourceParts.last.toNativeUtf8(allocator: arena);
      final destinationName =
          destinationParts.last.toNativeUtf8(allocator: arena);
      if (_renameAt(
              sourceParent, sourceName, destinationParent, destinationName) ==
          0) {
        syncDirectories(sourceParent, destinationParent);
        return;
      }
      if (errno().value != 18) fail('Cannot move torrent file');
      copyFile(sourceParent, sourceName, destinationParent, destinationName);
      if (_unlinkAt(sourceParent, sourceName, 0) != 0) {
        fail('Cannot delete moved torrent file');
      }
      syncDirectories(sourceParent, destinationParent);
    } finally {
      _close(sourceParent);
      if (destinationParent >= 0) _close(destinationParent);
    }
  });
}

/// Reads a range through no-follow directory descriptors on supported POSIX ABIs.
Uint8List readBeneath(String root, String relative, int offset, int length) {
  if (Platform.isWindows) {
    return windowsReadBeneath(root, relative, offset, length);
  }
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

/// Opens a torrent file for writing on the current platform.
SecureFileWriter openSecureWriter(String root, String relative, int length) {
  if (Platform.isWindows) {
    return WindowsSecureWriter.open(root, relative, length);
  }
  return PosixSecureWriter.open(root, relative, length);
}
