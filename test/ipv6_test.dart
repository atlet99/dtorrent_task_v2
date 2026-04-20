import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

class _IPv6FakeDriver implements StandaloneDHTDriver {
  final StreamController<StandaloneDHTDriverEvent> _events =
      StreamController<StandaloneDHTDriverEvent>.broadcast();

  bool _readOnly = false;
  StandaloneDHTAddressFamilyMode _mode =
      StandaloneDHTAddressFamilyMode.dualStackPreferIPv4;

  @override
  Stream<StandaloneDHTDriverEvent> get events => _events.stream;

  @override
  bool get readOnly => _readOnly;

  @override
  set readOnly(bool value) {
    _readOnly = value;
  }

  @override
  StandaloneDHTAddressFamilyMode get addressFamilyMode => _mode;

  @override
  set addressFamilyMode(StandaloneDHTAddressFamilyMode value) {
    _mode = value;
  }

  @override
  Future<int?> bootstrap({int port = 0}) async => 0;

  @override
  void announce(String infoHash, int port) {}

  @override
  void requestPeers(String infoHash) {}

  @override
  Future<void> addBootstrapNode(Uri url) async {}

  @override
  Future<void> stop() async {
    await _events.close();
  }
}

void main() {
  group('IPv6 Support (BEP 7, 32)', () {
    test('parses compact IPv6 peer address', () {
      final addr = InternetAddress('2001:db8::1');
      final port = 6881;
      final raw = Uint8List(18)
        ..setRange(0, 16, addr.rawAddress)
        ..[16] = port >> 8
        ..[17] = port & 0xff;

      final parsed = CompactAddress.parseIPv6Address(raw, 0);
      expect(parsed, isNotNull);
      expect(parsed!.address.type, InternetAddressType.IPv6);
      expect(parsed.port, port);
    });

    test('parses peers6 compact list', () {
      final addresses = [
        CompactAddress(InternetAddress('2001:db8::2'), 51413),
        CompactAddress(InternetAddress('2001:db8::3'), 51414),
      ];

      final bytes = <int>[];
      for (final address in addresses) {
        bytes.addAll(address.address.rawAddress);
        bytes.add((address.port >> 8) & 0xff);
        bytes.add(address.port & 0xff);
      }

      final parsed = CompactAddress.parseIPv6Addresses(bytes);
      expect(parsed, hasLength(2));
      expect(parsed.first.address.type, InternetAddressType.IPv6);
      expect(parsed.last.port, 51414);
    });

    test('supports dual-stack mode switching and preference events', () async {
      final adapter = BittorrentDHTAdapter(driver: _IPv6FakeDriver());
      final modes = <StandaloneDHTAddressFamilyMode>[];
      final listener = adapter.createListener();
      listener.on<StandaloneDHTAddressFamilyChangedEvent>(
        (event) => modes.add(event.mode),
      );

      adapter.setAddressFamilyMode(StandaloneDHTAddressFamilyMode.ipv4Only);
      adapter.setAddressFamilyMode(
        StandaloneDHTAddressFamilyMode.dualStackPreferIPv6,
      );
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(
        modes,
        [
          StandaloneDHTAddressFamilyMode.ipv4Only,
          StandaloneDHTAddressFamilyMode.dualStackPreferIPv6,
        ],
      );
      expect(
        adapter.addressFamilyMode,
        StandaloneDHTAddressFamilyMode.dualStackPreferIPv6,
      );

      listener.dispose();
      await adapter.stop();
    });
  });
}
