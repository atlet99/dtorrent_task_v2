import 'dart:typed_data';

import 'package:dtorrent_task_v2/src/encryption/protocol_encryption.dart';
import 'package:dtorrent_task_v2/src/encryption/rc4_encryption.dart';
import 'package:test/test.dart';

void main() {
  group('RC4Cipher', () {
    test('encrypt/decrypt roundtrip works', () {
      final key = Uint8List.fromList([1, 2, 3, 4, 5]);
      final plain = Uint8List.fromList('hello-bittorrent'.codeUnits);

      final enc = RC4Cipher(key).process(plain);
      final dec = RC4Cipher(key).process(enc);

      expect(dec, equals(plain));
    });
  });

  group('ProtocolEncryptionSession', () {
    test('stream encryption is symmetric for two sides', () {
      final cfg = ProtocolEncryptionConfig(
        level: EncryptionLevel.prefer,
        enableStreamEncryption: true,
      );
      final secret = 'shared-secret'.codeUnits;

      final left = ProtocolEncryptionSession.fromSharedSecret(
        config: cfg,
        sharedSecret: secret,
      );
      final right = ProtocolEncryptionSession.fromSharedSecret(
        config: cfg,
        sharedSecret: secret,
      );

      final payload = Uint8List.fromList(List<int>.generate(64, (i) => i));
      final encrypted = left.encryptOutbound(payload);
      final decrypted = right.decryptInbound(encrypted);

      expect(decrypted, equals(payload));
    });

    test('obfuscation is symmetric', () {
      final cfg = ProtocolEncryptionConfig(
        level: EncryptionLevel.prefer,
        enableMessageObfuscation: true,
      );
      final secret = 'obfuscation-secret'.codeUnits;
      final left = ProtocolEncryptionSession.fromSharedSecret(
        config: cfg,
        sharedSecret: secret,
      );
      final right = ProtocolEncryptionSession.fromSharedSecret(
        config: cfg,
        sharedSecret: secret,
      );

      final payload = Uint8List.fromList('payload'.codeUnits);
      final encrypted = left.encryptOutbound(payload);
      final decrypted = right.decryptInbound(encrypted);

      expect(decrypted, equals(payload));
    });

    test('config isEnabled reflects level and flags', () {
      expect(
        const ProtocolEncryptionConfig(
          level: EncryptionLevel.disable,
          enableStreamEncryption: true,
        ).isEnabled,
        isFalse,
      );
      expect(
        const ProtocolEncryptionConfig(
          level: EncryptionLevel.prefer,
          enableStreamEncryption: true,
        ).isEnabled,
        isTrue,
      );
    });
  });
}
