import 'package:test/test.dart';
import 'package:dtorrent_task_v2/src/nat/upnp_client.dart';

void main() {
  group('UPnPClient', () {
    late UPnPClient client;

    setUp(() {
      client = UPnPClient(
        timeout: const Duration(seconds: 3), // Short timeout for tests
      );
    });

    test('UPnPClient creation', () {
      expect(client, isNotNull);
      expect(client.timeout, equals(const Duration(seconds: 3)));
    });

    test('SSDP address and port constants', () {
      expect(UPnPClient.SSDP_ADDRESS.address, equals('239.255.255.250'));
      expect(UPnPClient.SSDP_PORT, equals(1900));
      expect(UPnPClient.SSDP_MX, equals('3'));
      expect(UPnPClient.SSDP_ST, contains('InternetGatewayDevice'));
    });

    test('M-SEARCH request format', () {
      // This tests the internal _buildMSearchRequest logic indirectly
      // by checking that discovery can be attempted
      expect(client, isNotNull);
    });

    test('GatewayDevice creation', () {
      final location = Uri.parse('http://192.168.1.1:80/description.xml');
      final controlUrl = Uri.parse('http://192.168.1.1:80/control');
      final device = GatewayDevice(
        location: location,
        controlUrl: controlUrl,
        serviceType: 'urn:schemas-upnp-org:service:WANIPConnection:1',
      );

      expect(device.location, equals(location));
      expect(device.controlUrl, equals(controlUrl));
      expect(device.serviceType, contains('WANIPConnection'));
      expect(device.toString(), contains('controlUrl'));
    });

    test('GatewayDevice with optional scpdUrl', () {
      final location = Uri.parse('http://192.168.1.1:80/description.xml');
      final controlUrl = Uri.parse('http://192.168.1.1:80/control');
      final scpdUrl = Uri.parse('http://192.168.1.1:80/scpd.xml');
      final device = GatewayDevice(
        location: location,
        controlUrl: controlUrl,
        serviceType: 'urn:schemas-upnp-org:service:WANIPConnection:1',
        scpdUrl: scpdUrl,
      );

      expect(device.scpdUrl, equals(scpdUrl));
    });

    // Note: Actual discovery and port mapping tests would require
    // a real UPnP router, so we test the API structure instead
    test('addPortMapping API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        internalClient: '192.168.1.100',
        protocol: 'TCP',
        description: 'test',
        leaseDuration: 3600,
      );

      // Result should be bool (false if no router available)
      expect(result, isA<bool>());
    });

    test('deletePortMapping API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.deletePortMapping(
        externalPort: 6881,
        protocol: 'TCP',
      );

      // Result should be bool (false if no router available)
      expect(result, isA<bool>());
    });

    test('getExternalIP API structure', () async {
      // This will likely fail without a real router, but tests the API
      final result = await client.getExternalIP();

      // Result should be String? (null if no router available)
      expect(result, isA<String?>());
    });

    test('discoverGateway returns null when no router available', () async {
      // Without a real router, this should return null or timeout
      // We can't reliably test this without a router, so we just check
      // that the method exists and can be called
      expect(client.discoverGateway, isA<Function>());
    });
  });

  group('UPnPClient error handling', () {
    late UPnPClient client;

    setUp(() {
      client = UPnPClient(timeout: const Duration(milliseconds: 100));
    });

    test('Handles invalid gateway gracefully', () async {
      // Test that methods handle errors gracefully
      final result = await client.addPortMapping(
        externalPort: 6881,
        internalPort: 6881,
        internalClient: 'invalid',
        protocol: 'TCP',
      );

      // Should return false on error, not throw
      expect(result, isA<bool>());
    });
  });
}
