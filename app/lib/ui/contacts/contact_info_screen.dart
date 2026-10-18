import 'package:flutter/material.dart';
import '../../core/crypto/identity.dart';
import '../../core/services/app_core.dart';
import '../media/media_viewer.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'qr_screen.dart';

class ContactInfoScreen extends StatelessWidget {
  const ContactInfoScreen({super.key, required this.userId});
  final String userId;

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    return ListenableBuilder(
      listenable: core,
      builder: (context, _) {
        final c = core.db.contact(userId);
        if (c == null) return const Scaffold(body: Center(child: Text('Unknown contact')));
        final sn = safetyNumber(core.identity.edPk, c.edPk);
        final media = core.db
            .messages('d:$userId', limit: 2000)
            .where((m) => m.attachmentId != null && (m.kind == 'image' || m.kind == 'video'))
            .toList()
            .reversed
            .take(12)
            .toList();
        return Scaffold(
          appBar: AppBar(title: const Text('Contact info')),
          body: ListView(children: [
            const SizedBox(height: 20),
            Center(child: Avatar(name: c.name, bytes: c.avatar, radius: 56)),
            const SizedBox(height: 12),
            Center(child: Text(c.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500))),
            Center(child: Text(core.cm.isOnline(userId) ? 'Nearby now' : fmtLastSeen(c.lastSeen), style: const TextStyle(color: Colors.grey))),
            const SizedBox(height: 12),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              _action(context, Icons.call, 'Audio', () async {
                final e = await core.calls.start(userId);
                if (e != null && context.mounted) toast(context, e);
              }),
              _action(context, Icons.videocam, 'Video', () async {
                final e = await core.calls.start(userId, video: true);
                if (e != null && context.mounted) toast(context, e);
              }),
            ]),
            const Divider(),
            ListTile(title: Text(c.about.isEmpty ? '—' : c.about), subtitle: const Text('About')),
            ListTile(
              title: const Text('Rename contact'),
              leading: const Icon(Icons.edit),
              onTap: () async {
                final n = await promptText(context, 'Contact name', initial: c.name);
                if (n == null || n.isEmpty) return;
                c.name = n;
                core.db.upsertContact(c);
                core.db.setConvFlag('d:$userId', 'title', n);
                core.notify();
              },
            ),
            if (media.isNotEmpty) ...[
              const Padding(padding: EdgeInsets.fromLTRB(16, 8, 16, 8), child: Text('Media', style: TextStyle(color: Colors.grey))),
              SizedBox(
                height: 84,
                child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: [
                  for (final m in media)
                    Builder(builder: (_) {
                      final a = core.db.attachment(m.attachmentId!);
                      if (a == null) return const SizedBox();
                      return GestureDetector(
                        onTap: a.done ? () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaViewer(att: a))) : null,
                        child: Container(
                          width: 76, margin: const EdgeInsets.all(4),
                          decoration: BoxDecoration(color: Colors.black12, borderRadius: BorderRadius.circular(6),
                              image: a.thumb != null ? DecorationImage(image: MemoryImage(a.thumb!), fit: BoxFit.cover) : null),
                          child: m.kind == 'video' ? const Icon(Icons.play_arrow, color: Colors.white) : null,
                        ),
                      );
                    }),
                ]),
              ),
            ],
            const Divider(),
            ListTile(
              leading: Icon(c.verified ? Icons.verified_user : Icons.gpp_maybe, color: c.verified ? AppTheme.teal : Colors.orange),
              title: Text(c.verified ? 'Verified' : 'Not verified yet'),
              subtitle: Text(c.verified
                  ? 'You confirmed this person\'s key in person.'
                  : 'Compare the safety number below in person, or scan their QR code.'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: Text(sn, textAlign: TextAlign.center,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1.5, height: 1.6)),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: Text('Both phones show the same 60 digits only if nobody is intercepting your chat.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
            ),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              TextButton.icon(
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan their code'),
                onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => QrScreen(verifyUserId: userId))),
              ),
              TextButton(
                onPressed: () {
                  core.db.setVerified(userId, !c.verified);
                  core.notify();
                },
                child: Text(c.verified ? 'Clear verification' : 'Mark as verified'),
              ),
            ]),
            const Divider(),
            ListTile(
              leading: Icon(Icons.block, color: c.blocked ? AppTheme.teal : Colors.red),
              title: Text(c.blocked ? 'Unblock ${c.name}' : 'Block ${c.name}', style: TextStyle(color: c.blocked ? null : Colors.red)),
              onTap: () async {
                if (!c.blocked && !await confirm(context, 'Block ${c.name}?',
                    'Blocked contacts cannot connect to you, message you or call you.', ok: 'Block', danger: true)) return;
                core.db.setBlocked(userId, !c.blocked);
                if (!c.blocked) await core.cm.disconnect(userId);
                core.notify();
              },
            ),
            ListTile(
              leading: const Icon(Icons.person_remove, color: Colors.red),
              title: const Text('Delete contact', style: TextStyle(color: Colors.red)),
              onTap: () async {
                if (!await confirm(context, 'Delete contact?', 'Chat history with ${c.name} will also be erased.', ok: 'Delete', danger: true)) return;
                core.db.deleteConversation('d:$userId');
                core.db.deleteContact(userId);
                core.notify();
                if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
            const SizedBox(height: 8),
            Center(child: SelectableText('ID ${c.userId}', style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Colors.grey))),
            const SizedBox(height: 24),
          ]),
        );
      },
    );
  }

  Widget _action(BuildContext context, IconData i, String l, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
          child: Column(children: [Icon(i, color: AppTheme.teal), const SizedBox(height: 4), Text(l)]),
        ),
      );
}
