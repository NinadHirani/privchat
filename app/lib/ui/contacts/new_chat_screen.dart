import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../../core/services/device_contacts_service.dart';
import '../../models/models.dart';
import '../chats/chat_screen.dart';
import '../groups/new_group_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'qr_screen.dart';

/// WhatsApp-style & Telegram-inspired Contacts selector:
/// Dual-section list with Google Contacts, 1-tap SMS/Share invites, and LAN nearby peers.
class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key, this.forCall = false});
  final bool forCall;

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final core = AppCore.I;
  final contactsSvc = DeviceContactsService.I;

  bool _searching = false;
  String _q = '';
  bool _loading = false;
  bool _hasPermission = false;
  List<DeviceContactItem> _deviceContacts = [];

  @override
  void initState() {
    super.initState();
    _checkAndLoadContacts();
  }

  Future<void> _checkAndLoadContacts() async {
    final hasPerm = await contactsSvc.hasPermission();
    if (mounted) setState(() => _hasPermission = hasPerm);
    if (hasPerm) {
      setState(() => _loading = true);
      final list = await contactsSvc.loadGoogleContacts(core.db);
      if (mounted) {
        setState(() {
          _deviceContacts = list;
          _loading = false;
        });
      }
    }
  }

  Future<void> _requestContacts() async {
    setState(() => _loading = true);
    final granted = await contactsSvc.hasPermission();
    if (!granted) {
      final list = await contactsSvc.loadGoogleContacts(core.db);
      if (mounted) {
        setState(() {
          _hasPermission = list.isNotEmpty;
          _deviceContacts = list;
          _loading = false;
        });
      }
    } else {
      await _checkAndLoadContacts();
    }
  }

  void _open(String uid, String name, {bool video = false}) async {
    if (widget.forCall) {
      Navigator.pop(context);
      final err = await core.calls.start(uid, video: video);
      if (err != null && mounted) toast(context, err);
      return;
    }
    final conv = core.db.directConversation(uid, name);
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id)));
  }

  Future<void> _connectByIp() async {
    final v = await promptText(context, 'Connect by address', hint: '192.168.43.12:40123', maxLength: 64);
    if (v == null || !v.contains(':')) return;
    final i = v.lastIndexOf(':');
    try {
      await core.cm.connectTo(v.substring(0, i).trim(), int.parse(v.substring(i + 1).trim()));
      if (mounted) toast(context, 'Connected');
    } catch (e) {
      if (mounted) toast(context, 'Could not connect: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final savedContacts = core.db.contacts().where((c) => c.added > 0 && !c.blocked).toList();
        final nearby = (core.cm.discovery?.current ?? [])
            .where((p) => !(core.db.contact(p.userId)?.added != null && core.db.contact(p.userId)!.added > 0))
            .where((p) => !(core.db.contact(p.userId)?.blocked ?? false))
            .toList();

        // Filter by search query
        var filteredPrivChat = savedContacts;
        var filteredNearby = nearby;
        var filteredGoogle = _deviceContacts;

        if (_q.isNotEmpty) {
          filteredPrivChat = filteredPrivChat.where((c) => c.name.toLowerCase().contains(_q)).toList();
          filteredNearby = filteredNearby.where((p) => p.name.toLowerCase().contains(_q)).toList();
          filteredGoogle = filteredGoogle
              .where((c) => c.displayName.toLowerCase().contains(_q) || c.phone.contains(_q))
              .toList();
        }

        final privchatGoogleContacts = filteredGoogle.where((c) => c.isOnPrivChat).toList();
        final inviteGoogleContacts = filteredGoogle.where((c) => !c.isOnPrivChat).toList();

        final totalContactsCount = savedContacts.length + _deviceContacts.length;

        return Scaffold(
          appBar: AppBar(
            title: _searching
                ? TextField(
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    cursorColor: AppTheme.amberAccent,
                    decoration: const InputDecoration(
                      hintText: 'Search contacts…',
                      hintStyle: TextStyle(color: Colors.white70),
                      border: InputBorder.none,
                    ),
                    onChanged: (v) => setState(() => _q = v.toLowerCase()),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.forCall ? 'Select contact to call' : 'Select contact'),
                      Text(
                        '$totalContactsCount contacts · ${core.cm.online.length} nearby',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
            actions: [
              IconButton(
                icon: Icon(_searching ? Icons.close : Icons.search),
                onPressed: () => setState(() {
                  _searching = !_searching;
                  _q = '';
                }),
              ),
              if (!_hasPermission)
                IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync Google Contacts',
                  onPressed: _requestContacts,
                ),
            ],
          ),
          body: ListView(
            children: [
              if (!_hasPermission && !_searching)
                _googleContactsPermissionBanner(),

              if (!widget.forCall && _q.isEmpty) ...[
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.amberAccent,
                    child: Icon(Icons.group, color: Colors.black),
                  ),
                  title: const Text('New group'),
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const NewGroupScreen()),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.mustardBrown,
                    child: Icon(Icons.qr_code, color: Colors.white),
                  ),
                  title: const Text('Add contact by QR code'),
                  subtitle: const Text('Direct in-person identity verification'),
                  onTap: () => Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (_) => const QrScreen()),
                  ),
                ),
                ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppTheme.cadetGrey,
                    child: Icon(Icons.lan, color: Colors.white),
                  ),
                  title: const Text('Connect by IP address'),
                  subtitle: Text('Direct Wi-Fi connection (port ${core.cm.port})'),
                  onTap: _connectByIp,
                ),
                const Divider(),
              ],

              // Nearby Peers (Wi-Fi / Hotspot)
              if (filteredNearby.isNotEmpty) ...[
                _header('Nearby now (LAN / Hotspot)'),
                for (final p in filteredNearby) _nearbyTile(p),
              ],

              // SECTION 1: Contacts on PrivChat
              _header('Contacts on PrivChat (${filteredPrivChat.length + privchatGoogleContacts.length})'),
              if (filteredPrivChat.isEmpty && privchatGoogleContacts.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'No PrivChat contacts yet. Invite friends from your Google Contacts below or scan their QR code.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),

              for (final c in filteredPrivChat) _privChatTile(c),
              for (final gc in privchatGoogleContacts) _googlePrivChatTile(gc),

              // SECTION 2: Invite to PrivChat (Google Contacts)
              if (_hasPermission && inviteGoogleContacts.isNotEmpty) ...[
                const Divider(height: 32),
                _header('Invite to PrivChat (Google Contacts · ${inviteGoogleContacts.length})'),
                for (final gc in inviteGoogleContacts) _inviteTile(gc),
              ],

              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  Widget _googleContactsPermissionBanner() {
    return Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.amberAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.amberAccent.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.contacts, color: AppTheme.mustardBrown, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Sync Google Contacts',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                SizedBox(height: 2),
                Text(
                  'Find friends already using PrivChat and invite others via SMS.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.mustardBrown,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            onPressed: _requestContacts,
            child: const Text('Enable', style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(
          t,
          style: const TextStyle(
            color: AppTheme.mustardBrown,
            fontWeight: FontWeight.w600,
            fontSize: 13,
            letterSpacing: 0.3,
          ),
        ),
      );

  Widget _privChatTile(Contact c) {
    final online = core.cm.isOnline(c.userId);
    return ListTile(
      leading: Avatar(name: c.name, bytes: c.avatar, online: online),
      title: Row(
        children: [
          Flexible(child: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w500))),
          if (c.verified)
            const Padding(
              padding: EdgeInsets.only(left: 4),
              child: Icon(Icons.verified, size: 16, color: AppTheme.amberAccent),
            ),
        ],
      ),
      subtitle: Text(
        online ? 'Nearby · Connected' : (c.about.isNotEmpty ? c.about : 'PrivChat Contact'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: widget.forCall
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.call, color: AppTheme.mustardBrown),
                  onPressed: () => _open(c.userId, c.name),
                ),
                IconButton(
                  icon: const Icon(Icons.videocam, color: AppTheme.mustardBrown),
                  onPressed: () => _open(c.userId, c.name, video: true),
                ),
              ],
            )
          : null,
      onTap: widget.forCall ? null : () => _open(c.userId, c.name),
    );
  }

  Widget _googlePrivChatTile(DeviceContactItem gc) {
    return ListTile(
      leading: gc.photo != null
          ? CircleAvatar(backgroundImage: MemoryImage(gc.photo!))
          : CircleAvatar(
              backgroundColor: AppTheme.mustardBrown,
              child: Text(gc.initials, style: const TextStyle(color: Colors.white)),
            ),
      title: Row(
        children: [
          Flexible(child: Text(gc.displayName, style: const TextStyle(fontWeight: FontWeight.w500))),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppTheme.amberAccent.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('PrivChat', style: TextStyle(fontSize: 10, color: AppTheme.mustardBrown, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      subtitle: Text(gc.phone.isNotEmpty ? gc.phone : 'Google Contact'),
      onTap: () {
        if (gc.privchatUserId != null) {
          _open(gc.privchatUserId!, gc.displayName);
        }
      },
    );
  }

  Widget _inviteTile(DeviceContactItem gc) {
    return ListTile(
      leading: gc.photo != null
          ? CircleAvatar(backgroundImage: MemoryImage(gc.photo!))
          : CircleAvatar(
              backgroundColor: Colors.grey.shade400,
              child: Text(gc.initials, style: const TextStyle(color: Colors.white)),
            ),
      title: Text(gc.displayName),
      subtitle: Text(gc.phone.isNotEmpty ? gc.phone : 'Google Contact'),
      trailing: OutlinedButton(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.amberAccent, width: 1.5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        ),
        onPressed: () => contactsSvc.inviteContact(gc),
        child: const Text(
          'INVITE',
          style: TextStyle(
            color: AppTheme.mustardBrown,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _nearbyTile(DiscoveredPeer p) {
    final connected = core.cm.isOnline(p.userId);
    return ListTile(
      leading: Avatar(name: p.name, online: connected),
      title: Text(p.name),
      subtitle: Text('${connected ? 'Connected' : 'Connecting…'} · via ${p.via}'),
      trailing: TextButton(
        onPressed: !connected
            ? null
            : () {
                core.db.setAdded(p.userId, DateTime.now().millisecondsSinceEpoch);
                core.messages.onPeerOnline(p.userId);
                core.notify();
                toast(context, '${p.name} added to contacts.');
              },
        child: const Text('Add'),
      ),
      onTap: connected ? () => _open(p.userId, p.name) : null,
    );
  }
}
