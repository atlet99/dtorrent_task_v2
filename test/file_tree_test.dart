import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/torrent/file_tree.dart';

void main() {
  group('FileTreeHelper', () {
    test('Parse simple file tree with single file', () {
      // Create a simple file tree structure
      final fileTreeData = {
        'file.txt': {
          '': {
            'length': 1024,
            'pieces root': Uint8List.fromList(List.filled(32, 0xAA)),
          }
        }
      };

      final tree = FileTreeHelper.parseFileTree(fileTreeData);
      expect(tree, isNotNull);
      expect(tree!.length, equals(1));
      expect(tree.containsKey('file.txt'), isTrue);

      final entry = tree['file.txt']!;
      expect(entry.isFile, isTrue);
      expect(entry.length, equals(1024));
      expect(entry.piecesRoot, isNotNull);
      expect(entry.piecesRoot!.length, equals(32));
    });

    test('Parse file tree with directory structure', () {
      final fileTreeData = {
        'dir1': {
          'dir2': {
            'file.txt': {
              '': {
                'length': 2048,
                'pieces root': Uint8List.fromList(List.filled(32, 0xBB)),
              }
            },
            'file2.txt': {
              '': {
                'length': 512,
                'pieces root': Uint8List.fromList(List.filled(32, 0xCC)),
              }
            }
          }
        }
      };

      final tree = FileTreeHelper.parseFileTree(fileTreeData);
      expect(tree, isNotNull);
      expect(tree!.length, equals(1));
      expect(tree.containsKey('dir1'), isTrue);

      final dir1 = tree['dir1']!;
      expect(dir1.isDirectory, isTrue);
      expect(dir1.children, isNotNull);
      expect(dir1.children!.length, equals(1));
      expect(dir1.children!.containsKey('dir2'), isTrue);

      final dir2 = dir1.children!['dir2']!;
      expect(dir2.isDirectory, isTrue);
      expect(dir2.children!.length, equals(2));
    });

    test('Extract files from file tree', () {
      final fileTreeData = {
        'dir1': {
          'file1.txt': {
            '': {
              'length': 1024,
              'pieces root': Uint8List.fromList(List.filled(32, 0xAA)),
            }
          },
          'dir2': {
            'file2.txt': {
              '': {
                'length': 2048,
                'pieces root': Uint8List.fromList(List.filled(32, 0xBB)),
              }
            }
          }
        }
      };

      final tree = FileTreeHelper.parseFileTree(fileTreeData);
      expect(tree, isNotNull);

      final files = FileTreeHelper.extractFiles(tree!, '');
      expect(files.length, equals(2));
      expect(files[0].path, equals('dir1/file1.txt'));
      expect(files[0].length, equals(1024));
      expect(files[1].path, equals('dir1/dir2/file2.txt'));
      expect(files[1].length, equals(2048));
    });

    test('Calculate total size from file tree', () {
      final fileTreeData = {
        'file1.txt': {
          '': {
            'length': 1024,
            'pieces root': Uint8List.fromList(List.filled(32, 0xAA)),
          }
        },
        'file2.txt': {
          '': {
            'length': 2048,
            'pieces root': Uint8List.fromList(List.filled(32, 0xBB)),
          }
        },
        'dir1': {
          'file3.txt': {
            '': {
              'length': 512,
              'pieces root': Uint8List.fromList(List.filled(32, 0xCC)),
            }
          }
        }
      };

      final tree = FileTreeHelper.parseFileTree(fileTreeData);
      expect(tree, isNotNull);

      final totalSize = FileTreeHelper.calculateTotalSize(tree!);
      expect(totalSize, equals(1024 + 2048 + 512));
    });

    test('Parse empty file tree returns null', () {
      final tree = FileTreeHelper.parseFileTree({});
      expect(tree, isNull);
    });

    test('Parse invalid file tree returns null', () {
      final tree = FileTreeHelper.parseFileTree('not a map');
      expect(tree, isNull);
    });

    test('File entry with invalid pieces root length throws', () {
      expect(() {
        FileTreeEntry.file(1024, Uint8List(20)); // Wrong length
      }, throwsArgumentError);
    });

    test('File entry with null pieces root is valid', () {
      final entry = FileTreeEntry.file(1024, null);
      expect(entry.isFile, isTrue);
      expect(entry.length, equals(1024));
      expect(entry.piecesRoot, isNull);
    });
  });
}
