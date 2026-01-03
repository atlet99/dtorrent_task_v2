import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/nat/port_forwarding_manager.dart';

void main() {
  group('PortForwardingManager', () {
    late PortForwardingManager manager;

    setUp(() {
      manager = PortForwardingManager(
        preferredMethod: PortForwardingMethod.auto,
        timeout: const Duration(seconds: 3),
      );
    });

    tearDown(() async {
      await manager.removeAllPortForwardings();
    });

    test('PortForwardingManager creation', () {
      expect(manager, isNotNull);
      expect(manager.preferredMethod, equals(PortForwardingMethod.auto));
      expect(manager.timeout, equals(const Duration(seconds: 3)));
    });

    test('PortForwardingMethod enum values', () {
      expect(PortForwardingMethod.upnp, isNotNull);
      expect(PortForwardingMethod.natpmp, isNotNull);
      expect(PortForwardingMethod.auto, isNotNull);
    });

    test('PortForwardingResult creation with success', () {
      final result = PortForwardingResult(
        success: true,
        method: PortForwardingMethod.upnp,
        externalIP: InternetAddress('1.2.3.4'),
      );

      expect(result.success, isTrue);
      expect(result.method, equals(PortForwardingMethod.upnp));
      expect(result.externalIP, isNotNull);
      expect(result.error, isNull);
      expect(result.toString(), contains('success: true'));
    });

    test('PortForwardingResult creation with error', () {
      final result = PortForwardingResult(
        success: false,
        error: 'No gateway found',
      );

      expect(result.success, isFalse);
      expect(result.error, equals('No gateway found'));
      expect(result.method, isNull);
      expect(result.externalIP, isNull);
      expect(result.toString(), contains('error'));
    });

    test('forwardPort API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await manager.forwardPort(
        port: 6881,
        protocol: 'TCP',
        description: 'test',
        leaseDuration: 3600,
      );

      expect(result, isA<PortForwardingResult>());
      expect(result.success, isA<bool>());
    });

    test('forwardPort with UDP protocol', () async {
      final result = await manager.forwardPort(
        port: 6881,
        protocol: 'UDP',
      );

      expect(result, isA<PortForwardingResult>());
    });

    test('removePortForwarding API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await manager.removePortForwarding(
        port: 6881,
        protocol: 'TCP',
      );

      expect(result, isA<bool>());
    });

    test('removeAllPortForwardings', () async {
      // Should not throw even if no mappings exist
      await manager.removeAllPortForwardings();
      expect(manager.activeMappings.isEmpty, isTrue);
    });

    test('getExternalIP API structure', () async {
      final result = await manager.getExternalIP();

      expect(result, isA<InternetAddress?>());
    });

    test('isAvailable API structure', () async {
      final result = await manager.isAvailable();

      expect(result, isA<bool>());
    });

    test('discover API structure', () async {
      final result = await manager.discover();

      expect(result, isA<PortForwardingMethod?>());
    });

    test('activeMappings is unmodifiable', () {
      final mappings = manager.activeMappings;

      // Should be unmodifiable map
      expect(
          () => mappings[6881] = PortForwardingMethod.upnp, throwsA(anything));
    });

    test('Manager with UPnP preferred method', () {
      final upnpManager = PortForwardingManager(
        preferredMethod: PortForwardingMethod.upnp,
      );

      expect(upnpManager.preferredMethod, equals(PortForwardingMethod.upnp));
    });

    test('Manager with NAT-PMP preferred method', () {
      final natpmpManager = PortForwardingManager(
        preferredMethod: PortForwardingMethod.natpmp,
      );

      expect(
          natpmpManager.preferredMethod, equals(PortForwardingMethod.natpmp));
    });
  });

  group('PortForwardingManager error handling', () {
    late PortForwardingManager manager;

    setUp(() {
      manager = PortForwardingManager(
        timeout: const Duration(milliseconds: 100),
      );
    });

    test('Handles missing gateway gracefully', () async {
      final result = await manager.forwardPort(port: 6881);

      // Should return error result, not throw
      expect(result, isA<PortForwardingResult>());
      expect(result.success, isFalse);
      expect(result.error, isNotNull);
    });

    test('Handles invalid port gracefully', () async {
      final result = await manager.forwardPort(port: 0);

      expect(result, isA<PortForwardingResult>());
    });

    test('removePortForwarding for non-existent port', () async {
      final result = await manager.removePortForwarding(port: 99999);

      // Should return false, not throw
      expect(result, isA<bool>());
    });
  });

  group('PortForwardingManager lease renewal', () {
    late PortForwardingManager manager;

    setUp(() {
      manager = PortForwardingManager(
        timeout: const Duration(seconds: 3),
      );
    });

    tearDown(() async {
      await manager.removeAllPortForwardings();
    });

    test('Lease renewal scheduled for NAT-PMP', () async {
      // Note: This test verifies the structure, actual renewal
      // would require a real NAT-PMP router
      final result = await manager.forwardPort(
        port: 6881,
        protocol: 'TCP',
        leaseDuration: 3600,
      );

      // If successful, lease renewal should be scheduled
      // (we can't verify without a real router)
      expect(result, isA<PortForwardingResult>());
    });
  });
}
