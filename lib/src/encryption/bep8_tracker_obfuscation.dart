import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'rc4_encryption.dart';

/// BEP 8 tracker obfuscation helpers.
///
/// Spec: https://www.bittorrent.org/beps/bep_0008.html
class Bep8TrackerObfuscation {
  static const int _dropBytes = 768;
  static const int _reservedBytes = 8;

  /// sha_ih = sha1(info_hash)
  static Uint8List shaIh(Uint8List infoHash) {
    return Uint8List.fromList(sha1.convert(infoHash).bytes);
  }

  /// Derive BEP 8 RC4 key.
  ///
  /// - no `iv`: key is raw infohash.
  /// - with `iv`: key is sha1(infohash || iv).
  static Uint8List deriveKey(Uint8List infoHash, {Uint8List? iv}) {
    if (iv == null || iv.isEmpty) {
      return Uint8List.fromList(infoHash);
    }
    return Uint8List.fromList(
      sha1.convert(Uint8List.fromList([...infoHash, ...iv])).bytes,
    );
  }

  /// Obfuscate announce port as unsigned 16-bit integer.
  static int obfuscateAnnouncePort({
    required Uint8List infoHash,
    required int port,
  }) {
    final input = Uint8List.fromList([
      (port >> 8) & 0xff,
      port & 0xff,
    ]);
    final output = _xorWithBep8Stream(
      plaintext: input,
      key: deriveKey(infoHash),
      offset: 0,
      cycleLength: null,
    );
    return (output[0] << 8) | output[1];
  }

  /// Obfuscate announce ip bytes.
  static Uint8List obfuscateAnnounceIp({
    required Uint8List infoHash,
    required InternetAddress ip,
  }) {
    final input = Uint8List.fromList(ip.rawAddress);
    return _xorWithBep8Stream(
      plaintext: input,
      key: deriveKey(infoHash),
      offset: 0,
      cycleLength: null,
    );
  }

  /// Deobfuscate tracker response peer list (`peers`/`peers6`).
  ///
  /// `offset` corresponds to 6*i (ipv4) or 18*i (ipv6) into pseudorandom stream
  /// after drop+reserved bytes.
  static Uint8List deobfuscatePeerList({
    required Uint8List ciphertext,
    required Uint8List infoHash,
    Uint8List? iv,
    required int offset,
    int? n,
  }) {
    return _xorWithBep8Stream(
      plaintext: ciphertext,
      key: deriveKey(infoHash, iv: iv),
      offset: offset,
      cycleLength: n,
    );
  }

  /// Decode `i` and `n` optimization fields from BEP 8 response.
  ///
  /// Returns `(decodedI, decodedN)`.
  static ({int i, int n}) decodeIAndN({
    required int encodedI,
    required int encodedN,
    required Uint8List infoHash,
    Uint8List? iv,
  }) {
    final prefix = _generatePseudorandomPrefix(deriveKey(infoHash, iv: iv));
    final x =
        (prefix[0] << 24) | (prefix[1] << 16) | (prefix[2] << 8) | prefix[3];
    final y =
        (prefix[4] << 24) | (prefix[5] << 16) | (prefix[6] << 8) | prefix[7];
    return (i: encodedI ^ x, n: encodedN ^ y);
  }

  static Uint8List _generatePseudorandomPrefix(Uint8List key) {
    final rc4 = RC4Cipher(key);
    final skipped = rc4.process(Uint8List(_dropBytes + _reservedBytes));
    return skipped.sublist(_dropBytes, _dropBytes + _reservedBytes);
  }

  static Uint8List _xorWithBep8Stream({
    required Uint8List plaintext,
    required Uint8List key,
    required int offset,
    int? cycleLength,
  }) {
    final total = _dropBytes + _reservedBytes + offset + plaintext.length;
    final rc4 = RC4Cipher(key);
    final keystream = rc4.process(Uint8List(total));
    final base = _dropBytes + _reservedBytes;
    final out = Uint8List(plaintext.length);

    for (var i = 0; i < plaintext.length; i++) {
      final ksIndex = (cycleLength != null && cycleLength > 0)
          ? base + ((offset + i) % cycleLength)
          : base + offset + i;
      out[i] = plaintext[i] ^ keystream[ksIndex];
    }

    return out;
  }
}
