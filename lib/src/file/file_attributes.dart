/// BEP 47 file attributes helper.
///
/// Attribute flags are stored as a compact string where each character is a
/// one-letter capability marker.
class FileAttributes {
  final Set<String> flags;

  const FileAttributes._(this.flags);

  static FileAttributes? parse(dynamic value) {
    if (value == null) return null;
    String raw;
    if (value is String) {
      raw = value;
    } else if (value is List<int>) {
      raw = String.fromCharCodes(value);
    } else {
      raw = value.toString();
    }
    if (raw.isEmpty) return null;

    final parsedFlags = <String>{};
    for (var i = 0; i < raw.length; i++) {
      final flag = raw[i];
      if (flag.trim().isEmpty) continue;
      parsedFlags.add(flag);
    }
    if (parsedFlags.isEmpty) return null;
    return FileAttributes._(parsedFlags);
  }

  bool hasFlag(String flag) => flags.contains(flag);

  /// BEP 47 padding marker.
  bool get isPadding => hasFlag('p');

  /// Symlink marker used in BEP 47 ecosystems.
  bool get isSymlink => hasFlag('l');

  /// Executable marker used in BEP 47 ecosystems.
  bool get isExecutable => hasFlag('x');

  /// Hidden marker used in BEP 47 ecosystems.
  bool get isHidden => hasFlag('h');

  String toAttrString() {
    final sorted = flags.toList()..sort();
    return sorted.join();
  }

  static bool isPaddingFileName(String fileName) {
    final pattern = RegExp(r'^_____padding_file_\d+_____$');
    return pattern.hasMatch(fileName);
  }

  static bool isPaddingFilePath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final fileName = normalized.split('/').last;
    return isPaddingFileName(fileName);
  }

  static bool detectPadding(String path, FileAttributes? attributes) {
    if (attributes?.isPadding == true) return true;
    return isPaddingFilePath(path);
  }

  @override
  String toString() => toAttrString();
}
