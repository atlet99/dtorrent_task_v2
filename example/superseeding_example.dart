import 'dart:io';
import 'dart:typed_data';
import 'package:args/args.dart';
import 'package:crypto/crypto.dart';
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
    ..addFlag('validate',
        abbr: 'v',
        defaultsTo: false,
        help: 'Validate all files and update bitfield (useful for seeding)')
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
    print('  # Validate files and update bitfield (for seeding)');
    print('  dart run example/superseeding_example.dart -t my.torrent -v');
    print('');
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
  final validate = results['validate'] as bool;

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
    final task = TorrentTask.newTask(torrent as TorrentModel, savePath);

    // Start task to initialize fileManager and pieceManager
    try {
      await task.start();
      _log.info('Task started, waiting for initialization...');
      await Future.delayed(const Duration(seconds: 3));

      // Wait for fileManager and pieceManager to be initialized
      var retries = 0;
      while ((task.fileManager == null || task.pieceManager == null) &&
          retries < 10) {
        await Future.delayed(const Duration(milliseconds: 500));
        retries++;
      }

      if (task.fileManager == null || task.pieceManager == null) {
        _log.warning(
            'Task initialization incomplete: fileManager=${task.fileManager != null}, pieceManager=${task.pieceManager != null}');
      }
    } catch (e) {
      _log.warning('Failed to start task: $e');
    }

    // Wait for fileManager to be ready
    if (task.fileManager == null) {
      _log.info('Waiting for fileManager initialization...');
      var retries = 0;
      while (task.fileManager == null && retries < 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        retries++;
      }
    }

    // Check if task is a seeder
    if (task.fileManager == null || !task.fileManager!.isAllComplete) {
      _log.info('Torrent appears incomplete in state file. Checking files...');

      // Check if bitfield is empty or almost empty (files might be complete but bitfield not updated)
      final isEmpty = task.fileManager == null ||
          task.fileManager!.localBitfield.completedPieces.isEmpty;
      final isAlmostEmpty = task.fileManager != null &&
          task.fileManager!.localBitfield.completedPieces.length <
              (torrent.pieces.length * 0.01); // Less than 1% complete

      // If validate flag is set or bitfield is empty/almost empty, validate files
      final shouldValidate = validate || isEmpty || isAlmostEmpty;

      if (shouldValidate) {
        if (isEmpty && !validate) {
          _log.info(
              'Bitfield is empty but files may exist. Auto-validating files...');
        } else {
          _log.info('Validating all files and updating bitfield...');
        }

        // Wait a bit more if managers are not ready
        if (task.fileManager == null || task.pieceManager == null) {
          _log.info('Waiting for task initialization...');
          var retries = 0;
          while ((task.fileManager == null || task.pieceManager == null) &&
              retries < 20) {
            await Future.delayed(const Duration(milliseconds: 500));
            retries++;
          }
        }

        if (task.fileManager != null && task.pieceManager != null) {
          try {
            // Normalize savePath (ensure it ends with path separator)
            var normalizedSavePath = savePath;
            if (!normalizedSavePath.endsWith(Platform.pathSeparator)) {
              normalizedSavePath =
                  '$normalizedSavePath${Platform.pathSeparator}';
            }

            // Quick validation first
            final validator = FileValidator(torrent as TorrentModel,
                task.pieceManager!.pieces.values.toList(), normalizedSavePath);
            final quickValid = await validator.quickValidate();
            if (!quickValid) {
              _log.warning(
                  'Quick validation failed - some files may be missing or have wrong size');
              _log.info('Will still attempt to validate existing pieces...');
            } else {
              _log.info('Quick validation passed');
            }

            _log.info('Validating all pieces from existing files...');
            _log.info('This may take a while for large torrents...');

            // Validate all pieces by reading directly from files
            var validatedCount = 0;
            var invalidCount = 0;
            var skippedCount = 0;

            for (var i = 0; i < torrent.pieces.length; i++) {
              try {
                // Read piece data directly from files
                final pieceData = await _readPieceDataFromFiles(
                    torrent as TorrentModel,
                    normalizedSavePath,
                    i,
                    torrent.pieceLength);
                if (pieceData.length !=
                    (i == torrent.pieces.length - 1
                        ? torrent.lastPieceLength
                        : torrent.pieceLength)) {
                  invalidCount++;
                  continue;
                }

                // Calculate hash
                final hash = sha1.convert(pieceData);
                final expectedHash = torrent.pieces[i];

                // Compare hashes
                if (hash.toString() == expectedHash) {
                  // Piece is valid, mark it as complete
                  await task.fileManager!.updateBitfield(i, true);
                  validatedCount++;
                } else {
                  invalidCount++;
                }
              } catch (e) {
                // File missing or read error - skip this piece
                skippedCount++;
                if (skippedCount <= 5 || skippedCount % 100 == 0) {
                  _log.fine('Piece $i skipped (file missing or error): $e');
                }
              }

              // Progress update every 100 pieces
              if ((i + 1) % 100 == 0) {
                _log.info(
                    'Validated ${i + 1}/${torrent.pieces.length} pieces... (valid: $validatedCount, invalid: $invalidCount, skipped: $skippedCount)');
              }
            }

            _log.info(
                'Validation complete: $validatedCount valid, $invalidCount invalid, $skippedCount skipped pieces');
            _log.info(
                'Updated bitfield: $validatedCount pieces marked as complete');
          } catch (e, stackTrace) {
            _log.warning('File validation failed', e, stackTrace);
          }
        }
      }

      // Wait a bit more after validation to let bitfield update
      if (validate) {
        await Future.delayed(const Duration(seconds: 1));
      }

      // Check again after validation
      if (task.fileManager == null || !task.fileManager!.isAllComplete) {
        print('');
        print('WARNING: Torrent is not complete. Superseeding only works when');
        print('the client is a seeder (has all pieces).');
        print('');
        print('Current status:');
        if (task.fileManager != null) {
          final completed =
              task.fileManager!.localBitfield.completedPieces.length;
          final total = task.fileManager!.localBitfield.piecesNum;
          print('  Completed pieces: $completed / $total');
          print('  Progress: ${(completed / total * 100).toStringAsFixed(1)}%');
        }
        print('');
        print(
            'Tip: Use --validate or -v to validate all files and update bitfield');
        print('');
        print('Please ensure:');
        print('  1. All torrent files are present in: $savePath');
        print('  2. All files are complete and valid');
        print('  3. The torrent has been fully downloaded');
        print('');
        await task.stop();
        exit(1);
      }
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
      // Make sure task is started
      try {
        await task.start();
        await Future.delayed(const Duration(seconds: 1));
      } catch (e) {
        _log.warning('Task may already be running: $e');
      }

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
    } else if (status) {
      // For status check, stop the task if it was started for validation
      try {
        await task.stop();
      } catch (e) {
        // Ignore if already stopped
      }
    } else {
      // If no action was taken, stop the task
      try {
        await task.stop();
      } catch (e) {
        // Ignore if already stopped
      }
    }
  } catch (e, stackTrace) {
    _log.severe('Error', e, stackTrace);
    exit(1);
  }
}

/// Helper function to read piece data directly from files
Future<Uint8List> _readPieceDataFromFiles(TorrentModel torrent, String savePath,
    int pieceIndex, int pieceLength) async {
  final pieceStart = pieceIndex * pieceLength;
  final pieceEnd = pieceStart +
      (pieceIndex == (torrent.pieces?.length ?? 0) - 1
          ? torrent.lastPieceLength
          : pieceLength);
  final pieceByteLength = pieceEnd - pieceStart;
  final data = Uint8List(pieceByteLength);
  var offset = 0;

  // Find which files contain this piece
  for (var file in torrent.files) {
    final fileStart = file.offset;
    final fileEnd = file.offset + file.length;

    if (pieceStart < fileEnd && pieceEnd > fileStart) {
      final readStart = pieceStart > fileStart ? pieceStart - fileStart : 0;
      final readEnd = pieceEnd < fileEnd ? pieceEnd - fileStart : file.length;
      final readLength = readEnd - readStart;

      // Normalize path: ensure savePath ends with separator and file.path doesn't start with one
      var normalizedSavePath = savePath;
      if (!normalizedSavePath.endsWith(Platform.pathSeparator)) {
        normalizedSavePath = '$normalizedSavePath${Platform.pathSeparator}';
      }
      var normalizedFilePath = file.path;
      if (normalizedFilePath.startsWith(Platform.pathSeparator)) {
        normalizedFilePath = normalizedFilePath.substring(1);
      }
      final filePath = '$normalizedSavePath$normalizedFilePath';
      final fileObj = File(filePath);
      if (await fileObj.exists()) {
        final access = await fileObj.open(mode: FileMode.read);
        await access.setPosition(readStart);
        final bytes = await access.read(readLength);
        data.setRange(offset, offset + bytes.length, bytes);
        offset += bytes.length;
        await access.close();
      } else {
        throw Exception('File not found: $filePath');
      }
    }
  }

  return data;
}
