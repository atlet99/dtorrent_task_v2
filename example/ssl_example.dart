/// Example: SSL/TLS configuration for peers and trackers.
Future<void> main() async {
  // final torrent = await TorrentModel.parse('path/to/file.torrent');
  //
  // final sslConfig = SSLConfig(
  //   enableForPeers: true,
  //   validateCertificates: true,
  //   allowSelfSigned: false,
  //   // trustedCaPath: '/path/to/ca.pem',
  //   // clientCertificatePath: '/path/to/client.crt',
  //   // clientPrivateKeyPath: '/path/to/client.key',
  // );
  //
  // final task = TorrentTask.newTask(
  //   torrent,
  //   '/tmp/downloads',
  //   false,
  //   null,
  //   null,
  //   null,
  //   ProxyConfig.https(host: '127.0.0.1', port: 8080),
  //   false,
  //   sslConfig,
  //   null,
  // );
  //
  // await task.start();
  // print('SSL enabled for peers: ${task.sslConfig?.enableForPeers}');
}
