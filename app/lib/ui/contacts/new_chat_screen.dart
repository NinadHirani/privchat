import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../chats/chat_screen.dart';
import '../groups/new_group_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'qr_screen.dart';

/// Contacts + people currently nearby on the local network.
class NewChatScreen extends StatelessWidget {
  const NewChatScreen({super.key, this.forCall = false});
  final bool forCall;

  void _open(BuildContext context, String uid, String name, {bool video = false}) async {
    final core = AppCore.I;
    if (forCall) {
      Navigator.pop(context);
      final err = await core.calls.start(uid, video: video);
      if (err != null && context.mounted) toast(context, err);
      return;
    }
    final conv = core.db.directConversation(uid, name);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id)));
  }

  Future<void> _connectByIp(BuildContext context) async {
    final v = await promptText(context, 'Connect by address', hint: '192.168.43.12:40123', maxLength: 64);
    if (v == null || !v.contains(':')) return;
    final i = v.lastIndexOf(':');
    try {
      await AppCore.I.cm.connectTo(v.substring(0, i).trim(), int.parse(v.substring(i + 1).trim()));
      if (context.mounted) toast(context, 'Connected');
    } catch (e) {
      if (context.mounted) toast(context, 'Could not connect: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final contacts = core.db.contacts().where((c) => c.added > 0 && !c.blocked).toList();
        final nearby = (core.cm.discovery?.current ?? [])
            .where((p) => !(core.db.contact(p.userId)?.added != null && core.db.contact(p.userId)!.added > 0))
            .where((p) => !(core.db.contact(p.userId)?.blocked ?? false))
            .toList();
        return Scaffold(
          appBar: AppBar(
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(forCall ? 'Select contact to call' : 'Select contact'),
              Text('${contacts.length} contacts · ${core.cm.online.length} nearby', style: const TextStyle(fontSize: 12.5)),
            ]),
          ),
          body: ListView(children: [
            if (!forCall) ...[
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppTheme.green, child: Icon(Icons.group, color: Colors.white)),
                title: const Text('New group'),
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NewGroupScreen())),
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: AppTheme.green, child: Icon(Icons.qr_code, color: Colors.white)),
                title: const Text('Add contact by QR code'),
                subtitle: const Text('Most secure: verifies their identity in person'),
                onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const QrScreen())),
              ),
              ListTile(
                leading: const CircleAvatar(backgroundColor: Colors.grey, child: Icon(Icons.lan, color: Colors.white)),
                title: const Text('Connect by IP address'),
                subtitle: Text('Your address: port ${core.cm.port}'),
                onTap: () => _connectByIp(context),
              ),
            ],
            if (nearby.isNotEmpty) _header('Nearby now (not in contacts)'),
            for (final p in nearby) _nearbyTile(context, p),
            _header('Contacts'),
            if (contacts.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Text('No contacts yet. Meet up and scan each other\'s QR code, or add someone from "Nearby now".',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
              ),
            for (final c in contacts)
              ListTile(
                leading: Avatar(name: c.name, bytes: c.avatar, online: core.cm.isOnline(c.userId)),
                title: Row(children: [
                  Flexible(child: Text(c.name)),
                  if (c.verified) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.verified, size: 16, color: AppTheme.teal)),
                ]),
                subtitle: Text(core.cm.isOnline(c.userId) ? 'Nearby' : c.about, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: forCall
                    ? Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: const Icon(Icons.call, color: AppTheme.teal), onPressed: () => _open(context, c.userId, c.name)),
                        IconButton(icon: const Icon(Icons.videocam, color: AppTheme.teal),
                            onPressed: () => _open(context, c.userId, c.name, video: true)),
                      ])
                    : null,
                onTap: forCall ? null : () => _open(context, c.userId, c.name),
              ),
          ]),
        );
      },
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(t, style: const TextStyle(color: AppTheme.teal, fontWeight: FontWeight.w600)),
      );

  Widget _nearbyTile(BuildContext context, DiscoveredPeer p) {
    final core = AppCore.I;
    final connected = core.cm.isOnline(p.userId);
    return ListTile(
      leading: Avatar(name: p.name, online: connected),
      title: Text(p.name),
      subtitle: Text('${connected ? 'Connected' : 'Connecting…'} · via ${p.via}  ·  ID ${p.userId.substring(0, 8)}'),
      trailing: TextButton(
        onPressed: !connected
            ? null
            : () {
                core.db.setAdded(p.userId, DateTime.now().millisecondsSinceEpoch);
                core.messages.onPeerOnline(p.userId);
                core.notify();
                toast(context, '${p.name} added. Verify their safety number in person for full security.');
              },
        child: const Text('Add'),
      ),
      onTap: connected ? () => _open(context, p.userId, p.name) : null,
    );
  }
}
