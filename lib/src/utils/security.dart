import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

/// Cryptographic hashing, message authentication, and constant-time utilities
/// for securing GameForge save payloads and runtime identifiers.
///
/// Implemented in pure Dart using explicit 32-bit unsigned masking so outputs
/// are bit-for-bit identical across Dart VM, JavaScript, and WebAssembly.
abstract final class GameSecurity {
  /// Maximum integer guaranteed to round-trip without precision loss across
  /// Dart VM, JavaScript numbers, and JSON (`2^53 - 1`).
  static const int maxSafeInteger = 9007199254740991;

  /// Length of a SHA-256 digest in bytes.
  static const int sha256DigestLength = 32;

  /// Length of a lowercase hex-encoded SHA-256 digest or HMAC-SHA256 tag.
  static const int sha256HexLength = 64;

  static final Random _secureRandom = Random.secure();

  static const List<int> _initialHash = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  static const List<int> _roundConstants = <int>[
    0x428a2f98,
    0x71374491,
    0xb5c0fbcf,
    0xe9b5dba5,
    0x3956c25b,
    0x59f111f1,
    0x923f82a4,
    0xab1c5ed5,
    0xd807aa98,
    0x12835b01,
    0x243185be,
    0x550c7dc3,
    0x72be5d74,
    0x80deb1fe,
    0x9bdc06a7,
    0xc19bf174,
    0xe49b69c1,
    0xefbe4786,
    0x0fc19dc6,
    0x240ca1cc,
    0x2de92c6f,
    0x4a7484aa,
    0x5cb0a9dc,
    0x76f988da,
    0x983e5152,
    0xa831c66d,
    0xb00327c8,
    0xbf597fc7,
    0xc6e00bf3,
    0xd5a79147,
    0x06ca6351,
    0x14292967,
    0x27b70a85,
    0x2e1b2138,
    0x4d2c6dfc,
    0x53380d13,
    0x650a7354,
    0x766a0abb,
    0x81c2c92e,
    0x92722c85,
    0xa2bfe8a1,
    0xa81a664b,
    0xc24b8b70,
    0xc76c51a3,
    0xd192e819,
    0xd6990624,
    0xf40e3585,
    0x106aa070,
    0x19a4c116,
    0x1e376c08,
    0x2748774c,
    0x34b0bcb5,
    0x391c0cb3,
    0x4ed8aa4a,
    0x5b9cca4f,
    0x682e6ff3,
    0x748f82ee,
    0x78a5636f,
    0x84c87814,
    0x8cc70208,
    0x90befffa,
    0xa4506ceb,
    0xbef9a3f7,
    0xc67178f2,
  ];

  /// Computes a SHA-256 digest (FIPS 180-4 / RFC 6234) over [data].
  ///
  /// Throws a [RangeError] if any element in [data] is outside `0..255`.
  static Uint8List sha256Bytes(List<int> data) {
    final validated = _validateBytes(data, 'data');
    final paddedLength = ((validated.length + 9 + 63) ~/ 64) * 64;
    final padded = Uint8List(paddedLength)..setAll(0, validated);
    padded[validated.length] = 0x80;

    // Bit length written as 64-bit big-endian integer without >32-bit shifts.
    final bitLenHi = validated.length ~/ 0x20000000;
    final bitLenLo = ((validated.length & 0x1FFFFFFF) << 3) & 0xFFFFFFFF;
    final lenOffset = paddedLength - 8;
    _writeUint32BE(padded, lenOffset, bitLenHi);
    _writeUint32BE(padded, lenOffset + 4, bitLenLo);

    var h0 = _initialHash[0];
    var h1 = _initialHash[1];
    var h2 = _initialHash[2];
    var h3 = _initialHash[3];
    var h4 = _initialHash[4];
    var h5 = _initialHash[5];
    var h6 = _initialHash[6];
    var h7 = _initialHash[7];

    final w = Uint32List(64);

    for (var offset = 0; offset < paddedLength; offset += 64) {
      for (var t = 0; t < 16; t++) {
        final i = offset + (t * 4);
        w[t] =
            ((padded[i] << 24) |
                (padded[i + 1] << 16) |
                (padded[i + 2] << 8) |
                padded[i + 3]) &
            0xFFFFFFFF;
      }

      for (var t = 16; t < 64; t++) {
        final w15 = w[t - 15];
        final w2 = w[t - 2];
        final s0 =
            (_rotr32(w15, 7) ^ _rotr32(w15, 18) ^ (w15 >>> 3)) & 0xFFFFFFFF;
        final s1 =
            (_rotr32(w2, 17) ^ _rotr32(w2, 19) ^ (w2 >>> 10)) & 0xFFFFFFFF;
        w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xFFFFFFFF;
      }

      var a = h0;
      var b = h1;
      var c = h2;
      var d = h3;
      var e = h4;
      var f = h5;
      var g = h6;
      var h = h7;

      for (var t = 0; t < 64; t++) {
        final s1 =
            (_rotr32(e, 6) ^ _rotr32(e, 11) ^ _rotr32(e, 25)) & 0xFFFFFFFF;
        final ch = ((e & f) ^ ((~e & 0xFFFFFFFF) & g)) & 0xFFFFFFFF;
        final temp1 = (h + s1 + ch + _roundConstants[t] + w[t]) & 0xFFFFFFFF;
        final s0 =
            (_rotr32(a, 2) ^ _rotr32(a, 13) ^ _rotr32(a, 22)) & 0xFFFFFFFF;
        final maj = ((a & b) ^ (a & c) ^ (b & c)) & 0xFFFFFFFF;
        final temp2 = (s0 + maj) & 0xFFFFFFFF;

        h = g;
        g = f;
        f = e;
        e = (d + temp1) & 0xFFFFFFFF;
        d = c;
        c = b;
        b = a;
        a = (temp1 + temp2) & 0xFFFFFFFF;
      }

      h0 = (h0 + a) & 0xFFFFFFFF;
      h1 = (h1 + b) & 0xFFFFFFFF;
      h2 = (h2 + c) & 0xFFFFFFFF;
      h3 = (h3 + d) & 0xFFFFFFFF;
      h4 = (h4 + e) & 0xFFFFFFFF;
      h5 = (h5 + f) & 0xFFFFFFFF;
      h6 = (h6 + g) & 0xFFFFFFFF;
      h7 = (h7 + h) & 0xFFFFFFFF;
    }

    zeroBytes(w);

    final out = Uint8List(sha256DigestLength);
    _writeUint32BE(out, 0, h0);
    _writeUint32BE(out, 4, h1);
    _writeUint32BE(out, 8, h2);
    _writeUint32BE(out, 12, h3);
    _writeUint32BE(out, 16, h4);
    _writeUint32BE(out, 20, h5);
    _writeUint32BE(out, 24, h6);
    _writeUint32BE(out, 28, h7);
    return out;
  }

  /// Computes a lowercase hexadecimal SHA-256 digest over [data].
  static String sha256Hex(List<int> data) => _bytesToHex(sha256Bytes(data));

  /// Computes a lowercase hexadecimal SHA-256 digest of UTF-8 encoded [input].
  static String sha256Utf8(String input) => sha256Hex(utf8.encode(input));

  /// Computes an HMAC-SHA256 authentication tag (RFC 2104) for [data] using [key].
  ///
  /// Throws an [ArgumentError] if [key] is empty or contains non-byte values.
  static Uint8List hmacSha256Bytes({
    required List<int> key,
    required List<int> data,
  }) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'HMAC key must not be empty.');
    }

    final validatedKey = _validateBytes(key, 'key');
    final validatedData = _validateBytes(data, 'data');

    const blockSize = 64;
    final keyBlock = Uint8List(blockSize);
    if (validatedKey.length > blockSize) {
      final hashedKey = sha256Bytes(validatedKey);
      keyBlock.setAll(0, hashedKey);
      zeroBytes(hashedKey);
    } else {
      keyBlock.setAll(0, validatedKey);
    }

    final iKeyPad = Uint8List(blockSize);
    final oKeyPad = Uint8List(blockSize);
    for (var i = 0; i < blockSize; i++) {
      iKeyPad[i] = keyBlock[i] ^ 0x36;
      oKeyPad[i] = keyBlock[i] ^ 0x5c;
    }

    final innerInput = Uint8List(blockSize + validatedData.length)
      ..setAll(0, iKeyPad)
      ..setAll(blockSize, validatedData);
    final innerHash = sha256Bytes(innerInput);

    final outerInput = Uint8List(blockSize + sha256DigestLength)
      ..setAll(0, oKeyPad)
      ..setAll(blockSize, innerHash);

    try {
      return sha256Bytes(outerInput);
    } finally {
      zeroBytes(validatedKey);
      zeroBytes(keyBlock);
      zeroBytes(iKeyPad);
      zeroBytes(oKeyPad);
      zeroBytes(innerInput);
      zeroBytes(innerHash);
      zeroBytes(outerInput);
    }
  }

  /// Computes a lowercase hexadecimal HMAC-SHA256 authentication tag.
  static String hmacSha256Hex({
    required List<int> key,
    required List<int> data,
  }) => _bytesToHex(hmacSha256Bytes(key: key, data: data));

  /// Compares two byte lists in constant time relative to their byte contents.
  static bool constantTimeEquals(List<int> a, List<int> b) {
    var diff = a.length ^ b.length;
    final maxLen = a.length > b.length ? a.length : b.length;
    for (var i = 0; i < maxLen; i++) {
      final aByte = i < a.length ? a[i] : 0;
      final bByte = i < b.length ? b[i] : 0;
      diff |= aByte ^ bByte;
    }
    return diff == 0;
  }

  /// Compares two strings in constant time over UTF-16 code units.
  static bool constantTimeStringEquals(String a, String b) =>
      constantTimeEquals(a.codeUnits, b.codeUnits);

  /// Compares two hexadecimal digest strings in constant time.
  ///
  /// Both strings must be non-empty, contain only hexadecimal digits
  /// (`0-9`, `a-f`, `A-F`), and match after ASCII lowercase normalization.
  static bool constantTimeHexEquals(String a, String b) {
    final aUnits = a.codeUnits;
    final bUnits = b.codeUnits;
    if (aUnits.isEmpty || bUnits.isEmpty) {
      return false;
    }

    var diff = aUnits.length ^ bUnits.length;
    var invalid = 0;
    final maxLen = aUnits.length > bUnits.length
        ? aUnits.length
        : bUnits.length;
    for (var i = 0; i < maxLen; i++) {
      final rawA = i < aUnits.length ? aUnits[i] : 0x30;
      final rawB = i < bUnits.length ? bUnits[i] : 0x30;
      final normA = _normalizeHexUnit(rawA);
      final normB = _normalizeHexUnit(rawB);
      if (normA < 0 || normB < 0) {
        invalid |= 1;
      }
      diff |= (normA & 0xFF) ^ (normB & 0xFF);
    }
    return invalid == 0 && diff == 0;
  }

  /// Generates [length] cryptographically strong random bytes.
  static Uint8List generateRandomBytes(int length) {
    if (length <= 0) {
      throw RangeError.value(length, 'length', 'Must be greater than zero.');
    }
    final bytes = Uint8List(length);
    for (var i = 0; i < length; i++) {
      bytes[i] = _secureRandom.nextInt(256);
    }
    return bytes;
  }

  /// Generates a cryptographically strong lowercase hexadecimal token.
  static String generateSecureToken({int byteLength = 32}) =>
      _bytesToHex(generateRandomBytes(byteLength));

  /// Overwrites a mutable byte or integer buffer with zeros.
  static void zeroBytes(List<int> buffer) {
    buffer.fillRange(0, buffer.length, 0);
  }

  static Uint8List _validateBytes(List<int> bytes, String name) {
    final out = Uint8List(bytes.length);
    for (var i = 0; i < bytes.length; i++) {
      final b = bytes[i];
      if (b < 0 || b > 0xFF) {
        throw RangeError.range(b, 0, 255, '$name[$i]');
      }
      out[i] = b;
    }
    return out;
  }

  static int _rotr32(int value, int shift) {
    final masked = value & 0xFFFFFFFF;
    return ((masked >>> shift) | (masked << (32 - shift))) & 0xFFFFFFFF;
  }

  static void _writeUint32BE(Uint8List target, int offset, int value) {
    final v = value & 0xFFFFFFFF;
    target[offset] = (v >>> 24) & 0xFF;
    target[offset + 1] = (v >>> 16) & 0xFF;
    target[offset + 2] = (v >>> 8) & 0xFF;
    target[offset + 3] = v & 0xFF;
  }

  static int _normalizeHexUnit(int codeUnit) {
    if (codeUnit >= 0x30 && codeUnit <= 0x39) {
      return codeUnit;
    }
    if (codeUnit >= 0x61 && codeUnit <= 0x66) {
      return codeUnit;
    }
    if (codeUnit >= 0x41 && codeUnit <= 0x46) {
      return codeUnit | 0x20;
    }
    return -1;
  }

  static String _bytesToHex(Uint8List bytes) {
    const hexChars = '0123456789abcdef';
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer
        ..write(hexChars[(byte >>> 4) & 0x0F])
        ..write(hexChars[byte & 0x0F]);
    }
    return buffer.toString();
  }
}
