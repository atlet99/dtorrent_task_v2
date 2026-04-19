/// Example: Partial Seeds (BEP 21) usage.
///
/// This example demonstrates:
/// - enabling partial-seeding mode
/// - announcing `event=paused` to HTTP(S) trackers
/// - reading partial-seed status and tracker downloaders stats
Future<void> main() async {
  // Replace with a real torrent in practical usage.
  // final torrent = await TorrentModel.parse('path/to/file.torrent');
  //
  // final task = TorrentTask.newTask(
  //   torrent,
  //   '/tmp/downloads',
  //   false,
  //   null,
  //   null,
  //   null,
  //   null,
  //   true, // partialSeedingEnabled
  // );
  //
  // task.enablePartialSeeding();
  // await task.start();
  // await task.announcePausedToTrackers();
  //
  // final scrape = await task.scrapeTracker();
  // final status = task.getPartialSeedStatus();
  //
  // print('Partial seed enabled: ${status.enabled}');
  // print('Is partial seed: ${status.isPartialSeed}');
  // print('Completed pieces: ${status.completedPieces}/${status.totalPieces}');
  // print('Tracker downloaders: ${status.trackerDownloaders}');
  // print('Scrape success: ${scrape.isSuccess}');
}
