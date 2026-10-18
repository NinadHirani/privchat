import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../calls/calls_tab.dart';
import '../chats/chat_screen.dart';
import '../contacts/new_chat_screen.dart';
import '../contacts/qr_screen.dart';
import '../groups/new_group_screen.dart';
import '../settings/appearance_screen.dart';
import '../settings/settings_screen.dart';
import '../status/status_tab.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'app_drawer.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final core = AppCore.I;
  bool _searching = false;
  String _q = '';
  int _categoryIndex = 0; // 0: All, 1: Personal, 2: Groups, 3: Unread

  static const _categories = ['All', 'Personal', 'Groups', 'Unread'];

  @override
  Widget build(BuildContext context) {
    final isDark = AppTheme.isDark(context);

    return ListenableBuilder(
      listenable: core,
      builder: (context, _) => Scaffold(
        drawer: const AppDrawer(),
        appBar: AppBar(
          leading: Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu),
              tooltip: 'Navigation Menu',
              onPressed: () => Scaffold.of(ctx).openDrawer(),
            ),
          ),
          title: _searching
              ? TextField(
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  cursorColor: AppTheme.amberAccent,
                  decoration: const InputDecoration(
                    hintText: 'Search chats, contacts…',
                    hintStyle: TextStyle(color: Colors.white70),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) => setState(() => _q = v.toLowerCase()),
                )
              : const Text(
                  'Pritoy',
                  style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
                ),
          actions: [
            IconButton(
              icon: const Icon(Icons.qr_code_scanner),
              tooltip: 'Add contact by QR',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const QrScreen()),
              ),
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
                  case 'status':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Status updates')),
                          body: const StatusTab(),
                          floatingActionButton: StatusTab.fab(context),
                        ),
                      ),
                    );
                    break;
                  case 'calls':
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => Scaffold(
                          appBar: AppBar(title: const Text('Calls')),
                          body: const CallsTab(),
                          floatingActionButton: FloatingActionButton(
                            onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const NewChatScreen(forCall: true)),
                            ),
                            child: const Icon(Icons.add_call),
                          ),
                        ),
                      ),
                    );
                    break;
                  case 'theme':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AppearanceScreen()),
                    );
                    break;
                  case 'archived':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const _ArchivedScreen()),
                    );
                    break;
                  case 'settings':
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                    break;
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'status', child: Text('Status updates')),
                PopupMenuItem(value: 'calls', child: Text('Calls')),
                PopupMenuItem(value: 'theme', child: Text('Chat appearance')),
                PopupMenuItem(value: 'archived', child: Text('Archived')),
                PopupMenuItem(value: 'settings', child: Text('Settings')),
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            NearbyBanner(count: core.cm.online.length),

            // Telegram-style Category Filter Chips
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: isDark ? const Color(0xFF161F24) : Colors.white,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, i) {
                  final isSel = _categoryIndex == i;
                  return ChoiceChip(
                    label: Text(
                      _categories[i],
                      style: TextStyle(
                        fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                        color: isSel ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                        fontSize: 13,
                      ),
                    ),
                    selected: isSel,
                    selectedColor: AppTheme.amberAccent,
                    backgroundColor: isDark ? const Color(0xFF222E35) : const Color(0xFFE9ECEF),
                    showCheckmark: false,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    onSelected: (v) => setState(() => _categoryIndex = i),
                  );
                },
              ),
            ),

            Expanded(
              child: ConversationList(
                query: _q,
                categoryIndex: _categoryIndex,
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          heroTag: 'new_chat_fab',
          backgroundColor: AppTheme.amberAccent,
          foregroundColor: Colors.black,
          tooltip: 'New Message',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          ),
          child: const Icon(Icons.edit, size: 24),
        ),
      ),
    );
  }
}

class ConversationList extends StatelessWidget {
  const ConversationList({
    super.key,
    this.query = '',
    this.archived = false,
    this.categoryIndex = 0,
  });

  final String query;
  final bool archived;
  final int categoryIndex;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    var convs = core.db.conversations(archived: archived);

    // Apply category filters
    switch (categoryIndex) {
      case 1: // Personal
        convs = convs.where((c) => !c.isGroup).toList();
        break;
      case 2: // Groups
        convs = convs.where((c) => c.isGroup).toList();
        break;
      case 3: // Unread
        convs = convs.where((c) => c.unread > 0).toList();
        break;
      default: // All
        break;
    }

    if (query.isNotEmpty) {
      convs = convs.where((c) => c.title.toLowerCase().contains(query)).toList();
    }

    if (convs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.forum_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 12),
              Text(
                archived
                    ? 'No archived chats'
                    : 'No chats in this folder yet.\nTap the pencil icon to message your Google Contacts or someone nearby.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
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
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          if (conv.pinned) const Icon(Icons.push_pin, size: 14, color: Colors.grey),
          if (conv.muted) const Icon(Icons.volume_off, size: 14, color: Colors.grey),
        ],
      ),
      subtitle: Text(
        typing ? 'typing…' : conv.lastPreview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: typing ? AppTheme.amberAccent : null),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            fmtListTime(conv.lastMsgTs),
            style: TextStyle(
              fontSize: 12,
              color: conv.unread > 0 ? AppTheme.amberAccent : Colors.grey,
            ),
          ),
          const SizedBox(height: 4),
          if (conv.unread > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.amberAccent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${conv.unread}',
                style: const TextStyle(color: Colors.black, fontSize: 12, fontWeight: FontWeight.bold),
              ),
            ),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id)),
      ),
      onLongPress: () => _menu(context),
    );
  }

  void _menu(BuildContext context) {
    final db = AppCore.I.db;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(conv.pinned ? 'Unpin' : 'Pin'),
              onTap: () {
                db.setConvFlag(conv.id, 'pinned', conv.pinned ? 0 : 1);
                AppCore.I.notify();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.volume_off_outlined),
              title: Text(conv.muted ? 'Unmute' : 'Mute notifications'),
              onTap: () {
                db.setConvFlag(conv.id, 'muted', conv.muted ? 0 : 1);
                AppCore.I.notify();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.archive_outlined),
              title: Text(conv.archived ? 'Unarchive' : 'Archive'),
              onTap: () {
                db.setConvFlag(conv.id, 'archived', conv.archived ? 0 : 1);
                AppCore.I.notify();
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.mark_chat_read_outlined),
              title: const Text('Mark as read'),
              onTap: () {
                AppCore.I.messages.markRead(conv.id);
                Navigator.pop(c);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete chat', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(c);
                if (await confirm(
                  context,
                  'Delete chat?',
                  'Messages are erased from this phone only.',
                  ok: 'Delete',
                  danger: true,
                )) {
                  db.deleteConversation(conv.id);
                  AppCore.I.notify();
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedScreen extends StatelessWidget {
  const _ArchivedScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Archived')),
        body: ListenableBuilder(
          listenable: AppCore.I,
          builder: (_, __) => const ConversationList(archived: true),
        ),
      );
}
