import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../calls/calls_tab.dart';
import '../chats/chat_screen.dart';
import '../contacts/new_chat_screen.dart';
import '../contacts/qr_screen.dart';
import '../groups/new_group_screen.dart';
import '../settings/settings_screen.dart';
import '../status/status_tab.dart';
import '../theme.dart';
import '../widgets/common.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(() => setState(() {}));
  final core = AppCore.I;
  bool _searching = false;
  String _q = '';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: core,
        builder: (context, _) => Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: Colors.white,
                    decoration: const InputDecoration(hintText: 'Search…', hintStyle: TextStyle(color: Colors.white70), border: InputBorder.none),
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  )
                : const Text('PrivChat', style: TextStyle(fontWeight: FontWeight.w600)),
            actions: [
              IconButton(
                icon: const Icon(Icons.qr_code_scanner),
                tooltip: 'Add contact by QR',
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const QrScreen())),
              ),
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _q = '';
                }),
              ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  switch (v) {
                    case 'group':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGroupScreen()));
                      break;
                    case 'archived':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const _ArchivedScreen()));
                      break;
                    case 'settings':
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                      break;
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'group', child: Text('New group')),
                  PopupMenuItem(value: 'archived', child: Text('Archived')),
                  PopupMenuItem(value: 'settings', child: Text('Settings')),
                ],
              ),
            ],
            bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'Chats'), Tab(text: 'Status'), Tab(text: 'Calls')]),
          ),
          body: Column(children: [
            NearbyBanner(count: core.cm.online.length),
            Expanded(
              child: TabBarView(controller: _tabs, children: [
                ConversationList(query: _q),
                const StatusTab(),
                const CallsTab(),
              ]),
            ),
          ]),
          floatingActionButton: _fab(),
        ),
      );

  Widget? _fab() {
    switch (_tabs.index) {
      case 0:
        return FloatingActionButton(
          heroTag: 'chat',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen())),
          child: const Icon(Icons.chat),
        );
      case 1:
        return StatusTab.fab(context);
      default:
        return FloatingActionButton(
          heroTag: 'call',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen(forCall: true))),
          child: const Icon(Icons.add_call),
        );
    }
  }
}

class ConversationList extends StatelessWidget {
  const ConversationList({super.key, this.query = '', this.archived = false});
  final String query;
  final bool archived;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    var convs = core.db.conversations(archived: archived);
    if (query.isNotEmpty) convs = convs.where((c) => c.title.toLowerCase().contains(query)).toList();
    if (convs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            Text(archived ? 'No archived chats' : 'No chats yet.\nTap the chat button to message someone nearby,\nor scan their QR code.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade600)),
          ]),
        ),
      );
    }
    return ListView.builder(
      itemCount: convs.length,
      itemBuilder: (context, i) => _ConvTile(conv: convs[i]),
    );
  }
}

class _ConvTile extends StatelessWidget {
  const _ConvTile({required this.conv});
  final Conversation conv;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final online = !conv.isGroup && core.cm.isOnline(conv.peerId!);
    final typing = core.typingPeers.contains(conv.id);
    final avatar = conv.isGroup ? core.db.group(conv.groupId!)?.avatar : core.avatarOf(conv.peerId!);
    final title = conv.isGroup ? conv.title : core.nameOf(conv.peerId!);
    return ListTile(
      leading: Avatar(name: title, bytes: avatar, group: conv.isGroup, online: online),
      title: Row(children: [
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
        if (conv.pinned) const Icon(Icons.push_pin, size: 14, color: Colors.grey),
        if (conv.muted) const Icon(Icons.volume_off, size: 14, color: Colors.grey),
      ]),
      subtitle: Text(typing ? 'typing…' : conv.lastPreview, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(color: typing ? AppTheme.green : null)),
      trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(fmtListTime(conv.lastMsgTs),
            style: TextStyle(fontSize: 12, color: conv.unread > 0 ? AppTheme.green : Colors.grey)),
        const SizedBox(height: 4),
        if (conv.unread > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(color: AppTheme.green, borderRadius: BorderRadius.circular(12)),
            child: Text('${conv.unread}', style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
      ]),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id))),
      onLongPress: () => _menu(context),
    );
  }

  void _menu(BuildContext context) {
    final db = AppCore.I.db;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.push_pin_outlined),
            title: Text(conv.pinned ? 'Unpin' : 'Pin'),
            onTap: () { db.setConvFlag(conv.id, 'pinned', conv.pinned ? 0 : 1); AppCore.I.notify(); Navigator.pop(c); },
          ),
          ListTile(
            leading: const Icon(Icons.volume_off_outlined),
            title: Text(conv.muted ? 'Unmute' : 'Mute notifications'),
            onTap: () { db.setConvFlag(conv.id, 'muted', conv.muted ? 0 : 1); AppCore.I.notify(); Navigator.pop(c); },
          ),
          ListTile(
            leading: const Icon(Icons.archive_outlined),
            title: Text(conv.archived ? 'Unarchive' : 'Archive'),
            onTap: () { db.setConvFlag(conv.id, 'archived', conv.archived ? 0 : 1); AppCore.I.notify(); Navigator.pop(c); },
          ),
          ListTile(
            leading: const Icon(Icons.mark_chat_read_outlined),
            title: const Text('Mark as read'),
            onTap: () { AppCore.I.messages.markRead(conv.id); Navigator.pop(c); },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete chat', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(c);
              if (await confirm(context, 'Delete chat?', 'Messages are erased from this phone only.', ok: 'Delete', danger: true)) {
                db.deleteConversation(conv.id);
                AppCore.I.notify();
              }
            },
          ),
        ]),
      ),
    );
  }
}

class _ArchivedScreen extends StatelessWidget {
  const _ArchivedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Archived')),
        body: ListenableBuilder(listenable: AppCore.I, builder: (_, __) => const ConversationList(archived: true)),
      );
}
