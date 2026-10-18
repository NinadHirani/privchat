import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/open.dart' as sqlopen;
import 'package:sqlite3/sqlite3.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import '../crypto/crypto.dart';
import '../../models/models.dart';

/// Encrypted local database (SQLCipher). Raw SQL, no codegen.
class AppDb {
  AppDb._(this._db);
  final Database _db;
  static AppDb? _i;
  static AppDb get I => _i!;

  static Future<AppDb> open(Uint8List key) async {
    if (_i != null) return _i!;
    sqlopen.open.overrideFor(sqlopen.OperatingSystem.android, openCipherOnAndroid);
    sqlopen.open.overrideFor(sqlopen.OperatingSystem.iOS, () => DynamicLibrary.process());
    await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    final dir = await getApplicationSupportDirectory();
    final db = sqlite3.open(p.join(dir.path, 'privchat.db'));
    final hex = key.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    db.execute("PRAGMA key = \"x'$hex'\";");
    db.execute('PRAGMA cipher_memory_security = ON;');
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    // throws if key wrong
    db.select('SELECT count(*) FROM sqlite_master');
    _i = AppDb._(db).._migrate();
    return _i!;
  }

  void _migrate() {
    _db.execute('''
    CREATE TABLE IF NOT EXISTS kv(k TEXT PRIMARY KEY, v TEXT);
    CREATE TABLE IF NOT EXISTS contacts(
      user_id TEXT PRIMARY KEY, ed_pk BLOB NOT NULL, name TEXT NOT NULL, avatar BLOB, about TEXT DEFAULT '',
      verified INTEGER DEFAULT 0, blocked INTEGER DEFAULT 0, last_seen INTEGER DEFAULT 0, added INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS conversations(
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, peer_id TEXT, group_id TEXT, title TEXT NOT NULL,
      last_msg_ts INTEGER DEFAULT 0, last_preview TEXT DEFAULT '', unread INTEGER DEFAULT 0, muted INTEGER DEFAULT 0,
      disappearing_secs INTEGER DEFAULT 0, archived INTEGER DEFAULT 0, pinned INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS messages(
      id TEXT PRIMARY KEY, conv_id TEXT NOT NULL, sender_id TEXT NOT NULL, ts INTEGER NOT NULL, kind TEXT NOT NULL,
      body TEXT NOT NULL, status TEXT DEFAULT 'pending', attachment_id TEXT, reply_to TEXT, expires_at INTEGER,
      deleted INTEGER DEFAULT 0, reactions TEXT DEFAULT '{}');
    CREATE INDEX IF NOT EXISTS idx_msg_conv ON messages(conv_id, ts);
    CREATE TABLE IF NOT EXISTS attachments(
      id TEXT PRIMARY KEY, file_id BLOB NOT NULL, name TEXT, mime TEXT, size INTEGER, key BLOB NOT NULL, hash BLOB NOT NULL,
      chunks INTEGER NOT NULL, local_path TEXT, received_chunks INTEGER DEFAULT 0, state TEXT DEFAULT 'pending', thumb BLOB);
    CREATE TABLE IF NOT EXISTS groups(
      gid TEXT PRIMARY KEY, name TEXT NOT NULL, version INTEGER NOT NULL, created INTEGER NOT NULL, state_json TEXT NOT NULL,
      my_ck BLOB, my_spk BLOB, my_ssk BLOB, my_n INTEGER DEFAULT 0, avatar BLOB);
    CREATE TABLE IF NOT EXISTS sender_keys(
      gid TEXT NOT NULL, sender_id TEXT NOT NULL, ck BLOB NOT NULL, spk BLOB NOT NULL, n INTEGER DEFAULT 0, skipped TEXT,
      PRIMARY KEY(gid, sender_id));
    CREATE TABLE IF NOT EXISTS outbox(
      id INTEGER PRIMARY KEY AUTOINCREMENT, target TEXT NOT NULL, envelope TEXT NOT NULL, created INTEGER NOT NULL,
      attempts INTEGER DEFAULT 0, ref_msg TEXT);
    CREATE INDEX IF NOT EXISTS idx_outbox_target ON outbox(target);
    CREATE TABLE IF NOT EXISTS status_posts(
      id TEXT PRIMARY KEY, author_id TEXT NOT NULL, ts INTEGER NOT NULL, expires INTEGER NOT NULL, kind TEXT NOT NULL,
      body TEXT NOT NULL, attachment_id TEXT, seen INTEGER DEFAULT 0);
    CREATE TABLE IF NOT EXISTS status_views(post_id TEXT, viewer_id TEXT, ts INTEGER, PRIMARY KEY(post_id, viewer_id));
    CREATE TABLE IF NOT EXISTS calls(
      id TEXT PRIMARY KEY, peer_id TEXT NOT NULL, ts INTEGER NOT NULL, outgoing INTEGER, answered INTEGER,
      duration INTEGER DEFAULT 0, video INTEGER DEFAULT 0);
    ''');
  }

  // ---------- kv ----------
  String? kvGet(String k) {
    final r = _db.select('SELECT v FROM kv WHERE k=?', [k]);
    return r.isEmpty ? null : r.first['v'] as String?;
  }
  void kvSet(String k, String v) => _db.execute('INSERT OR REPLACE INTO kv(k,v) VALUES(?,?)', [k, v]);

  // ---------- contacts ----------
  Contact _contact(Row r) => Contact(
      userId: r['user_id'], edPk: r['ed_pk'] as Uint8List, name: r['name'], avatar: r['avatar'] as Uint8List?,
      about: r['about'] ?? '', verified: r['verified'] == 1, blocked: r['blocked'] == 1, lastSeen: r['last_seen'] ?? 0,
      added: r['added'] ?? 0);

  List<Contact> contacts() => _db.select('SELECT * FROM contacts ORDER BY name COLLATE NOCASE').map(_contact).toList();
  Contact? contact(String id) {
    final r = _db.select('SELECT * FROM contacts WHERE user_id=?', [id]);
    return r.isEmpty ? null : _contact(r.first);
  }
  void upsertContact(Contact c) => _db.execute('''
    INSERT INTO contacts(user_id,ed_pk,name,avatar,about,verified,blocked,last_seen,added) VALUES(?,?,?,?,?,?,?,?,?)
    ON CONFLICT(user_id) DO UPDATE SET name=excluded.name, avatar=COALESCE(excluded.avatar,avatar), about=excluded.about,
      last_seen=MAX(last_seen,excluded.last_seen), added=MAX(added,excluded.added), verified=MAX(verified,excluded.verified)''',
      [c.userId, c.edPk, c.name, c.avatar, c.about, c.verified ? 1 : 0, c.blocked ? 1 : 0, c.lastSeen, c.added]);
  void setAdded(String id, int ts) => _db.execute('UPDATE contacts SET added=? WHERE user_id=?', [ts, id]);
  void setVerified(String id, bool v) => _db.execute('UPDATE contacts SET verified=? WHERE user_id=?', [v ? 1 : 0, id]);
  void setBlocked(String id, bool v) => _db.execute('UPDATE contacts SET blocked=? WHERE user_id=?', [v ? 1 : 0, id]);
  void touchContact(String id, int ts) => _db.execute('UPDATE contacts SET last_seen=? WHERE user_id=?', [ts, id]);
  void deleteContact(String id) => _db.execute('DELETE FROM contacts WHERE user_id=?', [id]);

  // ---------- conversations ----------
  Conversation _conv(Row r) => Conversation(
      id: r['id'], kind: r['kind'], peerId: r['peer_id'], groupId: r['group_id'], title: r['title'],
      lastMsgTs: r['last_msg_ts'] ?? 0, lastPreview: r['last_preview'] ?? '', unread: r['unread'] ?? 0,
      muted: r['muted'] == 1, disappearingSecs: r['disappearing_secs'] ?? 0, archived: r['archived'] == 1, pinned: r['pinned'] == 1);

  List<Conversation> conversations({bool archived = false}) => _db
      .select('SELECT * FROM conversations WHERE archived=? ORDER BY pinned DESC, last_msg_ts DESC', [archived ? 1 : 0])
      .map(_conv).toList();
  Conversation? conversation(String id) {
    final r = _db.select('SELECT * FROM conversations WHERE id=?', [id]);
    return r.isEmpty ? null : _conv(r.first);
  }
  Conversation directConversation(String peerId, String title) {
    final id = 'd:$peerId';
    final ex = conversation(id);
    if (ex != null) return ex;
    _db.execute('INSERT INTO conversations(id,kind,peer_id,title) VALUES(?,?,?,?)', [id, 'direct', peerId, title]);
    return conversation(id)!;
  }
  Conversation groupConversation(String gid, String title) {
    final id = 'g:$gid';
    final ex = conversation(id);
    if (ex != null) { if (ex.title != title) _db.execute('UPDATE conversations SET title=? WHERE id=?', [title, id]); return conversation(id)!; }
    _db.execute('INSERT INTO conversations(id,kind,group_id,title) VALUES(?,?,?,?)', [id, 'group', gid, title]);
    return conversation(id)!;
  }
  void bumpConversation(String id, int ts, String preview, {bool incrementUnread = false}) => _db.execute(
      'UPDATE conversations SET last_msg_ts=MAX(last_msg_ts,?), last_preview=?, unread=unread+? WHERE id=?',
      [ts, preview, incrementUnread ? 1 : 0, id]);
  void clearUnread(String id) => _db.execute('UPDATE conversations SET unread=0 WHERE id=?', [id]);
  void setConvFlag(String id, String col, Object v) => _db.execute('UPDATE conversations SET $col=? WHERE id=?', [v, id]);
  void clearMessages(String convId) {
    _db.execute('DELETE FROM messages WHERE conv_id=?', [convId]);
    _db.execute("UPDATE conversations SET last_preview='', unread=0 WHERE id=?", [convId]);
  }
  void deleteConversation(String id) {
    _db.execute('DELETE FROM messages WHERE conv_id=?', [id]);
    _db.execute('DELETE FROM conversations WHERE id=?', [id]);
  }

  // ---------- messages ----------
  Message _msg(Row r) => Message(
      id: r['id'], convId: r['conv_id'], senderId: r['sender_id'], ts: r['ts'], kind: r['kind'],
      body: jsonDecode(r['body']) as Map<String, dynamic>, status: r['status'], attachmentId: r['attachment_id'],
      replyTo: r['reply_to'], expiresAt: r['expires_at'], deleted: r['deleted'] == 1,
      reactions: Map<String, String>.from(jsonDecode(r['reactions'] ?? '{}')));

  List<Message> messages(String convId, {int limit = 200, int? before}) => _db
      .select('SELECT * FROM messages WHERE conv_id=? AND ts<? ORDER BY ts DESC LIMIT ?', [convId, before ?? 1 << 62, limit])
      .map(_msg).toList().reversed.toList();
  Message? message(String id) {
    final r = _db.select('SELECT * FROM messages WHERE id=?', [id]);
    return r.isEmpty ? null : _msg(r.first);
  }
  bool hasMessage(String id) => _db.select('SELECT 1 FROM messages WHERE id=?', [id]).isNotEmpty;
  void insertMessage(Message m) => _db.execute('''
    INSERT OR IGNORE INTO messages(id,conv_id,sender_id,ts,kind,body,status,attachment_id,reply_to,expires_at,deleted,reactions)
    VALUES(?,?,?,?,?,?,?,?,?,?,?,?)''',
      [m.id, m.convId, m.senderId, m.ts, m.kind, m.bodyJson, m.status, m.attachmentId, m.replyTo, m.expiresAt, m.deleted ? 1 : 0, jsonEncode(m.reactions)]);
  void updateMessageStatus(String id, String status) {
    // never downgrade read -> delivered
    _db.execute('''UPDATE messages SET status=? WHERE id=? AND NOT (status='read' AND ?<>'read')''', [status, id, status]);
  }
  void updateMessageBody(String id, Map<String, dynamic> body) => _db.execute('UPDATE messages SET body=? WHERE id=?', [jsonEncode(body), id]);
  void markDeleted(String id) => _db.execute("UPDATE messages SET deleted=1, kind='deleted', body='{}' WHERE id=?", [id]);
  void setReaction(String id, String userId, String? emoji) {
    final m = message(id); if (m == null) return;
    final r = Map<String, String>.from(m.reactions);
    if (emoji == null || emoji.isEmpty) { r.remove(userId); } else { r[userId] = emoji; }
    _db.execute('UPDATE messages SET reactions=? WHERE id=?', [jsonEncode(r), id]);
  }
  List<String> unreadIncomingIds(String convId, String me) => _db
      .select("SELECT id FROM messages WHERE conv_id=? AND sender_id<>? AND status<>'read'", [convId, me])
      .map((r) => r['id'] as String).toList();
  void markIncomingRead(String convId, String me) =>
      _db.execute("UPDATE messages SET status='read' WHERE conv_id=? AND sender_id<>?", [convId, me]);
  int purgeExpired() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('DELETE FROM messages WHERE expires_at IS NOT NULL AND expires_at<?', [now]);
    return _db.updatedRows;
  }
  List<Message> searchMessages(String q) => _db
      .select("SELECT * FROM messages WHERE kind='text' AND body LIKE ? ORDER BY ts DESC LIMIT 100", ['%${q.replaceAll('%', '')}%'])
      .map(_msg).toList();

  // ---------- attachments ----------
  Attachment _att(Row r) => Attachment(
      id: r['id'], fileId: r['file_id'], name: r['name'] ?? '', mime: r['mime'] ?? 'application/octet-stream', size: r['size'] ?? 0,
      key: r['key'], hash: r['hash'], chunks: r['chunks'], localPath: r['local_path'], receivedChunks: r['received_chunks'] ?? 0,
      state: r['state'], thumb: r['thumb']);
  Attachment? attachment(String id) {
    final r = _db.select('SELECT * FROM attachments WHERE id=?', [id]);
    return r.isEmpty ? null : _att(r.first);
  }
  void upsertAttachment(Attachment a) => _db.execute('''
    INSERT INTO attachments(id,file_id,name,mime,size,key,hash,chunks,local_path,received_chunks,state,thumb) VALUES(?,?,?,?,?,?,?,?,?,?,?,?)
    ON CONFLICT(id) DO UPDATE SET local_path=COALESCE(excluded.local_path,local_path), received_chunks=excluded.received_chunks,
      state=excluded.state, thumb=COALESCE(excluded.thumb,thumb)''',
      [a.id, a.fileId, a.name, a.mime, a.size, a.key, a.hash, a.chunks, a.localPath, a.receivedChunks, a.state, a.thumb]);
  void updateAttachmentProgress(String id, int received, String state, {String? path}) => _db.execute(
      'UPDATE attachments SET received_chunks=?, state=?, local_path=COALESCE(?,local_path) WHERE id=?', [received, state, path, id]);

  // ---------- groups ----------
  GroupInfo? group(String gid) {
    final r = _db.select('SELECT * FROM groups WHERE gid=?', [gid]);
    if (r.isEmpty) return null;
    final st = jsonDecode(r.first['state_json']) as Map<String, dynamic>;
    return GroupInfo(
        gid: gid, name: r.first['name'], version: r.first['version'], created: r.first['created'],
        members: (st['members'] as Map<String, dynamic>).map((k, v) => MapEntry(k, Crypto.b64d(v))),
        admins: (st['admins'] as List).cast<String>(), avatar: r.first['avatar']);
  }
  Map<String, dynamic>? groupStateDoc(String gid) {
    final r = _db.select('SELECT state_json FROM groups WHERE gid=?', [gid]);
    return r.isEmpty ? null : jsonDecode(r.first['state_json']);
  }
  List<GroupInfo> groups() => _db.select('SELECT gid FROM groups').map((r) => group(r['gid'])!).toList();
  void upsertGroup(String gid, Map<String, dynamic> stateDoc) => _db.execute('''
    INSERT INTO groups(gid,name,version,created,state_json) VALUES(?,?,?,?,?)
    ON CONFLICT(gid) DO UPDATE SET name=excluded.name, version=excluded.version, state_json=excluded.state_json''',
      [gid, stateDoc['name'], stateDoc['version'], stateDoc['created'], jsonEncode(stateDoc)]);
  void setGroupAvatar(String gid, Uint8List? a) => _db.execute('UPDATE groups SET avatar=? WHERE gid=?', [a, gid]);
  void deleteGroup(String gid) {
    _db.execute('DELETE FROM sender_keys WHERE gid=?', [gid]);
    _db.execute('DELETE FROM groups WHERE gid=?', [gid]);
  }
  (Uint8List, Uint8List, Uint8List, int)? mySenderKey(String gid) {
    final r = _db.select('SELECT my_ck,my_spk,my_ssk,my_n FROM groups WHERE gid=? AND my_ck IS NOT NULL', [gid]);
    if (r.isEmpty) return null;
    return (r.first['my_ck'], r.first['my_spk'], r.first['my_ssk'], r.first['my_n']);
  }
  void saveMySenderKey(String gid, Uint8List ck, Uint8List spk, Uint8List ssk, int n) =>
      _db.execute('UPDATE groups SET my_ck=?, my_spk=?, my_ssk=?, my_n=? WHERE gid=?', [ck, spk, ssk, n, gid]);
  (Uint8List, Uint8List, int, String?)? senderKey(String gid, String sender) {
    final r = _db.select('SELECT ck,spk,n,skipped FROM sender_keys WHERE gid=? AND sender_id=?', [gid, sender]);
    if (r.isEmpty) return null;
    return (r.first['ck'], r.first['spk'], r.first['n'], r.first['skipped']);
  }
  void saveSenderKey(String gid, String sender, Uint8List ck, Uint8List spk, int n, String skipped) => _db.execute(
      'INSERT OR REPLACE INTO sender_keys(gid,sender_id,ck,spk,n,skipped) VALUES(?,?,?,?,?,?)', [gid, sender, ck, spk, n, skipped]);
  void deleteSenderKeysFor(String gid) {
    _db.execute('DELETE FROM sender_keys WHERE gid=?', [gid]);
    _db.execute('UPDATE groups SET my_ck=NULL, my_spk=NULL, my_ssk=NULL WHERE gid=?', [gid]);
  }
  void setGroupLeft(String gid) => kvSet('left:$gid', '1');
  bool groupLeft(String gid) => kvGet('left:$gid') == '1';
  void deleteSenderKey(String gid, String sender) => _db.execute('DELETE FROM sender_keys WHERE gid=? AND sender_id=?', [gid, sender]);

  // ---------- outbox (store & forward) ----------
  void enqueue(String target, Map<String, dynamic> envelope, {String? refMsg}) => _db.execute(
      'INSERT INTO outbox(target,envelope,created,ref_msg) VALUES(?,?,?,?)',
      [target, jsonEncode(envelope), DateTime.now().millisecondsSinceEpoch, refMsg]);
  List<(int, Map<String, dynamic>, String?)> outboxFor(String target) => _db
      .select('SELECT id,envelope,ref_msg FROM outbox WHERE target=? ORDER BY id', [target])
      .map((r) => (r['id'] as int, jsonDecode(r['envelope']) as Map<String, dynamic>, r['ref_msg'] as String?)).toList();
  void dequeue(int id) => _db.execute('DELETE FROM outbox WHERE id=?', [id]);
  int outboxCount() => _db.select('SELECT count(*) c FROM outbox').first['c'] as int;
  void dropOutboxForMsg(String msgId) => _db.execute('DELETE FROM outbox WHERE ref_msg=?', [msgId]);

  // ---------- status ----------
  StatusPost _post(Row r) => StatusPost(
      id: r['id'], authorId: r['author_id'], ts: r['ts'], expires: r['expires'], kind: r['kind'],
      body: jsonDecode(r['body']), attachmentId: r['attachment_id'], seen: r['seen'] == 1,
      viewers: _db.select('SELECT viewer_id FROM status_views WHERE post_id=?', [r['id']]).map((x) => x['viewer_id'] as String).toList());
  List<StatusPost> statusPosts({String? author}) {
    final now = DateTime.now().millisecondsSinceEpoch;
    _db.execute('DELETE FROM status_posts WHERE expires<?', [now]);
    final rows = author == null
        ? _db.select('SELECT * FROM status_posts ORDER BY ts')
        : _db.select('SELECT * FROM status_posts WHERE author_id=? ORDER BY ts', [author]);
    return rows.map(_post).toList();
  }
  List<String> statusIds() => _db.select('SELECT id FROM status_posts').map((r) => r['id'] as String).toList();
  bool hasStatus(String id) => _db.select('SELECT 1 FROM status_posts WHERE id=?', [id]).isNotEmpty;
  void insertStatus(StatusPost s) => _db.execute(
      'INSERT OR IGNORE INTO status_posts(id,author_id,ts,expires,kind,body,attachment_id,seen) VALUES(?,?,?,?,?,?,?,?)',
      [s.id, s.authorId, s.ts, s.expires, s.kind, jsonEncode(s.body), s.attachmentId, s.seen ? 1 : 0]);
  void markStatusSeen(String id) => _db.execute('UPDATE status_posts SET seen=1 WHERE id=?', [id]);
  void addStatusView(String postId, String viewer) => _db.execute(
      'INSERT OR IGNORE INTO status_views(post_id,viewer_id,ts) VALUES(?,?,?)', [postId, viewer, DateTime.now().millisecondsSinceEpoch]);
  void deleteStatus(String id) => _db.execute('DELETE FROM status_posts WHERE id=?', [id]);

  // ---------- calls ----------
  List<CallLog> calls() => _db.select('SELECT * FROM calls ORDER BY ts DESC LIMIT 200').map((r) => CallLog(
      id: r['id'], peerId: r['peer_id'], ts: r['ts'], outgoing: r['outgoing'] == 1, answered: r['answered'] == 1,
      duration: r['duration'] ?? 0, video: r['video'] == 1)).toList();
  void upsertCall(CallLog c) => _db.execute('''INSERT INTO calls(id,peer_id,ts,outgoing,answered,duration,video) VALUES(?,?,?,?,?,?,?)
      ON CONFLICT(id) DO UPDATE SET answered=excluded.answered, duration=excluded.duration''',
      [c.id, c.peerId, c.ts, c.outgoing ? 1 : 0, c.answered ? 1 : 0, c.duration, c.video ? 1 : 0]);

  void close() { _db.dispose(); _i = null; }

  static Future<void> wipeFiles() async {
    final dir = await getApplicationSupportDirectory();
    for (final f in ['privchat.db', 'privchat.db-wal', 'privchat.db-shm']) {
      final file = File(p.join(dir.path, f));
      if (file.existsSync()) file.deleteSync();
    }
  }
}
