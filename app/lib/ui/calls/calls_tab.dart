import 'package:flutter/material.dart';
import '../../core/services/app_core.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CallsTab extends StatelessWidget {
  const CallsTab({super.key});
  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final calls = core.db.calls();
    if (calls.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Text('No calls yet.\n\nVoice & video calls work with no internet — just be on the same Wi-Fi, '
              'a phone hotspot, or Wi-Fi Direct.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    return ListView.builder(
      itemCount: calls.length,
      itemBuilder: (_, i) {
        final c = calls[i];
        final missed = !c.answered && !c.outgoing;
        return ListTile(
          leading: Avatar(name: core.nameOf(c.peerId), bytes: core.avatarOf(c.peerId), online: core.cm.isOnline(c.peerId)),
          title: Text(core.nameOf(c.peerId), style: TextStyle(color: missed ? Colors.red : null, fontWeight: FontWeight.w500)),
          subtitle: Row(children: [
            Icon(c.outgoing ? Icons.call_made : Icons.call_received, size: 16,
                color: missed ? Colors.red : (c.answered ? AppTheme.green : Colors.grey)),
            const SizedBox(width: 4),
            Text('${fmtListTime(c.ts)}${c.answered ? ' · ${fmtDuration(c.duration)}' : ''}'),
          ]),
          trailing: IconButton(
            icon: Icon(c.video ? Icons.videocam : Icons.call, color: AppTheme.teal),
            onPressed: () async {
              final e = await core.calls.start(c.peerId, video: c.video);
              if (e != null && context.mounted) toast(context, e);
            },
          ),
        );
      },
    );
  }
}
