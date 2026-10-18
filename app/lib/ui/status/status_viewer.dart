import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../core/services/app_core.dart';
import '../../core/storage/media_store.dart';
import '../../models/models.dart';
import '../widgets/common.dart';

class StatusViewer extends StatefulWidget {
  const StatusViewer({super.key, required this.posts, this.start = 0});
  final List<StatusPost> posts;
  final int start;
  @override
  State<StatusViewer> createState() => _StatusViewerState();
}

class _StatusViewerState extends State<StatusViewer> with SingleTickerProviderStateMixin {
  late int _i = widget.start;
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(seconds: 6))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _next();
    });
  VideoPlayerController? _video;
  Uint8List? _image;
  bool _loading = false;
  final core = AppCore.I;

  StatusPost get p => widget.posts[_i];
  bool get mine => p.authorId == core.identity.userId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    _anim.stop();
    await _video?.dispose();
    _video = null;
    _image = null;
    core.status.markSeen(p);
    final a = p.attachmentId == null ? null : core.db.attachment(p.attachmentId!);
    if (a != null) {
      if (!a.done) {
        setState(() => _loading = true);
        core.files.request(a.id);
        // wait (max 20 s) for the media to arrive
        for (var t = 0; t < 40 && !(core.db.attachment(a.id)?.done ?? false); t++) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (!mounted) return;
        }
      }
      final ready = core.db.attachment(a.id)!;
      if (ready.done) {
        if (p.kind == 'video') {
          final f = await MediaStore.openPlain(ready);
          if (f != null) {
            _video = VideoPlayerController.file(f);
            await _video!.initialize();
            _anim.duration = _video!.value.duration;
            await _video!.play();
          }
        } else {
          _image = await MediaStore.readPlain(ready);
          _anim.duration = const Duration(seconds: 6);
        }
      }
    } else {
      _anim.duration = const Duration(seconds: 6);
    }
    if (!mounted) return;
    setState(() => _loading = false);
    _anim.forward(from: 0);
  }

  void _next() {
    if (_i < widget.posts.length - 1) {
      setState(() => _i++);
      _load();
    } else {
      Navigator.pop(context);
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _load();
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bg = p.kind == 'text' ? Color((p.body['bg'] as num?)?.toInt() ?? 0xFF008069) : Colors.black;
    return Scaffold(
      backgroundColor: bg,
      body: GestureDetector(
        onTapUp: (d) => d.globalPosition.dx < MediaQuery.of(context).size.width / 3 ? _prev() : _next(),
        onLongPressStart: (_) { _anim.stop(); _video?.pause(); },
        onLongPressEnd: (_) { _anim.forward(); _video?.play(); },
        onVerticalDragEnd: (d) { if ((d.primaryVelocity ?? 0) > 300) Navigator.pop(context); },
        child: SafeArea(
          child: Stack(children: [
            Positioned.fill(child: Center(child: _body())),
            Column(children: [
              Padding(
                padding: const EdgeInsets.all(6),
                child: Row(children: [
                  for (var j = 0; j < widget.posts.length; j++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: AnimatedBuilder(
                          animation: _anim,
                          builder: (_, __) => LinearProgressIndicator(
                            value: j < _i ? 1 : j == _i ? _anim.value : 0,
                            minHeight: 2.5, backgroundColor: Colors.white30, color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
              ListTile(
                leading: Avatar(name: core.nameOf(p.authorId), bytes: core.avatarOf(p.authorId), radius: 18),
                title: Text(mine ? 'My status' : core.nameOf(p.authorId), style: const TextStyle(color: Colors.white)),
                subtitle: Text(fmtListTime(p.ts), style: const TextStyle(color: Colors.white70)),
                trailing: mine
                    ? IconButton(
                        icon: const Icon(Icons.delete, color: Colors.white),
                        onPressed: () async {
                          _anim.stop();
                          if (await confirm(context, 'Delete status?', 'It will also be removed from contacts\' phones.', ok: 'Delete', danger: true)) {
                            await core.status.delete(p.id);
                            if (context.mounted) Navigator.pop(context);
                          } else {
                            _anim.forward();
                          }
                        },
                      )
                    : null,
              ),
            ]),
            if (p.kind != 'text' && (p.body['text'] as String?)?.isNotEmpty == true)
              Positioned(
                left: 0, right: 0, bottom: mine ? 64 : 24,
                child: Container(
                  color: Colors.black45, padding: const EdgeInsets.all(12),
                  child: Text(p.body['text'], textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                ),
              ),
            if (mine)
              Positioned(
                left: 0, right: 0, bottom: 8,
                child: Center(
                  child: TextButton.icon(
                    icon: const Icon(Icons.remove_red_eye, color: Colors.white),
                    label: Text('${p.viewers.length}', style: const TextStyle(color: Colors.white)),
                    onPressed: () {
                      _anim.stop();
                      showModalBottomSheet(
                        context: context,
                        builder: (c) => ListView(children: [
                          ListTile(title: Text('Viewed by ${p.viewers.length}')),
                          for (final v in p.viewers)
                            ListTile(leading: Avatar(name: core.nameOf(v), bytes: core.avatarOf(v)), title: Text(core.nameOf(v))),
                        ]),
                      ).then((_) => _anim.forward());
                    },
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }

  Widget _body() {
    if (_loading) return const CircularProgressIndicator(color: Colors.white);
    switch (p.kind) {
      case 'text':
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Text(p.body['text'] as String? ?? '', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 30)),
        );
      case 'video':
        if (_video == null) return const Text('Video not available yet', style: TextStyle(color: Colors.white));
        return AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!));
      default:
        if (_image == null) return const Text('Photo not available yet', style: TextStyle(color: Colors.white));
        return Image.memory(_image!, fit: BoxFit.contain);
    }
  }
}
