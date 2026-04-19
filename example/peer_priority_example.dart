import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';

void main() {
  final localIp = InternetAddress('123.213.32.10');
  const localPort = 51413;

  final peers = [
    (InternetAddress('98.76.54.32'), 6881),
    (InternetAddress('123.213.32.234'), 6881),
    (InternetAddress('203.0.113.77'), 51413),
  ];

  final scored = peers
      .map((p) => (
            ip: p.$1,
            port: p.$2,
            priority: PeerPriority.canonicalPriority(
              clientIp: localIp,
              clientPort: localPort,
              peerIp: p.$1,
              peerPort: p.$2,
            ),
          ))
      .toList()
    ..sort((a, b) => b.priority.compareTo(a.priority));

  print('BEP 40 Canonical Peer Priority ranking:');
  for (final row in scored) {
    final hex = row.priority.toRadixString(16).padLeft(8, '0');
    print('${row.ip.address}:${row.port} -> 0x$hex');
  }
}
