import 'dart:async';
import 'package:flutter/services.dart';

/// Android-only Wi-Fi Direct (P2P) — lets two phones form their own network
/// with no router and no hotspot. Once connected, normal IP/TCP works and our
/// mDNS/UDP discovery kicks in on the p2p interface.
/// Native side: android/.../WifiDirectPlugin.kt
class WifiDirect {
  static const _m = MethodChannel('privchat/wifidirect');
  static const _e = EventChannel('privchat/wifidirect/events');
  static final _events = StreamController<Map<String, dynamic>>.broadcast();
  static StreamSubscription? _sub;
  static bool _available = false;
  static bool get available => _available;

  static Stream<Map<String, dynamic>> get events => _events.stream;

  static Future<bool> init() async {
    try {
      _sub ??= _e.receiveBroadcastStream().listen((e) => _events.add(Map<String, dynamic>.from(e as Map)));
      _available = (await _m.invokeMethod<bool>('isSupported')) ?? false;
    } on MissingPluginException { _available = false; } catch (_) { _available = false; }
    return _available;
  }

  static Future<void> discover() async { if (_available) await _m.invokeMethod('discover'); }
  static Future<void> stopDiscovery() async { if (_available) await _m.invokeMethod('stopDiscovery'); }
  static Future<List<Map<String, dynamic>>> peers() async {
    if (!_available) return [];
    final r = await _m.invokeMethod<List>('peers');
    return (r ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  static Future<void> connect(String deviceAddress) async { if (_available) await _m.invokeMethod('connect', {'address': deviceAddress}); }
  static Future<void> disconnect() async { if (_available) await _m.invokeMethod('disconnect'); }
  /// Returns {'isGroupOwner': bool, 'groupOwnerAddress': String?} or null when not connected.
  static Future<Map<String, dynamic>?> connectionInfo() async {
    if (!_available) return null;
    final r = await _m.invokeMethod<Map>('connectionInfo');
    return r == null ? null : Map<String, dynamic>.from(r);
  }
  static Future<void> createGroup() async { if (_available) await _m.invokeMethod('createGroup'); }
}
