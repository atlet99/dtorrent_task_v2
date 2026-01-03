import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_parser/dtorrent_parser.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:logging/logging.dart';

var _log = Logger('SuperseedingExample');

void main(List<String> args) async {
  Logger.root.level = Level.INFO;
  Logger.root.onRecord.listen((record) {
    print('[${record.level.name}] ${record.message}');
  });

  final parser = ArgParser()
    ..addOption('torrent',
        abbr: 't', help: 'Path to torrent file (must be complete/seeding)')
    ..addOption('save-path',
        abbr: 's',
        defaultsTo: 'tmp',
        help: 'Path where torrent files are located')
    ..addFlag('enable',
        abbr: 'e', defaultsTo: false, help: 'Enable superseeding mode')
    ..addFlag('disable',
        abbr: 'd', defaultsTo: false, help: 'Disable superseeding mode')
    ..addFlag('status',
        abbr: 'S', defaultsTo: false, help: 'Show superseeding status')
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
    print('Superseeding Example (BEP 16)');
    print('');
    print('Superseeding is a seeding algorithm designed to help a torrent');
    print('initiator with limited bandwidth "pump up" a large torrent,');
    print('reducing the amount of data it needs to upload in order to spawn');
    print('new seeds in the torrent.');
    print('');
    print('IMPORTANT: Superseeding is NOT recommended for general use.');
    print('It should only be used for initial seeding when you are the only');
    print('or primary seeder.');
    print('');
    print('Usage: dart run example/superseeding_example.dart [options]');
    print('');
    print(parser.usage);
    print('');
    print('Examples:');
    print('  # Enable superseeding for a completed torrent');
    print('  dart run example/superseeding_example.dart -t my.torrent -e');
    print('');
    print('  # Check superseeding status');
    print('  dart run example/superseeding_example.dart -t my.torrent -S');
    print('');
    print('  # Disable superseeding');
    print('  dart run example/superseeding_example.dart -t my.torrent -d');
    exit(0);
  }

  final torrentFile = results['torrent'] as String?;
  final savePath = results['save-path'] as String;
  final enable = results['enable'] as bool;
  final disable = results['disable'] as bool;
  final status = results['status'] as bool;

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

  if (enable && disable) {
    print('Error: Cannot enable and disable superseeding at the same time');
    exit(1);
  }

  try {
    final torrent = await Torrent.parse(torrentFile);
    _log.info('Loaded torrent: ${torrent.name}');
    _log.info(
        'Total size: ${(torrent.length / 1024 / 1024).toStringAsFixed(2)} MB');
    _log.info('Pieces: ${torrent.pieces.length}');

    // Ensure save directory exists
    final saveDir = Directory(savePath);
    if (!await saveDir.exists()) {
      print('Error: Save directory does not exist: $savePath');
      print(
          'The torrent files must already be in this directory (seeding mode)');
      exit(1);
    }

    // Create task (must be in seeding mode - all files complete)
    _log.info('Creating torrent task...');
    final task = TorrentTask.newTask(torrent, savePath);

    // Wait a bit for task to initialize
    await Future.delayed(const Duration(seconds: 2));

    // Check if task is a seeder
    if (task.fileManager == null || !task.fileManager!.isAllComplete) {
      print('');
      print('WARNING: Torrent is not complete. Superseeding only works when');
      print('the client is a seeder (has all pieces).');
      print('');
      print('Please ensure:');
      print('  1. All torrent files are present in: $savePath');
      print('  2. All files are complete and valid');
      print('  3. The torrent has been fully downloaded');
      print('');
      exit(1);
    }

    _log.info('Torrent is complete - client is a seeder');

    if (status) {
      print('');
      print('Superseeding Status:');
      print('  Enabled: ${task.isSuperseedingEnabled}');
      print('');
      if (task.isSuperseedingEnabled) {
        print('Superseeding is currently ENABLED');
        print('');
        print('In superseeding mode:');
        print('  - The seeder masquerades as a peer with no data');
        print('  - Only rare pieces are offered to peers, one at a time');
        print('  - Next piece is offered only after previous is distributed');
        print('  - This reduces redundant uploads and improves efficiency');
      } else {
        print('Superseeding is currently DISABLED');
        print('Use --enable or -e to enable superseeding');
      }
      print('');
    }

    if (enable) {
      if (task.isSuperseedingEnabled) {
        print('Superseeding is already enabled');
      } else {
        _log.info('Enabling superseeding...');
        task.enableSuperseeding();
        print('');
        print('✓ Superseeding enabled successfully!');
        print('');
        print('The seeder will now:');
        print('  - Masquerade as a peer with no data (no bitfield sent)');
        print('  - Offer only rare pieces to peers, one at a time');
        print('  - Wait for piece distribution before offering next piece');
        print('');
        print('This mode is optimized for initial seeding when you are the');
        print('only or primary seeder. It reduces the amount of data needed');
        print('to upload to spawn new seeds (from 150-200% to ~105%).');
        print('');
        print('To disable superseeding, use --disable or -d');
        print('');
      }
    }

    if (disable) {
      if (!task.isSuperseedingEnabled) {
        print('Superseeding is already disabled');
      } else {
        _log.info('Disabling superseeding...');
        task.disableSuperseeding();
        print('');
        print('✓ Superseeding disabled');
        print('The seeder will now operate in normal seeding mode.');
        print('');
      }
    }

    // If we enabled or disabled, keep the task running for a bit to see it in action
    if (enable || disable) {
      _log.info('Task is running. Press Ctrl+C to stop...');
      _log.info('Connected peers: ${task.connectedPeersNumber}');
      _log.info(
          'Upload speed: ${(task.uploadSpeed / 1024).toStringAsFixed(2)} KB/s');

      // Keep running until interrupted
      try {
        await Future.delayed(const Duration(hours: 1));
      } catch (e) {
        // Ignore interruption
      }
    }

    await task.stop();
  } catch (e, stackTrace) {
    _log.severe('Error', e, stackTrace);
    exit(1);
  }
}
