import 'dart:typed_data';

/// Stateful RC4 stream cipher implementation.
///
/// Note: RC4 is considered cryptographically weak by modern standards.
/// It is provided here for BitTorrent protocol-compatibility scenarios.
class RC4Cipher {
  final Uint8List _s = Uint8List(256);
  int _i = 0;
  int _j = 0;

  RC4Cipher(Uint8List key) {
    if (key.isEmpty) {
      throw ArgumentError('RC4 key must not be empty');
    }

    for (var i = 0; i < 256; i++) {
      _s[i] = i;
    }

    var j = 0;
    for (var i = 0; i < 256; i++) {
      j = (j + _s[i] + key[i % key.length]) & 0xff;
      final tmp = _s[i];
      _s[i] = _s[j];
      _s[j] = tmp;
    }
  }

  /// Encrypt/decrypt bytes in-place semantics (RC4 is symmetric).
  Uint8List process(Uint8List data) {
    final out = Uint8List(data.length);
    for (var n = 0; n < data.length; n++) {
      _i = (_i + 1) & 0xff;
      _j = (_j + _s[_i]) & 0xff;

      final tmp = _s[_i];
      _s[_i] = _s[_j];
      _s[_j] = tmp;

      final k = _s[(_s[_i] + _s[_j]) & 0xff];
      out[n] = data[n] ^ k;
    }
    return out;
  }
}
