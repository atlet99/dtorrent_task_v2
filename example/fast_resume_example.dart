import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';

var _log = Logger('FastResumeExample');

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.message}');
  });

  final parser = ArgParser()
    ..addOption('torrent', abbr: 't', help: 'Path to torrent file')
    ..addOption('save-path',
        abbr: 's', defaultsTo: 'tmp', help: 'Path where torrent will be saved')
    ..addFlag('validate',
        abbr: 'v', defaultsTo: false, help: 'Validate files on resume')
    ..addFlag('recover',
        abbr: 'r',
        defaultsTo: false,
        help: 'Attempt to recover from corrupted state file')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help');

  ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print('Error parsing arguments: $e');
    print(parser.usage);
    exit(1);
  }

  if (results['help']) {
    print('Fast Resume Example');
    print('');
    print('Usage: dart run example/fast_resume_example.dart [options]');
    print('');
    print(parser.usage);
    exit(0);
  }

  final torrentFile = results['torrent'] as String?;
  final savePath = results['save-path'] as String;
  final validate = results['validate'] as bool;
  final recover = results['recover'] as bool;

  if (torrentFile == null) {
    print('Error: Torrent file is required');
    print('Use --torrent or -t to specify torrent file');
    print('');
    print(parser.usage);
    exit(1);
  }

  if (!await File(torrentFile).exists()) {
    print('Error: Torrent file not found: $torrentFile');
    exit(1);
  }

  try {
    final torrent = await Torrent.parse(torrentFile);
    _log.info('Loaded torrent: ${torrent.name}');

    // Ensure save directory exists
    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      await saveDir.create(recursive: true);
      _log.info('Created save directory: $savePath');
    }

    // Load or create state file
    _log.info('Loading state file...');
    final stateFile = await StateFileV2.getStateFile(savePath, torrent);

    if (stateFile.isValid) {
      _log.info('State file is valid (version: ${stateFile.version})');
      if (stateFile.lastModified != null) {
        _log.info('Last modified: ${stateFile.lastModified}');
      }
    } else {
      _log.warning('State file validation failed');
      if (recover) {
        _log.info('Attempting recovery...');
        // Recovery would be implemented here
        _log.info('Recovery not yet fully implemented in this example');
      }
    }

    // Validate files if requested
    if (validate) {
      _log.info('Validating downloaded files...');
      _log.info('File validation requires a running task with pieces');
      _log.info(
          'Use validateOnResume option when creating DownloadFileManager');
    }

    _log.info('State file loaded successfully');
    _log.info('Downloaded: ${stateFile.downloaded} bytes');
    _log.info('Uploaded: ${stateFile.uploaded} bytes');
    _log.info(
        'Completed pieces: ${stateFile.bitfield.completedPieces.length} / ${stateFile.bitfield.piecesNum}');

    await stateFile.close();
  } catch (e, stackTrace) {
    _log.severe('Error', e, stackTrace);
    exit(1);
  }
}
