import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/app_core.dart';
import '../contacts/contact_info_screen.dart';
import '../media/media_utils.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'new_group_screen.dart';

class GroupInfoScreen extends StatelessWidget {
  const GroupInfoScreen({super.key, required this.gid});
  final String gid;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final g = core.db.group(gid);
        if (g == null) return const Scaffold(body: Center(child: Text('Group not found')));
        final me = core.identity.userId;
        final amAdmin = g.admins.contains(me);
        final left = core.db.groupLeft(gid);
        final members = g.members.keys.toList()
          ..sort((a, b) => a == me ? -1 : b == me ? 1 : core.nameOf(a).compareTo(core.nameOf(b)));
        return Scaffold(
          appBar: AppBar(title: const Text('Group info')),
          body: ListView(children: [
            const SizedBox(height: 20),
            Center(
              child: GestureDetector(
                onTap: () async {
                  final x = await ImagePicker().pickImage(source: ImageSource.gallery);
                  if (x == null) return;
                  core.db.setGroupAvatar(gid, await MediaUtils.makeAvatar(x.path)); // local only
                  core.notify();
                },
                child: Avatar(name: g.name, bytes: g.avatar, radius: 56, group: true),
              ),
            ),
            const SizedBox(height: 12),
            Center(child: Text(g.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
            Center(child: Text('Group · ${g.members.length} members', style: const TextStyle(color: Colors.grey))),
            const SizedBox(height: 8),
            if (amAdmin && !left)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Rename group'),
                onTap: () async {
                  final n = await promptText(context, 'Group name', initial: g.name, maxLength: 50);
                  if (n != null && n.isNotEmpty) await core.groups.rename(gid, n);
                },
              ),
            const Divider(),
            Padding(padding: const EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('${g.members.length} members', style: const TextStyle(color: Colors.grey))),
            if (amAdmin && !left)
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppTheme.green, child: Icon(Icons.person_add, color: Colors.white)),
                title: const Text('Add members'),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => NewGroupScreen(addToGid: gid))),
              ),
            for (final uid in members)
              ListTile(
                leading: Avatar(name: core.nameOf(uid), bytes: core.avatarOf(uid), online: uid != me && core.cm.isOnline(uid)),
                title: Text(uid == me ? 'You' : core.nameOf(uid)),
                subtitle: Text(core.db.contact(uid)?.about ?? ''),
                trailing: g.admins.contains(uid)
                    ? Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: AppTheme.green.withOpacity(.15), borderRadius: BorderRadius.circular(4)),
                        child: const Text('Group admin', style: TextStyle(fontSize: 11, color: AppTheme.teal)),
                      )
                    : null,
                onTap: uid == me ? null : () => _memberMenu(context, uid, amAdmin && !left, g.admins.contains(uid)),
              ),
            const Divider(),
            if (!left)
              ListTile(
                leading: const Icon(Icons.exit_to_app, color: Colors.red),
                title: const Text('Exit group', style: TextStyle(color: Colors.red)),
                onTap: () async {
                  if (await confirm(context, 'Exit "${g.name}"?', 'You will stop receiving messages from this group.', ok: 'Exit', danger: true)) {
                    await core.groups.leave(gid);
                  }
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Delete group from this phone', style: TextStyle(color: Colors.red)),
              onTap: () async {
                if (!await confirm(context, 'Delete group?', 'Erases the group and its messages from this phone.', ok: 'Delete', danger: true)) return;
                if (!left) await core.groups.leave(gid);
                core.db.deleteConversation('g:$gid');
                core.db.deleteGroup(gid);
                core.notify();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  void _memberMenu(BuildContext context, String uid, bool canManage, bool isAdmin) {
    final core = AppCore.I;
    showModalBottomSheet(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            leading: const Icon(Icons.message),
            title: Text('Message ${core.nameOf(uid)}'),
            onTap: () {
              Navigator.pop(c);
              core.db.directConversation(uid, core.nameOf(uid));
              Navigator.push(context, MaterialPageRoute(builder: (_) => ContactInfoScreen(userId: uid)));
            },
          ),
          if (canManage)
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: Text(isAdmin ? 'Dismiss as admin' : 'Make group admin'),
              onTap: () {
                Navigator.pop(c);
                core.groups.setAdmin(gid, uid, !isAdmin);
              },
            ),
          if (canManage)
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: Text('Remove ${core.nameOf(uid)}', style: const TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(c);
                core.groups.removeMember(gid, uid);
              },
            ),
        ]),
      ),
    );
  }
}
