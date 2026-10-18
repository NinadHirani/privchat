import 'package:uuid/uuid.dart';
import '../protocol/envelope.dart';
import '../storage/media_store.dart';
import '../../models/models.dart';
import 'app_core.dart';
import 'message_service.dart';

/// Status / stories: lives on YOUR phone, pushed directly to contacts when they're in range,
/// auto-expires after 24 h everywhere. No server ever holds it.
class StatusService {
  StatusService(this.core);
  final AppCore core;
  static const ttl = Duration(hours: 24);
  String get me => core.identity.userId;

  /// Audience: contacts you explicitly added, minus anyone in the "hide status from" list.
  List<String> get audience {
    final hidden = (core.db.kvGet('status_hidden') ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    return core.db.contacts().where((c) => c.added > 0 && !c.blocked && !hidden.contains(c.userId)).map((c) => c.userId).toList();
  }

  Set<String> get hiddenFrom => (core.db.kvGet('status_hidden') ?? '').split(',').where((s) => s.isNotEmpty).toSet();
  void setHiddenFrom(Set<String> ids) {
    core.db.kvSet('status_hidden', ids.join(','));
    core.notify();
  }

  Future<void> postText(String text, int bgColor) => _post('text', {'text': text, 'bg': bgColor});

  Future<void> postMedia(Attachment att, String kind, {String? caption}) async {
    core.db.upsertAttachment(att);
    await _post(kind, {if (caption != null && caption.isNotEmpty) 'text': caption}, att: att);
  }

  Future<void> _post(String kind, Map<String, dynamic> body, {Attachment? att}) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final p = StatusPost(id: const Uuid().v4(), authorId: me, ts: now, expires: now + ttl.inMilliseconds,
        kind: kind, body: body, attachmentId: att?.id, seen: true);
    core.db.insertStatus(p);
    core.notify();
    for (final uid in audience) {
      await core.cm.send(uid, _env(p), queueIfOffline: true);
    }
  }

  Map<String, dynamic> _env(StatusPost p) => {
        'type': Env.statusPost, 'id': p.id, 'ts': p.ts, 'expires': p.expires, 'kind': p.kind, 'body': p.body,
        if (p.attachmentId != null) 'att': MessageService.attMeta(core.db.attachment(p.attachmentId!)!),
      };

  Future<void> delete(String id) async {
    final p = core.db.statusPosts(author: me).where((s) => s.id == id).firstOrNull;
    if (p == null) return;
    core.db.deleteStatus(id);
    core.notify();
    for (final uid in audience) {
      await core.cm.send(uid, {'type': 'status.delete', 'id': id}, queueIfOffline: true);
    }
  }

  Future<void> markSeen(StatusPost p) async {
    if (p.authorId == me || p.seen) return;
    core.db.markStatusSeen(p.id);
    core.notify();
    if (core.readReceipts) {
      await core.cm.send(p.authorId, {'type': Env.statusSeen, 'id': p.id}, queueIfOffline: true);
    }
  }

  void onPeerOnline(String peerId) {
    if (!audience.contains(peerId)) return;
    for (final p in core.db.statusPosts(author: me)) {
      core.cm.send(peerId, _env(p), queueIfOffline: false); // receiver de-dupes by id
    }
  }

  void handle(String from, Map<String, dynamic> env) {
    final c = core.db.contact(from);
    switch (env['type']) {
      case Env.statusPost:
        if (c == null || c.added == 0 || c.blocked) return; // only from people YOU added
        final id = env['id'] as String;
        if (core.db.hasStatus(id)) return;
        final now = DateTime.now().millisecondsSinceEpoch;
        var expires = (env['expires'] as num).toInt();
        final ts = (env['ts'] as num).toInt();
        if (expires < now) return;
        if (expires - ts > ttl.inMilliseconds) expires = ts + ttl.inMilliseconds; // cap at 24h
        String? attId;
        final meta = env['att'] as Map<String, dynamic>?;
        if (meta != null) {
          final a = MessageService.attFromMeta(meta);
          if (core.db.attachment(a.id) == null) core.db.upsertAttachment(a);
          attId = a.id;
          core.files.registerSource(a.id, from);
          core.files.request(a.id);
        }
        core.db.insertStatus(StatusPost(id: id, authorId: from, ts: ts, expires: expires, kind: env['kind'] as String,
            body: Map<String, dynamic>.from(env['body'] as Map), attachmentId: attId));
        core.notify();
        break;
      case Env.statusSeen:
        final id = env['id'] as String;
        if (core.db.statusPosts(author: me).any((s) => s.id == id)) {
          core.db.addStatusView(id, from);
          core.notify();
        }
        break;
      case 'status.delete':
        final id = env['id'] as String;
        final p = core.db.statusPosts(author: from).where((s) => s.id == id).firstOrNull;
        if (p != null) {
          core.db.deleteStatus(id);
          final a = p.attachmentId == null ? null : core.db.attachment(p.attachmentId!);
          if (a != null) MediaStore.deleteAttachment(a);
          core.notify();
        }
        break;
    }
  }
}
