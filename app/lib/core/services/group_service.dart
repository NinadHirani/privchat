import 'dart:async';
import 'dart:typed_data';
import '../crypto/crypto.dart';
import '../crypto/group_crypto.dart';
import '../protocol/envelope.dart';
import '../../models/models.dart';
import 'app_core.dart';

/// Serverless groups: admin-signed membership chain + Signal-style sender keys.
/// Every group message is encrypted ONCE and fanned out over pairwise E2EE links
/// (store-and-forward per member when they're not in range).
class GroupService {
  GroupService(this.core);
  final AppCore core;
  final Map<String, List<Map<String, dynamic>>> _pending = {}; // "gid|author" -> undecryptable msgs awaiting key
  String get me => core.identity.userId;

  GroupState? stateOf(String gid) {
    final d = core.db.groupStateDoc(gid);
    return d == null ? null : GroupState.parse(d);
  }

  bool isAdmin(String gid) => stateOf(gid)?.admins.contains(me) ?? false;
  bool isMember(String gid) => stateOf(gid)?.members.containsKey(me) ?? false;

  // ------------------------------------------------------------- sender keys
  SenderKey _mine(String gid) {
    final r = core.db.mySenderKey(gid);
    if (r != null) {
      final (ck, spk, ssk, n) = r;
      return SenderKey(Crypto.b64d(gid), me, ck, spk, signSk: ssk, n: n);
    }
    return _rotate(gid);
  }

  SenderKey _rotate(String gid) {
    final k = SenderKey.generate(Crypto.b64d(gid), me);
    _saveMine(gid, k);
    return k;
  }

  void _saveMine(String gid, SenderKey k) => core.db.saveMySenderKey(gid, k.chainKey, k.signPk, k.signSk!, k.n);

  Future<void> _distributeMine(String gid, Iterable<String> to) async {
    final dist = _mine(gid).distribution();
    for (final t in to) {
      if (t != me) await core.cm.send(t, {'type': Env.groupSenderKey, 'gid': gid, 'skey': dist});
    }
  }

  Map<String, String> _names(Iterable<String> ids) => {
        for (final id in ids) id: id == me ? core.displayName : core.nameOf(id),
      };

  /// Learn other members' identity keys (from the admin-signed state) + display names (informational).
  void _learnMembers(GroupState st, Map<String, dynamic>? names) {
    for (final e in st.members.entries) {
      if (e.key == me || core.db.contact(e.key) != null) continue;
      var n = (names?[e.key] as String?)?.trim() ?? '';
      if (n.isEmpty || n.length > 64) n = e.key.substring(0, 8);
      core.db.upsertContact(Contact(userId: e.key, edPk: e.value, name: n));
    }
  }

  // ------------------------------------------------------------- admin ops
  Future<String> create(String name, List<String> memberIds, {Uint8List? avatar}) async {
    final members = <String, Uint8List>{me: core.identity.edPk};
    for (final id in memberIds) {
      final c = core.db.contact(id);
      if (c != null) members[id] = c.edPk;
    }
    final st = GroupState(gid: Crypto.I.random(16), name: name.trim(), version: 1, members: members, admins: [me],
        created: DateTime.now().millisecondsSinceEpoch);
    final doc = st.sign(core.identity);
    final gid = st.gidB64;
    core.db.upsertGroup(gid, doc);
    if (avatar != null) core.db.setGroupAvatar(gid, avatar);
    _rotate(gid);
    final conv = core.db.groupConversation(gid, st.name);
    core.messages.addSystemMessage(conv.id, 'You created group "${st.name}"');
    for (final m in members.keys) {
      if (m != me) await core.cm.send(m, {'type': Env.groupState, 'doc': doc, 'names': _names(members.keys)});
    }
    await _distributeMine(gid, members.keys);
    core.notify();
    return conv.id;
  }

  Future<void> _publish(String gid, GroupState next, {Iterable<String> alsoNotify = const []}) async {
    final prev = stateOf(gid)!;
    final doc = next.sign(core.identity);
    GroupState.verify(doc, prev); // self-check
    core.db.upsertGroup(gid, doc);
    final targets = {...next.members.keys, ...prev.members.keys, ...alsoNotify}..remove(me);
    for (final t in targets) {
      await core.cm.send(t, {'type': Env.groupState, 'doc': doc, 'names': _names(next.members.keys)});
    }
    await _applyEffects(gid, prev, next, actor: me);
  }

  Future<void> addMembers(String gid, List<String> ids) async {
    final st = stateOf(gid)!;
    final members = Map<String, Uint8List>.from(st.members);
    for (final id in ids) {
      final c = core.db.contact(id);
      if (c != null) members[id] = c.edPk;
    }
    await _publish(gid, st.copyWith(members: members));
  }

  Future<void> removeMember(String gid, String id) async {
    final st = stateOf(gid)!;
    final members = Map<String, Uint8List>.from(st.members)..remove(id);
    final admins = st.admins.where((a) => a != id).toList();
    await _publish(gid, st.copyWith(members: members, admins: admins), alsoNotify: [id]);
  }

  Future<void> rename(String gid, String name) async => _publish(gid, stateOf(gid)!.copyWith(name: name.trim()));

  Future<void> setAdmin(String gid, String id, bool admin) async {
    final st = stateOf(gid)!;
    final admins = {...st.admins};
    admin ? admins.add(id) : admins.remove(id);
    if (admins.isEmpty) return;
    await _publish(gid, st.copyWith(admins: admins.toList()));
  }

  Future<void> leave(String gid) async {
    final st = stateOf(gid);
    if (st == null) return;
    if (st.admins.contains(me)) {
      final members = Map<String, Uint8List>.from(st.members)..remove(me);
      var admins = st.admins.where((a) => a != me).toList();
      if (admins.isEmpty && members.isNotEmpty) admins = [(members.keys.toList()..sort()).first];
      if (members.isNotEmpty) await _publish(gid, st.copyWith(members: members, admins: admins));
    } else {
      for (final a in st.admins) {
        await core.cm.send(a, {'type': 'group.leave', 'gid': gid});
      }
    }
    core.messages.addSystemMessage('g:$gid', 'You left the group');
    core.db.deleteSenderKeysFor(gid);
    core.db.setGroupLeft(gid);
    core.notify();
  }

  // ------------------------------------------------------------- send
  /// Returns true if delivered to at least one member right now.
  Future<bool> sendToGroup(String gid, Map<String, dynamic> env, {String? msgId, bool queue = true}) async {
    final st = stateOf(gid);
    if (st == null || !st.members.containsKey(me)) return false;
    final k = _mine(gid);
    final m = k.encryptJson(env);
    _saveMine(gid, k);
    var any = false;
    for (final t in st.members.keys) {
      if (t == me) continue;
      final ok = await core.cm.send(t, {'type': Env.groupMsg, 'gid': gid, 'author': me, 'm': m},
          queueIfOffline: queue, refMsg: msgId);
      any |= ok;
    }
    return any || st.members.length == 1;
  }

  // ------------------------------------------------------------- incoming
  void handle(String from, Map<String, dynamic> env) {
    switch (env['type']) {
      case Env.groupState:
        _onState(from, Map<String, dynamic>.from(env['doc'] as Map), env['names'] as Map<String, dynamic>?);
        break;
      case Env.groupSenderKey:
        _onSenderKey(from, env['gid'] as String, Map<String, dynamic>.from(env['skey'] as Map));
        break;
      case Env.groupMsg:
        _onMsg(from, env);
        break;
      case 'group.leave':
        _onLeave(from, env['gid'] as String);
        break;
    }
  }

  Future<void> _onState(String from, Map<String, dynamic> doc, [Map<String, dynamic>? names]) async {
    final gid = doc['gid'] as String;
    final prev = stateOf(gid);
    final ver = (doc['version'] as num).toInt();
    if (prev != null && ver <= prev.version) return;
    GroupState next;
    try {
      if (prev == null) {
        // First time we hear of this group. v1 is fully verifiable; for later versions we
        // require the sender to be a member and trust-on-first-use the admin signature.
        if (ver == 1) {
          next = GroupState.verify(doc, null);
        } else {
          final tmp = GroupState.parse(doc);
          final signer = doc['signer'] as String;
          if (!tmp.admins.contains(signer) || !tmp.members.containsKey(from)) return;
          final prevLike = GroupState(gid: tmp.gid, name: tmp.name, version: ver - 1, members: tmp.members,
              admins: tmp.admins, created: tmp.created);
          next = GroupState.verify(doc, prevLike);
        }
      } else if (ver == prev.version + 1) {
        next = GroupState.verify(doc, prev);
      } else {
        // We missed intermediate versions: accept if signed by an admin we already know.
        final prevLike = GroupState(gid: prev.gid, name: prev.name, version: ver - 1, members: prev.members,
            admins: prev.admins, created: prev.created);
        next = GroupState.verify(doc, prevLike);
      }
    } catch (_) {
      return; // forged / invalid — drop
    }
    final c = core.db.contact(from);
    if (prev == null && core.contactsOnly && (c == null || c.added == 0)) return; // don't let strangers add you
    if (prev == null && !next.members.containsKey(me)) return;
    core.db.upsertGroup(gid, doc);
    _learnMembers(next, names);
    await _applyEffects(gid, prev, next, actor: doc['signer'] as String);
  }

  Future<void> _applyEffects(String gid, GroupState? prev, GroupState next, {required String actor}) async {
    final conv = core.db.groupConversation(gid, next.name);
    final who = core.nameOf(actor);
    if (prev == null) {
      core.messages.addSystemMessage(conv.id, '$who added you to "${next.name}"');
    } else {
      if (prev.name != next.name) core.messages.addSystemMessage(conv.id, '$who renamed the group to "${next.name}"');
      for (final a in next.members.keys.where((k) => !prev.members.containsKey(k))) {
        core.messages.addSystemMessage(conv.id, '$who added ${core.nameOf(a)}');
      }
      for (final r in prev.members.keys.where((k) => !next.members.containsKey(k))) {
        core.messages.addSystemMessage(conv.id, r == actor ? '${core.nameOf(r)} left' : '$who removed ${core.nameOf(r)}');
        core.db.deleteSenderKey(gid, r);
      }
      for (final a in next.admins.where((k) => !prev.admins.contains(k))) {
        core.messages.addSystemMessage(conv.id, '${core.nameOf(a)} is now an admin');
      }
    }
    if (!next.members.containsKey(me)) {
      core.db.deleteSenderKeysFor(gid);
      core.db.setGroupLeft(gid);
      core.notify();
      return;
    }
    core.db.kvSet('left:$gid', '0');
    final removed = prev != null && prev.members.keys.any((k) => !next.members.containsKey(k));
    final added = next.members.keys.where((k) => prev == null || !prev.members.containsKey(k)).toList();
    if (prev == null || removed || !prev.members.containsKey(me)) {
      // Removed members must not read future messages → fresh sender key for everyone.
      if (removed) _rotate(gid);
      await _distributeMine(gid, next.members.keys);
    } else if (added.isNotEmpty) {
      await _distributeMine(gid, added);
    }
    core.notify();
  }

  void _onSenderKey(String from, String gid, Map<String, dynamic> d) {
    final st = stateOf(gid);
    if (st == null || !st.members.containsKey(from)) return;
    final incoming = SenderKey.fromDistribution(from, d);
    if (!Crypto.constEq(incoming.gid, Crypto.b64d(gid))) return;
    final existing = core.db.senderKey(gid, from);
    if (existing != null) {
      final (_, spk, n, _) = existing;
      if (Crypto.constEq(spk, incoming.signPk) && n >= incoming.n) return; // stale re-send
    }
    core.db.saveSenderKey(gid, from, incoming.chainKey, incoming.signPk, incoming.n, '{}');
    final pending = _pending.remove('$gid|$from') ?? [];
    for (final p in pending) {
      _decryptAndDeliver(gid, from, p);
    }
  }

  void _onMsg(String from, Map<String, dynamic> env) {
    final gid = env['gid'] as String;
    final author = env['author'] as String;
    final st = stateOf(gid);
    if (st == null || !st.members.containsKey(author) || !st.members.containsKey(from)) return;
    if (!st.members.containsKey(me)) return;
    final m = Map<String, dynamic>.from(env['m'] as Map);
    if (core.db.senderKey(gid, author) == null) {
      final list = _pending.putIfAbsent('$gid|$author', () => []);
      if (list.length < 200) list.add(m);
      return;
    }
    _decryptAndDeliver(gid, author, m);
  }

  void _decryptAndDeliver(String gid, String author, Map<String, dynamic> m) {
    final r = core.db.senderKey(gid, author);
    if (r == null) return;
    final (ck, spk, n, skipped) = r;
    final k = SenderKey(Crypto.b64d(gid), author, ck, spk, n: n, skipped: SenderKey.skippedFromJson(skipped));
    Map<String, dynamic> inner;
    try {
      inner = k.decryptJson(m);
    } catch (_) {
      return; // replay / forgery / too old
    }
    core.db.saveSenderKey(gid, author, k.chainKey, k.signPk, k.n, k.skippedToJson());
    core.messages.handleGroupInner(gid, author, inner);
  }

  Future<void> _onLeave(String from, String gid) async {
    final st = stateOf(gid);
    if (st == null || !st.admins.contains(me) || !st.members.containsKey(from)) return;
    final members = Map<String, Uint8List>.from(st.members)..remove(from);
    await _publish(gid, st.copyWith(members: members, admins: st.admins.where((a) => a != from).toList()));
  }

  /// When a member comes in range, re-share the current state so they catch up on missed changes.
  void onPeerOnline(String peerId) {
    for (final g in core.db.groups()) {
      if (!g.members.containsKey(peerId) || !g.members.containsKey(me)) continue;
      final doc = core.db.groupStateDoc(g.gid);
      if (doc != null) {
        core.cm.send(peerId, {'type': Env.groupState, 'doc': doc, 'names': _names(g.members.keys)}, queueIfOffline: false);
      }
    }
  }
}
