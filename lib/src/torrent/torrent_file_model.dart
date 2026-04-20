import 'package:dtorrent_task_v2/src/file/file_attributes.dart';

/// Represents a file in a torrent (v1 format)
/// Compatible with TorrentFile from dtorrent_parser
class TorrentFileModel {
  /// File path (relative to torrent root)
  final String path;

  /// File name (last component of path)
  String get name => path.split('/').last;

  /// File length in bytes
  final int length;

  /// File offset in the torrent (for v1 format)
  final int offset;

  /// Optional BEP 47 attributes.
  final FileAttributes? attributes;

  /// True for BEP 47 padding files.
  final bool isPaddingFile;

  /// Optional BEP 47 symlink target path (path segments).
  final List<String>? symlinkPath;

  /// End position of the file
  int get end => offset + length;

  TorrentFileModel({
    required this.path,
    required this.length,
    required this.offset,
    this.attributes,
    this.symlinkPath,
    bool? isPaddingFile,
  }) : isPaddingFile =
            isPaddingFile ?? FileAttributes.detectPadding(path, attributes);

  @override
  String toString() =>
      'TorrentFileModel(path: $path, length: $length, offset: $offset, '
      'isPaddingFile: $isPaddingFile, attr: ${attributes?.toAttrString()})';
}
