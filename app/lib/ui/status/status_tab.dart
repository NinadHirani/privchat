import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../core/services/app_core.dart';
import '../../models/models.dart';
import '../media/media_utils.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'status_viewer.dart';
import 'text_status_screen.dart';

class StatusTab extends StatelessWidget {
  const StatusTab({super.key});

  static Widget fab(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        FloatingActionButton.small(
          heroTag: 'st_text',
          backgroundColor: Colors.blueGrey.shade100,
          foregroundColor: Colors.blueGrey.shade800,
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TextStatusScreen())),
          child: const Icon(Icons.edit),
        ),
        const SizedBox(height: 12),
        FloatingActionButton(heroTag: 'st_cam', onPressed: () => postMedia(context), child: const Icon(Icons.camera_alt)),
      ]);

  static Future<void> postMedia(BuildContext context) async {
    final src = await showModalBottomSheet<String>(
      context: context,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Take photo'), onTap: () => Navigator.pop(c, 'cam')),
          ListTile(leading: const Icon(Icons.photo), title: const Text('Photo from gallery'), onTap: () => Navigator.pop(c, 'gal')),
          ListTile(leading: const Icon(Icons.videocam), title: const Text('Video from gallery (≤30 s)'), onTap: () => Navigator.pop(c, 'vid')),
        ]),
      ),
    );
    if (src == null) return;
    try {
      final picker = ImagePicker();
      if (src == 'vid') {
        final x = await picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(seconds: 30));
        if (x == null) return;
        if (!context.mounted) return;
        final cap = await promptText(context, 'Caption (optional)', maxLength: 200);
        await AppCore.I.status.postMedia(await MediaUtils.importVideo(x.path), 'video', caption: cap);
      } else {
        final x = await picker.pickImage(source: src == 'cam' ? ImageSource.camera : ImageSource.gallery);
        if (x == null) return;
        if (!context.mounted) return;
        final cap = await promptText(context, 'Caption (optional)', maxLength: 200);
        await AppCore.I.status.postMedia(await MediaUtils.importImage(x.path), 'image', caption: cap);
      }
      if (context.mounted) toast(context, 'Status posted. Contacts get it when they are nearby.');
    } catch (e) {
      if (context.mounted) toast(context, 'Failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final me = core.identity.userId;
    final all = core.db.statusPosts();
    final mine = all.where((p) => p.authorId == me).toList();
    final byAuthor = <String, List<StatusPost>>{};
    for (final p in all.where((p) => p.authorId != me)) {
      (byAuthor[p.authorId] ??= []).add(p);
    }
    final recent = byAuthor.entries.where((e) => e.value.any((p) => !p.seen)).toList()
      ..sort((a, b) => b.value.last.ts.compareTo(a.value.last.ts));
    final viewed = byAuthor.entries.where((e) => e.value.every((p) => p.seen)).toList()
      ..sort((a, b) => b.value.last.ts.compareTo(a.value.last.ts));

    return ListView(children: [
      ListTile(
        leading: Stack(children: [
          _Ring(posts: mine, child: Avatar(name: core.displayName, bytes: core.avatar, radius: 24)),
          if (mine.isEmpty)
            const Positioned(right: 0, bottom: 0,
                child: CircleAvatar(radius: 10, backgroundColor: AppTheme.green, child: Icon(Icons.add, size: 16, color: Colors.white))),
        ]),
        title: const Text('My status', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(mine.isEmpty
            ? 'Tap to add status update'
            : '${mine.length} update${mine.length > 1 ? 's' : ''} · ${mine.fold<int>(0, (s, p) => s + p.viewers.length)} views'),
        onTap: () => mine.isEmpty
            ? postMedia(context)
            : Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewer(posts: mine))),
      ),
      if (recent.isNotEmpty) _header('Recent updates'),
      for (final e in recent) _authorTile(context, e.key, e.value),
      if (viewed.isNotEmpty) _header('Viewed updates'),
      for (final e in viewed) _authorTile(context, e.key, e.value),
      if (byAuthor.isEmpty)
        const Padding(
          padding: EdgeInsets.all(32),
          child: Text('Status updates from your contacts appear here when you are near each other.\nThey disappear after 24 hours.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
        ),
    ]);
  }

  Widget _header(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Text(t, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w600, fontSize: 13)),
      );

  Widget _authorTile(BuildContext context, String uid, List<StatusPost> posts) {
    final core = AppCore.I;
    return ListTile(
      leading: _Ring(posts: posts, child: Avatar(name: core.nameOf(uid), bytes: core.avatarOf(uid), radius: 24)),
      title: Text(core.nameOf(uid), style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(fmtListTime(posts.last.ts)),
      onTap: () {
        final start = posts.indexWhere((p) => !p.seen);
        Navigator.push(context, MaterialPageRoute(builder: (_) => StatusViewer(posts: posts, start: start < 0 ? 0 : start)));
      },
    );
  }
}

class _Ring extends StatelessWidget {
  const _Ring({required this.posts, required this.child});
  final List<StatusPost> posts;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    if (posts.isEmpty) return child;
    final unseen = posts.any((p) => !p.seen);
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: unseen ? AppTheme.green : Colors.grey, width: 2.5)),
      child: child,
    );
  }
}
