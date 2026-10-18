import 'dart:convert';
import 'dart:typed_data';
import 'crypto.dart';
import 'identity.dart';

const protocolVersion = 1;
const helloMaxSkewMs = 10 * 60 * 1000;
const ptJson = 0x01;
const ptFileChunk = 0x02;

class ProtocolException implements Exception {
  ProtocolException(this.message);
  final String message;
  @override
  String toString() => 'ProtocolException: $message';
}

class Hello {
  Hello(this.edPk, this.ephPk, this.ts, this.nonce, this.name, this.sig);
  final Uint8List edPk, ephPk, nonce, sig;
  final int ts;
  final String name;
  late final String userId = userIdFromEdPk(edPk);

  static Uint8List signingBytes(Uint8List edPk, Uint8List ephPk, int ts, Uint8List nonce, String name) {
    final nb = Crypto.utf8e(name);
    return Crypto.concat([
      Crypto.utf8e('privchat-hello-v1'), edPk, ephPk, Crypto.u64be(ts), nonce, Crypto.u16be(nb.length), nb
    ]);
  }

  static Uint8List build(Identity id, Uint8List ephPk, String name, {int? ts, Uint8List? nonce}) {
    ts ??= DateTime.now().millisecondsSinceEpoch;
    nonce ??= Crypto.I.random(16);
    final sig = id.sign(signingBytes(id.edPk, ephPk, ts, nonce, name));
    return Crypto.utf8e(Crypto.canonicalJson({
      'v': protocolVersion, 'ed': Crypto.b64e(id.edPk), 'eph': Crypto.b64e(ephPk),
      'ts': ts, 'nonce': Crypto.b64e(nonce), 'name': name, 'sig': Crypto.b64e(sig),
    }));
  }

  static Hello verify(Uint8List payload, {int? nowMs}) {
    final d = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    if (d['v'] != protocolVersion) throw ProtocolException('unsupported protocol version');
    final h = Hello(Crypto.b64d(d['ed']), Crypto.b64d(d['eph']), (d['ts'] as num).toInt(),
        Crypto.b64d(d['nonce']), d['name'] as String, Crypto.b64d(d['sig']));
    if (h.edPk.length != 32 || h.ephPk.length != 32 || h.nonce.length != 16 || h.sig.length != 64) {
      throw ProtocolException('bad hello field lengths');
    }
    if (h.name.length > 64) throw ProtocolException('name too long');
    if (!Identity.verify(h.edPk, signingBytes(h.edPk, h.ephPk, h.ts, h.nonce, h.name), h.sig)) {
      throw ProtocolException('bad hello signature');
    }
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    if ((now - h.ts).abs() > helloMaxSkewMs) throw ProtocolException('hello timestamp outside allowed skew');
    return h;
  }
}

/// Pairwise forward-secret session. Mirrors protocol/privchat_protocol/session.py.
class Session {
  Session(this.ident, this.name, {Uint8List? ephSk}) {
    _ephSk = ephSk ?? Crypto.I.random(32);
    ephPk = Crypto.I.scalarmultBase(_ephSk);
  }
  final Identity ident;
  final String name;
  late Uint8List _ephSk;
  late final Uint8List ephPk;
  Hello? peer;
  Uint8List? sid;
  Uint8List? _sendCk, _recvCk;
  int sendN = 0, recvN = 0;
  bool get established => sid != null;

  Uint8List hello({int? ts, Uint8List? nonce}) => Hello.build(ident, ephPk, name, ts: ts, nonce: nonce);

  Hello accept(Uint8List peerHello, {int? nowMs}) {
    final h = Hello.verify(peerHello, nowMs: nowMs);
    if (Crypto.constEq(h.edPk, ident.edPk)) throw ProtocolException('refusing to talk to self');
    peer = h;
    _derive(h);
    return h;
  }

  void _derive(Hello h) {
    final iAmA = ident.userId.compareTo(h.userId) < 0;
    final peerIk = Crypto.I.edPkToX(h.edPk);
    final c = Crypto.I;
    final dh1 = c.scalarmult(_ephSk, h.ephPk);
    Uint8List dh2, dh3, ephA, ephB;
    if (iAmA) {
      dh2 = c.scalarmult(ident.xSk, h.ephPk);
      dh3 = c.scalarmult(_ephSk, peerIk);
      ephA = ephPk; ephB = h.ephPk;
    } else {
      dh2 = c.scalarmult(_ephSk, peerIk);
      dh3 = c.scalarmult(ident.xSk, h.ephPk);
      ephA = h.ephPk; ephB = ephPk;
    }
    final master = c.blake2b(Crypto.concat([Crypto.utf8e('privchat-3dh-v1'), dh1, dh2, dh3]));
    sid = c.blake2b(Crypto.concat([Crypto.utf8e('privchat-sid-v1'), ephA, ephB]), outLen: 16);
    final ckA2B = c.blake2b(Crypto.utf8e('A2B'), key: master);
    final ckB2A = c.blake2b(Crypto.utf8e('B2A'), key: master);
    _sendCk = iAmA ? ckA2B : ckB2A;
    _recvCk = iAmA ? ckB2A : ckA2B;
    _ephSk.fillRange(0, 32, 0);
    master.fillRange(0, 32, 0);
  }

  static (Uint8List, Uint8List) step(Uint8List ck) => (
        Crypto.I.blake2b(Uint8List.fromList([1]), key: ck),
        Crypto.I.blake2b(Uint8List.fromList([2]), key: ck),
      );

  Uint8List _ad(int n) => Crypto.concat([sid!, Crypto.u32be(n)]);

  /// Returns ENC frame payload: u32 counter || nonce(24) || ct
  Uint8List encrypt(int ptype, Uint8List body, {Uint8List? nonce}) {
    if (!established) throw ProtocolException('session not established');
    final (mk, nck) = step(_sendCk!);
    _sendCk!.fillRange(0, 32, 0);
    _sendCk = nck;
    final n = sendN++;
    nonce ??= Crypto.I.random(24);
    final ct = Crypto.I.aeadEncrypt(Crypto.concat([[ptype], body]), nonce, mk, _ad(n));
    mk.fillRange(0, 32, 0);
    return Crypto.concat([Crypto.u32be(n), nonce, ct]);
  }

  /// Returns (ptype, body). Throws on tamper / replay / reorder.
  (int, Uint8List) decrypt(Uint8List payload) {
    if (!established) throw ProtocolException('session not established');
    if (payload.length < 4 + 24 + 16) throw ProtocolException('short payload');
    final n = Crypto.readU32be(payload);
    if (n != recvN) throw ProtocolException('counter mismatch: expected $recvN got $n');
    final nonce = payload.sublist(4, 28), ct = payload.sublist(28);
    final (mk, nck) = step(_recvCk!);
    final pt = Crypto.I.aeadDecrypt(ct, nonce, mk, _ad(n)); // throws on tamper
    _recvCk!.fillRange(0, 32, 0);
    _recvCk = nck;
    recvN++;
    return (pt[0], pt.sublist(1));
  }

  Uint8List encryptJson(Map<String, dynamic> obj) =>
      encrypt(ptJson, Crypto.utf8e(Crypto.canonicalJson(obj)));

  Map<String, dynamic> decryptJson(Uint8List payload) {
    final (pt, body) = decrypt(payload);
    if (pt != ptJson) throw ProtocolException('not a JSON plaintext');
    return jsonDecode(utf8.decode(body)) as Map<String, dynamic>;
  }

  static Map<String, dynamic> decodeJson(Uint8List body) => jsonDecode(utf8.decode(body)) as Map<String, dynamic>;

  // test-only accessors
  Uint8List? get debugSendCk => _sendCk;
}
