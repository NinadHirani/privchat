import 'dart:typed_data';
import 'crypto.dart';

String userIdFromEdPk(Uint8List edPk) =>
    Crypto.b32NoPad(Crypto.I.blake2b(edPk, outLen: 20));

/// 60-digit safety number, symmetric in (a, b). Shown as 12 groups of 5.
String safetyNumber(Uint8List a, Uint8List b) {
  final cmp = _compare(a, b);
  final lo = cmp <= 0 ? a : b, hi = cmp <= 0 ? b : a;
  final h = Crypto.I.blake2b(
      Crypto.concat([Crypto.utf8e('privchat-safety-v1'), lo, hi]), outLen: 32);
  var n = BigInt.zero;
  for (final x in h) n = (n << 8) | BigInt.from(x);
  final digits = (n % BigInt.from(10).pow(60)).toString().padLeft(60, '0');
  return [for (var i = 0; i < 60; i += 5) digits.substring(i, i + 5)].join(' ');
}

int _compare(Uint8List a, Uint8List b) {
  for (var i = 0; i < a.length && i < b.length; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return a.length - b.length;
}

class Identity {
  Identity._(this.seed, this.edPk, this.edSk, this.xPk, this.xSk);
  final Uint8List seed, edPk, edSk, xPk, xSk;

  factory Identity.fromSeed(Uint8List seed) {
    assert(seed.length == 32);
    final (edPk, edSk) = Crypto.I.signSeedKeyPair(seed);
    return Identity._(seed, edPk, edSk, Crypto.I.edPkToX(edPk), Crypto.I.edSkToX(edSk));
  }
  factory Identity.generate() => Identity.fromSeed(Crypto.I.random(32));

  late final String userId = userIdFromEdPk(edPk);
  Uint8List sign(Uint8List msg) => Crypto.I.sign(msg, edSk);
  static bool verify(Uint8List edPk, Uint8List msg, Uint8List sig) => Crypto.I.verify(msg, sig, edPk);
}
