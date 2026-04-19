import 'dart:io';

/// SSL/TLS configuration for tracker and peer connections.
class SSLConfig {
  /// Enable TLS for peer sockets.
  final bool enableForPeers;

  /// Validate server certificates.
  final bool validateCertificates;

  /// Allow self-signed certificates.
  final bool allowSelfSigned;

  /// Optional trusted CA certificate path.
  final String? trustedCaPath;

  /// Optional client certificate chain path.
  final String? clientCertificatePath;

  /// Optional client private key path.
  final String? clientPrivateKeyPath;

  /// Optional private key password.
  final String? privateKeyPassword;

  const SSLConfig({
    this.enableForPeers = false,
    this.validateCertificates = true,
    this.allowSelfSigned = false,
    this.trustedCaPath,
    this.clientCertificatePath,
    this.clientPrivateKeyPath,
    this.privateKeyPassword,
  });

  SecurityContext buildSecurityContext() {
    final context = SecurityContext.defaultContext;
    if (trustedCaPath != null && trustedCaPath!.isNotEmpty) {
      context.setTrustedCertificates(trustedCaPath!);
    }
    if (clientCertificatePath != null && clientCertificatePath!.isNotEmpty) {
      context.useCertificateChain(clientCertificatePath!);
    }
    if (clientPrivateKeyPath != null && clientPrivateKeyPath!.isNotEmpty) {
      context.usePrivateKey(
        clientPrivateKeyPath!,
        password: privateKeyPassword,
      );
    }
    return context;
  }

  bool onBadCertificate(X509Certificate cert) {
    if (!validateCertificates) return true;
    if (allowSelfSigned) return true;
    return false;
  }
}
