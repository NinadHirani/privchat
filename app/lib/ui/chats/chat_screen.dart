import 'dart:async';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import '../../core/crypto/crypto.dart';
import '../../core/protocol/envelope.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../contacts/contact_info_screen.dart';
import '../groups/group_info_screen.dart';
import '../location/location_screen.dart';
import '../media/media_utils.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'forward_screen.dart';
import 'message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key, required this.convId});
  final String convId;
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final core = AppCore.I;
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _recorder = AudioRecorder();
  Message? _replyTo;
  String? _highlight;
  bool _recording = false, _sendingTyping = false;
  DateTime? _recStart;
  Timer? _recTicker, _typingOff;

  Conversation get conv => core.db.conversation(widget.convId)!;

  @override
  void initState() {
    super.initState();
    core.notifications.activeConvId = widget.convId;
    core.addListener(_onCore);
    WidgetsBinding.instance.addPostFrameCallback((_) => core.messages.markRead(widget.convId));
    _text.addListener(_onTyping);
  }

  void _onCore() {
    if (!mounted) return;
    if (core.db.conversation(widget.convId)?.unread != 0) core.messages.markRead(widget.convId);
  }

  void _onTyping() {
    setState(() {});
    if (_text.text.isEmpty) return;
    if (!_sendingTyping) {
      _sendingTyping = true;
      core.messages.sendTyping(widget.convId, true);
    }
    _typingOff?.cancel();
    _typingOff = Timer(const Duration(seconds: 3), () {
      _sendingTyping = false;
      core.messages.sendTyping(widget.convId, false);
    });
  }

  @override
  void dispose() {
    core.notifications.activeConvId = null;
    core.removeListener(_onCore);
    _typingOff?.cancel();
    _recTicker?.cancel();
    _recorder.dispose();
    if (_sendingTyping) core.messages.sendTyping(widget.convId, false);
    super.dispose();
  }

  // ------------------------------------------------------------------ sending
  Future<void> _sendText() async {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _text.clear();
    final reply = _replyTo?.id;
    setState(() => _replyTo = null);
    await core.messages.sendText(widget.convId, t, replyTo: reply);
  }

  Future<void> _guard(Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (mounted) toast(context, 'Failed: $e');
    }
  }

  Future<String?> _caption() => promptText(context, 'Add a caption (optional)', maxLength: 500);

  Future<void> _pickImage(ImageSource src) => _guard(() async {
        final x = await ImagePicker().pickImage(source: src);
        if (x == null) return;
        final cap = await _caption();
        final att = await MediaUtils.importImage(x.path);
        await core.messages.sendAttachment(widget.convId, att, MsgKind.image, caption: cap, replyTo: _takeReply());
      });

  Future<void> _pickVideo(ImageSource src) => _guard(() async {
        final x = await ImagePicker().pickVideo(source: src, maxDuration: const Duration(minutes: 5));
        if (x == null) return;
        final cap = await _caption();
        final att = await MediaUtils.importVideo(x.path);
        await core.messages.sendAttachment(widget.convId, att, MsgKind.video, caption: cap, replyTo: _takeReply());
      });

  Future<void> _pickDoc() => _guard(() async {
        final r = await FilePicker.platform.pickFiles(withData: false);
        final f = r?.files.single;
        if (f?.path == null) return;
        if (f!.size > 512 * 1024 * 1024) {
          if (mounted) toast(context, 'Files up to 512 MB are supported');
          return;
        }
        final att = await MediaUtils.importDocument(f.path!, f.name);
        await core.messages.sendAttachment(widget.convId, att, MsgKind.doc, replyTo: _takeReply());
      });

  Future<void> _pickContact() => _guard(() async {
        if (!await fc.FlutterContacts.requestPermission(readonly: true)) {
          if (mounted) toast(context, 'Contacts permission denied');
          return;
        }
        final c = await fc.FlutterContacts.openExternalPick();
        if (c == null) return;
        final full = await fc.FlutterContacts.getContact(c.id) ?? c;
        await core.messages.sendContactCard(widget.convId,
            name: full.displayName, phones: full.phones.map((p) => p.number).toList());
      });

  Future<void> _sharePrivchatContact() async {
    final contacts = core.db.contacts().where((c) => c.added > 0).toList();
    final picked = await showModalBottomSheet<Contact>(
      context: context,
      builder: (c) => ListView(children: [
        const ListTile(title: Text('Share a PrivChat contact', style: TextStyle(fontWeight: FontWeight.bold))),
        for (final ct in contacts)
          ListTile(leading: Avatar(name: ct.name, bytes: ct.avatar), title: Text(ct.name), onTap: () => Navigator.pop(c, ct)),
      ]),
    );
    if (picked == null) return;
    await core.messages.sendContactCard(widget.convId, name: picked.name, uid: picked.userId, edPk: Crypto.b64e(picked.edPk));
  }

  Future<void> _location() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ShareLocationScreen(convId: widget.convId)));
  }

  String? _takeReply() {
    final r = _replyTo?.id;
    if (mounted) setState(() => _replyTo = null);
    return r;
  }

  void _attachSheet() {
    Widget item(IconData i, String label, Color color, VoidCallback onTap) => InkWell(
          onTap: () {
            Navigator.pop(context);
            onTap();
          },
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            CircleAvatar(radius: 28, backgroundColor: color, child: Icon(i, color: Colors.white)),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12.5)),
          ]),
        );
    showModalBottomSheet(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: GridView.count(
            crossAxisCount: 4, shrinkWrap: true, mainAxisSpacing: 18,
            children: [
              item(Icons.insert_drive_file, 'Document', Colors.indigo, _pickDoc),
              item(Icons.camera_alt, 'Camera', Colors.pink, () => _pickImage(ImageSource.camera)),
              item(Icons.photo, 'Gallery', Colors.purple, () => _pickImage(ImageSource.gallery)),
              item(Icons.videocam, 'Video', Colors.deepOrange, () => _pickVideo(ImageSource.gallery)),
              item(Icons.location_on, 'Location', Colors.green, _location),
              item(Icons.person, 'Phone contact', Colors.blue, _pickContact),
              item(Icons.verified_user, 'PrivChat contact', AppTheme.teal, _sharePrivchatContact),
              item(Icons.video_call, 'Record video', Colors.red, () => _pickVideo(ImageSource.camera)),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------ voice notes
  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) toast(context, 'Microphone permission needed');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 48000, sampleRate: 24000, numChannels: 1), path: path);
    HapticFeedback.mediumImpact();
    setState(() {
      _recording = true;
      _recStart = DateTime.now();
    });
    _recTicker = Timer.periodic(const Duration(milliseconds: 500), (_) => setState(() {}));
  }

  Future<void> _stopRecording({required bool send}) async {
    _recTicker?.cancel();
    final path = await _recorder.stop();
    final dur = DateTime.now().difference(_recStart ?? DateTime.now());
    setState(() => _recording = false);
    if (path == null) return;
    if (!send || dur.inMilliseconds < 700) {
      await _recorder.cancel();
      return;
    }
    await _guard(() async {
      final att = await MediaUtils.importAudio(path);
      await core.messages.sendAttachment(widget.convId, att, MsgKind.audio, durationMs: dur.inMilliseconds, replyTo: _takeReply());
    });
  }

  // ------------------------------------------------------------------ message actions
  void _actions(Message m) {
    final mine = m.senderId == core.identity.userId;
    final canAct = m.kind != MsgKind.system && m.kind != MsgKind.deleted && m.kind != MsgKind.call;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (canAct)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                for (final e in ['👍', '❤️', '😂', '😮', '😢', '🙏'])
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(c);
                      core.messages.react(m.id, m.reactions[core.identity.userId] == e ? null : e);
                    },
                    child: Text(e, style: const TextStyle(fontSize: 30)),
                  ),
              ]),
            ),
          if (canAct)
            ListTile(leading: const Icon(Icons.reply), title: const Text('Reply'), onTap: () {
              Navigator.pop(c);
              setState(() => _replyTo = m);
            }),
          if (m.kind == MsgKind.text)
            ListTile(leading: const Icon(Icons.copy), title: const Text('Copy'), onTap: () {
              Clipboard.setData(ClipboardData(text: m.text));
              Navigator.pop(c);
              toast(context, 'Copied');
            }),
          if (canAct)
            ListTile(leading: const Icon(Icons.shortcut), title: const Text('Forward'), onTap: () {
              Navigator.pop(c);
              Navigator.push(context, MaterialPageRoute(builder: (_) => ForwardScreen(msgId: m.id)));
            }),
          if (mine && m.status == MsgStatus.pending)
            ListTile(leading: const Icon(Icons.schedule), title: const Text('Waiting for recipient to be nearby'), onTap: () => Navigator.pop(c)),
          if (mine && m.kind == MsgKind.liveLocation && core.messages.isSharingLive(m.id))
            ListTile(leading: const Icon(Icons.location_off, color: Colors.red), title: const Text('Stop sharing live location'), onTap: () {
              Navigator.pop(c);
              core.messages.stopLiveLocation(m.id);
            }),
          ListTile(leading: const Icon(Icons.delete_outline), title: const Text('Delete for me'), onTap: () {
            Navigator.pop(c);
            core.messages.deleteForMe(m.id);
          }),
          if (mine && canAct)
            ListTile(
              leading: const Icon(Icons.delete_forever, color: Colors.red),
              title: const Text('Delete for everyone', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(c);
                core.messages.deleteForEveryone(m.id);
              },
            ),
        ]),
      ),
    );
  }

  // ------------------------------------------------------------------ header
  Future<void> _call(bool video) async {
    final err = await core.calls.start(conv.peerId!, video: video);
    if (err != null && mounted) toast(context, err);
  }

  void _openInfo() {
    final c = conv;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => c.isGroup ? GroupInfoScreen(gid: c.groupId!) : ContactInfoScreen(userId: c.peerId!),
    ));
  }

  Future<void> _disappearing() async {
    final opts = {0: 'Off', 3600: '1 hour', 86400: '24 hours', 604800: '7 days', 7776000: '90 days'};
    final v = await showDialog<int>(
      context: context,
      builder: (c) => SimpleDialog(
        title: const Text('Disappearing messages'),
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text('New messages you send will be erased from both phones after this time.', style: TextStyle(fontSize: 13))),
          for (final e in opts.entries)
            RadioListTile<int>(value: e.key, groupValue: conv.disappearingSecs, title: Text(e.value), onChanged: (x) => Navigator.pop(c, x)),
        ],
      ),
    );
    if (v == null) return;
    core.db.setConvFlag(widget.convId, 'disappearing_secs', v);
    core.messages.addSystemMessage(widget.convId, v == 0 ? 'You turned off disappearing messages' : 'You set disappearing messages to ${opts[v]}');
  }

  String _subtitle() {
    final c = conv;
    if (c.isGroup) {
      final g = core.db.group(c.groupId!);
      if (g == null) return '';
      if (core.db.groupLeft(c.groupId!)) return "You're no longer a member";
      final names = g.members.keys.map(core.nameOf).toList()..sort();
      return names.join(', ');
    }
    if (core.typingPeers.contains(c.id)) return 'typing…';
    if (core.cm.isOnline(c.peerId!)) return 'nearby · online';
    return fmtLastSeen(core.db.contact(c.peerId!)?.lastSeen ?? 0);
  }

  // ------------------------------------------------------------------ build
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: core,
        builder: (context, _) {
          final c = core.db.conversation(widget.convId);
          if (c == null) return const Scaffold(body: Center(child: Text('Chat deleted')));
          final title = c.isGroup ? c.title : core.nameOf(c.peerId!);
          final avatar = c.isGroup ? core.db.group(c.groupId!)?.avatar : core.avatarOf(c.peerId!);
          final msgs = core.db.messages(widget.convId, limit: 500);
          final peer = c.isGroup ? null : core.db.contact(c.peerId!);
          final left = c.isGroup && core.db.groupLeft(c.groupId!);
          final dark = AppTheme.isDark(context);
          return Scaffold(
            appBar: AppBar(
              titleSpacing: 0,
              title: InkWell(
                onTap: _openInfo,
                child: Row(children: [
                  Avatar(name: title, bytes: avatar, radius: 18, group: c.isGroup),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Flexible(child: Text(title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
                        if (peer?.verified ?? false) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16)),
                      ]),
                      Text(_subtitle(), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12.5, color: Colors.white70)),
                    ]),
                  ),
                ]),
              ),
              actions: [
                if (!c.isGroup) ...[
                  IconButton(icon: const Icon(Icons.videocam), onPressed: () => _call(true)),
                  IconButton(icon: const Icon(Icons.call), onPressed: () => _call(false)),
                ],
                PopupMenuButton<String>(
                  onSelected: (v) async {
                    switch (v) {
                      case 'info': _openInfo(); break;
                      case 'disappear': _disappearing(); break;
                      case 'mute':
                        core.db.setConvFlag(c.id, 'muted', c.muted ? 0 : 1);
                        core.notify();
                        break;
                      case 'clear':
                        if (await confirm(context, 'Clear chat?', 'All messages in this chat will be erased from this phone.', ok: 'Clear', danger: true)) {
                          core.db.clearMessages(c.id);
                          core.notify();
                        }
                        break;
                    }
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'info', child: Text(c.isGroup ? 'Group info' : 'Contact info')),
                    const PopupMenuItem(value: 'disappear', child: Text('Disappearing messages')),
                    PopupMenuItem(value: 'mute', child: Text(c.muted ? 'Unmute notifications' : 'Mute notifications')),
                    const PopupMenuItem(value: 'clear', child: Text('Clear chat')),
                  ],
                ),
              ],
            ),
            body: Container(
              color: dark ? AppTheme.chatBgDark : AppTheme.chatBg,
              child: Column(children: [
                if (peer != null && peer.added == 0) _strangerBanner(peer),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    reverse: true,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: msgs.length + 1,
                    itemBuilder: (_, i) {
                      if (i == msgs.length) return _e2eeNotice();
                      final idx = msgs.length - 1 - i;
                      final m = msgs[idx];
                      final showDay = idx == 0 || fmtDay(msgs[idx - 1].ts) != fmtDay(m.ts);
                      return Column(children: [
                        if (showDay) _dayChip(m.ts),
                        MessageBubble(
                          key: ValueKey(m.id), m: m, isGroup: c.isGroup, selected: _highlight == m.id,
                          onLongPress: () => _actions(m),
                          onReplyTap: (id) {
                            setState(() => _highlight = id);
                            Future.delayed(const Duration(seconds: 2), () { if (mounted) setState(() => _highlight = null); });
                          },
                        ),
                      ]);
                    },
                  ),
                ),
                if (left)
                  Container(
                    padding: const EdgeInsets.all(16),
                    color: Theme.of(context).cardColor,
                    width: double.infinity,
                    child: const Text("You can't send messages to this group because you're no longer a member.", textAlign: TextAlign.center),
                  )
                else
                  _inputBar(),
              ]),
            ),
          );
        },
      );

  Widget _strangerBanner(Contact peer) => Container(
        color: Theme.of(context).cardColor,
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          Text('${peer.name} is not in your contacts. They found you on the local network.', textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13)),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            TextButton.icon(
              icon: const Icon(Icons.block, color: Colors.red),
              label: const Text('Block', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                core.db.setBlocked(peer.userId, true);
                await core.cm.disconnect(peer.userId);
                core.notify();
                if (mounted) Navigator.pop(context);
              },
            ),
            TextButton.icon(
              icon: const Icon(Icons.person_add),
              label: const Text('Add contact'),
              onPressed: () {
                core.db.setAdded(peer.userId, DateTime.now().millisecondsSinceEpoch);
                core.messages.onPeerOnline(peer.userId);
                core.notify();
              },
            ),
          ]),
        ]),
      );

  Widget _e2eeNotice() => Center(
        child: Container(
          margin: const EdgeInsets.fromLTRB(40, 8, 40, 12),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
              color: AppTheme.isDark(context) ? const Color(0xFF182229) : const Color(0xFFFFF3C4), borderRadius: BorderRadius.circular(8)),
          child: const Text(
            '🔒 Messages and calls are end-to-end encrypted and travel directly between devices. '
            'No server, no internet, no one else can read them. Tap the name to verify the safety number.',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 12),
          ),
        ),
      );

  Widget _dayChip(int ts) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(8)),
        child: Text(fmtDay(ts), style: const TextStyle(fontSize: 12)),
      );

  Widget _inputBar() {
    final hasText = _text.text.trim().isNotEmpty;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(color: Theme.of(context).cardColor, borderRadius: BorderRadius.circular(24)),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (_replyTo != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(6, 6, 6, 0),
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(.05), borderRadius: BorderRadius.circular(10),
                      border: const Border(left: BorderSide(color: AppTheme.teal, width: 3)),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(core.nameOf(_replyTo!.senderId), style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600)),
                          Text(_replyTo!.preview(), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                      ),
                      IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _replyTo = null)),
                    ]),
                  ),
                _recording
                    ? SizedBox(
                        height: 48,
                        child: Row(children: [
                          const SizedBox(width: 14),
                          const Icon(Icons.fiber_manual_record, color: Colors.red, size: 16),
                          const SizedBox(width: 8),
                          Text(fmtDuration(DateTime.now().difference(_recStart!).inSeconds)),
                          const Spacer(),
                          TextButton(onPressed: () => _stopRecording(send: false), child: const Text('Cancel', style: TextStyle(color: Colors.red))),
                        ]),
                      )
                    : Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _text,
                            minLines: 1, maxLines: 6,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: const InputDecoration(hintText: 'Message', border: InputBorder.none),
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.attach_file), onPressed: _attachSheet),
                        if (!hasText) IconButton(icon: const Icon(Icons.camera_alt), onPressed: () => _pickImage(ImageSource.camera)),
                      ]),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          FloatingActionButton.small(
            heroTag: null,
            elevation: 1,
            onPressed: hasText
                ? _sendText
                : _recording
                    ? () => _stopRecording(send: true)
                    : _startRecording,
            child: Icon(hasText || _recording ? Icons.send : Icons.mic),
          ),
        ]),
      ),
    );
  }
}
