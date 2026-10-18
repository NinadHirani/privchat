import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:video_player/video_player.dart';
import '../../core/storage/media_store.dart';
import '../../models/models.dart';

/// Full-screen photo (pinch-zoom) / video player. Decrypts in memory (photos) or to wiped cache (video).
class MediaViewer extends StatefulWidget {
  const MediaViewer({super.key, required this.att});
  final Attachment att;
  @override
  State<MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<MediaViewer> {
  Uint8List? _bytes;
  VideoPlayerController? _video;
  bool get isVideo => widget.att.mime.startsWith('video/');

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (isVideo) {
      final f = await MediaStore.openPlain(widget.att);
      if (f == null) return;
      _video = VideoPlayerController.file(f);
      await _video!.initialize();
      await _video!.play();
      _video!.addListener(() => mounted ? setState(() {}) : null);
    } else {
      _bytes = await MediaStore.readPlain(widget.att);
    }
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    // Explicit user action: exports a decrypted copy to another app.
    final f = await MediaStore.openPlain(widget.att);
    if (f != null) await Share.shareXFiles([XFile(f.path, mimeType: widget.att.mime)]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          actions: [IconButton(icon: const Icon(Icons.share), tooltip: 'Export (leaves PrivChat)', onPressed: _share)],
        ),
        body: Center(
          child: isVideo
              ? (_video?.value.isInitialized ?? false)
                  ? GestureDetector(
                      onTap: () => _video!.value.isPlaying ? _video!.pause() : _video!.play(),
                      child: Stack(alignment: Alignment.bottomCenter, children: [
                        AspectRatio(aspectRatio: _video!.value.aspectRatio, child: VideoPlayer(_video!)),
                        if (!_video!.value.isPlaying) const Center(child: Icon(Icons.play_circle, color: Colors.white70, size: 72)),
                        VideoProgressIndicator(_video!, allowScrubbing: true),
                      ]),
                    )
                  : const CircularProgressIndicator()
              : _bytes == null
                  ? const CircularProgressIndicator()
                  : Hero(tag: widget.att.id, child: InteractiveViewer(maxScale: 5, child: Image.memory(_bytes!))),
        ),
      );
}
