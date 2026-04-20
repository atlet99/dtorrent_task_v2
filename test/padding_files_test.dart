import 'dart:io';
import 'dart:typed_data';

import 'package:b_encode_decode/b_encode_decode.dart';
import 'package:crypto/crypto.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:dtorrent_task_v2/src/piece/base_piece_selector.dart';
import 'package:test/test.dart';

class _FakeStateFile {
  final Bitfield bitfield;
  int downloaded = 0;

  _FakeStateFile(int piecesNum)
      : bitfield = Bitfield.createEmptyBitfield(piecesNum);

  Future<bool> updateBitfield(int index, bool have) async {
    bitfield.setBit(index, have);
    return true;
  }

  Future<bool> updateUploaded(int uploaded) async => true;

  Future<void> close() async {}

  Future<void> delete() async {}
}

void main() {
  group('Padding files and attributes (BEP 47)', () {
    test('parses v1 attr and detects padding by name/attr', () {
      final pieces = Uint8List(20); // one SHA-1 hash placeholder
      final torrentMap = <String, dynamic>{
        'announce': 'http://tracker.example.org/announce',
        'info': <String, dynamic>{
          'name': 'sample',
          'piece length': 4,
          'pieces': pieces,
          'files': <Map<String, dynamic>>[
            <String, dynamic>{
              'length': 2,
              'path': <String>['real.bin'],
            },
            <String, dynamic>{
              'length': 2,
              'path': <String>['_____padding_file_0_____'],
            },
            <String, dynamic>{
              'length': 1,
              'path': <String>['attr_padding.bin'],
              'attr': 'p',
            },
          ],
        },
      };

      final model =
          TorrentParser.parseBytes(Uint8List.fromList(encode(torrentMap)));
      expect(model.files.length, 3);
      expect(model.files[0].isPaddingFile, isFalse);
      expect(model.files[1].isPaddingFile, isTrue); // by BEP47 naming
      expect(model.files[2].isPaddingFile, isTrue); // by attr = p
      expect(model.files[2].attributes?.isPadding, isTrue);
    });

    test('parses symlink metadata from torrent file entries', () {
      final pieces = Uint8List(20);
      final torrentMap = <String, dynamic>{
        'announce': 'http://tracker.example.org/announce',
        'info': <String, dynamic>{
          'name': 'sample',
          'piece length': 4,
          'pieces': pieces,
          'files': <Map<String, dynamic>>[
            <String, dynamic>{
              'length': 0,
              'path': <String>['link.txt'],
              'attr': 'l',
              'symlink path': <String>['target.txt'],
            },
          ],
        },
      };

      final model =
          TorrentParser.parseBytes(Uint8List.fromList(encode(torrentMap)));
      expect(model.files.length, 1);
      expect(model.files.first.attributes?.isSymlink, isTrue);
      expect(model.files.first.symlinkPath, <String>['target.txt']);
    });

    test('parses v2 file tree attr and exposes attributes', () {
      final torrentMap = <String, dynamic>{
        'announce': 'http://tracker.example.org/announce',
        'info': <String, dynamic>{
          'name': 'v2-sample',
          'piece length': 16,
          'meta version': 2,
          'file tree': <String, dynamic>{
            'pad.bin': <String, dynamic>{
              '': <String, dynamic>{'length': 1, 'attr': 'p'},
            },
            'run.sh': <String, dynamic>{
              '': <String, dynamic>{'length': 2, 'attr': 'x'},
            },
          },
        },
      };

      final model =
          TorrentParser.parseBytes(Uint8List.fromList(encode(torrentMap)));
      expect(model.files.length, 2);
      final pad = model.files.firstWhere((f) => f.path.endsWith('pad.bin'));
      final exec = model.files.firstWhere((f) => f.path.endsWith('run.sh'));
      expect(pad.isPaddingFile, isTrue);
      expect(pad.attributes?.isPadding, isTrue);
      expect(exec.attributes?.isExecutable, isTrue);
    });

    test('DownloadFileManager keeps padding files virtual (no disk file)',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dtorrent_padding_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final files = <TorrentFileModel>[
        TorrentFileModel(path: 'content.bin', length: 2, offset: 0),
        TorrentFileModel(
          path: '_____padding_file_0_____',
          length: 2,
          offset: 2,
          attributes: FileAttributes.parse('p'),
        ),
      ];
      final model = TorrentModel(
        name: 'padding',
        files: files,
        infoHashBuffer: Uint8List(20),
        pieceLength: 4,
        pieces: <Uint8List>[Uint8List(20)],
        announces: const <Uri>[],
        nodes: const <Uri>[],
        version: TorrentVersion.v1,
      );
      final state = _FakeStateFile(1);
      final pieces = <Piece>[Piece('00' * 20, 0, 4, 0)];

      final manager = await DownloadFileManager.createFileManager(
        model,
        tempDir.path,
        state,
        pieces,
      );
      addTearDown(() async {
        await manager.close();
      });

      final writeOk = await manager.writeFile(0, 0, <int>[1, 2, 0, 0]);
      expect(writeOk, isTrue);

      final realFile =
          File('${tempDir.path}${Platform.pathSeparator}content.bin');
      final paddingFile = File(
          '${tempDir.path}${Platform.pathSeparator}_____padding_file_0_____');

      expect(await realFile.exists(), isTrue);
      expect(await realFile.length(), 2);
      expect(await paddingFile.exists(), isFalse);

      final readPadding = await manager.readFile(0, 2, 2);
      expect(readPadding, <int>[0, 0]);
    });

    test('FileValidator validates piece with missing padding file via zeros',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dtorrent_padding_val_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final realFile =
          File('${tempDir.path}${Platform.pathSeparator}content.bin');
      await realFile.writeAsBytes(<int>[1, 2], flush: true);

      final files = <TorrentFileModel>[
        TorrentFileModel(path: 'content.bin', length: 2, offset: 0),
        TorrentFileModel(
          path: '_____padding_file_0_____',
          length: 2,
          offset: 2,
          attributes: FileAttributes.parse('p'),
        ),
      ];
      final pieceBytes = Uint8List.fromList(<int>[1, 2, 0, 0]);
      final digest = sha1.convert(pieceBytes).bytes;
      final hashHex =
          digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
      final piece = Piece(hashHex, 0, 4, 0, isComplete: true);

      final model = TorrentModel(
        name: 'padding',
        files: files,
        infoHashBuffer: Uint8List(20),
        pieceLength: 4,
        pieces: <Uint8List>[Uint8List.fromList(digest)],
        announces: const <Uri>[],
        nodes: const <Uri>[],
        version: TorrentVersion.v1,
      );

      final validator = FileValidator(
        model,
        <Piece>[piece],
        '${tempDir.path}${Platform.pathSeparator}',
      );

      expect(await validator.quickValidate(), isTrue);
      expect(await validator.validatePiece(0), isTrue);
    });

    test('PieceManager auto-completes padding-only piece with zero hash', () {
      final bytes = Uint8List(4); // all zeros
      final digest = sha1.convert(bytes).bytes;
      final model = TorrentModel(
        name: 'padding-only',
        files: <TorrentFileModel>[
          TorrentFileModel(
            path: '_____padding_file_0_____',
            length: 4,
            offset: 0,
            attributes: FileAttributes.parse('p'),
          ),
        ],
        infoHashBuffer: Uint8List(20),
        pieceLength: 4,
        pieces: <Uint8List>[Uint8List.fromList(digest)],
        announces: const <Uri>[],
        nodes: const <Uri>[],
        version: TorrentVersion.v1,
      );

      final bitfield = Bitfield.createEmptyBitfield(1);
      final manager =
          PieceManager.createPieceManager(BasePieceSelector(), model, bitfield);

      expect(bitfield.getBit(0), isTrue);
      expect(manager[0]?.isCompletelyWritten, isTrue);
    });

    test('DownloadFileManager restores executable and symlink attributes',
        () async {
      final tempDir =
          await Directory.systemTemp.createTemp('dtorrent_attr_restore_');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final basePath = '${tempDir.path}${Platform.pathSeparator}';
      final targetPath = '${basePath}target.bin';
      await File(targetPath).writeAsBytes(<int>[7], flush: true);

      final model = TorrentModel(
        name: 'attrs',
        files: <TorrentFileModel>[
          TorrentFileModel(
            path: 'target.bin',
            length: 1,
            offset: 0,
            attributes: FileAttributes.parse('x'),
          ),
          TorrentFileModel(
            path: 'link.bin',
            length: 0,
            offset: 1,
            attributes: FileAttributes.parse('l'),
            symlinkPath: const <String>['target.bin'],
          ),
        ],
        infoHashBuffer: Uint8List(20),
        pieceLength: 1,
        pieces: <Uint8List>[Uint8List(20)],
        announces: const <Uri>[],
        nodes: const <Uri>[],
        version: TorrentVersion.v1,
      );

      final manager = await DownloadFileManager.createFileManager(
        model,
        tempDir.path,
        _FakeStateFile(1),
        <Piece>[Piece('00' * 20, 0, 1, 0)],
      );
      addTearDown(() async {
        await manager.close();
      });

      if (!Platform.isWindows) {
        final stat = await File(targetPath).stat();
        expect((stat.modeString().contains('x')), isTrue);

        final link = Link('${basePath}link.bin');
        expect(await link.exists(), isTrue);
      }
    });
  });
}
