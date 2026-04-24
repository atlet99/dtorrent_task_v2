import 'package:dtorrent_task_v2/dtorrent_task_v2.dart';
import 'package:test/test.dart';
import 'dart:io';

void main() {
  group('ProxyConfig', () {
    test('create HTTP proxy', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
      );
      expect(config.type, ProxyType.http);
      expect(config.host, 'proxy.example.com');
      expect(config.port, 8080);
      expect(config.useForTrackers, isTrue);
      expect(config.useForPeers, isFalse);
    });

    test('create HTTPS proxy', () {
      final config = ProxyConfig.https(
        host: 'proxy.example.com',
        port: 8443,
      );
      expect(config.type, ProxyType.https);
      expect(config.host, 'proxy.example.com');
      expect(config.port, 8443);
    });

    test('create SOCKS5 proxy', () {
      final config = ProxyConfig.socks5(
        host: 'socks.example.com',
        port: 1080,
      );
      expect(config.type, ProxyType.socks5);
      expect(config.host, 'socks.example.com');
      expect(config.port, 1080);
      expect(config.useForTrackers, isFalse);
      expect(config.useForPeers, isTrue);
    });

    test('proxy with authentication', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
        username: 'user',
        password: 'pass',
      );
      expect(config.requiresAuth, isTrue);
      expect(config.username, 'user');
      expect(config.password, 'pass');
    });

    test('proxy without authentication', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
      );
      expect(config.requiresAuth, isFalse);
    });

    test('proxy URI generation', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
        username: 'user',
        password: 'pass',
      );
      final uri = config.uri;
      expect(uri.scheme, 'http');
      expect(uri.host, 'proxy.example.com');
      expect(uri.port, 8080);
    });
  });

  group('HttpProxyClient', () {
    test('create HTTP proxy client', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
      );
      final client = HttpProxyClient(config);
      expect(client.config, config);
    });

    test('create HTTPS proxy client', () {
      final config = ProxyConfig.https(
        host: 'proxy.example.com',
        port: 8443,
      );
      final client = HttpProxyClient(config);
      expect(client.config, config);
    });

    test('reject non-HTTP proxy', () {
      final config = ProxyConfig.socks5(
        host: 'socks.example.com',
        port: 1080,
      );
      expect(() => HttpProxyClient(config), throwsArgumentError);
    });

    test('get proxy auth header', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
        username: 'user',
        password: 'pass',
      );
      final client = HttpProxyClient(config);
      final header = client.getProxyAuthHeader();
      expect(header, isNotNull);
      expect(header, startsWith('Basic '));
    });

    test('get proxy URL', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
      );
      final client = HttpProxyClient(config);
      expect(client.getProxyUrl(), 'http://proxy.example.com:8080');
    });
  });

  group('Socks5Client', () {
    test('create SOCKS5 client', () {
      final config = ProxyConfig.socks5(
        host: 'socks.example.com',
        port: 1080,
      );
      final client = Socks5Client(config);
      expect(client.config, config);
    });

    test('reject non-SOCKS5 proxy', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
      );
      expect(() => Socks5Client(config), throwsArgumentError);
    });

    test('handles coalesced SOCKS5 proxy responses', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async => server.close());

      server.listen((socket) {
        var responded = false;
        socket.listen((_) {
          if (responded) return;
          responded = true;

          socket.add(<int>[
            0x05, 0x00, // auth accepted
            0x05, 0x00, 0x00, 0x01, // connect accepted, IPv4 bound address
            127, 0, 0, 1, // bound address
            0x1A, 0xE1, // bound port 6881
          ]);
          Future<void>.delayed(const Duration(milliseconds: 10), () {
            socket.add(<int>[0xAA, 0xBB]);
          });
        });
      });

      final config = ProxyConfig.socks5(
        host: InternetAddress.loopbackIPv4.address,
        port: server.port,
      );
      final client = Socks5Client(config);
      final socket = await client.connect(InternetAddress.loopbackIPv4, 6881);
      addTearDown(() async => socket.close());

      expect(socket.remotePort, server.port);
      expect(socket, emits(<int>[0xAA, 0xBB]));
    });

    test('exposes typed SOCKS5 exception messages', () {
      const error = Socks5Exception('example failure');

      expect(error.toString(), 'Socks5Exception: example failure');
    });
  });

  group('ProxyManager', () {
    test('create without proxy', () {
      final manager = ProxyManager(null);
      expect(manager.config, isNull);
      expect(manager.shouldUseForTrackers(), isFalse);
      expect(manager.shouldUseForPeers(), isFalse);
    });

    test('create with HTTP proxy for trackers', () {
      final config = ProxyConfig.http(
        host: 'proxy.example.com',
        port: 8080,
        useForTrackers: true,
        useForPeers: false,
      );
      final manager = ProxyManager(config);
      expect(manager.config, config);
      expect(manager.shouldUseForTrackers(), isTrue);
      expect(manager.shouldUseForPeers(), isFalse);
      expect(manager.httpProxyClient, isNotNull);
      expect(manager.socks5Client, isNull);
    });

    test('create with SOCKS5 proxy for peers', () {
      final config = ProxyConfig.socks5(
        host: 'socks.example.com',
        port: 1080,
        useForTrackers: false,
        useForPeers: true,
      );
      final manager = ProxyManager(config);
      expect(manager.config, config);
      expect(manager.shouldUseForTrackers(), isFalse);
      expect(manager.shouldUseForPeers(), isTrue);
      expect(manager.httpProxyClient, isNull);
      expect(manager.socks5Client, isNotNull);
    });
  });
}
