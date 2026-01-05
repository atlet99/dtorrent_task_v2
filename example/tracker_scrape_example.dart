import 'dart:io';
import 'package:args/args.dart';
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

/// Example demonstrating tracker scrape functionality (BEP 48)
///
/// This example shows how to get torrent statistics (seeders, leechers, downloads)
/// from trackers without performing a full announce.
void main(List<String> args) async {
  // Handle --help
  if (args.contains('--help') || args.contains('-h')) {
    _showHelp();
    exit(0);
  }

  // Parse command line arguments
  final parser = ArgParser()
    ..addOption('torrent', abbr: 't', help: 'Path to torrent file')
    ..addFlag('help',
        abbr: 'h', negatable: false, help: 'Show usage information');

  ArgResults results;
  try {
    results = parser.parse(args);
  } on FormatException catch (e) {
    print('Error: $e');
    print('');
    _showHelp();
    exit(1);
  }

  final torrentPath = results['torrent'] as String?;

  if (torrentPath == null || torrentPath.isEmpty) {
    _showHelp();
    exit(1);
  }
  final torrentFile = File(torrentPath);

  if (!await torrentFile.exists()) {
    print('Error: Torrent file not found: $torrentPath');
    exit(1);
  }

  print('Loading torrent: $torrentPath');
  final torrent = await TorrentModel.parse(torrentPath);
  print('Torrent name: ${torrent.name}');
  print('Info hash: ${torrent.infoHash}');
  print('');

  // Create a task (we don't need to start it for scraping)
  final savePath = Directory.systemTemp.path;
  final task = TorrentTask.newTask(torrent, savePath);

  print('Available trackers:');
  if (torrent.announces.isEmpty) {
    print('  No trackers found in torrent file');
    exit(1);
  }

  final trackerList = torrent.announces.toList();
  for (var i = 0; i < trackerList.length; i++) {
    print('  ${i + 1}. ${trackerList[i]}');
  }
  print('');

  // Try to scrape from the first tracker
  print('Scraping tracker for statistics...');
  print('Tracker: ${trackerList.first}');
  print('');

  try {
    final result = await task.scrapeTracker();

    if (result.isSuccess) {
      print('✓ Scrape successful!');
      print('');

      // Get stats for this torrent's info hash
      final infoHashHex = torrent.infoHash.toLowerCase();
      final stats = result.getStatsForInfoHash(infoHashHex);

      if (stats != null) {
        print('Torrent Statistics:');
        print('  Seeders (complete):    ${stats.complete}');
        print('  Leechers (incomplete): ${stats.incomplete}');
        print('  Total downloads:        ${stats.downloaded}');
        print('');
        print('Total peers: ${stats.complete + stats.incomplete}');
      } else {
        print('⚠ Statistics not found for this torrent');
        print('  Info hash: $infoHashHex');
        print('  Available hashes: ${result.stats.keys.join(", ")}');
      }
    } else {
      print('✗ Scrape failed: ${result.error}');
      print('');
      print('Possible reasons:');
      print('  - Tracker does not support scrape');
      print('  - Network connection issue');
      print('  - Tracker is down or unreachable');
      print('  - Tracker requires authentication');
    }
  } catch (e, stackTrace) {
    print('✗ Error during scrape: $e');
    print('');
    print('Stack trace:');
    print(stackTrace);
  }

  // Example: Scrape from a specific tracker URL
  if (trackerList.length > 1) {
    print('');
    print('=' * 60);
    print('Example: Scraping from a specific tracker');
    print('=' * 60);
    print('');

    final specificTracker = trackerList[1];
    print('Scraping from: $specificTracker');

    try {
      final result = await task.scrapeTracker(specificTracker);

      if (result.isSuccess) {
        print('✓ Scrape successful!');
        final infoHashHex = torrent.infoHash.toLowerCase();
        final stats = result.getStatsForInfoHash(infoHashHex);

        if (stats != null) {
          print('  Seeders: ${stats.complete}');
          print('  Leechers: ${stats.incomplete}');
          print('  Downloads: ${stats.downloaded}');
        }
      } else {
        print('✗ Scrape failed: ${result.error}');
      }
    } catch (e) {
      print('✗ Error: $e');
    }
  }

  // Cleanup
  await task.dispose();
  print('');
  print('Done!');
}

void _showHelp() {
  print('Tracker Scrape Example (BEP 48)');
  print('');
  print('Usage:');
  print(
      '  dart run example/tracker_scrape_example.dart --torrent <torrent_file>');
  print('');
  print('Options:');
  print('  -t, --torrent    Path to torrent file (required)');
  print('  -h, --help       Show this help message');
  print('');
  print('Example:');
  print(
      '  dart run example/tracker_scrape_example.dart --torrent example.torrent');
  print('  dart run example/tracker_scrape_example.dart -t example.torrent');
  print('');
  print('This example demonstrates how to get torrent statistics (seeders,');
  print(
      'leechers, downloads) from trackers without performing a full announce.');
  print('');
}
