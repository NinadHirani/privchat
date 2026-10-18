import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'link.dart';

/// iOS-only: Multipeer Connectivity transport (works iPhone↔iPhone with no router,
/// over Bluetooth + peer-to-peer Wi-Fi). Native side: ios/Runner/MultipeerPlugin.swift
class Multipeer {
  static const _m = MethodChannel('privchat/multipeer');
  static const _e = EventChannel('privchat/multipeer/events');
  static final _links = <String, MultipeerLink>{};
  static final _peerFound = StreamController<Map<String, dynamic>>.broadcast();
  static final _peerLost = StreamController<String>.broadcast();
  static final _connected = StreamController<MultipeerLink>.broadcast();
  static StreamSubscription? _sub;

  static Stream<Map<String, dynamic>> get peerFound => _peerFound.stream;
  static Stream<String> get peerLost => _peerLost.stream;
  static Stream<MultipeerLink> get connected => _connected.stream;

  static Future<bool> start(String userId, String name) async {
    try {
      _sub ??= _e.receiveBroadcastStream().listen(_onEvent);
      await _m.invokeMethod('start', {'userId': userId, 'name': name});
      return true;
    } on MissingPluginException {
      return false; // not iOS
    } catch (_) {
      return false;
    }
  }

  static Future<void> stop() async { try { await _m.invokeMethod('stop'); } catch (_) {} }
  static Future<void> invite(String peerUserId) async { try { await _m.invokeMethod('invite', {'userId': peerUserId}); } catch (_) {} }

  static void _onEvent(dynamic ev) {
    final m = Map<String, dynamic>.from(ev as Map);
    final uid = m['userId'] as String?;
    switch (m['type']) {
      case 'found': _peerFound.add(m); break;
      case 'lost': if (uid != null) _peerLost.add(uid); break;
      case 'connected':
        if (uid == null) break;
        final l = MultipeerLink._(uid, m['name'] as String? ?? '');
        _links[uid] = l;
        _connected.add(l);
        break;
      case 'data':
        if (uid != null) _links[uid]?._ctrl.add(m['data'] as Uint8List);
        break;
      case 'disconnected':
        if (uid != null) _links.remove(uid)?._finish();
        break;
    }
  }
}

class MultipeerLink implements PeerLink {
  MultipeerLink._(this.peerUserId, this.peerName);
  final String peerUserId, peerName;
  final _ctrl = StreamController<Uint8List>();
  final _done = Completer<void>();
  void _finish() { if (!_done.isCompleted) _done.complete(); if (!_ctrl.isClosed) _ctrl.close(); }
  @override
  Stream<Uint8List> get data => _ctrl.stream;
  @override
  Future<void> get done => _done.future;
  @override
  void send(Uint8List bytes) => Multipeer._m.invokeMethod('send', {'userId': peerUserId, 'data': bytes});
  @override
  Future<void> flush() async {}
  @override
  Future<void> close() async { await Multipeer._m.invokeMethod('disconnect', {'userId': peerUserId}); _finish(); }
  @override
  String get describe => 'multipeer://$peerUserId';
  @override
  bool get isIp => false;
  @override
  String? get remoteHost => null;
}
