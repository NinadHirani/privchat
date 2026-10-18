import 'dart:convert';
import 'dart:typed_data';
import 'crypto.dart';
import 'identity.dart';
import 'session.dart' show ProtocolException, Session;

const maxSkip = 500;

/// Sender key for one member in one group. Mirrors group.py.
class SenderKey {
  SenderKey(this.gid, this.senderId, this.chainKey, this.signPk, {this.signSk, this.n = 0, Map<int, Uint8List>? skipped})
      : skipped = skipped ?? {};
  final Uint8List gid;
  final String senderId;
  Uint8List chainKey;
  final Uint8List signPk;
  final Uint8List? signSk;
  int n;
  final Map<int, Uint8List> skipped;

  factory SenderKey.generate(Uint8List gid, String senderId) {
    final (pk, sk) = Crypto.I.signKeyPair();
    return SenderKey(gid, senderId, Crypto.I.random(32), pk, signSk: sk);
  }

  Map<String, dynamic> distribution() =>
      {'gid': Crypto.b64e(gid), 'ck': Crypto.b64e(chainKey), 'spk': Crypto.b64e(signPk), 'n': n};

  factory SenderKey.fromDistribution(String senderId, Map<String, dynamic> d) => SenderKey(
      Crypto.b64d(d['gid']), senderId, Crypto.b64d(d['ck']), Crypto.b64d(d['spk']), n: (d['n'] as num).toInt());

  static Uint8List _ctx(Uint8List gid, int n, Uint8List nonce, Uint8List ct) =>
      Crypto.concat([Crypto.utf8e('privchat-grp-v1'), gid, Crypto.u32be(n), nonce, ct]);

  Uint8List _ad(int n) => Crypto.concat([gid, Crypto.utf8e(senderId), Crypto.u32be(n)]);

  Map<String, dynamic> encrypt(Uint8List plaintext, {Uint8List? nonce}) {
    if (signSk == null) throw ProtocolException('not our sender key');
    final (mk, nck) = Session.step(chainKey);
    chainKey = nck;
    final cur = n++;
    nonce ??= Crypto.I.random(24);
    final ct = Crypto.I.aeadEncrypt(plaintext, nonce, mk, _ad(cur));
    final sig = Crypto.I.sign(_ctx(gid, cur, nonce, ct), signSk!);
    return {'gid': Crypto.b64e(gid), 'n': cur, 'nonce': Crypto.b64e(nonce), 'ct': Crypto.b64e(ct), 'sig': Crypto.b64e(sig)};
  }

  Uint8List _keyFor(int target) {
    final cached = skipped.remove(target);
    if (cached != null) return cached;
    if (target < n) throw ProtocolException('replayed or too-old group message');
    if (target - n > maxSkip) throw ProtocolException('too many skipped group messages');
    while (n < target) {
      final (mk, nck) = Session.step(chainKey);
      skipped[n] = mk;
      chainKey = nck;
      n++;
    }
    final (mk, nck) = Session.step(chainKey);
    chainKey = nck;
    n++;
    return mk;
  }

  Uint8List decrypt(Map<String, dynamic> m) {
    final mn = (m['n'] as num).toInt();
    final nonce = Crypto.b64d(m['nonce']), ct = Crypto.b64d(m['ct']), sig = Crypto.b64d(m['sig']);
    if (!Crypto.constEq(Crypto.b64d(m['gid']), gid)) throw ProtocolException('gid mismatch');
    if (!Crypto.I.verify(_ctx(gid, mn, nonce, ct), sig, signPk)) throw ProtocolException('bad group signature');
    final mk = _keyFor(mn);
    return Crypto.I.aeadDecrypt(ct, nonce, mk, _ad(mn));
  }

  Map<String, dynamic> encryptJson(Map<String, dynamic> obj) => encrypt(Crypto.utf8e(Crypto.canonicalJson(obj)));
  Map<String, dynamic> decryptJson(Map<String, dynamic> m) => jsonDecode(utf8.decode(decrypt(m))) as Map<String, dynamic>;

  String skippedToJson() => jsonEncode(skipped.map((k, v) => MapEntry(k.toString(), Crypto.b64e(v))));
  static Map<int, Uint8List> skippedFromJson(String? s) {
    if (s == null || s.isEmpty) return {};
    return (jsonDecode(s) as Map<String, dynamic>).map((k, v) => MapEntry(int.parse(k), Crypto.b64d(v)));
  }
}

/// Signed group membership document. Mirrors GroupState in group.py.
class GroupState {
  GroupState({required this.gid, required this.name, required this.version, required this.members,
      required this.admins, required this.created});
  final Uint8List gid;
  final String name;
  final int version;
  final Map<String, Uint8List> members; // userId -> edPk
  final List<String> admins;
  final int created;

  String get gidB64 => Crypto.b64e(gid);

  Map<String, dynamic> _doc() {
    final keys = members.keys.toList()..sort();
    return {
      'gid': Crypto.b64e(gid), 'name': name, 'version': version,
      'members': {for (final k in keys) k: Crypto.b64e(members[k]!)},
      'admins': [...admins]..sort(), 'created': created,
    };
  }

  Uint8List canonical() => Crypto.concat([Crypto.utf8e('privchat-grpstate-v1'), Crypto.utf8e(Crypto.canonicalJson(_doc()))]);

  Map<String, dynamic> sign(Identity admin) {
    if (!admins.contains(admin.userId)) throw ProtocolException('not an admin');
    return {..._doc(), 'signer': admin.userId, 'sig': Crypto.b64e(admin.sign(canonical()))};
  }

  /// Parse a document we already verified and stored (no signature check).
  static GroupState parse(Map<String, dynamic> doc) => GroupState(
        gid: Crypto.b64d(doc['gid']), name: doc['name'] as String, version: (doc['version'] as num).toInt(),
        members: (doc['members'] as Map).map((k, v) => MapEntry(k as String, Crypto.b64d(v as String))),
        admins: (doc['admins'] as List).cast<String>(), created: (doc['created'] as num).toInt(),
      );

  static GroupState verify(Map<String, dynamic> doc, GroupState? previous) {
    final st = GroupState(
      gid: Crypto.b64d(doc['gid']), name: doc['name'] as String, version: (doc['version'] as num).toInt(),
      members: (doc['members'] as Map<String, dynamic>).map((k, v) => MapEntry(k, Crypto.b64d(v))),
      admins: (doc['admins'] as List).cast<String>(), created: (doc['created'] as num).toInt(),
    );
    final signer = doc['signer'] as String;
    if (!st.admins.every(st.members.containsKey)) throw ProtocolException('admin not a member');
    for (final e in st.members.entries) {
      if (userIdFromEdPk(e.value) != e.key) throw ProtocolException('member id/key mismatch');
    }
    Uint8List signerPk;
    if (previous == null) {
      if (st.version != 1 || !st.admins.contains(signer)) throw ProtocolException('initial state must be v1 signed by an admin');
      signerPk = st.members[signer]!;
    } else {
      if (!Crypto.constEq(st.gid, previous.gid) || st.version != previous.version + 1 || st.created != previous.created) {
        throw ProtocolException('bad state transition');
      }
      if (!previous.admins.contains(signer)) throw ProtocolException('signer was not an admin');
      signerPk = previous.members[signer]!;
    }
    if (!Crypto.I.verify(st.canonical(), Crypto.b64d(doc['sig']), signerPk)) throw ProtocolException('bad group state signature');
    return st;
  }

  GroupState copyWith({String? name, Map<String, Uint8List>? members, List<String>? admins}) => GroupState(
      gid: gid, name: name ?? this.name, version: version + 1, members: members ?? this.members,
      admins: admins ?? this.admins, created: created);
}
