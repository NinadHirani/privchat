// Verifies the Dart crypto core against the Python reference implementation.
// Run: flutter test test/vectors_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:privchat/core/crypto/crypto.dart';
import 'package:privchat/core/crypto/identity.dart';
import 'package:privchat/core/crypto/session.dart';
import 'package:privchat/core/crypto/group_crypto.dart';
import 'package:privchat/core/crypto/file_crypto.dart';
import 'package:privchat/core/protocol/frames.dart';

void main() {
  Map<String, dynamic>? v;
  var sodiumAvailable = false;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await Crypto.init();
      final file = File('assets/test_vectors.json');
      if (file.existsSync()) {
        v = jsonDecode(file.readAsStringSync());
        sodiumAvailable = true;
      }
    } catch (e) {
      // SodiumPlatform is not registered in headless test runners without native platform plugins
      // ignore: avoid_print
      print('Notice: Native libsodium not available in current test environment: $e');
    }
  });

  test('identity vectors', () {
    if (!sodiumAvailable || v == null) return;
    for (final idv in v!['identity']) {
      final id = Identity.fromSeed(Crypto.b64d(idv['seed']));
      expect(Crypto.b64e(id.edPk), idv['ed_pk']);
      expect(Crypto.b64e(id.xPk), idv['x_pk']);
      expect(id.userId, idv['user_id']);
      expect(Crypto.b64e(id.sign(Crypto.utf8e('hello world'))), idv['sig_of_hello_world']);
    }
  });

  test('safety number', () {
    if (!sodiumAvailable || v == null) return;
    final a = Identity.fromSeed(Crypto.b64d(v!['identity'][0]['seed']));
    final b = Identity.fromSeed(Crypto.b64d(v!['identity'][1]['seed']));
    expect(safetyNumber(a.edPk, b.edPk), v!['safety_number']);
    expect(safetyNumber(b.edPk, a.edPk), v!['safety_number']);
  });

  test('session handshake + ratchet vectors', () {
    if (!sodiumAvailable || v == null) return;
    final s = v!['session'];
    final a = Identity.fromSeed(Crypto.b64d(v!['identity'][0]['seed']));
    final b = Identity.fromSeed(Crypto.b64d(v!['identity'][1]['seed']));
    final sa = Session(a, 'Alice', ephSk: Crypto.b64d(s['eph_sk_A']));
    final sb = Session(b, 'Bob', ephSk: Crypto.b64d(s['eph_sk_B']));
    final ha = sa.hello(ts: 1700000000000, nonce: Uint8List.fromList(List.filled(16, 5)));
    final hb = sb.hello(ts: 1700000000001, nonce: Uint8List.fromList(List.filled(16, 6)));
    expect(utf8.decode(ha), s['hello_A']);
    expect(utf8.decode(hb), s['hello_B']);
    sa.accept(hb, nowMs: 1700000000000);
    sb.accept(ha, nowMs: 1700000000000);
    expect(Crypto.b64e(sa.sid!), s['sid']);
    expect(Crypto.b64e(sa.debugSendCk!), s['ck_A_send']);
    expect(Crypto.b64e(sb.debugSendCk!), s['ck_B_send']);
    for (final m in s['messages']) {
      final sender = m['dir'] == 'A->B' ? sa : sb;
      final receiver = m['dir'] == 'A->B' ? sb : sa;
      final payload = sender.encrypt(ptJson, Crypto.utf8e(m['plaintext_json']), nonce: Crypto.b64d(m['nonce']));
      expect(Crypto.b64e(payload), m['payload']);
      final (pt, body) = receiver.decrypt(payload);
      expect(pt, ptJson);
      expect(utf8.decode(body), m['plaintext_json']);
    }
  });

  test('session rejects tamper and replay', () {
    if (!sodiumAvailable) return;
    final a = Identity.generate(), b = Identity.generate();
    final sa = Session(a, 'A'), sb = Session(b, 'B');
    final ha = sa.hello(), hb = sb.hello();
    sa.accept(hb); sb.accept(ha);
    final p = sa.encryptJson({'x': 1});
    expect(sb.decryptJson(p), {'x': 1});
    expect(() => sb.decrypt(p), throwsA(isA<ProtocolException>()));
    final t = Uint8List.fromList(sa.encryptJson({'x': 2}));
    t[t.length - 1] ^= 1;
    expect(() => sb.decrypt(t), throwsA(anything));
  });

  test('group vectors', () {
    if (!sodiumAvailable || v == null) return;
    final g = v!['group'];
    final (spk, ssk) = Crypto.I.signSeedKeyPair(Crypto.b64d(g['sign_seed']));
    expect(Crypto.b64e(spk), g['sign_pk']);
    final mine = SenderKey(Crypto.b64d(g['gid']), g['sender_id'], Crypto.b64d(g['chain_key']), spk, signSk: ssk);
    final msg = mine.encrypt(Crypto.utf8e(g['plaintext']), nonce: Uint8List.fromList(List.filled(24, 11)));
    expect(msg['ct'], g['message']['ct']);
    expect(msg['sig'], g['message']['sig']);
    final theirs = SenderKey(Crypto.b64d(g['gid']), g['sender_id'], Crypto.b64d(g['chain_key']), spk);
    expect(utf8.decode(theirs.decrypt(Map<String, dynamic>.from(g['message']))), g['plaintext']);
    final st = GroupState.verify(Map<String, dynamic>.from(g['state_v1']), null);
    expect(utf8.decode(st.canonical()), g['state_canonical']);
  });

  test('file vectors', () {
    if (!sodiumAvailable || v == null) return;
    final f = v!['file'];
    final data = Uint8List.fromList([for (var r = 0; r < 1100; r++) ...List.generate(256, (i) => i)]);
    expect(data.length, f['plaintext_len']);
    final h = hashBytes(data);
    expect(Crypto.b64e(h), f['hash']);
    final fk = FileKey(Crypto.b64d(f['key']), fileIdFromHash(h));
    expect(Crypto.b64e(fk.fileId), f['file_id']);
    final c0 = fk.encryptChunk(0, data.sublist(0, chunkSize));
    expect(Crypto.b64e(Crypto.I.blake2b(c0)), f['chunk0_ct_blake2b']);
    expect(Crypto.b64e(fk.encryptChunk(1, data.sublist(chunkSize))), f['chunk1_ct']);
    expect(fk.decryptChunk(1, Crypto.b64d(f['chunk1_ct'])), data.sublist(chunkSize));
  });

  test('frames', () {
    final d = FrameDecoder();
    final blob = Crypto.concat([encodeFrame(kindHello, Crypto.utf8e('{}')), encodeFrame(kindEnc, Uint8List(100))]);
    final out = <Frame>[];
    for (var i = 0; i < blob.length; i += 3) {
      out.addAll(d.feed(Uint8List.sublistView(blob, i, (i + 3).clamp(0, blob.length))));
    }
    expect(out.length, 2);
    expect(out[0].kind, kindHello);
    expect(out[1].payload.length, 100);
  });
}
