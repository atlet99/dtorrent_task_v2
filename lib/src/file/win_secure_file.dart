import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../torrent/safe_torrent_path.dart';
import 'secure_file_writer.dart';

DynamicLibrary? _ntdllLibrary;
DynamicLibrary get _ntdll => _ntdllLibrary ??= DynamicLibrary.open('ntdll.dll');
DynamicLibrary? _kernel32Library;
DynamicLibrary get _kernel32 =>
    _kernel32Library ??= DynamicLibrary.open('kernel32.dll');

final _ntCreateFile = _ntdll.lookupFunction<
    Int32 Function(Pointer<IntPtr>, Uint32, Pointer<Uint8>, Pointer<Uint8>,
        Pointer<Int64>, Uint32, Uint32, Uint32, Uint32, Pointer<Uint8>, Uint32),
    int Function(
        Pointer<IntPtr>,
        int,
        Pointer<Uint8>,
        Pointer<Uint8>,
        Pointer<Int64>,
        int,
        int,
        int,
        int,
        Pointer<Uint8>,
        int)>('NtCreateFile');
final _ntSetInformationFile = _ntdll.lookupFunction<
    Int32 Function(IntPtr, Pointer<Uint8>, Pointer<Uint8>, Uint32, Uint32),
    int Function(
        int, Pointer<Uint8>, Pointer<Uint8>, int, int)>('NtSetInformationFile');
final _rtlNtStatusToDosError =
    _ntdll.lookupFunction<Uint32 Function(Int32), int Function(int)>(
        'RtlNtStatusToDosError');

final _closeHandle = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('CloseHandle');
final _readFile = _kernel32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>),
    int Function(
        int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer<Uint8>)>('ReadFile');
final _writeFile = _kernel32.lookupFunction<
    Int32 Function(
        IntPtr, Pointer<Uint8>, Uint32, Pointer<Uint32>, Pointer<Uint8>),
    int Function(int, Pointer<Uint8>, int, Pointer<Uint32>,
        Pointer<Uint8>)>('WriteFile');
final _setFilePointerEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Int64, Pointer<Int64>, Uint32),
    int Function(int, int, Pointer<Int64>, int)>('SetFilePointerEx');
final _setEndOfFile = _kernel32
    .lookupFunction<Int32 Function(IntPtr), int Function(int)>('SetEndOfFile');
final _flushFileBuffers =
    _kernel32.lookupFunction<Int32 Function(IntPtr), int Function(int)>(
        'FlushFileBuffers');
final _getFileInformationByHandleEx = _kernel32.lookupFunction<
    Int32 Function(IntPtr, Uint32, Pointer<Uint8>, Uint32),
    int Function(
        int, int, Pointer<Uint8>, int)>('GetFileInformationByHandleEx');
final _getLastError =
    _kernel32.lookupFunction<Uint32 Function(), int Function()>('GetLastError');

const _shareAll = 0x7;
const _fileOpen = 1;
const _fileCreate = 2;
const _fileOverwriteIf = 5;
const _objCaseInsensitive = 0x40;
const _objDontReparse = 0x1000;
const _fileDirectoryFile = 0x1;
const _fileNonDirectoryFile = 0x40;
const _fileSynchronousIoNonAlert = 0x20;
const _fileOpenReparsePoint = 0x200000;
const _fileAttributeNormal = 0x80;
const _fileAttributeDirectory = 0x10;
const _fileAttributeReparsePoint = 0x400;
const _fileBegin = 0;
const _fileRenameInformation = 10;
const _fileDispositionInformation = 13;
const _fileAttributeTagInfo = 9;
const _fileStandardInfo = 1;
const _directoryAccess = 0x1000A1;
const _readAccess = 0x120089;
const _writeAccess = 0x120196;
const _deleteAccess = 0x10000 | 0x80 | 0x100000;
const _directoryOptions =
    _fileDirectoryFile | _fileSynchronousIoNonAlert | _fileOpenReparsePoint;
const _fileOptions =
    _fileNonDirectoryFile | _fileSynchronousIoNonAlert | _fileOpenReparsePoint;
const _statusObjectNameCollision = -1073741771;
const _statusObjectNameNotFound = -1073741772;
const _statusNotSameDevice = -1073741612;

void _ensureWindowsSupport() {
  // ponytail: reject 32-bit Windows, whose struct layouts are not handled.
  if (!Platform.isWindows || sizeOf<Pointer>() != 8) {
    throw UnsupportedError(
        'Secure file operations are unavailable on ${Abi.current()}');
  }
}

String _ntPath(String path) {
  if (path.startsWith(r'\\')) return '${r'\??\UNC\'}${path.substring(2)}';
  return r'\??\' + path;
}

FileSystemException _winError(int status, String path) {
  final code = _rtlNtStatusToDosError(status);
  return FileSystemException(
      'Secure file operation failed '
      '(NTSTATUS 0x${status.toUnsigned(32).toRadixString(16)})',
      path,
      OSError('', code));
}

FileSystemException _lastError(String path) => FileSystemException(
    'Secure file operation failed', path, OSError('', _getLastError()));

(int, int) _ntOpenRaw(Allocator arena, int parent, String name, int access,
    int disposition, int options,
    {bool dontReparse = true}) {
  final objectName = arena<Uint8>(16)..asTypedList(16).fillRange(0, 16, 0);
  final buffer = name.toNativeUtf16(allocator: arena);
  final length = name.length * 2;
  objectName.cast<Uint16>()[0] = length;
  objectName.cast<Uint16>()[1] = length;
  (objectName + 8).cast<Pointer<Uint16>>().value = buffer.cast<Uint16>();
  final attributes = arena<Uint8>(48)..asTypedList(48).fillRange(0, 48, 0);
  attributes.cast<Uint32>().value = 48;
  (attributes + 8).cast<IntPtr>().value = parent;
  (attributes + 16).cast<Pointer<Uint8>>().value = objectName;
  (attributes + 24).cast<Uint32>().value =
      _objCaseInsensitive | (parent != 0 && dontReparse ? _objDontReparse : 0);
  final ioStatus = arena<Uint8>(16)..asTypedList(16).fillRange(0, 16, 0);
  final handle = arena<IntPtr>(1)..value = 0;
  final status = _ntCreateFile(handle, access, attributes, ioStatus, nullptr,
      _fileAttributeNormal, _shareAll, disposition, options, nullptr, 0);
  return (status, status < 0 ? -1 : handle.value);
}

int _openRoot(Allocator arena, String root) {
  final (status, handle) = _ntOpenRaw(
      arena, 0, _ntPath(root), _directoryAccess, _fileOpen, _directoryOptions,
      dontReparse: false);
  if (status < 0) throw _winError(status, root);
  return handle;
}

int _openParent(Allocator arena, String root, List<String> parts,
    {bool create = false}) {
  var handle = _openRoot(arena, root);
  try {
    for (final part in parts.take(parts.length - 1)) {
      var (status, next) = _ntOpenRaw(
          arena, handle, part, _directoryAccess, _fileOpen, _directoryOptions);
      if (status == _statusObjectNameNotFound && create) {
        (status, next) = _ntOpenRaw(arena, handle, part, _directoryAccess,
            _fileCreate, _directoryOptions);
        if (status == _statusObjectNameCollision) {
          (status, next) = _ntOpenRaw(arena, handle, part, _directoryAccess,
              _fileOpen, _directoryOptions);
        }
      }
      if (status < 0) throw _winError(status, part);
      _closeHandle(handle);
      handle = next;
    }
    return handle;
  } catch (_) {
    _closeHandle(handle);
    rethrow;
  }
}

void _ensureRegularFile(Allocator arena, int handle, String path) {
  final buffer = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 0);
  if (_getFileInformationByHandleEx(handle, _fileAttributeTagInfo, buffer, 8) ==
      0) {
    throw _lastError(path);
  }
  final attributes = buffer.cast<Uint32>().value;
  if (attributes & _fileAttributeReparsePoint != 0 ||
      attributes & _fileAttributeDirectory != 0) {
    throw FileSystemException('Torrent path is not a regular file', path);
  }
}

List<String> _checkedParts(String relative) {
  final parts = relative.split('/');
  for (final part in parts) {
    validateTorrentPathComponent(part);
  }
  return parts;
}

/// Reads a range through NT relative opens that reject reparse points.
Uint8List windowsReadBeneath(
    String root, String relative, int offset, int length) {
  _ensureWindowsSupport();
  if (offset < 0 || length < 0) throw ArgumentError('Invalid read range');
  final parts = _checkedParts(relative);
  return using((arena) {
    final parent = _openParent(arena, root, parts);
    var handle = -1;
    try {
      final (status, opened) = _ntOpenRaw(
          arena, parent, parts.last, _readAccess, _fileOpen, _fileOptions,
          dontReparse: false);
      if (status < 0) throw _winError(status, relative);
      handle = opened;
      _ensureRegularFile(arena, handle, relative);
      if (_setFilePointerEx(handle, offset, nullptr, _fileBegin) == 0) {
        throw _lastError(relative);
      }
      final buffer = arena<Uint8>(length == 0 ? 1 : length);
      final count = arena<Uint32>(1);
      var total = 0;
      while (total < length) {
        if (_readFile(handle, buffer + total, length - total, count, nullptr) ==
            0) {
          throw _lastError(relative);
        }
        if (count.value == 0) break;
        total += count.value;
      }
      return Uint8List.fromList(buffer.asTypedList(total));
    } finally {
      if (handle >= 0) _closeHandle(handle);
      _closeHandle(parent);
    }
  });
}

/// Returns the size of one regular file beneath [root], or null if absent.
int? windowsSizeBeneath(String root, String relative) {
  _ensureWindowsSupport();
  final parts = _checkedParts(relative);
  return using((arena) {
    final parent = _openParent(arena, root, parts);
    var handle = -1;
    try {
      final (status, opened) = _ntOpenRaw(
          arena, parent, parts.last, _readAccess, _fileOpen, _fileOptions,
          dontReparse: false);
      if (status == _statusObjectNameNotFound) return null;
      if (status < 0) throw _winError(status, relative);
      handle = opened;
      _ensureRegularFile(arena, handle, relative);
      final buffer = arena<Uint8>(32)..asTypedList(32).fillRange(0, 32, 0);
      if (_getFileInformationByHandleEx(
              handle, _fileStandardInfo, buffer, 32) ==
          0) {
        throw _lastError(relative);
      }
      return (buffer + 8).cast<Int64>().value;
    } finally {
      if (handle >= 0) _closeHandle(handle);
      _closeHandle(parent);
    }
  });
}

/// Unlinks one entry through NT relative opens without following reparse points.
void windowsUnlinkBeneath(String root, String relative) {
  _ensureWindowsSupport();
  final parts = _checkedParts(relative);
  using((arena) {
    final parent = _openParent(arena, root, parts);
    var handle = -1;
    try {
      final (status, opened) = _ntOpenRaw(
          arena, parent, parts.last, _deleteAccess, _fileOpen, _fileOptions,
          dontReparse: false);
      if (status < 0) throw _winError(status, relative);
      handle = opened;
      final buffer = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 0);
      if (_getFileInformationByHandleEx(
              handle, _fileAttributeTagInfo, buffer, 8) ==
          0) {
        throw _lastError(relative);
      }
      final attributes = buffer.cast<Uint32>().value;
      if (attributes & _fileAttributeDirectory != 0 &&
          attributes & _fileAttributeReparsePoint == 0) {
        throw FileSystemException(
            'Torrent path is not a regular file', relative);
      }
      final disposition = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 0);
      disposition.value = 1;
      final ioStatus = arena<Uint8>(16)..asTypedList(16).fillRange(0, 16, 0);
      final result = _ntSetInformationFile(
          handle, ioStatus, disposition, 1, _fileDispositionInformation);
      if (result < 0) throw _winError(result, relative);
    } finally {
      if (handle >= 0) _closeHandle(handle);
      _closeHandle(parent);
    }
  });
}

/// Moves one entry between NT relative opens without following reparse points.
void windowsMoveBeneath(String sourceRoot, String sourceRelative,
    String destinationRoot, String destinationRelative) {
  _ensureWindowsSupport();
  final sourceParts = _checkedParts(sourceRelative);
  final destinationParts = _checkedParts(destinationRelative);
  using((arena) {
    final sourceParent = _openParent(arena, sourceRoot, sourceParts);
    var destinationParent = -1;
    var source = -1;
    try {
      destinationParent = _openParent(arena, destinationRoot, destinationParts);
      final (openStatus, opened) = _ntOpenRaw(
          arena,
          sourceParent,
          sourceParts.last,
          _deleteAccess | _readAccess,
          _fileOpen,
          _fileOptions,
          dontReparse: false);
      if (openStatus < 0) throw _winError(openStatus, sourceRelative);
      source = opened;
      final name = destinationParts.last;
      final nameBytes = name.length * 2;
      final info = arena<Uint8>(32 + nameBytes)
        ..asTypedList(32 + nameBytes).fillRange(0, 32 + nameBytes, 0);
      info.value = 1;
      (info + 8).cast<IntPtr>().value = destinationParent;
      (info + 16).cast<Uint32>().value = nameBytes;
      (info + 20)
          .cast<Uint16>()
          .asTypedList(name.length)
          .setAll(0, name.codeUnits);
      final ioStatus = arena<Uint8>(16)..asTypedList(16).fillRange(0, 16, 0);
      final status = _ntSetInformationFile(
          source, ioStatus, info, 20 + nameBytes, _fileRenameInformation);
      if (status >= 0) return;
      if (status != _statusNotSameDevice) {
        throw _winError(status, sourceRelative);
      }
      _copyToDestination(
          arena, source, destinationParent, name, sourceRelative);
      final disposition = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 0);
      disposition.value = 1;
      final deleted = _ntSetInformationFile(
          source, ioStatus, disposition, 1, _fileDispositionInformation);
      if (deleted < 0) throw _winError(deleted, sourceRelative);
    } finally {
      if (source >= 0) _closeHandle(source);
      _closeHandle(sourceParent);
      if (destinationParent >= 0) _closeHandle(destinationParent);
    }
  });
}

void _copyToDestination(Allocator arena, int source, int destinationParent,
    String name, String path) {
  var destination = -1;
  try {
    final (status, opened) = _ntOpenRaw(arena, destinationParent, name,
        _writeAccess, _fileOverwriteIf, _fileOptions,
        dontReparse: false);
    if (status < 0) throw _winError(status, path);
    destination = opened;
    _ensureRegularFile(arena, destination, path);
    if (_setFilePointerEx(source, 0, nullptr, _fileBegin) == 0) {
      throw _lastError(path);
    }
    if (_setFilePointerEx(destination, 0, nullptr, _fileBegin) == 0) {
      throw _lastError(path);
    }
    final buffer = arena<Uint8>(65536);
    final count = arena<Uint32>(1);
    while (true) {
      if (_readFile(source, buffer, 65536, count, nullptr) == 0) {
        throw _lastError(path);
      }
      final read = count.value;
      if (read == 0) break;
      var written = 0;
      while (written < read) {
        if (_writeFile(destination, buffer + written, read - written, count,
                nullptr) ==
            0) {
          throw _lastError(path);
        }
        if (count.value <= 0) {
          throw FileSystemException('Cannot write destination file', path);
        }
        written += count.value;
      }
    }
    if (_flushFileBuffers(destination) == 0) throw _lastError(path);
  } catch (_) {
    if (destination >= 0) {
      _closeHandle(destination);
      destination = -1;
      final (status, opened) = _ntOpenRaw(arena, destinationParent, name,
          _deleteAccess, _fileOpen, _fileOptions,
          dontReparse: false);
      if (status >= 0) {
        final disposition = arena<Uint8>(8)..asTypedList(8).fillRange(0, 8, 0);
        disposition.value = 1;
        final ioStatus = arena<Uint8>(16)..asTypedList(16).fillRange(0, 16, 0);
        _ntSetInformationFile(
            opened, ioStatus, disposition, 1, _fileDispositionInformation);
        _closeHandle(opened);
      }
    }
    rethrow;
  } finally {
    if (destination >= 0) _closeHandle(destination);
  }
}

/// A regular file opened without following reparse points beneath a trusted
/// directory.
final class WindowsSecureWriter implements SecureFileWriter {
  WindowsSecureWriter._(this._handle, this.path);

  int _handle;
  final String path;

  static WindowsSecureWriter open(String root, String relative, int length) {
    _ensureWindowsSupport();
    if (length < 0) throw ArgumentError.value(length, 'length');
    final parts = _checkedParts(relative);
    return using((arena) {
      final parent = _openParent(arena, root, parts, create: true);
      try {
        var (status, handle) = _ntOpenRaw(
            arena, parent, parts.last, _writeAccess, _fileCreate, _fileOptions,
            dontReparse: false);
        final created = status >= 0;
        if (status == _statusObjectNameCollision) {
          (status, handle) = _ntOpenRaw(
              arena, parent, parts.last, _writeAccess, _fileOpen, _fileOptions,
              dontReparse: false);
        }
        if (status < 0) throw _winError(status, relative);
        try {
          _ensureRegularFile(arena, handle, relative);
          if (created) {
            if (_setFilePointerEx(handle, length, nullptr, _fileBegin) == 0) {
              throw _lastError(relative);
            }
            if (_setEndOfFile(handle) == 0) throw _lastError(relative);
          }
          return WindowsSecureWriter._(handle, relative);
        } catch (_) {
          _closeHandle(handle);
          rethrow;
        }
      } finally {
        _closeHandle(parent);
      }
    });
  }

  @override
  void write(int offset, List<int> data, int start, int end) {
    if (_handle < 0) throw StateError('File is closed');
    if (offset < 0 || start < 0 || end < start || end > data.length) {
      throw RangeError('Invalid write range');
    }
    using((arena) {
      final count = end - start;
      final buffer = arena<Uint8>(count == 0 ? 1 : count);
      buffer.asTypedList(count).setAll(0, data.skip(start).take(count));
      if (_setFilePointerEx(_handle, offset, nullptr, _fileBegin) == 0) {
        throw _lastError(path);
      }
      final written = arena<Uint32>(1);
      var total = 0;
      while (total < count) {
        if (_writeFile(
                _handle, buffer + total, count - total, written, nullptr) ==
            0) {
          throw _lastError(path);
        }
        if (written.value <= 0) {
          throw FileSystemException('Cannot write torrent file', path);
        }
        total += written.value;
      }
    });
  }

  @override
  void flush() {
    if (_handle < 0) throw StateError('File is closed');
    if (_flushFileBuffers(_handle) == 0) throw _lastError(path);
  }

  @override
  void close() {
    if (_handle < 0) return;
    final handle = _handle;
    _handle = -1;
    if (_closeHandle(handle) == 0) throw _lastError(path);
  }
}
