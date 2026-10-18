import 'dart:async';
import 'package:uuid/uuid.dart';
import '../crypto/crypto.dart';
import '../protocol/envelope.dart';
import '../../models/models.dart';
import 'app_core.dart';

/// 1-to-1 chat (and the shared logic used by groups): send, receive, receipts,
/// typing, delete-for-everyone, reactions, forwarding, live location.
class MessageService {
  MessageService(this.core);
  final AppCore core;
  static const _uuid = Uuid();
  final Map<String, Timer> _typingTimers = {};
  final Map<String, Timer> _liveTimers = {};
  final Map<String, StreamSubscription> _liveSubs = {};

  String get me => core.identity.userId;

  // ---------------------------------------------------------------- attachments meta
  static Map<String, dynamic> attMeta(Attachment a) => {
        'id': a.id, 'name': a.name, 'mime': a.mime, 'size': a.size, 'chunks': a.chunks,
        'key': Crypto.b64e(a.key), 'hash': Crypto.b64e(a.hash),
        if (a.thumb != null) 'thumb': Crypto.b64e(a.thumb!),
      };

  static Attachment attFromMeta(Map<String, dynamic> m) {
    final a = Attachment(
      id: m['id'] as String, fileId: Crypto.b64d(m['id'] as String), name: (m['name'] ?? 'file') as String,
      mime: (m['mime'] ?? 'application/octet-stream') as String, size: (m['size'] as num).toInt(),
      key: Crypto.b64d(m['key'] as String), hash: Crypto.b64d(m['hash'] as String),
      chunks: (m['chunks'] as num).toInt(), thumb: m['thumb'] != null ? Crypto.b64d(m['thumb'] as String) : null,
    );
    if (a.fileId.length != 16 || a.key.length != 32 || a.hash.length != 32 || a.chunks < 1 || a.chunks > 100000) {
      throw const FormatException('bad attachment meta');
    }
    return a;
  }

  // ---------------------------------------------------------------- outgoing
  Message _newMessage(Conversation conv, String kind, Map<String, dynamic> body, {String? attachmentId, String? replyTo}) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return Message(
      id: _uuid.v4(), convId: conv.id, senderId: me, ts: ts, kind: kind, body: body,
      attachmentId: attachmentId, replyTo: replyTo,
      expiresAt: conv.disappearingSecs > 0 ? ts + conv.disappearingSecs * 1000 : null,
    );
  }

  Map<String, dynamic> _envelopeFor(Message m, Conversation conv) => {
        'type': Env.chat, 'id': m.id, 'ts': m.ts, 'kind': m.kind, 'body': m.body,
        if (m.replyTo != null) 'reply_to': m.replyTo,
        if (conv.disappearingSecs > 0) 'expires_in': conv.disappearingSecs,
        if (m.attachmentId != null) 'att': attMeta(core.db.attachment(m.attachmentId!)!),
      };

  Future<Message> send(String convId, String kind, Map<String, dynamic> body, {String? attachmentId, String? replyTo}) async {
    final conv = core.db.conversation(convId)!;
    final m = _newMessage(conv, kind, body, attachmentId: attachmentId, replyTo: replyTo);
    core.db.insertMessage(m);
    core.db.bumpConversation(conv.id, m.ts, m.preview());
    core.notify();
    await _deliver(m, conv);
    return m;
  }

  Future<void> _deliver(Message m, Conversation conv) async {
    final env = _envelopeFor(m, conv);
    if (conv.isGroup) {
      final ok = await core.groups.sendToGroup(conv.groupId!, env, msgId: m.id);
      core.db.updateMessageStatus(m.id, ok ? MsgStatus.sent : MsgStatus.pending);
    } else {
      final ok = await core.cm.send(conv.peerId!, env, refMsg: m.id);
      core.db.updateMessageStatus(m.id, ok ? MsgStatus.sent : MsgStatus.pending);
    }
    core.notify();
  }

  Future<Message> sendText(String convId, String text, {String? replyTo}) =>
      send(convId, MsgKind.text, {'text': text}, replyTo: replyTo);

  Future<Message> sendAttachment(String convId, Attachment att, String kind, {String? caption, int? durationMs, String? replyTo}) {
    core.db.upsertAttachment(att);
    return send(convId, kind, {
      'name': att.name, 'mime': att.mime, 'size': att.size,
      if (caption != null && caption.isNotEmpty) 'text': caption,
      if (durationMs != null) 'duration': durationMs,
    }, attachmentId: att.id, replyTo: replyTo);
  }

  Future<Message> sendLocation(String convId, double lat, double lng, {double? accuracy}) =>
      send(convId, MsgKind.location, {'lat': lat, 'lng': lng, if (accuracy != null) 'acc': accuracy});

  Future<Message> sendContactCard(String convId, {required String name, List<String> phones = const [], String? uid, String? edPk}) =>
      send(convId, MsgKind.contact, {'name': name, 'phones': phones, if (uid != null) 'uid': uid, if (edPk != null) 'pk': edPk});

  /// Live location: one message whose body is updated for [duration].
  Future<Message> startLiveLocation(String convId, Duration duration, Stream<(double, double, double)> positions,
      {required double lat, required double lng}) async {
    final until = DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    final m = await send(convId, MsgKind.liveLocation, {'lat': lat, 'lng': lng, 'until': until, 'active': true});
    var lastSent = 0;
    _liveSubs[m.id] = positions.listen((p) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now > until) return stopLiveLocation(m.id);
      if (now - lastSent < 5000) return; // throttle
      lastSent = now;
      final (la, ln, acc) = p;
      final body = {'lat': la, 'lng': ln, 'acc': acc, 'until': until, 'active': true, 'updated': now};
      core.db.updateMessageBody(m.id, body);
      core.notify();
      await _sendToConv(m.convId, {'type': Env.locationLive, 'id': m.id, ...body}, queue: false);
    });
    _liveTimers[m.id] = Timer(duration, () => stopLiveLocation(m.id));
    return m;
  }

  bool isSharingLive(String msgId) => _liveSubs.containsKey(msgId);

  Future<void> stopLiveLocation(String msgId) async {
    _liveTimers.remove(msgId)?.cancel();
    await _liveSubs.remove(msgId)?.cancel();
    final m = core.db.message(msgId);
    if (m == null) return;
    final body = {...m.body, 'active': false};
    core.db.updateMessageBody(msgId, body);
    core.notify();
    await _sendToConv(m.convId, {'type': Env.locationLive, 'id': msgId, ...body});
  }

  Future<void> _sendToConv(String convId, Map<String, dynamic> env, {bool queue = true}) async {
    final conv = core.db.conversation(convId);
    if (conv == null) return;
    if (conv.isGroup) {
      await core.groups.sendToGroup(conv.groupId!, env, queue: queue);
    } else {
      await core.cm.send(conv.peerId!, env, queueIfOffline: queue);
    }
  }

  Future<void> deleteForEveryone(String msgId) async {
    final m = core.db.message(msgId);
    if (m == null || m.senderId != me) return;
    core.db.markDeleted(msgId);
    core.db.dropOutboxForMsg(msgId); // never delivered? then it never leaves the phone
    core.notify();
    await _sendToConv(m.convId, {'type': Env.delete, 'ids': [msgId]});
  }

  void deleteForMe(String msgId) {
    core.db.markDeleted(msgId);
    core.notify();
  }

  Future<void> react(String msgId, String? emoji) async {
    final m = core.db.message(msgId);
    if (m == null) return;
    core.db.setReaction(msgId, me, emoji);
    core.notify();
    await _sendToConv(m.convId, {'type': Env.reaction, 'id': msgId, 'emoji': emoji ?? ''});
  }

  Future<void> forward(String msgId, String toConvId) async {
    final m = core.db.message(msgId);
    if (m == null || m.deleted) return;
    await send(toConvId, m.kind, {...m.body, 'forwarded': true}, attachmentId: m.attachmentId);
  }

  Future<void> sendTyping(String convId, bool on) async {
    final conv = core.db.conversation(convId);
    if (conv == null || conv.isGroup) return;
    await core.cm.send(conv.peerId!, {'type': Env.typing, 'on': on}, queueIfOffline: false);
  }

  Future<void> markRead(String convId) async {
    final ids = core.db.unreadIncomingIds(convId, me);
    core.db.clearUnread(convId);
    core.notifications.cancelConv(convId);
    if (ids.isEmpty) {
      core.notify();
      return;
    }
    core.db.markIncomingRead(convId, me);
    core.notify();
    if (!core.readReceipts) return;
    final byAuthor = <String, List<String>>{};
    for (final id in ids) {
      final mm = core.db.message(id);
      if (mm != null && mm.kind != MsgKind.call && mm.kind != MsgKind.system) (byAuthor[mm.senderId] ??= []).add(id);
    }
    for (final e in byAuthor.entries) {
      await core.cm.send(e.key, {'type': Env.ack, 'ids': e.value, 'state': MsgStatus.read}, queueIfOffline: false);
    }
  }

  Map<String, dynamic> _profileEnv() => {
        'type': Env.profile, 'name': core.displayName, 'about': core.about,
        if (core.avatar != null) 'avatar': Crypto.b64e(core.avatar!),
      };

  /// Profile (name/photo/about) goes ONLY to contacts you explicitly added.
  void broadcastProfile() {
    for (final c in core.db.contacts()) {
      if (c.added > 0 && !c.blocked) core.cm.send(c.userId, _profileEnv(), queueIfOffline: false);
    }
  }

  void onPeerOnline(String peerId) {
    final c = core.db.contact(peerId);
    if (c != null && c.added > 0 && !c.blocked) core.cm.send(peerId, _profileEnv(), queueIfOffline: false);
    core.groups.onPeerOnline(peerId);
    core.status.onPeerOnline(peerId);
  }

  // ---------------------------------------------------------------- incoming
  void handle(String from, Map<String, dynamic> env) {
    final sender = core.db.contact(from);
    if (sender?.blocked ?? false) return;
    switch (env['type']) {
      case Env.chat:
        if (core.contactsOnly && (sender == null || sender.added == 0)) return; // silently drop strangers
        final conv = core.db.directConversation(from, core.nameOf(from));
        handleIncomingChat(conv, from, env);
        core.cm.send(from, {'type': Env.ack, 'ids': [env['id']], 'state': MsgStatus.delivered}, queueIfOffline: false);
        break;
      case Env.ack:
        for (final id in (env['ids'] as List)) {
          final m = core.db.message(id as String);
          if (m != null && m.senderId == me) core.db.updateMessageStatus(id, env['state'] as String);
        }
        core.notify();
        break;
      case Env.typing:
        final convId = 'd:$from';
        _typingTimers[convId]?.cancel();
        if (env['on'] == true) {
          core.typingPeers.add(convId);
          _typingTimers[convId] = Timer(const Duration(seconds: 6), () {
            core.typingPeers.remove(convId);
            core.notify();
          });
        } else {
          core.typingPeers.remove(convId);
        }
        core.notify();
        break;
      case Env.delete:
        _applyDelete(from, env);
        break;
      case Env.reaction:
        _applyReaction(from, env);
        break;
      case Env.locationLive:
        _applyLiveLocation(from, env);
        break;
      case Env.profile:
        final c = sender;
        if (c == null) return;
        final n = (env['name'] as String?)?.trim() ?? '';
        if (c.added == 0 && n.isNotEmpty) c.name = n.length > 64 ? n.substring(0, 64) : n;
        c.about = (env['about'] as String?) ?? c.about;
        final av = env['avatar'] as String?;
        if (av != null && av.length < 200000) c.avatar = Crypto.b64d(av);
        core.db.upsertContact(c);
        core.notify();
        break;
    }
  }

  /// Shared by direct and group paths. [author] is the authenticated author.
  void handleIncomingChat(Conversation conv, String author, Map<String, dynamic> env) {
    final id = env['id'] as String;
    if (core.db.hasMessage(id)) return;
    final kind = env['kind'] as String;
    final ts = (env['ts'] as num).toInt();
    final expiresIn = (env['expires_in'] as num?)?.toInt();
    String? attId;
    final meta = env['att'] as Map<String, dynamic>?;
    if (meta != null) {
      final a = attFromMeta(meta);
      if (core.db.attachment(a.id) == null) core.db.upsertAttachment(a);
      attId = a.id;
      core.files.registerSource(a.id, author);
      // auto-download photos / voice notes / small videos; documents and big files on tap
      final auto = kind == MsgKind.image || kind == MsgKind.audio || (kind == MsgKind.video && a.size <= 32 << 20);
      if (auto) core.files.request(a.id);
    }
    final m = Message(
      id: id, convId: conv.id, senderId: author, ts: ts, kind: kind,
      body: Map<String, dynamic>.from(env['body'] as Map), status: MsgStatus.delivered, attachmentId: attId,
      replyTo: env['reply_to'] as String?,
      expiresAt: expiresIn != null && expiresIn > 0 ? DateTime.now().millisecondsSinceEpoch + expiresIn * 1000 : null,
    );
    core.db.insertMessage(m);
    core.db.bumpConversation(conv.id, ts, m.preview(), incrementUnread: true);
    final title = conv.isGroup ? '${conv.title} · ${core.nameOf(author)}' : core.nameOf(author);
    core.notifications.message(convId: conv.id, title: title, body: m.preview(), muted: conv.muted);
    core.notify();
  }

  void _applyDelete(String from, Map<String, dynamic> env) {
    for (final id in (env['ids'] as List)) {
      final m = core.db.message(id as String);
      if (m != null && m.senderId == from) core.db.markDeleted(id); // only the author can delete
    }
    core.notify();
  }

  void _applyReaction(String from, Map<String, dynamic> env) {
    final emoji = env['emoji'] as String? ?? '';
    if (emoji.length > 16) return;
    core.db.setReaction(env['id'] as String, from, emoji.isEmpty ? null : emoji);
    core.notify();
  }

  void _applyLiveLocation(String from, Map<String, dynamic> env) {
    final m = core.db.message(env['id'] as String);
    if (m == null || m.senderId != from) return;
    core.db.updateMessageBody(m.id, {
      'lat': env['lat'], 'lng': env['lng'], 'acc': env['acc'], 'until': env['until'],
      'active': env['active'] ?? false, 'updated': env['updated'] ?? DateTime.now().millisecondsSinceEpoch,
    });
    core.notify();
  }

  /// Called by GroupService after sender-key decryption (author authenticated by signature).
  void handleGroupInner(String gid, String author, Map<String, dynamic> inner) {
    final g = core.db.group(gid);
    if (g == null) return;
    final conv = core.db.groupConversation(gid, g.name);
    switch (inner['type']) {
      case Env.chat:
        handleIncomingChat(conv, author, inner);
        core.cm.send(author, {'type': Env.ack, 'ids': [inner['id']], 'state': MsgStatus.delivered}, queueIfOffline: false);
        break;
      case Env.delete:
        _applyDelete(author, inner);
        break;
      case Env.reaction:
        _applyReaction(author, inner);
        break;
      case Env.locationLive:
        _applyLiveLocation(author, inner);
        break;
    }
  }

  /// Serve a file only to participants of a conversation that contains it (or our status viewers).
  bool canServeFile(String peerId, String attId) {
    if (core.db.messages('d:$peerId', limit: 100000).any((m) => m.attachmentId == attId)) return true;
    for (final g in core.db.groups()) {
      if (!g.members.containsKey(peerId)) continue;
      if (core.db.messages('g:${g.gid}', limit: 100000).any((m) => m.attachmentId == attId)) return true;
    }
    if (core.db.statusPosts(author: me).any((s) => s.attachmentId == attId)) {
      return (core.db.contact(peerId)?.added ?? 0) > 0;
    }
    return false;
  }

  void addSystemMessage(String convId, String text) {
    final m = Message(id: _uuid.v4(), convId: convId, senderId: me, ts: DateTime.now().millisecondsSinceEpoch,
        kind: MsgKind.system, body: {'text': text}, status: MsgStatus.read);
    core.db.insertMessage(m);
    core.db.bumpConversation(convId, m.ts, text);
    core.notify();
  }

  void logCall(String peerId, {required bool outgoing, required bool answered, required int duration, required bool video}) {
    final conv = core.db.directConversation(peerId, core.nameOf(peerId));
    final m = Message(
      id: _uuid.v4(), convId: conv.id, senderId: outgoing ? me : peerId, ts: DateTime.now().millisecondsSinceEpoch,
      kind: MsgKind.call, body: {'outgoing': outgoing, 'missed': !answered, 'duration': duration, 'video': video},
      status: MsgStatus.read,
    );
    core.db.insertMessage(m);
    core.db.bumpConversation(conv.id, m.ts, m.preview(), incrementUnread: !answered && !outgoing);
    core.notify();
  }
}
