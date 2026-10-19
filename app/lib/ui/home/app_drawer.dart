import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/constants/app_version.dart';
import '../../core/services/app_core.dart';
import '../calls/calls_tab.dart';
import '../chats/chat_screen.dart';
import '../contacts/new_chat_screen.dart';
import '../groups/new_group_screen.dart';
import '../settings/appearance_screen.dart';
import '../settings/settings_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key});

  void _openSavedMessages(BuildContext context) {
    Navigator.pop(context);
    final core = AppCore.I;
    final conv = core.db.directConversation(core.identity.userId, 'Saved Messages');
    Navigator.push(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id)));
  }

  void _inviteFriends(BuildContext context) {
    Navigator.pop(context);
    Share.share(
      'Hey! Chat with me privately and securely on Pritoy. Download it here: https://github.com/NinadHirani/privchat/releases/latest',
      subject: 'Join me on Pritoy',
    );
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final isDark = AppTheme.isDark(context);
    final userPhone = core.db.kvGet('user_phone');
    final userEmail = core.db.kvGet('user_email');
    final userHandle = (userPhone != null && userPhone.isNotEmpty)
        ? userPhone
        : ((userEmail != null && userEmail.isNotEmpty) ? userEmail : 'Offline Identity');

    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(20, MediaQuery.of(context).padding.top + 20, 20, 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? const [Color(0xFF1E282D), Color(0xFF131A1E)]
                    : const [Color(0xFF263238), Color(0xFF1C2429)],
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Avatar(name: core.displayName, bytes: core.avatar, radius: 32),
                    IconButton(
                      icon: const Icon(Icons.qr_code, color: Colors.white70),
                      tooltip: 'My QR Code',
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen()));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  core.displayName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      userHandle,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.amberAccent.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.shield, size: 11, color: AppTheme.amberAccent),
                          SizedBox(width: 3),
                          Text(
                            'E2EE',
                            style: TextStyle(
                              color: AppTheme.amberAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Menu Items
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                ListTile(
                  leading: const Icon(Icons.contacts_outlined),
                  title: const Text('Contacts'),
                  subtitle: const Text('Google Contacts & nearby peers'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewChatScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.bookmark_border),
                  title: const Text('Saved Messages'),
                  subtitle: const Text('Personal cloud notes & files'),
                  onTap: () => _openSavedMessages(context),
                ),
                ListTile(
                  leading: const Icon(Icons.group_add_outlined),
                  title: const Text('New Group'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const NewGroupScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.call_outlined),
                  title: const Text('Calls'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const Scaffold(
                      appBar: PreferredSize(preferredSize: Size.fromHeight(56), child: _CallsAppBar()),
                      body: CallsTab(),
                    )));
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.palette_outlined),
                  title: const Text('Chat Appearance'),
                  subtitle: const Text('Cadet grey, mustard bubbles & wallpapers'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const AppearanceScreen()));
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  subtitle: const Text('Privacy, app lock, encrypted vault'),
                  onTap: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                  },
                ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.person_add_outlined),
                  title: const Text('Invite Friends'),
                  subtitle: const Text('Share Pritoy download link'),
                  onTap: () => _inviteFriends(context),
                ),
              ],
            ),
          ),

          // Version info & quick update check
          InkWell(
            onTap: () async {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Checking for updates…'),
                  duration: Duration(seconds: 1),
                ),
              );
              final res = await core.updates.check(silent: false);
              if (!context.mounted) return;
              if (res.hasUpdate && res.release != null && res.targetAsset != null) {
                core.updates.showUpdateDialog(context: context, result: res);
              } else if (res.error != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Update check failed: ${res.error}. Check your internet connection.'),
                    backgroundColor: Colors.red.shade800,
                  ),
                );
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pritoy is up to date (v${AppVersion.current})'),
                    backgroundColor: AppTheme.mustardBrown,
                  ),
                );
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Pritoy for Android & iOS', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('v${AppVersion.current}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                      const SizedBox(width: 4),
                      Icon(Icons.refresh_rounded, size: 13, color: Colors.grey.shade600),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallsAppBar extends StatelessWidget {
  const _CallsAppBar();
  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Calls'),
    );
  }
}
