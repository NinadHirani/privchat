import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:uuid/uuid.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import '../protocol/envelope.dart';
import '../../models/models.dart';
import 'app_core.dart';

enum CallState { idle, outgoing, incoming, connecting, active, ended }

/// Voice / video calls with ZERO internet:
///  - WebRTC with an EMPTY ICE server list → only local (host) candidates → direct LAN/hotspot/Wi-Fi Direct path.
///  - Offer/answer/ICE travel inside our E2EE channel, so the DTLS fingerprint in the SDP is authenticated:
///    nobody on the network can man-in-the-middle the SRTP media.
///  - Opus audio, echo cancellation, noise suppression, jitter buffer come from libwebrtc.
class CallService extends ChangeNotifier {
  CallService(this.core);
  final AppCore core;

  CallState state = CallState.idle;
  String? callId, peerId, endReason;
  bool video = false, outgoing = false, muted = false, speaker = false, cameraOff = false;
  int? startedAt;
  final localRenderer = RTCVideoRenderer();
  final remoteRenderer = RTCVideoRenderer();
  bool _renderersReady = false;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  Map<String, dynamic>? _offer;
  final List<RTCIceCandidate> _pendingIce = [];
  bool _remoteSet = false;
  Timer? _ringTimer, _iceFailTimer;
  bool _answered = false;

  static const Map<String, dynamic> _rtcConfig = {
    'iceServers': <Map<String, dynamic>>[], // offline: no STUN, no TURN, no Google servers
    'sdpSemantics': 'unified-plan',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
  };

  bool get busy => state != CallState.idle;
  Duration get elapsed => startedAt == null
      ? Duration.zero
      : Duration(milliseconds: DateTime.now().millisecondsSinceEpoch - startedAt!);

  void _set(CallState s) {
    state = s;
    notifyListeners();
  }

  Future<void> _ensureRenderers() async {
    if (_renderersReady) return;
    await localRenderer.initialize();
    await remoteRenderer.initialize();
    _renderersReady = true;
  }

  // ------------------------------------------------------------- outgoing
  /// Returns an error string for the UI, or null on success.
  Future<String?> start(String peer, {bool video = false}) async {
    if (busy) return 'You are already in a call';
    final conn = core.cm.connection(peer);
    if (conn == null) {
      return '${core.nameOf(peer)} is not nearby. Calls work when you are both on the same Wi-Fi, '
          'a phone hotspot, or Wi-Fi Direct — no internet needed.';
    }
    if (!conn.isIp) return 'This device is connected via Bluetooth/Multipeer only. Join the same Wi-Fi or hotspot to call.';
    if (!await _permissions(video)) return 'Microphone${video ? '/camera' : ''} permission is required for calls';
    _reset();
    callId = const Uuid().v4();
    peerId = peer;
    this.video = video;
    outgoing = true;
    speaker = video;
    _set(CallState.outgoing);
    try {
      await _ensureRenderers();
      await _createPc();
      await _openMedia();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true, 'offerToReceiveVideo': video});
      await _pc!.setLocalDescription(offer);
      await core.cm.send(peer, {'type': Env.callOffer, 'id': callId, 'sdp': offer.sdp, 'video': video}, queueIfOffline: false);
      _ringTimer = Timer(const Duration(seconds: 45), () => hangup(reason: 'No answer'));
      await WakelockPlus.enable();
      return null;
    } catch (e) {
      await _teardown('Call failed: $e', notifyPeer: true);
      return 'Could not start call';
    }
  }

  // ------------------------------------------------------------- incoming
  Future<void> accept() async {
    if (state != CallState.incoming || _offer == null) return;
    _ringTimer?.cancel();
    core.notifications.cancelCall(callId!);
    if (!await _permissions(video)) {
      await decline();
      return;
    }
    _set(CallState.connecting);
    _answered = true;
    try {
      await _ensureRenderers();
      await _createPc();
      await _openMedia();
      await _pc!.setRemoteDescription(RTCSessionDescription(_offer!['sdp'] as String, 'offer'));
      _remoteSet = true;
      await _drainIce();
      final answer = await _pc!.createAnswer({'offerToReceiveAudio': true, 'offerToReceiveVideo': video});
      await _pc!.setLocalDescription(answer);
      await core.cm.send(peerId!, {'type': Env.callAnswer, 'id': callId, 'sdp': answer.sdp}, queueIfOffline: false);
      await WakelockPlus.enable();
      _iceFailTimer = Timer(const Duration(seconds: 20), () {
        if (state == CallState.connecting) hangup(reason: 'Could not connect');
      });
    } catch (e) {
      await _teardown('Call failed', notifyPeer: true);
    }
  }

  Future<void> decline() async {
    if (state != CallState.incoming) return;
    await core.cm.send(peerId!, {'type': Env.callEnd, 'id': callId, 'reason': 'declined'}, queueIfOffline: false);
    await _teardown('Declined');
  }

  Future<void> hangup({String reason = 'Call ended'}) async {
    if (!busy || state == CallState.ended) return;
    await _teardown(reason, notifyPeer: true);
  }

  void handle(String from, Map<String, dynamic> env) {
    final id = env['id'] as String?;
    switch (env['type']) {
      case Env.callOffer:
        if (core.db.contact(from)?.blocked ?? false) return;
        if (busy) {
          core.cm.send(from, {'type': Env.callBusy, 'id': id}, queueIfOffline: false);
          return;
        }
        _reset();
        callId = id;
        peerId = from;
        video = env['video'] == true;
        speaker = video;
        outgoing = false;
        _offer = env;
        _set(CallState.incoming);
        HapticFeedback.heavyImpact();
        core.notifications.incomingCall(id!, core.nameOf(from));
        _ringTimer = Timer(const Duration(seconds: 45), () => _teardown('Missed call'));
        break;
      case Env.callAnswer:
        if (id != callId || from != peerId || !outgoing) return;
        _ringTimer?.cancel();
        _answered = true;
        _set(CallState.connecting);
        _pc?.setRemoteDescription(RTCSessionDescription(env['sdp'] as String, 'answer')).then((_) {
          _remoteSet = true;
          _drainIce();
        });
        _iceFailTimer = Timer(const Duration(seconds: 20), () {
          if (state == CallState.connecting) hangup(reason: 'Could not connect');
        });
        break;
      case Env.callIce:
        if (id != callId || from != peerId) return;
        final c = RTCIceCandidate(env['c'] as String?, env['mid'] as String?, (env['idx'] as num?)?.toInt());
        if (_pc != null && _remoteSet) {
          _pc!.addCandidate(c);
        } else {
          _pendingIce.add(c);
        }
        break;
      case Env.callEnd:
        if (id != callId || from != peerId) return;
        _teardown(env['reason'] == 'declined' ? 'Declined' : (state == CallState.incoming ? 'Missed call' : 'Call ended'));
        break;
      case Env.callBusy:
        if (id != callId || from != peerId) return;
        _teardown('Busy');
        break;
    }
  }

  void onPeerOffline(String uid) {
    if (busy && uid == peerId && state != CallState.active) _teardown('Connection lost');
    // In an ACTIVE call the media path is independent of the signaling socket; WebRTC decides.
  }

  // ------------------------------------------------------------- controls
  void toggleMute() {
    muted = !muted;
    for (final t in _local?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speaker = !speaker;
    await Helper.setSpeakerphoneOn(speaker);
    notifyListeners();
  }

  void toggleCamera() {
    cameraOff = !cameraOff;
    for (final t in _local?.getVideoTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !cameraOff;
    }
    notifyListeners();
  }

  Future<void> switchCamera() async {
    final tracks = _local?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) await Helper.switchCamera(tracks.first);
  }

  // ------------------------------------------------------------- internals
  Future<bool> _permissions(bool video) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;
    if (video && !(await Permission.camera.request()).isGranted) return false;
    return true;
  }

  Future<void> _createPc() async {
    _pc = await createPeerConnection(_rtcConfig);
    _pc!.onIceCandidate = (c) {
      if (c.candidate == null || peerId == null) return;
      core.cm.send(peerId!, {'type': Env.callIce, 'id': callId, 'c': c.candidate, 'mid': c.sdpMid, 'idx': c.sdpMLineIndex},
          queueIfOffline: false);
    };
    _pc!.onTrack = (e) {
      if (e.streams.isNotEmpty) {
        remoteRenderer.srcObject = e.streams.first;
        notifyListeners();
      }
    };
    _pc!.onConnectionState = (s) {
      switch (s) {
        case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
          _iceFailTimer?.cancel();
          if (state != CallState.active) {
            startedAt = DateTime.now().millisecondsSinceEpoch;
            Helper.setSpeakerphoneOn(speaker);
            _set(CallState.active);
          }
          break;
        case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
          _teardown('Connection lost', notifyPeer: true);
          break;
        default:
          break;
      }
    };
  }

  Future<void> _openMedia() async {
    _local = await navigator.mediaDevices.getUserMedia({
      'audio': {'echoCancellation': true, 'noiseSuppression': true, 'autoGainControl': true},
      'video': video ? {'facingMode': 'user', 'width': 640, 'height': 480, 'frameRate': 24} : false,
    });
    for (final t in _local!.getTracks()) {
      await _pc!.addTrack(t, _local!);
    }
    if (video) localRenderer.srcObject = _local;
  }

  Future<void> _drainIce() async {
    for (final c in _pendingIce) {
      await _pc?.addCandidate(c);
    }
    _pendingIce.clear();
  }

  void _reset() {
    callId = peerId = endReason = null;
    _offer = null;
    _pendingIce.clear();
    _remoteSet = false;
    _answered = false;
    muted = cameraOff = false;
    startedAt = null;
  }

  Future<void> _teardown(String reason, {bool notifyPeer = false}) async {
    if (state == CallState.ended || state == CallState.idle) return;
    final wasState = state;
    _ringTimer?.cancel();
    _iceFailTimer?.cancel();
    if (notifyPeer && peerId != null) {
      core.cm.send(peerId!, {'type': Env.callEnd, 'id': callId}, queueIfOffline: false);
    }
    if (callId != null) core.notifications.cancelCall(callId!);
    final duration = startedAt == null ? 0 : (DateTime.now().millisecondsSinceEpoch - startedAt!) ~/ 1000;
    if (peerId != null) {
      final answered = startedAt != null || (_answered && wasState == CallState.active);
      core.db.upsertCall(CallLog(id: callId!, peerId: peerId!, ts: DateTime.now().millisecondsSinceEpoch,
          outgoing: outgoing, answered: answered, duration: duration, video: video));
      core.messages.logCall(peerId!, outgoing: outgoing, answered: answered, duration: duration, video: video);
      if (!outgoing && !answered) {
        core.notifications.message(convId: 'd:$peerId', title: 'Missed call', body: core.nameOf(peerId!));
      }
    }
    endReason = reason;
    try {
      for (final t in _local?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _local?.dispose();
      await _pc?.close();
    } catch (_) {}
    _local = null;
    _pc = null;
    if (_renderersReady) {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    }
    await WakelockPlus.disable();
    _set(CallState.ended);
    Timer(const Duration(milliseconds: 1500), () {
      if (state == CallState.ended) {
        _reset();
        _set(CallState.idle);
      }
    });
  }
}
