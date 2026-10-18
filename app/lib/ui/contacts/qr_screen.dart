import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/crypto/crypto.dart';
import '../../core/crypto/identity.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../chats/chat_screen.dart';
import '../widgets/common.dart';

/// QR payload = identity key + name + (optional) LAN addresses for direct connect.
/// Scanning in person == cryptographic verification: you KNOW this key belongs to the person in front of you.
class QrScreen extends StatefulWidget {
  const QrScreen({super.key, this.verifyUserId});
  /// When set, we're verifying an existing contact: the scanned key must match.
  final String? verifyUserId;
  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 2, vsync: this, initialIndex: widget.verifyUserId != null ? 1 : 0);
  final core = AppCore.I;
  String? _payload;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _build();
  }

  Future<void> _build() async {
    final hosts = <String>[];
    try {
      for (final i in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in i.addresses) {
          if (!a.isLoopback) hosts.add(a.address);
        }
      }
    } catch (_) {}
    setState(() => _payload = jsonEncode({
          'pc': 1, 'u': core.identity.userId, 'k': Crypto.b64e(core.identity.edPk), 'n': core.displayName,
          'h': hosts.take(3).toList(), 'p': core.cm.port,
        }));
  }

  Future<void> _onScan(String raw) async {
    if (_handled) return;
    Map<String, dynamic> d;
    try {
      d = jsonDecode(raw) as Map<String, dynamic>;
      if (d['pc'] != 1) throw const FormatException();
    } catch (_) {
      return; // not ours; keep scanning
    }
    _handled = true;
    final uid = d['u'] as String, pk = Crypto.b64d(d['k'] as String);
    final name = (d['n'] as String? ?? 'Contact').trim();
    if (pk.length != 32 || userIdFromEdPk(pk) != uid) {
      return _fail('Invalid code — the key does not match the ID.');
    }
    if (uid == core.identity.userId) return _fail("That's your own code 🙂");
    if (widget.verifyUserId != null) {
      if (uid != widget.verifyUserId) {
        return _fail('⚠️ This code belongs to a DIFFERENT identity. You may not be talking to who you think.');
      }
      core.db.setVerified(uid, true);
      core.notify();
      if (mounted) {
        toast(context, '✅ Verified! Your chat with $name is secure.');
        Navigator.pop(context);
      }
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = core.db.contact(uid);
    core.db.upsertContact(Contact(userId: uid, edPk: pk, name: existing?.added == 0 || existing == null ? name : existing.name,
        added: now, verified: true));
    core.db.setVerified(uid, true);
    final conv = core.db.directConversation(uid, name);
    // Try a direct connection using the addresses embedded in the QR (helps when multicast is blocked).
    final port = (d['p'] as num?)?.toInt();
    if (port != null && !core.cm.isOnline(uid)) {
      for (final h in (d['h'] as List? ?? []).cast<String>()) {
        try {
          await core.cm.connectTo(h, port);
          break;
        } catch (_) {}
      }
    }
    core.messages.onPeerOnline(uid);
    core.notify();
    if (!mounted) return;
    toast(context, '$name added and verified ✅');
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ChatScreen(convId: conv.id)));
  }

  void _fail(String msg) {
    showDialog(context: context, builder: (c) => AlertDialog(content: Text(msg), actions: [
      TextButton(onPressed: () => Navigator.pop(c), child: const Text('OK')),
    ])).then((_) => _handled = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.verifyUserId != null ? 'Verify contact' : 'Add contact'),
          bottom: TabBar(controller: _tabs, tabs: const [Tab(text: 'My code'), Tab(text: 'Scan code')]),
        ),
        body: TabBarView(controller: _tabs, physics: const NeverScrollableScrollPhysics(), children: [
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(children: [
                Avatar(name: core.displayName, bytes: core.avatar, radius: 36),
                const SizedBox(height: 8),
                Text(core.displayName, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
                const SizedBox(height: 16),
                if (_payload != null)
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.all(12),
                    child: QrImageView(data: _payload!, size: 260, backgroundColor: Colors.white),
                  ),
                const SizedBox(height: 16),
                const Text('Let your friend scan this in person.\nIt contains only your public key — nothing secret.',
                    textAlign: TextAlign.center),
                const SizedBox(height: 8),
                SelectableText('ID: ${core.identity.userId}', style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
              ]),
            ),
          ),
          MobileScanner(onDetect: (cap) {
            for (final b in cap.barcodes) {
              final v = b.rawValue;
              if (v != null) _onScan(v);
            }
          }),
        ]),
      );
}
