import 'dart:io';

import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';

void main() {
  group('DHTMultipleAddressTable (BEP 45)', () {
    test('supports multiple addresses for one node in shared table', () {
      final table = DHTMultipleAddressTable();
      final nodeId = 'node-1';
      final ipv4 = CompactAddress(InternetAddress('1.1.1.1'), 6881);
      final ipv6 = CompactAddress(InternetAddress('2001:db8::1'), 6881);

      table.addAddress(nodeId: nodeId, address: ipv4);
      table.addAddress(nodeId: nodeId, address: ipv6);

      expect(table.nodeCount, 1);
      expect(table.addressCount, 2);
      expect(table.getAddresses(nodeId), hasLength(2));
    });

    test('tracks connectivity state independently per address', () {
      final table = DHTMultipleAddressTable();
      final nodeId = 'node-2';
      final a1 = CompactAddress(InternetAddress('2.2.2.2'), 6881);
      final a2 = CompactAddress(InternetAddress('2.2.2.3'), 6881);

      table.markReachable(nodeId: nodeId, address: a1);
      table.markUnreachable(nodeId: nodeId, address: a2);

      final states = table.getAddresses(nodeId);
      final reachable =
          states.firstWhere((s) => s.address.address == a1.address);
      final unreachable =
          states.firstWhere((s) => s.address.address == a2.address);

      expect(reachable.connectivity, DHTAddressConnectivity.reachable);
      expect(unreachable.connectivity, DHTAddressConnectivity.unreachable);
      expect(reachable.successfulChecks, 1);
      expect(unreachable.failedChecks, 1);
    });

    test('prioritizes reachable addresses first, then by score', () {
      final table = DHTMultipleAddressTable();
      const nodeId = 'node-3';
      final best = CompactAddress(InternetAddress('3.3.3.3'), 6881);
      final medium = CompactAddress(InternetAddress('3.3.3.4'), 6881);
      final worst = CompactAddress(InternetAddress('3.3.3.5'), 6881);

      table.addAddress(nodeId: nodeId, address: best);
      table.addAddress(nodeId: nodeId, address: medium);
      table.addAddress(nodeId: nodeId, address: worst);

      table.markReachable(nodeId: nodeId, address: medium);
      table.markReachable(nodeId: nodeId, address: best);
      table.markReachable(nodeId: nodeId, address: best);
      table.markUnreachable(nodeId: nodeId, address: worst);

      final prioritized = table.getPrioritizedAddresses(nodeId);
      expect(prioritized.first.address, best.address);
      expect(prioritized[1].address, medium.address);
      expect(prioritized.last.address, worst.address);
    });
  });
}
