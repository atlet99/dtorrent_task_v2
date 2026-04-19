import 'dart:io';

import 'dtorrent_common.dart';

/// Converts external compact-address-like objects into local [CompactAddress].
///
/// This is intentionally used only on package boundaries (for example DHT),
/// where third-party packages may emit their own address classes.
CompactAddress compactAddressFromExternal(Object address) {
  if (address is CompactAddress) return address;

  try {
    final raw = (address as dynamic).toBytes(false) as List<int>;
    final v4 = CompactAddress.parseIPv4Address(raw, 0);
    if (v4 != null && raw.length == 6) return v4;
    final v6 = CompactAddress.parseIPv6Address(raw, 0);
    if (v6 != null && raw.length == 18) return v6;
  } catch (_) {
    // fallback below
  }

  try {
    final ip = (address as dynamic).address as InternetAddress;
    final port = (address as dynamic).port as int;
    return CompactAddress(ip, port);
  } catch (_) {
    throw ArgumentError('Unsupported compact address type: $address');
  }
}
