# About
Dart library for implementing BitTorrent client.

The Dart Torrent client consists of several parts:
- [Bencode](https://pub.dev/packages/b_encode_decode) 
- [Tracker](https://pub.dev/packages/dtorrent_tracker)
- [DHT](https://pub.dev/packages/bittorrent_dht)
- [Torrent model](https://pub.dev/packages/dtorrent_parser)
- [Common library](https://pub.dev/packages/dtorrent_common)
- [UTP](https://pub.dev/packages/utp_protocol)

This package implements the regular BitTorrent Protocol and manages the above packages to work together for downloading.

## BEP Support
- [BEP 0003 The BitTorrent Protocol Specification](https://www.bittorrent.org/beps/bep_0003.html)
- [BEP 0005 DHT Protocol](https://www.bittorrent.org/beps/bep_0005.html)
- [BEP 0006 Fast Extension](https://www.bittorrent.org/beps/bep_0006.html)
- [BEP 0009 Extension for Peers to Send Metadata Files](https://www.bittorrent.org/beps/bep_0009.html)
- [BEP 0010 Extension Protocol](https://www.bittorrent.org/beps/bep_0010.html)
- [BEP 0011 Peer Exchange (PEX)](https://www.bittorrent.org/beps/bep_0011.html)
- [BEP 0012 Multitracker Metadata Extension](https://www.bittorrent.org/beps/bep_0012.html)
- [BEP 0014 Local Service Discovery](https://www.bittorrent.org/beps/bep_0014.html)
- [BEP 0015 UDP Tracker Protocol](https://www.bittorrent.org/beps/bep_0015.html)
- [BEP 0019 HTTP/FTP Seeding (GetRight-style)](https://www.bittorrent.org/beps/bep_0019.html)
- [BEP 0027 Private Torrents](https://www.bittorrent.org/beps/bep_0027.html)
- [BEP 0029 uTorrent transport protocol](https://www.bittorrent.org/beps/bep_0029.html)
- [BEP 0040 Canonical Peer Priority](https://www.bittorrent.org/beps/bep_0040.html)
- [BEP 0048 Tracker Scrape Extension](https://www.bittorrent.org/beps/bep_0048.html)
- [BEP 0052 BitTorrent v2](https://www.bittorrent.org/beps/bep_0052.html)
- [BEP 0053 Magnet URI extension - Select specific file indices](https://www.bittorrent.org/beps/bep_0053.html)
- [BEP 0055 Holepunch extension](https://www.bittorrent.org/beps/bep_0055.html)

## How to use

This package requires dependency [`dtorrent_parser`](https://pub.dev/packages/dtorrent_parser):
```yaml
dependencies:
  dtorrent_parser: ^1.0.8
  dtorrent_task_v2: ^0.4.7
```

Download from: [DTORRENT_TASK_V2](https://pub.dev/packages/dtorrent_task_v2)

Import the library:
```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
```

First, create a `Torrent` model from a .torrent file:

```dart
  var model = await Torrent.parse('some.torrent');
```

Second, create a `Torrent Task` and start it:
```dart
  var task = TorrentTask.newTask(model, 'savepath');
  await task.start();
```

You can add event listeners to monitor `TorrentTask` execution:
```dart
  EventsListener<TaskEvent> listener = task.createListener();
  listener
    ..on<TaskCompleted>((event) {
      print('Download completed!');
    })
    ..on<TaskFileCompleted>((event) {
      print('File completed: ${event.file.originalFileName}');
    })
    ..on<TaskStopped>((event) {
      print('Task stopped');
    });
```

And there are methods to control the `TorrentTask`:

```dart
   // Stop task:
   await task.stop();
   // Pause task:
   task.pause();
   // Resume task:
   task.resume();
```

## Using Magnet Links

The library supports downloading from magnet links with automatic metadata download:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Parse magnet link
final magnet = MagnetParser.parse('magnet:?xt=urn:btih:...');
if (magnet == null) {
  print('Invalid magnet URI');
  return;
}

// Download metadata first
final metadata = MetadataDownloader.fromMagnet('magnet:?xt=urn:btih:...');
final metadataListener = metadata.createListener();

metadataListener
  ..on<MetaDataDownloadProgress>((event) {
    print('Metadata progress: ${(event.progress * 100).toInt()}%');
  })
  ..on<MetaDataDownloadComplete>((event) {
    print('Metadata downloaded!');
    // Parse torrent from metadata
    final msg = decode(event.data);
    final torrentMap = <String, dynamic>{'info': msg};
    final torrentModel = parseTorrentFileContent(torrentMap);
    
    if (torrentModel != null) {
      // Start download with web seeds and selected files from magnet link
      final task = TorrentTask.newTask(
        torrentModel,
        'savepath',
        false, // stream
        magnet.webSeeds.isNotEmpty ? magnet.webSeeds : null,
        magnet.acceptableSources.isNotEmpty ? magnet.acceptableSources : null,
      );
      
      // Apply selected files from magnet link (BEP 0053)
      if (magnet.selectedFileIndices != null && 
          magnet.selectedFileIndices!.isNotEmpty) {
        task.applySelectedFiles(magnet.selectedFileIndices!);
      }
      
      await task.start();
      
      // Transfer peers from metadata downloader to avoid reconnection delays
      final metadataPeers = metadata.activePeers;
      for (var peer in metadataPeers) {
        task.addPeer(peer.address, PeerSource.manual, type: peer.type);
      }
      
      // Add trackers from magnet link
      if (magnet.trackers.isNotEmpty) {
        final infoHashBuffer = Uint8List.fromList(
          List.generate(magnet.infoHashString.length ~/ 2, (i) {
            final s = magnet.infoHashString.substring(i * 2, i * 2 + 2);
            return int.parse(s, radix: 16);
          }),
        );
        for (var trackerUrl in magnet.trackers) {
          task.startAnnounceUrl(trackerUrl, infoHashBuffer);
        }
      }
    }
  });

metadata.startDownload();
```

## Advanced Features

### Web Seeding (BEP 0019)

The library supports HTTP/FTP seeding from web seed URLs specified in magnet links:

```dart
// Web seeds are automatically used when no peers are available for a piece
// They are specified in magnet links with the 'ws' parameter:
// magnet:?xt=urn:btih:...&ws=http://example.com/file.torrent

final task = TorrentTask.newTask(
  torrentModel,
  'savepath',
  false,
  [Uri.parse('http://example.com/file.torrent')], // webSeeds
  null, // acceptableSources
);
```

### Selected Files (BEP 0053)

You can download only specific files from a torrent:

```dart
// Select files by index (0-based)
task.applySelectedFiles([0, 2, 5]); // Only download files at indices 0, 2, and 5

// This is especially useful with magnet links:
// magnet:?xt=urn:btih:...&so=0&so=2&so=5
```

### BitTorrent Protocol v2 Support (NEW in 0.4.6)

The library now supports BitTorrent Protocol v2 (BEP 52) with full backward compatibility:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Automatic version detection
var model = await Torrent.parse('torrent_v2.torrent');
var task = TorrentTask.newTask(model, 'savepath');

// The library automatically detects v1, v2, or hybrid torrents
// and uses appropriate hash algorithms (SHA-1 for v1, SHA-256 for v2)

await task.start();
```

**BEP 52 Features:**
- **Automatic version detection**: Detects v1, v2, or hybrid torrents via `meta version` field
- **v2 info hash**: 32-byte SHA-256 info hash support (backward compatible with 20-byte v1)
- **SHA-256 piece hashing**: Automatic piece validation with SHA-256 for v2 torrents
- **File tree structure**: Support for v2 file tree organization
- **Piece layers**: Merkle tree layer support for efficient piece validation
- **Merkle tree validation**: Full Merkle tree validation for v2 files
- **Hash messages**: Support for hash request/hashes/hash reject messages (ID 21, 22, 23)
- **Hybrid torrents**: Seamless support for torrents with both v1 and v2 structures

**Helper Classes:**
```dart
// File tree operations
final fileTree = FileTreeHelper.parseFileTree(torrentData);
final files = FileTreeHelper.extractFiles(fileTree, '');
final totalSize = FileTreeHelper.calculateTotalSize(fileTree);

// Piece layers operations
final pieceLayers = PieceLayersHelper.parsePieceLayers(torrentData);
final pieceHashes = PieceLayersHelper.getPieceHashesForFile(pieceLayers, piecesRoot);

// Merkle tree validation
final isValid = MerkleTreeHelper.validateFile(fileData, piecesRoot);
final pieceValid = MerkleTreeHelper.validatePiece(pieceData, expectedHash);
```

See `example/bittorrent_v2_example.dart` for complete examples.

### Sequential Download for Streaming (NEW in 0.4.5)

The library now supports advanced sequential download optimized for video/audio streaming:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Create sequential configuration
final config = SequentialConfig.forVideoStreaming();

// Create task with streaming enabled
final task = TorrentTask.newTask(
  torrent,
  savePath,
  true, // Enable streaming mode
  null, // webSeeds
  null, // acceptableSources  
  config, // Sequential configuration
);

await task.start();

// Update playback position during seek operations
task.setPlaybackPosition(seekPositionInBytes);

// Get streaming statistics
final stats = task.getSequentialStats();
if (stats != null) {
  print('Buffer health: ${stats.bufferHealth}%');
  print('Strategy: ${stats.currentStrategy.name}');
  print('Buffered pieces: ${stats.bufferedPieces}');
}
```

**Sequential Configuration Options:**

```dart
// Video streaming (optimized for MP4/MKV)
final videoConfig = SequentialConfig.forVideoStreaming();

// Audio streaming (optimized for MP3/FLAC)
final audioConfig = SequentialConfig.forAudioStreaming();

// Minimal configuration
final minimalConfig = SequentialConfig.minimal();

// Custom configuration
final customConfig = SequentialConfig(
  lookAheadSize: 20,              // Buffer 20 pieces ahead
  criticalZoneSize: 10 * 1024 * 1024, // 10MB critical zone
  adaptiveStrategy: true,          // Auto-switch strategies
  autoDetectMoovAtom: true,       // Prioritize moov atom for MP4
  seekLatencyTolerance: 1,        // 1 second seek tolerance
  enablePeerPriority: true,       // BEP 40 peer priority
  enableFastResumption: true,     // BEP 53 fast resumption
);
```

**Features:**
- **Look-ahead buffer**: Downloads pieces ahead of playback position
- **Adaptive strategy**: Automatically switches between sequential and rarest-first
- **Moov atom detection**: Prioritizes MP4 metadata for faster playback start
- **Seek support**: Fast priority rebuilding on seek operations
- **Buffer health monitoring**: Real-time streaming quality metrics
- **BEP 40 integration**: Peer prioritization for sequential pieces
- **BEP 53 support**: Efficient partial piece resumption

See `example/sequential_streaming_example.dart` for complete examples.

### Fast Resume and State File Management (NEW in 0.4.7)

The library now includes an enhanced state file system with automatic recovery and validation:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Load or create state file (automatically migrates from v1 to v2)
final stateFile = await StateFileV2.getStateFile(savePath, torrent);

// Check state file validity
if (stateFile.isValid) {
  print('State file version: ${stateFile.version}');
  print('Last modified: ${stateFile.lastModified}');
  print('Downloaded: ${stateFile.downloaded} bytes');
  print('Uploaded: ${stateFile.uploaded} bytes');
} else {
  print('State file is invalid, attempting recovery...');
  // Recover from corrupted state file
  final recovery = StateRecovery(torrent, savePath, pieces);
  final recoveredStateFile = await recovery.recoverStateFile();
  if (recoveredStateFile != null) {
    print('Recovery successful!');
  }
}

// Validate downloaded files
final validator = FileValidator(torrent, pieces, savePath);

// Quick validation (checks file existence and sizes)
final quickValid = await validator.quickValidate();

// Full validation (validates all pieces with hash verification)
final validationResult = await validator.validateAll();
if (validationResult.isValid) {
  print('All files validated successfully');
} else {
  print('Found ${validationResult.invalidPieces.length} invalid pieces');
}
```

**State File v2 Features:**
- **Automatic migration**: Seamlessly migrates from v1 to v2 format
- **Compression**: Gzip compression for large bitfields (reduces file size)
- **Sparse storage**: Optimized storage format for partially downloaded torrents (<10% completion)
- **Integrity validation**: CRC32 checksums for header and bitfield validation
- **Metadata tracking**: Version, timestamp, and storage flags

**File Validation:**
- **Quick validation**: Fast check for file existence and sizes
- **Full validation**: Complete hash verification of all pieces
- **Per-file validation**: Validate specific files only
- **Automatic validation on resume**: Enable with `validateOnResume` option

**State Recovery:**
- Automatic detection of corrupted state files
- Rebuilds bitfield from validated downloaded files
- Backup functionality before recovery operations

**Usage with DownloadFileManager:**

```dart
// Enable validation on resume
final fileManager = await DownloadFileManager.createFileManager(
  torrent,
  savePath,
  stateFile,
  pieces,
  validateOnResume: true, // Automatically validate files on resume
);
```

See `example/fast_resume_example.dart` for complete examples.

### Tracker Scrape (BEP 48) (NEW in 0.4.7)

The library supports tracker scrape requests to get torrent statistics without performing a full announce:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Scrape tracker for torrent statistics
final result = await task.scrapeTracker();

if (result.isSuccess) {
  final stats = result.getStatsForInfoHash(task.metaInfo.infoHash);
  if (stats != null) {
    print('Seeders: ${stats.complete}');
    print('Leechers: ${stats.incomplete}');
    print('Downloads: ${stats.downloaded}');
  }
} else {
  print('Scrape failed: ${result.error}');
}

// Scrape specific tracker URL
final customResult = await task.scrapeTracker(Uri.parse('https://tracker.example.com/announce'));
```

**Features:**
- Get torrent statistics (seeders, leechers, downloads) without full announce
- Automatic URL conversion from announce to scrape endpoint
- Support for HTTP and UDP trackers
- Error handling for unavailable trackers

See `example/tracker_scrape_example.dart` for complete examples.

### Proxy Support (NEW in 0.4.7)

The library supports HTTP, HTTPS, and SOCKS5 proxies for tracker requests and peer connections:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Configure proxy
final proxyConfig = ProxyConfig(
  httpProxy: Uri.parse('http://proxy.example.com:8080'),
  httpsProxy: Uri.parse('https://proxy.example.com:8080'),
  socks5Proxy: Uri.parse('socks5://proxy.example.com:1080'),
  username: 'user', // Optional
  password: 'pass', // Optional
);

// Create task with proxy
final task = TorrentTask.newTask(
  torrent,
  savePath,
  false, // stream
  null, // webSeeds
  null, // acceptableSources
  null, // sequentialConfig
  proxyConfig, // proxy configuration
);

await task.start();
```

**Proxy Types:**
- **HTTP/HTTPS Proxy**: For HTTP tracker requests and web seed connections
- **SOCKS5 Proxy**: For peer connections (TCP and uTP)
- **Authentication**: Support for username/password authentication

**Features:**
- Automatic proxy selection based on connection type
- Support for authenticated proxies
- Transparent integration with existing code

See `example/proxy_example.dart` for complete examples.

### Torrent Queue Management (NEW in 0.4.7)

The library includes a queue management system for organizing and prioritizing torrent downloads:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Create queue manager with concurrent download limit
final queueManager = QueueManager(maxConcurrentDownloads: 3);

// Listen to queue events
final queueListener = queueManager.createListener();
queueListener
  ..on<QueueItemAdded>((event) {
    print('Torrent added to queue: ${event.item.metaInfo.name}');
  })
  ..on<QueueItemStarted>((event) {
    print('Download started: ${event.item.metaInfo.name}');
  })
  ..on<QueueItemCompleted>((event) {
    print('Download completed: ${event.item.metaInfo.name}');
  });

// Add torrents to queue with priorities
final item1 = await queueManager.addTorrent(
  torrent1,
  savePath1,
  priority: QueuePriority.high,
);

final item2 = await queueManager.addTorrent(
  torrent2,
  savePath2,
  priority: QueuePriority.normal,
);

// Update priority
queueManager.updatePriority(item1.id, QueuePriority.urgent);

// Get queue status
print('Active downloads: ${queueManager.activeDownloads}');
print('Queued items: ${queueManager.queuedItems}');
```

**Priority Levels:**
- `QueuePriority.low`: Lowest priority
- `QueuePriority.normal`: Default priority
- `QueuePriority.high`: High priority
- `QueuePriority.urgent`: Highest priority

**Features:**
- Concurrent download limit control
- Priority-based queue ordering
- Automatic queue progression
- Event-based queue monitoring
- FIFO ordering within same priority

See `example/torrent_queue_example.dart` for complete examples.

### Port Forwarding (NEW in 0.4.7)

The library supports automatic port forwarding via UPnP and NAT-PMP:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Create port forwarding manager
final portManager = PortForwardingManager();

// Forward port automatically
final result = await portManager.forwardPort(
  port: 6881,
  protocol: 'TCP',
  description: 'BitTorrent',
);

if (result.isSuccess) {
  print('Port forwarded successfully');
  print('External port: ${result.externalPort}');
  print('Lease duration: ${result.leaseDuration} seconds');
} else {
  print('Port forwarding failed: ${result.error}');
}

// Remove port forwarding
await portManager.removePortForwarding(6881, 'TCP');

// Cleanup
await portManager.dispose();
```

**Protocols:**
- **UPnP**: Universal Plug and Play port forwarding
- **NAT-PMP**: NAT Port Mapping Protocol

**Features:**
- Automatic gateway discovery
- Lease renewal for NAT-PMP
- Support for TCP and UDP protocols
- Error handling and retry logic

See `example/port_forwarding_example.dart` for complete examples.

### IP Filtering (NEW in 0.4.7)

The library supports IP filtering to block or allow peer connections:

```dart
import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

// Create IP filter
final ipFilter = IPFilter();

// Load from eMule dat file
await ipFilter.loadFromEmuleDat('ipfilter.dat');

// Or load from PeerGuardian format
await ipFilter.loadFromPeerGuardian('blocklist.p2p');

// Add custom IP ranges
ipFilter.addRange('192.168.1.0', '192.168.1.255');
ipFilter.addCIDR('10.0.0.0/8');

// Set filter mode (blacklist or whitelist)
ipFilter.mode = IPFilterMode.blacklist; // Block listed IPs
// or
ipFilter.mode = IPFilterMode.whitelist; // Allow only listed IPs

// Apply filter to task
task.setIPFilter(ipFilter);

// Check if IP is allowed
if (ipFilter.isAllowed(InternetAddress('192.168.1.100'))) {
  print('IP is allowed');
} else {
  print('IP is blocked');
}
```

**Supported Formats:**
- **eMule dat format**: Standard IP filter format used by eMule
- **PeerGuardian format**: P2P blocklist format

**Features:**
- Blacklist and whitelist modes
- CIDR block support
- IP range support
- Automatic peer blocking
- Dynamic filter updates

See `example/ip_filtering_example.dart` for complete examples.

### Monitoring Download Progress

You can monitor detailed download progress:

```dart
final listener = task.createListener();
listener.on<StateFileUpdated>((event) {
  final downloaded = task.downloaded ?? 0;
  final progress = task.progress * 100;
  final connectedPeers = task.connectedPeersNumber;
  final seederCount = task.seederNumber;
  final downloadSpeed = task.currentDownloadSpeed;
  final avgSpeed = task.averageDownloadSpeed;
  
  print('Progress: ${progress.toStringAsFixed(2)}%');
  print('Downloaded: ${(downloaded / 1024 / 1024).toStringAsFixed(2)} MB');
  print('Peers: $connectedPeers ($seederCount seeders)');
  print('Speed: ${(downloadSpeed * 1000 / 1024).toStringAsFixed(2)} KB/s');
  print('Avg: ${(avgSpeed * 1000 / 1024).toStringAsFixed(2)} KB/s');
});
```

### Adding Peers Manually

You can add peer addresses manually:

```dart
import 'package:dtorrent_common/dtorrent_common.dart';

// Add a peer by address
final peerAddress = CompactAddress(
  InternetAddress('192.168.1.100'),
  6881,
);
task.addPeer(peerAddress, PeerSource.manual, type: PeerType.TCP);

// Add a peer with existing socket
task.addPeer(peerAddress, PeerSource.incoming, 
    type: PeerType.TCP, socket: socket);
```

### DHT Support

The library includes built-in DHT support for peer discovery:

```dart
// DHT is automatically enabled in TorrentTask
// You can add bootstrap nodes:
for (var node in torrentModel.nodes) {
  task.addDHTNode(node);
}

// Or manually request peers from DHT:
task.requestPeersFromDHT();
```

## Monitoring and Error Tracking

The library includes comprehensive error tracking for uTP protocol stability:

```dart
import 'package:dtorrent_task_v2/src/peer/protocol/peer.dart';

// Check RangeError metrics
if (Peer.rangeErrorCount > 0) {
  print('Total RangeErrors: ${Peer.rangeErrorCount}');
  print('uTP RangeErrors: ${Peer.utpRangeErrorCount}');
  print('Errors by reason: ${Peer.rangeErrorByReason}');
}

// Reset metrics for new monitoring period
Peer.resetRangeErrorMetrics();
```

These metrics help monitor uTP protocol stability and debug RangeError crashes, particularly those related to selective ACK processing and buffer handling.

## Features

### Stability Improvements
- **uTP RangeError Protection**: Comprehensive protection against RangeError crashes in uTP protocol with:
  - Buffer bounds validation before all operations
  - Message length validation (negative, oversized, and overflow protection)
  - Integer overflow protection in calculations
  - Detailed error tracking and metrics
  - Extensive test coverage (stress tests, reordering, extreme values, long sessions)
- **Critical Bug Fixes**: Fixed race condition in bitfield processing that prevented downloads from starting (see [issue #4](https://github.com/atlet99/dtorrent_task_v2/issues/4))

### Protocol Support
- Full BitTorrent protocol implementation
- **BitTorrent Protocol v2 (BEP 52)** with automatic version detection
- **Tracker Scrape (BEP 48)** for torrent statistics without full announce
- uTP (uTorrent transport protocol) support with enhanced stability
- TCP fallback support
- Multiple extension protocols (PEX, LSD, Holepunch, Metadata Exchange)
- Magnet link support via `MagnetParser` with automatic metadata download
- Torrent creation via `TorrentCreator`
- Web seeding (HTTP/FTP) support (BEP 0019)
- Selected file download (BEP 0053)
- Private torrent support (BEP 0027) with automatic DHT/PEX disabling
- Hybrid torrent support (v1 + v2 compatibility)
- HTTP/HTTPS and SOCKS5 proxy support
- UPnP and NAT-PMP port forwarding
- IP filtering with eMule dat and PeerGuardian format support

### Performance
- Efficient piece management and selection
- Memory-optimized file handling
- Streaming support for media files with isolate-based processing
- Optimized congestion control for uTP connections
- Debounced progress events for reduced UI update frequency
- Automatic peer transfer from metadata download to actual download
- Metadata caching to avoid re-downloading
- Parallel metadata download from multiple peers
- Compressed state file storage for large torrents
- Sparse bitfield storage for partially downloaded torrents

### State File and Recovery
- Enhanced state file format (v2) with versioning and validation
- Automatic migration from v1 to v2 format
- Gzip compression for bitfield storage
- Sparse storage format for partially downloaded torrents
- CRC32 checksums for integrity validation
- Automatic state file recovery from corruption
- File validation with quick and full modes
- Automatic validation on resume option

### Magnet Link Features
- Automatic metadata download from magnet links
- Support for Base32 and hex infohash formats (RFC 4648)
- Tracker tier support (BEP 0012) with tier-by-tier announcement
- Web seed URL parsing and integration (BEP 0019)
- Acceptable source URL support
- Selected file indices parsing (BEP 0053)
- Automatic peer and tracker transfer from metadata phase to download phase

### Queue Management
- Priority-based torrent queue system
- Concurrent download limit control
- Automatic queue progression
- Event-based queue monitoring
- FIFO ordering within same priority level

### Network Features
- HTTP/HTTPS and SOCKS5 proxy support for tracker requests and peer connections
- UPnP and NAT-PMP automatic port forwarding
- IP filtering with blacklist/whitelist modes
- eMule dat and PeerGuardian format support for IP filters
- CIDR block and IP range support
