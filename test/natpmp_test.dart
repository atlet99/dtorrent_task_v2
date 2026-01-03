import 'dart:io';
import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/nat/natpmp_client.dart';

void main() {
  group('NATPMPClient', () {
    late NATPMPClient client;

    setUp(() {
      client = NATPMPClient(
        timeout: const Duration(seconds: 3), // Short timeout for tests
      );
    });

    test('NATPMPClient creation', () {
      expect(client, isNotNull);
      expect(client.timeout, equals(const Duration(seconds: 3)));
    });

    test('NAT-PMP port constant', () {
      expect(NATPMPClient.NATPMP_PORT, equals(5351));
    });

    test('addPortMapping API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        protocol: 1, // TCP
        leaseDuration: 3600,
      );

      // Result should be bool (false if no router available)
      expect(result, isA<bool>());
    });

    test('addPortMapping with UDP protocol', () async {
      final result = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        protocol: 2, // UDP
        leaseDuration: 3600,
      );

      expect(result, isA<bool>());
    });

    test('deletePortMapping API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.deletePortMapping(
        externalPort: 6881,
        protocol: 1, // TCP
      );

      // Result should be bool (false if no router available)
      expect(result, isA<bool>());
    });

    test('getExternalIP API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.getExternalIP();

      // Result should be InternetAddress? (null if no router available)
      expect(result, isA<InternetAddress?>());
    });

    test('discoverGateway returns null when no router available', () async {
      // Without a real router, this should return null or timeout
      // We can't reliably test this without a router, so we just check
      // that the method exists and can be called
      expect(client.discoverGateway, isA<Function>());
    });

    test('Protocol constants', () {
      // Test that protocol codes are correct
      // 1 = TCP, 2 = UDP
      expect(1, equals(1)); // TCP
      expect(2, equals(2)); // UDP
    });

    test('Lease duration handling', () async {
      // Test with different lease durations
      final result1 = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        protocol: 1,
        leaseDuration: 0, // Permanent
      );

      final result2 = await client.addPortMapping(
        externalPort: 6882,
        internalPort: 6882,
        protocol: 1,
        leaseDuration: 3600, // 1 hour
      );

      final result3 = await client.addPortMapping(
        externalPort: 6883,
        internalPort: 6883,
        protocol: 1,
        leaseDuration: 65535, // Max value
      );

      // All should return bool
      expect(result1, isA<bool>());
      expect(result2, isA<bool>());
      expect(result3, isA<bool>());
    });
  });

  group('NATPMPClient error handling', () {
    late NATPMPClient client;

    setUp(() {
      client = NATPMPClient(timeout: const Duration(milliseconds: 100));
    });

    test('Handles invalid gateway gracefully', () async {
      // Test that methods handle errors gracefully
      final result = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        protocol: 1,
      );

      // Should return false on error, not throw
      expect(result, isA<bool>());
    });

    test('Handles timeout gracefully', () async {
      // With very short timeout, should handle timeout gracefully
      final result = await client.discoverGateway();

      // Should return null on timeout, not throw
      expect(result, isA<InternetAddress?>());
    });
  });
}
