## 0.5.3

- add initial WebTorrent tracker support with `WebSocketTracker` for `ws://`/`wss://` announce signalling and regression tests
- extend magnet parsing for WebTorrent-style links with `ws://`/`wss://` trackers and `xs` exact-source URLs
- add Sintel and Big Buck Bunny WebTorrent magnet fixtures covering UDP/WSS trackers, web seeds, and exact sources
- refine standalone tracker event/error models by replacing untyped payload fields with explicit `Object?` contracts and immutable announce event DTOs
- refactor tracker retry scheduler internals to typed record storage (`timer`, `retryTimes`) instead of untyped timer lists
- harden scrape/tracker API signatures with explicit return types (`Future<void>`, `Future<ScrapeEvent?>`) and null-safe error paths in HTTP scrape flow
- replace remaining parser/tracker helper `dynamic` usages (`Object?`-based retry/external-ip/compact-peer parsing and typed required-option extraction)
- optimize `Makefile` quality gates: run `dart fix` once through analyzer context, keep `check-all` focused on fixes/format/analyze, and make `test-all` a single coverage run
- clean coverage output before test coverage generation and expose `COVERAGE_DIR`/`DART_FIX_TARGET` for local customization
- align analyzer excludes with generated/non-project folders (`build/**`, `doc/api/**`, `example/bttest/**`) so `dart fix`/analysis skip local artifacts consistently
- update padding-file regression tests to use real `StateFileV2` instead of an outdated fake state file, matching the current `DownloadFileManager` contract
- document `0.5.3` WebTorrent compatibility in README, including WebSocket trackers, `ws` web seeds, and `xs` exact-source magnet URLs
- expand `example/example.dart` with a runnable WebTorrent-style magnet section for WSS trackers, web seeds, and current WebRTC scope
- improve WebTorrent regression coverage for binary tracker responses, update announces, signalling payload variants, invalid peer IDs, `xs` round-trips, numbered exact sources, and invalid scheme filtering
- fix pub.dev static-analysis score issues by renaming legacy ALL_CAPS constants/fields to lowerCamelCase and re-enabling identifier-name lints locally
- exclude generated coverage output and internal `example/test_*.dart` smoke files from the publish archive via `.pubignore`
- tighten LSD/piece/scrape internals with typed futures, `Object?` scrape payloads, and precise `StateError`/`ArgumentError` failures instead of broad `Exception`
- harden SOCKS5 proxy reads with a buffered socket reader and typed `Socks5Exception` errors
- normalize `FileValidator` torrent file path resolution and replace missing-file generic exceptions with `FileSystemException` in validator/example flows
- update README snippets to import public `dtorrent_task_v2.dart` API instead of package-internal `src/` paths
- expose documented LSD, NAT/port-forwarding, and standalone announce tracker helpers through the public barrel API so published examples no longer depend on package-internal imports

## 0.5.2

- refactor streaming isolate request/response pipeline to use single listener with request correlation IDs (removes ReceivePort re-listen conflicts and stabilizes concurrent metadata/playlist requests)
- simplify and harden isolate tests by removing stream-listen workarounds and adding dedicated concurrent request regression coverage
- refactor peer swarm internals (`PeersManager`) with typed request buffers (Dart records) instead of untyped nested lists for safer queue/resume/dispose flows
- improve metadata pipeline safety and maintainability (`MetadataDownloader`, `MagnetParser`) with better payload guards, reduced duplication, and extracted parsing helpers
- harden async file/state request handling (`DownloadFile`, `StateFile`, `StateFileV2`, `Debouncer`) with stricter typing and safer pause/resume/finally behavior
- improve `QueueManager` and `TorrentTask` internals (deduplicated terminal event handling, extracted scheduler/auto-move helpers, cleaner logging)
- replace dynamic state-file casts in `DownloadFileManager`/`TorrentTask` with typed `StateFile`/`StateFileV2` pattern matching for safer resume/path/update operations
- tighten peer extension typing (`ExtendedProcessor`, `Peer`, `PeersManager`, `MetadataDownloader`, `PEX`) with explicit payload guards for `handshake`/`ut_pex`/`ut_holepunch` flows
- refactor standalone tracker and DHT internals to stronger typed contracts (UDP/HTTP tracker response paths, socket error signatures, typed options maps, decoded datagram handling)
- remove remaining analyzer noise after refactor (including tracker extension test cast cleanup) and keep full `dart analyze` green
- improve local developer quality gates:
  - fix `NO_COLOR` warning in `Makefile`
  - scope analyze targets to project source dirs
  - keep test suite separated from analyze/check flow as configured
- expand analyzer excludes for non-project directories (`test_results/**`, `tmp/**`, `coverage/**`, `.dart_tool/**`, `test_download_*/**`, etc.) and add explicit formatter config in `analysis_options.yaml`
- update direct and dev dependency constraints to latest compatible versions (`b_encode_decode`, `utp_protocol`, `events_emitter2`, `collection`, `crypto`, `logging`, `lints`, `path`, `test`)

## 0.5.1

- add file moving support during active downloads with state path persistence and rebind support (`moveDownloadedFile`, `detectMovedFiles`, `validateMovedFilePath`)
- add moved-path persistence sidecar for resume (`*.bt.paths.json`) in state file implementations
- add auto-move manager with extension-based rules, default destination, and external-disk guardrails
- add schedule manager for pause/resume automation and time-window speed caps
- add RSS/Atom feed modules (parser, filters, manager) with deduplication and queue auto-add integration
- add queue-level RSS auto-download API (`enableRssAutoDownload`, `disableRssAutoDownload`)
- add examples for move/auto-move/scheduling/rss (`file_moving_example.dart`, `auto_move_example.dart`, `scheduling_example.dart`, `rss_auto_download_example.dart`)
- add regression tests for section 5 features (`test/file_moving_test.dart`, `test/auto_move_test.dart`, `test/scheduling_test.dart`, `test/rss_test.dart`)
- refine README structure to be feature-focused (without release-centric navigation sections)

## 0.5.0

- migrate `dtorrent_common` to built-in standalone module (`lib/src/standalone/dtorrent_common.dart`)
- migrate `dtorrent_tracker` to built-in standalone module (`lib/src/standalone/dtorrent_tracker.dart`)
- remove direct dependencies on external `dtorrent_common` and `dtorrent_tracker` packages
- add standalone tracker migration regression tests (`standalone_tracker_migration_test.dart`)
- harden HTTP announce query generation with BEP 3 required fields and safe defaults
- keep de-facto tracker compatibility fields in announce requests: `numwant`, `key`, `trackerid`, `no_peer_id`
- ignore discouraged announce params `ipv4`/`ipv6` (BEP 7 guidance)
- improve announce option merge strategy (preserve BEP-safe defaults for partial provider maps)
- add BEP 41 `URLData` support in UDP announce (path/query extension options)
- add UDP tracker extension payload parsing and extension support marker (`udp_options`, `udp_extensions_supported`)
- add BEP 41 regression tests for URLData encoding/chunking and extended UDP announce response parsing (`test/udp_tracker_extensions_test.dart`)
- update README BEP support matrix with tracker-related BEPs: 23, 24, 31, 41
- add BEP 47 file-attribute model (`FileAttributes`) with padding/flags parsing (`p`, `l`, `x`, `h`)
- parse BEP 47 `attr` for both v1 file lists and v2 file tree entries, and expose it via `TorrentFileModel`/`FileTreeFile`
- detect padding files via BEP 47 naming convention (`_____padding_file_<n>_____`) and `attr = p`
- treat padding files as virtual in file IO: no disk file creation, zero-filled reads, no-op flush/write persistence
- update file validation to support virtual padding segments (piece reconstruction with zero bytes)
- add padding regression tests for parser + file manager + validator (`test/padding_files_test.dart`)
- add BEP 47 symlink metadata parsing (`symlink path`) for v1/v2 torrent structures
- restore file attributes on startup/completion (executable bit on Unix-like systems, platform-safe fallback on Windows)
- restore symlink files from torrent metadata when supported by platform
- add padding-only piece handling in piece manager (zero-hash auto-complete and validation bypass for pure padding pieces)
- add BEP 54 `lt_donthave` support (extended message encode/decode and peer-state updates)
- add `PeerDontHaveEvent` and wire it into task piece scheduling (drop availability and fail matching pending requests)
- register `lt_donthave` in peer extension handshake and add swarm broadcast helper (`sendDontHaveToAll`)
- improve extension dispatch to resolve remote extension names by negotiated id (handshake map)
- add BEP 54 regression tests for valid/invalid donthave flows (`test/donthave_extension_test.dart`)
- migrate DHT integration to built-in standalone facade/driver (`lib/src/standalone/dht/standalone_dht.dart`)
- remove direct dependency on external `bittorrent_dht` package
- add retry/backoff policy and graceful shutdown handling for standalone DHT operations
- add standalone DHT regression tests for bootstrap failures, retry paths, idempotent stop, and peer-event flood handling (`test/standalone_dht_test.dart`)
- improve DHT runtime diagnostics in `TorrentTask` and `MetadataDownloader` (retry/error observability)
- add BEP 43 read-only DHT mode with explicit API (`readOnly`, `setReadOnly`) and change event (`StandaloneDHTReadOnlyChangedEvent`)
- block write operations in read-only mode (`announce`/`announce_peer`) while preserving routing/get-peers behavior
- add BEP 44 standalone DHT storage primitives for immutable/mutable values with seq/CAS/signature validation (`lib/src/dht/dht_storage.dart`)
- add BEP 45 multiple-address DHT table with per-address connectivity tracking and prioritized address selection (`lib/src/dht/dht_multiple_addresses.dart`)
- add BEP 50 pub/sub topic manager for push-style updates over DHT-like topics (`lib/src/dht/dht_pubsub.dart`)
- add BEP 51 infohash indexing with keyword search and metadata-based indexing (`lib/src/dht/dht_indexing.dart`)
- export DHT enhancement modules in public API (`dht_storage`, `dht_multiple_addresses`, `dht_pubsub`, `dht_indexing`)
- add regression tests for BEP 44/45/50/51 modules (`test/dht_storage_test.dart`, `test/dht_multiple_addresses_test.dart`, `test/dht_pubsub_test.dart`, `test/dht_indexing_test.dart`)
- add IPv6/dual-stack mode controls for standalone DHT (`ipv4Only`, `ipv6Only`, `dualStackPreferIPv4`, `dualStackPreferIPv6`)
- add address-family change event for DHT configuration observability (`StandaloneDHTAddressFamilyChangedEvent`)
- add dual-socket standalone DHT bootstrap (IPv4 + IPv6) with family-aware routing and preference-based node query ordering
- add TorrentTask API for IPv6 policy management (`setDHTAddressFamilyMode`, `dhtAddressFamilyMode`)
- add IPv6 regression tests for compact peers and DHT address-family switching (`test/ipv6_test.dart`)

## 0.4.9

- improve test reliability and coverage for peer communication, fast extension, and metadata flows
- add mock socket test infrastructure (`MockSocket`, `MockServerSocket`) for deterministic TCP peer tests
- add new regression test suites:
  - `peer_message_validation_test.dart` for invalid/oversized/fragmented message handling
  - `metadata_messenger_test.dart` for `ut_metadata` message encoding validation
  - `debug_peer_test.dart` and `mock_socket_test.dart` for handshake/data-flow stability checks
- refactor fragile tests to event-driven synchronization (reduce fixed-delay race conditions)
- improve magnet parsing robustness:
  - case-insensitive `magnet:?` / `xt=urn:btih:` handling
  - case-insensitive query keys (`xt`, `dn`, `tr`, `ws`, `as`, `so`)
  - stable multi-value parsing for duplicate and numbered params (`tr.N`, `ws.N`, `as.N`, `so.N`)
- harden metadata download validation and safety:
  - validate info hash via `ArgumentError` (not assert-only)
  - verify cached metadata hash before emitting completion
  - add guards for malformed metadata payload boundaries and stopped downloader states
- improve logging and diagnostics:
  - replace noisy debug prints with structured logger calls in peer/metadata paths
  - keep malformed metadata messages non-fatal
- improve parser compatibility in torrent parsing for mixed bencoded value types
- add public API documentation for key exported symbols/events and exceptions
- add official minimal `example/example.dart` for pub.dev package layout compliance
- add `.pubignore` to exclude local artifacts and keep publish archives small/clean

## 0.4.8

- add BEP 16 Superseeding support with `SuperSeeder` class and `enableSuperseeding()`/`disableSuperseeding()` methods in `TorrentTask`
- add superseeding algorithm implementation that masquerades seeder as peer with no data to improve seeding efficiency
- add piece rarity tracking and distribution monitoring for superseeding mode
- add automatic superseeding activation when download completes (if enabled before completion)
- add file priority management system with `FilePriorityManager` class and `FilePriority` enum (skip, low, normal, high)
- add `setFilePriority()` and `setFilePriorities()` methods for individual and batch file priority management
- add `getFilePriority()` method to retrieve current file priority
- add `autoPrioritizeFiles()` method for automatic priority assignment based on file extensions (video/audio files get high priority, subtitles get normal, others get low)
- add piece prioritization based on file priorities (high priority files download first)
- add file priority persistence in state file (StateFileV2) for resume support
- add `TorrentParser` class to replace external `dtorrent_parser` dependency
- add `TorrentModel` class as replacement for `Torrent` class from `dtorrent_parser`
- add full BEP 52 (v2) support in built-in parser with automatic version detection
- add support for parsing v1, v2, and hybrid torrents in `TorrentParser`
- add `TorrentModel.parse()` static method for backward compatibility with `Torrent.parse()`
- add `TorrentParser.parseBytes()` and `TorrentParser.parseFromMap()` for flexible parsing
- remove dependency on `dtorrent_parser` package (now built-in)
- add comprehensive superseeding example (`superseeding_example.dart`) with CLI interface
- add file validation and bitfield update functionality in superseeding example
- improve piece distribution logic in `SuperSeeder` for better efficiency
- improve state file handling with file priorities support
- improve temporary file cleanup during state file operations
- export `FilePriority` and `FilePriorityManager` in public API
- export `SuperSeeder` in public API (via seeding module)
- add comprehensive test suite for superseeding functionality
- update all examples and tests to use `TorrentModel` instead of `Torrent` from `dtorrent_parser`

## 0.4.7

- add BEP 48 Tracker Scrape support with `scrapeTracker()` method in `TorrentTask`
- add `ScrapeClient` class for retrieving torrent statistics (seeders, leechers, downloads) without full announce
- add UPnP and NAT-PMP port forwarding support with `PortForwardingManager` class
- add `NATPMPClient` and `UPnPClient` for automatic port mapping and gateway discovery
- add IP filtering functionality with `IPFilter` class supporting blacklist and whitelist modes
- add eMule dat format parser (`EmuleDatParser`) for loading IP filters from .dat files
- add PeerGuardian format parser (`PeerGuardianParser`) for loading IP filters from .p2p files
- add HTTP proxy support with `ProxyConfig` and `ProxyManager` classes
- add SOCKS5 proxy support with `Socks5Client` class
- add HTTP proxy client (`HttpProxyClient`) for HTTP/HTTPS proxy connections
- add torrent queue management system with `QueueManager` and `TorrentQueue` classes
- add priority-based queue system with `QueuePriority` enum (low, normal, high, urgent)
- add concurrent download limit support in queue manager
- add queue events (`QueueItemAdded`, `QueueItemCompleted`, `QueueItemFailed`, etc.)
- add enhanced state file format (StateFileV2) with versioning and validation
- add magic bytes ("DTSF") for state file format identification
- add automatic migration from v1 to v2 state file format
- add gzip compression support for bitfield storage (reduces file size for large torrents)
- add sparse storage format for partially downloaded torrents (optimizes storage for <10% completion)
- add CRC32 checksums for header and bitfield validation
- add state file integrity validation with `validate()` method
- add `StateRecovery` class for automatic recovery from corrupted state files
- add `FileValidator` class for validating downloaded files against piece hashes
- add quick validation mode (checks file existence and sizes without hash verification)
- add full validation mode (validates all pieces with SHA-1/SHA-256 hashes)
- add per-file validation support for selective file verification
- add automatic file validation on resume with `validateOnResume` option in `DownloadFileManager`
- add state file metadata tracking (version, last modified timestamp, storage flags)
- add dynamic storage format switching (sparse/full based on completion ratio)
- add state file backup functionality before recovery operations
- export new classes in public API (`StateFileV2`, `StateRecovery`, `FileValidator`, `ProxyConfig`, `ProxyManager`, `QueueManager`, `IPFilter`, `PortForwardingManager`)
- add comprehensive examples (`proxy_example.dart`, `torrent_queue_example.dart`, `fast_resume_example.dart`, `ip_filtering_example.dart`, `port_forwarding_example.dart`, `simple_integration_example.dart`)
- add comprehensive test suites for all new features

## 0.4.6

- add BitTorrent Protocol v2 (BEP 52) support
- add v2 info hash support (32 bytes SHA-256 instead of 20 bytes SHA-1)
- add v2 piece hashing with SHA-256 algorithm
- add hybrid torrent support (v1 + v2 compatibility)
- add torrent version detection via meta version field
- add file tree structure support (BEP 52) with `FileTreeHelper` class
- add piece layers support with `PieceLayersHelper` class
- add Merkle tree validation for v2 files with `MerkleTreeHelper` class
- add hash request/hashes/hash reject messages (ID 21, 22, 23) for v2 protocol
- add hybrid torrent handshake upgrade (4th bit in reserved bytes)
- add v2 info hash calculation (SHA-256 from bencoded info dict)
- add `TorrentVersionHelper` for version detection and hash algorithm selection
- update handshake protocol to support v2 extension bit
- update piece validation to support both SHA-1 (v1) and SHA-256 (v2)
- update `PieceManager` to handle piece layers for v2 torrents
- update `DownloadFileManager` to support file tree structure
- add comprehensive test suite for BEP 52 features (33 new tests)
- export BEP 52 helper classes in public API (`FileTreeHelper`, `PieceLayersHelper`, `MerkleTreeHelper`)

## 0.4.5

- add advanced sequential download support for streaming
- add `SequentialConfig` class for flexible streaming configuration
- add `AdvancedSequentialPieceSelector` with look-ahead buffer
- add `SequentialStats` for download metrics and health monitoring
- add look-ahead buffer for smooth playback (configurable size)
- add critical piece prioritization (moov atom for MP4 files)
- add adaptive strategy (automatic switching between sequential and rarest-first)
- add seek operation support with fast priority rebuilding
- add auto-detection of moov atom for MP4 files
- add peer priority optimization (BEP 40 - Canonical Peer Priority)
- add fast piece resumption support (BEP 53 - Partial data)
- add sequential statistics API (`getSequentialStats()`)
- add playback position tracking (`setPlaybackPosition()`)
- add factory methods for common use cases (`forVideoStreaming()`, `forAudioStreaming()`)
- add comprehensive streaming examples
- export sequential download classes in public API

## 0.4.4

- add Base32 infohash support in magnet links (RFC 4648)
- integrate trackers from magnet links into MetadataDownloader for peer discovery
- add automatic retry mechanism (up to 3 attempts) when metadata verification fails
- implement parallel metadata download from multiple peers for faster completion
- improve timeout handling with exponential backoff (10s base, +5s per retry, max 30s)
- add TrackerTier class for grouping trackers by tiers (BEP 0012)
- support parsing numbered tracker parameters (tr.1, tr.2, etc.) as separate tiers
- announce to trackers tier by tier for better reliability
- detect private torrent flag in metadata handshake (BEP 0027)
- automatically disable DHT announce for private torrents
- block PEX peer exchange for private torrents
- parse ws (Web Seed) parameter from magnet links (BEP 0019)
- parse as (Acceptable Source) parameter from magnet links
- support multiple web seed URLs
- implement WebSeedDownloader class for HTTP/FTP seeding (BEP 0019)
- support HTTP Range requests for efficient piece downloading
- integrate web seed URLs from magnet links into TorrentTask
- automatic fallback to P2P when web seeds are unavailable
- support multiple web seed URLs with retry mechanism (max 3 attempts per URL)
- handle both Partial Content (206) and Full Content (200) HTTP responses
- proper resource cleanup and HttpClient management
- web seed download triggered when no peers available for a piece
- update TorrentTask.newTask() to accept webSeeds and acceptableSources parameters
- parse so (select only) parameter from magnet links (BEP 0053)
- add applySelectedFiles() method to TorrentTask for prioritizing selected files
- add metadata caching to avoid re-downloading metadata for same infohash
- add configurable cache directory (defaults to system temp + metadata_cache)
- enhance error handling and logging throughout metadata download process
- improve timeout management with per-piece retry tracking
- update example showing all new magnet link features
- fix magnet parser to properly handle multiple parameters with same key (so, ws, as)
- improve LSD port conflict handling in TorrentTask.start() to gracefully continue without LSD
- add early validation for empty piece size in WebSeedDownloader to prevent unnecessary HTTP requests
- fix PieceManager tests to properly set remote bitfield for peer selection
- fix PieceManager test for writeComplete to check isCompletelyWritten instead of flushed flag
- improve streaming isolate tests to handle ReceivePort reuse errors gracefully
- fix torrent creator tests to accept both ArgumentError and PathNotFoundException for empty directories
- fix torrent client tests to skip when required torrent file is missing
- enhance web seeding integration tests with better port conflict detection
- improve test reliability by handling resource conflicts in parallel test execution
- fix critical bug: "Invalid message buffer size: length=1" error for messages without payload (choke, unchoke, interested, not interested)
- fix peer transfer from MetadataDownloader to TorrentTask after metadata download completes
- transfer active peers from metadata download phase to actual download phase to avoid reconnection delays
- add trackers from magnet link to TorrentTask to ensure all trackers are used even if not in metadata
- improve bitfield handling: properly support messages without payload according to BEP 0003
- enhance test example with comprehensive diagnostics and automatic completion detection

## 0.4.3

- fix critical bug where downloads don't start despite connected peers (fixes #4)
- fix race condition in bitfield processing when peer sends unchoke before interested
- optimize progress event emission with debouncing to reduce UI update frequency
- improve uTP congestion control with optimized initial window size
- add streaming isolate support for better performance during video streaming
- export magnet parser and torrent creator in public API

## 0.4.2

- update mime dependency from ^1.0.6 to ^2.0.0
- optimize lookupMimeType usage to avoid duplicate calls
- update lints dev dependency from ^2.1.1 to ^6.0.0
- fix linter warnings for new lint rules (unnecessary_library_name, strict_top_level_inference, unintended_html_in_doc_comment)
- fix uTP RangeError crashes with comprehensive protection:
  - add buffer bounds validation before all setRange operations
  - add message length validation (negative, oversized, and overflow values)
  - add integer overflow protection for message length calculations
  - wrap all critical uTP operations in try-catch blocks with RangeError handling
  - add RangeError metrics tracking (Peer.rangeErrorCount, Peer.utpRangeErrorCount)
  - add detailed logging for uTP debugging (buffer sizes, message parsing)
  - extract magic numbers to constants (MAX_MESSAGE_SIZE, BUFFER_SIZE_WARNING_THRESHOLD)
- create comprehensive test suite for uTP RangeError protection:
  - utp_range_error_protection_test.dart: basic validation tests
  - utp_stress_test.dart: stress tests with 50+ parallel peers
  - utp_reorder_test.dart: packet reordering and burst ACK tests
  - utp_extreme_values_test.dart: extreme value tests (large seq/ack, overflows)
  - utp_long_session_test.dart: long session stability tests

## 0.4.1

- update dependencies to latest compatible versions
- upgrade SDK constraint to >=3.0.0
- fix dead code warnings in examples
- remove unused code (\_hookUTP method, unused imports)
- fix TCPConnectException to properly use exception field
- update analysis options to disable constant naming checks

## 0.4.0

- enable utp
- decouple some parts of the code
- use logging package
- select pieces when stream is seeking
- cache piece in memory until it is validated then write to disk
- enable lsd
- fixes for PEX
- emit useful events
- add simple binary for testing
- optimizing
- fix memory leaks
- some refactoring and cleanup

## 0.3.5

- use more broad collection constraints

## 0.3.4

- use events_emitter and streams when possible
- video streaming fixes
- fix tests
- validate completed pieces
- add task start, task stop, task resume events
- move more dynamic types to explicit types
- update deps and sdk constraints

## 0.3.3

- migrate to events_emitter2

## 0.3.2

- pub.dev fixes

## 0.3.1

- nullsafety

## 0.3.0

- Add Send Metadata extension (BEP0009)

## 0.2.1

- Change congestion control

## 0.2.0

- Add UTP support
- Add holepunch extension
- Add LSD extension
- Fix PEX extension bugs

## 0.1.4

- Fix some issues
- Fix peer download slow issue

## 0.1.2

- Support peer reconnect
- Fix some bugs

## 0.1.1

- Add DHT support
- Add PEX support
- Change Tracker
- Fix some bugs

## 0.0.2

- Fix license file error
- Fix example error

## 0.0.1

- Initial version
