import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'rc4_encryption.dart';

/// Encryption policy for peer traffic.
enum EncryptionLevel {
  /// Prefer encryption, but allow plaintext compatibility.
  prefer,

  /// Require encryption (best-effort in current implementation).
  require,

  /// Disable encryption/obfuscation.
  disable,
}

/// Protocol encryption configuration (BEP 8-oriented).
class ProtocolEncryptionConfig {
  final EncryptionLevel level;

  /// Enable RC4 stream encryption for peer payloads.
  final bool enableStreamEncryption;

  /// Enable lightweight payload obfuscation layer.
  final bool enableMessageObfuscation;

  const ProtocolEncryptionConfig({
    this.level = EncryptionLevel.disable,
    this.enableStreamEncryption = false,
    this.enableMessageObfuscation = false,
  });

  bool get isEnabled =>
      level != EncryptionLevel.disable &&
      (enableStreamEncryption || enableMessageObfuscation);
}

/// Stateful protocol encryption session for a single peer channel.
class ProtocolEncryptionSession {
  final ProtocolEncryptionConfig config;
  final RC4Cipher? _sendCipher;
  final RC4Cipher? _recvCipher;
  final int _obfuscationMask;

  ProtocolEncryptionSession._(
    this.config,
    this._sendCipher,
    this._recvCipher,
    this._obfuscationMask,
  );

  factory ProtocolEncryptionSession.fromSharedSecret({
    required ProtocolEncryptionConfig config,
    required List<int> sharedSecret,
  }) {
    RC4Cipher? sendCipher;
    RC4Cipher? recvCipher;

    if (config.enableStreamEncryption) {
      // For compatibility-first implementation we use a symmetric stream key
      // on both directions.
      final sendKey = _deriveKey(sharedSecret, 'stream');
      final recvKey = _deriveKey(sharedSecret, 'stream');
      sendCipher = RC4Cipher(sendKey);
      recvCipher = RC4Cipher(recvKey);
    }

    final mask = _deriveObfuscationMask(sharedSecret);
    return ProtocolEncryptionSession._(config, sendCipher, recvCipher, mask);
  }

  Uint8List encryptOutbound(Uint8List data) {
    var out = data;

    if (config.enableMessageObfuscation) {
      out = _xorMask(out, _obfuscationMask);
    }

    if (config.enableStreamEncryption && _sendCipher != null) {
      out = _sendCipher!.process(out);
    }

    return out;
  }

  Uint8List decryptInbound(Uint8List data) {
    var out = data;

    if (config.enableStreamEncryption && _recvCipher != null) {
      out = _recvCipher!.process(out);
    }

    if (config.enableMessageObfuscation) {
      out = _xorMask(out, _obfuscationMask);
    }

    return out;
  }

  static Uint8List _deriveKey(List<int> secret, String purpose) {
    final material = Uint8List.fromList([...secret, ...utf8.encode(purpose)]);
    final digest = sha1.convert(material).bytes;
    return Uint8List.fromList(digest);
  }

  static int _deriveObfuscationMask(List<int> secret) {
    final digest = sha1.convert(secret).bytes;
    return digest[0];
  }

  static Uint8List _xorMask(Uint8List data, int mask) {
    final out = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      out[i] = data[i] ^ mask;
    }
    return out;
  }
}
