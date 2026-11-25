import 'dart:io';

import 'package:path/path.dart' as p;

void validateTorrentPathComponent(String component) {
  if (component.isEmpty ||
      component == '.' ||
      component == '..' ||
      component.endsWith('.') ||
      component.endsWith(' ') ||
      RegExp(r'^(con|prn|aux|nul|com[1-9]|lpt[1-9])(\.|$)',
              caseSensitive: false)
          .hasMatch(component) ||
      component.contains(RegExp(r'[/\\:\x00]'))) {
    throw FormatException('Invalid torrent path component: $component');
  }
}

String resolveTorrentPath(String root, String relative) {
  for (final component in relative.split('/')) {
    validateTorrentPathComponent(component);
  }
  final base = p.normalize(p.absolute(root));
  final result = p.normalize(p.joinAll([base, ...relative.split('/')]));
  if (!p.isWithin(base, result)) {
    throw FormatException('Torrent path escapes download directory: $relative');
  }
  return result;
}

Future<void> rejectSymlinks(String root, String path) async {
  // shortcut: checks are not atomic with open; use no-follow directory handles to prevent concurrent swaps.
  final base = p.normalize(p.absolute(root));
  final target = p.normalize(p.absolute(path));
  if (!p.isWithin(base, target)) {
    throw FileSystemException('Path outside download directory', path);
  }
  var current = base;
  for (final part in p.split(p.relative(target, from: base))) {
    current = p.join(current, part);
    if (await FileSystemEntity.type(current, followLinks: false) ==
        FileSystemEntityType.link) {
      throw FileSystemException('Symbolic link in torrent path', current);
    }
  }
}
