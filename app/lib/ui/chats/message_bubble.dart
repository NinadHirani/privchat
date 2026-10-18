import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import '../../core/crypto/crypto.dart';
import '../../core/crypto/identity.dart';
import '../../core/protocol/envelope.dart';
import '../../core/services/app_core.dart';
import '../../core/storage/media_store.dart';
import '../../models/models.dart';
import '../location/location_screen.dart';
import '../media/media_viewer.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// In-memory only cache of decrypted images (never written to disk).
class _ImgCache {
  static final _m = <String, Uint8List>{};
  static Uint8List? get(String id) => _m[id];
  static void put(String id, Uint8List b) {
    if (_m.length > 40) _m.remove(_m.keys.first);
    _m[id] = b;
  }
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({super.key, required this.m, required this.isGroup, this.onLongPress, this.onReplyTap, this.selected = false});
  final Message m;
  final bool isGroup, selected;
  final VoidCallback? onLongPress;
  final void Function(String id)? onReplyTap;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final mine = m.senderId == core.identity.userId;
    final dark = AppTheme.isDark(context);

    if (m.kind == MsgKind.system) {
      return Center(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 40),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: dark ? const Color(0xFF182229) : const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(8)),
          child: Text(m.text, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12.5)),
        ),
      );
    }

    final bg = mine ? (dark ? AppTheme.bubbleOutDark : AppTheme.bubbleOut) : (dark ? AppTheme.bubbleInDark : AppTheme.bubbleIn);
    final reactions = m.reactions.values.toSet().join();
    return GestureDetector(
      onLongPress: onLongPress,
      child: Container(
        color: selected ? AppTheme.teal.withOpacity(.18) : Colors.transparent,
        padding: EdgeInsets.only(left: mine ? 56 : 8, right: mine ? 8 : 56, top: 2, bottom: reactions.isEmpty ? 2 : 14),
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Stack(clipBehavior: Clip.none, children: [
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .78),
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(10), topRight: const Radius.circular(10),
                bottomLeft: Radius.circular(mine ? 10 : 2), bottomRight: Radius.circular(mine ? 2 : 10),
              ),
              boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 1, offset: Offset(0, 1))],
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              if (isGroup && !mine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(core.nameOf(m.senderId),
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600,
                          color: Colors.primaries[m.senderId.hashCode.abs() % Colors.primaries.length])),
                ),
              if (m.body['forwarded'] == true)
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.shortcut, size: 14, color: Colors.grey),
                  Text(' Forwarded', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey)),
                ]),
              if (m.replyTo != null) _ReplyQuote(id: m.replyTo!, onTap: onReplyTap),
              _content(context, mine),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                if (m.expiresAt != null) const Icon(Icons.timer_outlined, size: 12, color: Colors.grey),
                Text(' ${fmtTime(m.ts)}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (mine && m.kind != MsgKind.call) ...[const SizedBox(width: 3), _Tick(status: m.status)],
              ]),
            ]),
          ),
          if (reactions.isNotEmpty)
            Positioned(
              bottom: -13, left: mine ? null : 8, right: mine ? 8 : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(12),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)]),
                child: Text('$reactions${m.reactions.length > 1 ? ' ${m.reactions.length}' : ''}', style: const TextStyle(fontSize: 13)),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _content(BuildContext context, bool mine) {
    final core = AppCore.I;
    final att = m.attachmentId == null ? null : core.db.attachment(m.attachmentId!);
    switch (m.kind) {
      case MsgKind.deleted:
        return Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.block, size: 16, color: Colors.grey),
          Text(mine ? ' You deleted this message' : ' This message was deleted',
              style: const TextStyle(fontStyle: FontStyle.italic, color: Colors.grey)),
        ]);
      case MsgKind.image:
        return _withCaption(_ImageBody(att: att));
      case MsgKind.video:
        return _withCaption(_VideoBody(att: att));
      case MsgKind.audio:
        return _AudioBody(att: att, durationMs: (m.body['duration'] as num?)?.toInt());
      case MsgKind.doc:
        return _withCaption(_DocBody(att: att));
      case MsgKind.location:
      case MsgKind.liveLocation:
        return _LocationBody(m: m);
      case MsgKind.contact:
        return _ContactBody(m: m);
      case MsgKind.call:
        final missed = m.body['missed'] == true, video = m.body['video'] == true;
        final out = m.body['outgoing'] == true;
        return Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(video ? Icons.videocam : Icons.call, color: missed ? Colors.red : AppTheme.teal, size: 20),
          const SizedBox(width: 8),
          Text(missed
              ? (out ? 'No answer' : 'Missed ${video ? 'video' : 'voice'} call')
              : '${video ? 'Video' : 'Voice'} call · ${fmtDuration((m.body['duration'] as num?)?.toInt() ?? 0)}'),
        ]);
      default:
        return SelectableText(m.text, style: const TextStyle(fontSize: 15.5));
    }
  }

  Widget _withCaption(Widget media) {
    if (m.text.isEmpty) return media;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      media,
      Padding(padding: const EdgeInsets.only(top: 4), child: Text(m.text, style: const TextStyle(fontSize: 15))),
    ]);
  }
}

class _Tick extends StatelessWidget {
  const _Tick({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    switch (status) {
      case MsgStatus.pending:
        return const Icon(Icons.schedule, size: 14, color: Colors.grey);
      case MsgStatus.sent:
        return const Icon(Icons.done, size: 15, color: Colors.grey);
      case MsgStatus.delivered:
        return const Icon(Icons.done_all, size: 15, color: Colors.grey);
      case MsgStatus.read:
        return const Icon(Icons.done_all, size: 15, color: AppTheme.tickBlue);
      default:
        return const Icon(Icons.error_outline, size: 14, color: Colors.red);
    }
  }
}

class _ReplyQuote extends StatelessWidget {
  const _ReplyQuote({required this.id, this.onTap});
  final String id;
  final void Function(String id)? onTap;
  @override
  Widget build(BuildContext context) {
    final q = AppCore.I.db.message(id);
    return GestureDetector(
      onTap: () => onTap?.call(id),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.06),
          borderRadius: BorderRadius.circular(6),
          border: const Border(left: BorderSide(color: AppTheme.teal, width: 3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(q == null ? '' : AppCore.I.nameOf(q.senderId),
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5, color: AppTheme.teal)),
          Text(q?.preview() ?? 'Message unavailable', maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
        ]),
      ),
    );
  }
}

/// Shows download state for attachments that haven't arrived yet.
class _Pending extends StatelessWidget {
  const _Pending({required this.att, required this.icon});
  final Attachment att;
  final IconData icon;
  @override
  Widget build(BuildContext context) {
    final transferring = att.state == 'transferring';
    return GestureDetector(
      onTap: () {
        AppCore.I.files.request(att.id);
        if (!transferring) toast(context, 'Downloading when the sender is nearby…');
      },
      child: Stack(alignment: Alignment.center, children: [
        if (att.thumb != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: ImageFiltered(
              imageFilter: ColorFilter.mode(Colors.black.withOpacity(.25), BlendMode.darken),
              child: Image.memory(att.thumb!, width: 240, height: 200, fit: BoxFit.cover),
            ),
          )
        else
          Container(width: 240, height: 140, decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(6)),
              child: Icon(icon, size: 48, color: Colors.grey)),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
          child: transferring
              ? SizedBox(width: 28, height: 28,
                  child: CircularProgressIndicator(value: att.progress, strokeWidth: 3, color: Colors.white))
              : const Icon(Icons.download, color: Colors.white, size: 28),
        ),
        Positioned(bottom: 6, left: 8,
            child: Text(fmtBytes(att.size), style: const TextStyle(color: Colors.white, fontSize: 12, shadows: [Shadow(blurRadius: 3)]))),
      ]),
    );
  }
}

class _ImageBody extends StatelessWidget {
  const _ImageBody({required this.att});
  final Attachment? att;
  @override
  Widget build(BuildContext context) {
    final a = att;
    if (a == null) return const Text('Image unavailable');
    if (!a.done) return _Pending(att: a, icon: Icons.image);
    final cached = _ImgCache.get(a.id);
    final child = cached != null
        ? Image.memory(cached, width: 240, fit: BoxFit.cover, gaplessPlayback: true)
        : FutureBuilder<Uint8List?>(
            future: MediaStore.readPlain(a).then((b) {
              if (b != null) _ImgCache.put(a.id, b);
              return b;
            }),
            builder: (_, s) => s.data == null
                ? Container(width: 240, height: 200, color: Colors.black12)
                : Image.memory(s.data!, width: 240, fit: BoxFit.cover, gaplessPlayback: true),
          );
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaViewer(att: a))),
      child: Hero(tag: a.id, child: ClipRRect(borderRadius: BorderRadius.circular(6), child: child)),
    );
  }
}

class _VideoBody extends StatelessWidget {
  const _VideoBody({required this.att});
  final Attachment? att;
  @override
  Widget build(BuildContext context) {
    final a = att;
    if (a == null) return const Text('Video unavailable');
    if (!a.done) return _Pending(att: a, icon: Icons.videocam);
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaViewer(att: a))),
      child: Container(
        width: 240, height: 160,
        decoration: BoxDecoration(color: Colors.black87, borderRadius: BorderRadius.circular(6)),
        child: Stack(alignment: Alignment.center, children: [
          const Icon(Icons.play_circle_fill, color: Colors.white, size: 56),
          Positioned(bottom: 6, left: 8,
              child: Row(children: [
                const Icon(Icons.videocam, color: Colors.white70, size: 16),
                Text(' ${fmtBytes(a.size)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ])),
        ]),
      ),
    );
  }
}

class _AudioBody extends StatefulWidget {
  const _AudioBody({required this.att, this.durationMs});
  final Attachment? att;
  final int? durationMs;
  @override
  State<_AudioBody> createState() => _AudioBodyState();
}

class _AudioBodyState extends State<_AudioBody> {
  final _player = AudioPlayer();
  Duration _pos = Duration.zero, _dur = Duration.zero;
  bool _playing = false;
  final _subs = <StreamSubscription>[];

  @override
  void initState() {
    super.initState();
    _dur = Duration(milliseconds: widget.durationMs ?? 0);
    _subs.add(_player.onPositionChanged.listen((p) => setState(() => _pos = p)));
    _subs.add(_player.onDurationChanged.listen((d) => setState(() => _dur = d)));
    _subs.add(_player.onPlayerComplete.listen((_) => setState(() { _playing = false; _pos = Duration.zero; })));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final a = widget.att!;
    if (_playing) {
      await _player.pause();
      setState(() => _playing = false);
      return;
    }
    final f = await MediaStore.openPlain(a);
    if (f == null) return;
    await _player.play(DeviceFileSource(f.path));
    setState(() => _playing = true);
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.att;
    if (a == null) return const Text('Voice message unavailable');
    final ready = a.done;
    return SizedBox(
      width: 230,
      child: Row(children: [
        ready
            ? IconButton(icon: Icon(_playing ? Icons.pause : Icons.play_arrow, size: 32), onPressed: _toggle)
            : IconButton(
                icon: a.state == 'transferring'
                    ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: a.progress, strokeWidth: 2))
                    : const Icon(Icons.download),
                onPressed: () => AppCore.I.files.request(a.id)),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Slider(
              value: _dur.inMilliseconds == 0 ? 0 : (_pos.inMilliseconds / _dur.inMilliseconds).clamp(0, 1).toDouble(),
              onChanged: ready && _dur.inMilliseconds > 0
                  ? (v) => _player.seek(Duration(milliseconds: (v * _dur.inMilliseconds).round()))
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.only(left: 22),
              child: Text(fmtDuration((_playing ? _pos : _dur).inSeconds), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ),
          ]),
        ),
        const Icon(Icons.mic, color: AppTheme.teal, size: 20),
      ]),
    );
  }
}

class _DocBody extends StatelessWidget {
  const _DocBody({required this.att});
  final Attachment? att;
  @override
  Widget build(BuildContext context) {
    final a = att;
    if (a == null) return const Text('Document unavailable');
    return InkWell(
      onTap: () async {
        if (!a.done) {
          AppCore.I.files.request(a.id);
          toast(context, 'Downloading when the sender is nearby…');
          return;
        }
        final f = await MediaStore.openPlain(a);
        if (f != null) await OpenFilex.open(f.path);
      },
      child: Container(
        width: 250,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.black.withOpacity(.05), borderRadius: BorderRadius.circular(6)),
        child: Row(children: [
          Icon(a.mime == 'application/pdf' ? Icons.picture_as_pdf : Icons.insert_drive_file, size: 36,
              color: a.mime == 'application/pdf' ? Colors.red : AppTheme.teal),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)),
              Text(fmtBytes(a.size), style: const TextStyle(fontSize: 12, color: Colors.grey)),
            ]),
          ),
          if (!a.done)
            a.state == 'transferring'
                ? SizedBox(width: 24, height: 24, child: CircularProgressIndicator(value: a.progress, strokeWidth: 2))
                : const Icon(Icons.download, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _LocationBody extends StatelessWidget {
  const _LocationBody({required this.m});
  final Message m;
  @override
  Widget build(BuildContext context) {
    final live = m.kind == MsgKind.liveLocation;
    final active = live && m.body['active'] == true && ((m.body['until'] as num?) ?? 0) > DateTime.now().millisecondsSinceEpoch;
    final lat = (m.body['lat'] as num?)?.toDouble() ?? 0, lng = (m.body['lng'] as num?)?.toDouble() ?? 0;
    return InkWell(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocationViewScreen(msgId: m.id))),
      child: Container(
        width: 240,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [AppTheme.teal.withOpacity(.25), AppTheme.green.withOpacity(.15)]),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(live ? Icons.share_location : Icons.location_on, color: active ? Colors.red : AppTheme.teal, size: 32),
            const SizedBox(width: 8),
            Expanded(
              child: Text(live ? (active ? 'Live location' : 'Live location ended') : 'Location',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ]),
          const SizedBox(height: 6),
          Text('${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}', style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
          if (m.body['acc'] != null) Text('±${(m.body['acc'] as num).round()} m', style: const TextStyle(fontSize: 12, color: Colors.grey)),
          const SizedBox(height: 4),
          const Text('Tap for compass & distance', style: TextStyle(fontSize: 12, color: AppTheme.teal)),
        ]),
      ),
    );
  }
}

class _ContactBody extends StatelessWidget {
  const _ContactBody({required this.m});
  final Message m;
  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final name = m.body['name'] as String? ?? 'Contact';
    final phones = (m.body['phones'] as List?)?.cast<String>() ?? [];
    final uid = m.body['uid'] as String?, pk = m.body['pk'] as String?;
    final known = uid != null && (core.db.contact(uid)?.added ?? 0) > 0;
    return SizedBox(
      width: 240,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Avatar(name: name, radius: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
              for (final p in phones.take(3)) Text(p, style: const TextStyle(fontSize: 12.5)),
              if (uid != null) const Text('PrivChat user', style: TextStyle(fontSize: 12, color: AppTheme.teal)),
            ]),
          ),
        ]),
        if (uid != null && pk != null && uid != core.identity.userId && !known) ...[
          const Divider(),
          Center(
            child: TextButton(
              onPressed: () {
                final edPk = Crypto.b64d(pk);
                if (edPk.length != 32 || userIdFromEdPk(edPk) != uid) {
                  toast(context, 'This contact card is invalid or was tampered with');
                  return;
                }
                core.db.upsertContact(Contact(userId: uid, edPk: edPk, name: name, added: DateTime.now().millisecondsSinceEpoch));
                core.db.directConversation(uid, name);
                core.notify();
                toast(context, '$name added. Verify their safety number when you meet.');
              },
              child: const Text('Add to contacts'),
            ),
          ),
        ],
      ]),
    );
  }
}
