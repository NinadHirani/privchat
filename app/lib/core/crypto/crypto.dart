// Single choke-point for every libsodium call. If the `sodium` package API
// ever shifts, this is the ONLY file that needs touching.
import 'dart:convert';
import 'dart:typed_data';
import 'package:sodium_libs/sodium_libs.dart';

class Crypto {
  Crypto._(this._s);
  final SodiumSumo _s;
  static Crypto? _instance;
  static Crypto get I => _instance ?? (throw StateError('Crypto not initialised'));

  static Future<void> init() async {
    _instance ??= Crypto._(await SodiumSumoInit.init());
  }

  // ---- helpers -------------------------------------------------------------
  SecureKey _key(Uint8List k) => SecureKey.fromList(_s, k);

  /// Some sodium APIs return SecureKey, others Uint8List (varies by version). Normalise.
  static Uint8List _bytes(dynamic x) {
    if (x is Uint8List) return x;
    if (x is SecureKey) {
      final b = x.extractBytes();
      x.dispose();
      return b;
    }
    throw StateError('unexpected sodium return type ${x.runtimeType}');
  }

  Uint8List random(int n) => _s.randombytes.buf(n);

  Uint8List blake2b(Uint8List data, {int outLen = 32, Uint8List? key}) {
    final k = key == null ? null : _key(key);
    try {
      return _s.crypto.genericHash.call(message: data, outLen: outLen, key: k);
    } finally {
      k?.dispose();
    }
  }

  // ---- Ed25519 -------------------------------------------------------------
  /// Returns (ed_pk, ed_sk[64]).
  (Uint8List, Uint8List) signSeedKeyPair(Uint8List seed) {
    final s = _key(seed);
    try {
      final kp = _s.crypto.sign.seedKeyPair(s);
      final sk = kp.secretKey.extractBytes();
      kp.secretKey.dispose();
      return (kp.publicKey, sk);
    } finally {
      s.dispose();
    }
  }

  (Uint8List, Uint8List) signKeyPair() => signSeedKeyPair(random(32));

  Uint8List sign(Uint8List msg, Uint8List edSk) {
    final k = _key(edSk);
    try {
      return _s.crypto.sign.detached(message: msg, secretKey: k);
    } finally {
      k.dispose();
    }
  }

  bool verify(Uint8List msg, Uint8List sig, Uint8List edPk) {
    try {
      return _s.crypto.sign.verifyDetached(message: msg, signature: sig, publicKey: edPk);
    } catch (_) {
      return false;
    }
  }

  Uint8List edPkToX(Uint8List edPk) => _s.crypto.sign.pkToCurve25519(edPk);

  Uint8List edSkToX(Uint8List edSk) {
    final k = _key(edSk);
    try {
      final dynamic x = _s.crypto.sign.skToCurve25519(k);
      return _bytes(x);
    } finally {
      k.dispose();
    }
  }

  // ---- X25519 --------------------------------------------------------------
  Uint8List scalarmultBase(Uint8List sk) {
    final k = _key(sk);
    try {
      final dynamic r = _s.crypto.scalarmult.base(n: k);
      return _bytes(r);
    } finally {
      k.dispose();
    }
  }

  Uint8List scalarmult(Uint8List sk, Uint8List pk) {
    final k = _key(sk);
    try {
      final dynamic r = _s.crypto.scalarmult.call(n: k, p: pk);
      return _bytes(r);
    } finally {
      k.dispose();
    }
  }

  // ---- XChaCha20-Poly1305-IETF --------------------------------------------
  Uint8List aeadEncrypt(Uint8List pt, Uint8List nonce, Uint8List key, Uint8List ad) {
    final k = _key(key);
    try {
      return _s.crypto.aeadXChaCha20Poly1305IETF
          .encrypt(message: pt, nonce: nonce, key: k, additionalData: ad);
    } finally {
      k.dispose();
    }
  }

  /// Throws on authentication failure.
  Uint8List aeadDecrypt(Uint8List ct, Uint8List nonce, Uint8List key, Uint8List ad) {
    final k = _key(key);
    try {
      return _s.crypto.aeadXChaCha20Poly1305IETF
          .decrypt(cipherText: ct, nonce: nonce, key: k, additionalData: ad);
    } finally {
      k.dispose();
    }
  }

  // ---- encodings -----------------------------------------------------------
  static String b64e(List<int> b) => base64Encode(b);
  static Uint8List b64d(String s) => base64Decode(s);
  static Uint8List utf8e(String s) => Uint8List.fromList(utf8.encode(s));

  static const _b32 = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
  static String b32NoPad(Uint8List data) {
    final out = StringBuffer();
    int bits = 0, value = 0;
    for (final byte in data) {
      value = (value << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        out.write(_b32[(value >> (bits - 5)) & 31]);
        bits -= 5;
      }
    }
    if (bits > 0) out.write(_b32[(value << (5 - bits)) & 31]);
    return out.toString();
  }

  static Uint8List concat(List<List<int>> parts) {
    final b = BytesBuilder(copy: false);
    for (final p in parts) b.add(p);
    return b.toBytes();
  }

  static Uint8List u32be(int n) => Uint8List(4)..buffer.asByteData().setUint32(0, n);
  static Uint8List u16be(int n) => Uint8List(2)..buffer.asByteData().setUint16(0, n);
  static Uint8List u64be(int n) => Uint8List(8)..buffer.asByteData().setUint64(0, n);
  static int readU32be(Uint8List b, [int off = 0]) => ByteData.sublistView(b, off, off + 4).getUint32(0);

  static bool constEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var r = 0;
    for (var i = 0; i < a.length; i++) r |= a[i] ^ b[i];
    return r == 0;
  }

  /// Canonical JSON: sorted keys, no whitespace (matches Python sort_keys/separators).
  static String canonicalJson(Object? v) {
    if (v is Map) {
      final keys = v.keys.map((k) => k.toString()).toList()..sort();
      return '{${keys.map((k) => '${jsonEncode(k)}:${canonicalJson(v[k])}').join(',')}}';
    }
    if (v is List) return '[${v.map(canonicalJson).join(',')}]';
    return jsonEncode(v);
  }
}
