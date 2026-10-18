import 'dart:async';
import 'dart:typed_data';
import '../crypto/crypto.dart';
import '../protocol/envelope.dart';
import '../storage/db.dart';
import '../storage/media_store.dart';
import '../../models/models.dart';
import 'connection_manager.dart';
import 'peer_connection.dart';

/// Pull-based, resumable encrypted file transfer.
/// Receiver: file.req{id, from} → Sender streams chunks (ptype 2) → file.done{id}
class FileTransfer {
  FileTransfer(this.cm) {
    cm.envelopes.listen((e) => _onEnvelope(e.$1, e.$2));
    cm.chunks.listen((e) => _onChunk(e.$1, e.$2, e.$3, e.$4));
    cm.events.listen((e) { if (e.type == 'online') _resumePending(e.peerId); });
  }
  final ConnectionManager cm;
  final _progress = StreamController<Attachment>.broadcast();
  Stream<Attachment> get progress => _progress.stream;
  final Map<String, Set<String>> _sources = {}; // attId -> peer ids that can serve it
  final Set<String> _active = {};

  /// Peer that announced the attachment (so we know whom to ask).
  void registerSource(String attId, String peerId) => (_sources[attId] ??= {}).add(peerId);

  /// Permission check: only serve a file to a peer that is a participant of a conversation containing it.
  bool Function(String peerId, String attId)? canServe;

  Future<void> request(String attId) async {
    final att = AppDb.I.attachment(attId);
    if (att == null || att.done || _active.contains(attId)) return;
    final src = _sources[attId]?.firstWhere(cm.isOnline, orElse: () => '') ?? '';
    if (src.isEmpty) return;
    final have = MediaStore.partialChunkCount(att);
    _active.add(attId);
    AppDb.I.updateAttachmentProgress(attId, have, 'transferring');
    _progress.add(att..receivedChunks = have..state = 'transferring');
    await cm.send(src, {'type': Env.fileReq, 'id': attId, 'from': have}, queueIfOffline: false);
  }

  void _resumePending(String peerId) {
    for (final e in _sources.entries) {
      if (e.value.contains(peerId)) {
        final a = AppDb.I.attachment(e.key);
        if (a != null && !a.done && a.state != 'failed') { _active.remove(e.key); request(e.key); }
      }
    }
  }

  Future<void> _onEnvelope(PeerConnection c, Map<String, dynamic> env) async {
    switch (env['type']) {
      case Env.fileReq:
        final id = env['id'] as String;
        final from = (env['from'] as num?)?.toInt() ?? 0;
        if (canServe != null && !canServe!(c.peerId, id)) return;
        final att = AppDb.I.attachment(id);
        if (att == null || !att.done) return;
        unawaited(_serve(c, att, from));
        break;
      case Env.fileDone:
        final id = env['id'] as String;
        final att = AppDb.I.attachment(id);
        if (att == null) return;
        _active.remove(id);
        final ok = await MediaStore.finalize(att);
        AppDb.I.updateAttachmentProgress(id, ok ? att.chunks : 0, ok ? 'done' : 'failed', path: ok ? MediaStore.vaultPath(id) : null);
        _progress.add(AppDb.I.attachment(id)!);
        break;
    }
  }

  Future<void> _serve(PeerConnection c, Attachment att, int from) async {
    for (var i = from; i < att.chunks; i++) {
      if (c.closed) return;
      final ct = await MediaStore.readCipherChunk(att, i);
      if (ct == null) return;
      try { await c.sendChunk(att.fileId, i, ct); } catch (_) { return; }
    }
    try { await c.sendEnvelope({'type': Env.fileDone, 'id': att.id}); } catch (_) {}
  }

  Future<void> _onChunk(PeerConnection c, Uint8List fileId, int index, Uint8List ct) async {
    final id = Crypto.b64e(fileId);
    final att = AppDb.I.attachment(id);
    if (att == null || att.done) return;
    final have = MediaStore.partialChunkCount(att);
    if (index != have) return; // out-of-order (e.g. duplicate serve) — ignore; resume logic re-requests
    await MediaStore.appendCipherChunk(att, index, ct);
    att.receivedChunks = index + 1;
    att.state = 'transferring';
    if (index % 4 == 0 || index == att.chunks - 1) {
      AppDb.I.updateAttachmentProgress(id, att.receivedChunks, 'transferring');
      _progress.add(att);
    }
  }

  void cancel(String attId) { _active.remove(attId); }
}
