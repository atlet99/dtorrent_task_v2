import 'dart:io';
import 'dart:typed_data';

/// BEP 40 Canonical Peer Priority helper.
///
/// Reference: https://www.bittorrent.org/beps/bep_0040.html
class PeerPriority {
  /// Computes canonical peer priority between local and remote endpoints.
  ///
  /// The returned value is an unsigned 32-bit integer in [0, 2^32-1].
  static int canonicalPriority({
    required InternetAddress clientIp,
    required int clientPort,
    required InternetAddress peerIp,
    required int peerPort,
  }) {
    final clientBytes = clientIp.rawAddress;
    final peerBytes = peerIp.rawAddress;

    if (clientBytes.length == peerBytes.length) {
      if (_bytesEqual(clientBytes, peerBytes)) {
        // BEP 40: if IPs are equal, use ports.
        return _priorityForPorts(clientPort, peerPort);
      }
      return _priorityForAddresses(clientBytes, peerBytes);
    }

    // Mixed family (IPv4/IPv6) is outside BEP 40 scope.
    // Keep deterministic ordering using endpoint bytes.
    final left = Uint8List(clientBytes.length + 2)
      ..setAll(0, clientBytes)
      ..setAll(clientBytes.length, _portBytes(clientPort));
    final right = Uint8List(peerBytes.length + 2)
      ..setAll(0, peerBytes)
      ..setAll(peerBytes.length, _portBytes(peerPort));
    return _crc32c(_concatSorted(left, right));
  }

  static int _priorityForAddresses(Uint8List clientIp, Uint8List peerIp) {
    final mask = _deriveMask(clientIp, peerIp);

    final maskedClient = Uint8List(clientIp.length);
    final maskedPeer = Uint8List(peerIp.length);
    for (var i = 0; i < clientIp.length; i++) {
      maskedClient[i] = clientIp[i] & mask[i];
      maskedPeer[i] = peerIp[i] & mask[i];
    }

    return _crc32c(_concatSorted(maskedClient, maskedPeer));
  }

  static int _priorityForPorts(int clientPort, int peerPort) {
    final clientBytes = _portBytes(clientPort);
    final peerBytes = _portBytes(peerPort);
    return _crc32c(_concatSorted(clientBytes, peerBytes));
  }

  static Uint8List _deriveMask(Uint8List clientIp, Uint8List peerIp) {
    if (clientIp.length == 4) {
      // IPv4 BEP 40 masks:
      // default: FF.FF.55.55
      // same /16: FF.FF.FF.55
      // same /24: FF.FF.FF.FF
      if (clientIp[0] == peerIp[0] &&
          clientIp[1] == peerIp[1] &&
          clientIp[2] == peerIp[2]) {
        return Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
      }
      if (clientIp[0] == peerIp[0] && clientIp[1] == peerIp[1]) {
        return Uint8List.fromList([0xFF, 0xFF, 0xFF, 0x55]);
      }
      return Uint8List.fromList([0xFF, 0xFF, 0x55, 0x55]);
    }

    // IPv6 BEP 40 mask derivation:
    // base: FFFF:FFFF:FFFF:5555:...
    final mask = Uint8List(16)..fillRange(0, 16, 0x55);
    for (var i = 0; i < 6; i++) {
      mask[i] = 0xFF; // /48 base
    }

    // For each additional matching byte beyond /48, promote mask byte to 0xFF.
    var matchingBytes = 0;
    for (var i = 0; i < 16; i++) {
      if (clientIp[i] == peerIp[i]) {
        matchingBytes++;
      } else {
        break;
      }
    }
    final extra = matchingBytes - 6;
    if (extra > 0) {
      final extraBytes = extra > 10 ? 10 : extra;
      for (var i = 0; i < extraBytes; i++) {
        mask[6 + i] = 0xFF;
      }
    }

    return mask;
  }

  static Uint8List _portBytes(int port) {
    final safePort = port.clamp(0, 65535);
    return Uint8List.fromList([
      (safePort >> 8) & 0xFF,
      safePort & 0xFF,
    ]);
  }

  static Uint8List _concatSorted(Uint8List a, Uint8List b) {
    final leftFirst = _compareLexicographically(a, b) <= 0;
    final left = leftFirst ? a : b;
    final right = leftFirst ? b : a;
    return Uint8List.fromList([...left, ...right]);
  }

  static int _compareLexicographically(Uint8List a, Uint8List b) {
    final minLen = a.length < b.length ? a.length : b.length;
    for (var i = 0; i < minLen; i++) {
      final diff = a[i] - b[i];
      if (diff != 0) return diff;
    }
    return a.length - b.length;
  }

  static bool _bytesEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  // CRC32-C (Castagnoli) reflected polynomial.
  static const int _crc32cPolynomial = 0x82F63B78;

  static int _crc32c(Uint8List data) {
    var crc = 0xFFFFFFFF;
    for (final b in data) {
      crc ^= b;
      for (var i = 0; i < 8; i++) {
        if ((crc & 1) != 0) {
          crc = (crc >> 1) ^ _crc32cPolynomial;
        } else {
          crc >>= 1;
        }
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
