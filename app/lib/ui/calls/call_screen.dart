import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../../core/services/app_core.dart';
import '../../core/services/call_service.dart';
import '../theme.dart';
import '../widgets/common.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});
  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final calls = AppCore.I.calls;
  Timer? _tick;
  bool _popped = false;

  @override
  void initState() {
    super.initState();
    calls.addListener(_onChange);
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  void _onChange() {
    if (!mounted) return;
    if (calls.state == CallState.idle && !_popped) {
      _popped = true;
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  void dispose() {
    calls.removeListener(_onChange);
    _tick?.cancel();
    super.dispose();
  }

  String _status() {
    switch (calls.state) {
      case CallState.outgoing: return 'Ringing…';
      case CallState.incoming: return 'Incoming ${calls.video ? 'video' : 'voice'} call';
      case CallState.connecting: return 'Connecting…';
      case CallState.active: return fmtDuration(calls.elapsed.inSeconds);
      case CallState.ended: return calls.endReason ?? 'Call ended';
      case CallState.idle: return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final core = AppCore.I;
    final peer = calls.peerId;
    final name = peer == null ? '' : core.nameOf(peer);
    final showVideo = calls.video && calls.state == CallState.active;
    return PopScope(
      canPop: calls.state == CallState.idle || calls.state == CallState.ended,
      child: Scaffold(
        backgroundColor: AppTheme.tealDark,
        body: Stack(children: [
          if (showVideo) Positioned.fill(child: RTCVideoView(calls.remoteRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)),
          if (calls.video && !calls.cameraOff && calls.state != CallState.incoming)
            Positioned(
              right: 16, top: 60, width: 110, height: 160,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: RTCVideoView(calls.localRenderer, mirror: true, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover),
              ),
            ),
          SafeArea(
            child: Column(children: [
              const SizedBox(height: 16),
              const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.lock, size: 14, color: Colors.white60),
                SizedBox(width: 4),
                Text('End-to-end encrypted · peer-to-peer', style: TextStyle(color: Colors.white60, fontSize: 12.5)),
              ]),
              if (!showVideo) ...[
                const SizedBox(height: 40),
                Avatar(name: name, bytes: peer == null ? null : core.avatarOf(peer), radius: 64),
              ],
              const SizedBox(height: 20),
              Text(name, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w500,
                  shadows: [Shadow(blurRadius: 4)])),
              const SizedBox(height: 8),
              Text(_status(), style: const TextStyle(color: Colors.white70, fontSize: 16, shadows: [Shadow(blurRadius: 4)])),
              const Spacer(),
              if (calls.state == CallState.incoming) _incomingControls() else if (calls.state != CallState.ended) _activeControls(),
              const SizedBox(height: 40),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _incomingControls() => Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        _round(Icons.call_end, Colors.red, 'Decline', calls.decline, size: 70),
        _round(calls.video ? Icons.videocam : Icons.call, AppTheme.green, 'Accept', calls.accept, size: 70),
      ]);

  Widget _activeControls() => Column(children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _round(calls.speaker ? Icons.volume_up : Icons.volume_down, calls.speaker ? Colors.white : Colors.white24, 'Speaker',
              calls.toggleSpeaker, fg: calls.speaker ? Colors.black : Colors.white),
          if (calls.video) ...[
            _round(calls.cameraOff ? Icons.videocam_off : Icons.videocam, calls.cameraOff ? Colors.white : Colors.white24, 'Camera',
                calls.toggleCamera, fg: calls.cameraOff ? Colors.black : Colors.white),
            _round(Icons.cameraswitch, Colors.white24, 'Flip', calls.switchCamera),
          ],
          _round(calls.muted ? Icons.mic_off : Icons.mic, calls.muted ? Colors.white : Colors.white24, 'Mute', calls.toggleMute,
              fg: calls.muted ? Colors.black : Colors.white),
        ]),
        const SizedBox(height: 28),
        _round(Icons.call_end, Colors.red, 'End', () => calls.hangup(), size: 70),
      ]);

  Widget _round(IconData i, Color bg, String label, VoidCallback onTap, {double size = 56, Color fg = Colors.white}) => Column(children: [
        SizedBox(
          width: size, height: size,
          child: RawMaterialButton(onPressed: onTap, shape: const CircleBorder(), fillColor: bg, elevation: 0,
              child: Icon(i, color: fg, size: size * .45)),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]);
}
