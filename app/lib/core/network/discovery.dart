import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bonsoir/bonsoir.dart';
import '../../models/models.dart';

/// Finds other PrivChat devices on the local network with NO server:
///  1. mDNS/Bonjour (`_privchat._tcp`) — works Android↔iOS on any Wi-Fi / hotspot
///  2. UDP broadcast on 47474 every 4 s — fallback for routers/hotspots that drop multicast
/// Both advertise only: user_id, display name, TCP port, protocol version.
class Discovery {
  Discovery({required this.userId, required this.name, required this.tcpPort});
  final String userId;
  String name;
  final int tcpPort;

  static const serviceType = '_privchat._tcp';
  static const udpPort = 47474;

  final _peers = <String, DiscoveredPeer>{};
  final _ctrl = StreamController<List<DiscoveredPeer>>.broadcast();
  Stream<List<DiscoveredPeer>> get peers => _ctrl.stream;
  List<DiscoveredPeer> get current => _peers.values.toList();

  BonsoirBroadcast? _bcast;
  BonsoirDiscovery? _disc;
  RawDatagramSocket? _udp;
  Timer? _beacon, _prune;
  final _resolved = <String, StreamSubscription>{};

  Future<void> start() async {
    await _startMdns();
    await _startUdp();
    _prune = Timer.periodic(const Duration(seconds: 10), (_) => _pruneStale());
  }

  Future<void> _startMdns() async {
    try {
      final svc = BonsoirService(name: 'pc-${userId.substring(0, 12)}', type: serviceType, port: tcpPort,
          attributes: {'uid': userId, 'name': name, 'v': '1'});
      _bcast = BonsoirBroadcast(service: svc);
      await _bcast!.ready;
      await _bcast!.start();

      _disc = BonsoirDiscovery(type: serviceType);
      await _disc!.ready;
      _disc!.eventStream!.listen((e) {
        final s = e.service;
        if (s == null) return;
        if (e.type == BonsoirDiscoveryEventType.discoveryServiceFound) {
          s.resolve(_disc!.serviceResolver);
        } else if (e.type == BonsoirDiscoveryEventType.discoveryServiceResolved) {
          final uid = s.attributes['uid'];
          if (uid == null || uid == userId) return;
          final host = (s is ResolvedBonsoirService) ? s.host : null;
          if (host == null) return;
          _add(DiscoveredPeer(userId: uid, name: s.attributes['name'] ?? 'Unknown', host: host, port: s.port, via: 'mdns',
              seenAt: DateTime.now().millisecondsSinceEpoch));
        } else if (e.type == BonsoirDiscoveryEventType.discoveryServiceLost) {
          final uid = s.attributes['uid'];
          if (uid != null && _peers[uid]?.via == 'mdns') { _peers.remove(uid); _emit(); }
        }
      });
      await _disc!.start();
    } catch (_) {
      // mDNS unavailable (emulator, restricted network) — UDP fallback still works
    }
  }

  Future<void> _startUdp() async {
    try {
      _udp = await RawDatagramSocket.bind(InternetAddress.anyIPv4, udpPort, reuseAddress: true, reusePort: true);
      _udp!.broadcastEnabled = true;
      _udp!.listen((ev) {
        if (ev != RawSocketEvent.read) return;
        final dg = _udp!.receive();
        if (dg == null) return;
        try {
          final m = jsonDecode(utf8.decode(dg.data)) as Map<String, dynamic>;
          if (m['app'] != 'privchat' || m['v'] != 1) return;
          final uid = m['uid'] as String;
          if (uid == userId) return;
          _add(DiscoveredPeer(userId: uid, name: m['name'] ?? 'Unknown', host: dg.address.address, port: m['port'] as int,
              via: 'udp', seenAt: DateTime.now().millisecondsSinceEpoch));
        } catch (_) {}
      });
      _beacon = Timer.periodic(const Duration(seconds: 4), (_) => _sendBeacon());
      _sendBeacon();
    } catch (_) {}
  }

  Future<void> _sendBeacon() async {
    if (_udp == null) return;
    final payload = utf8.encode(jsonEncode({'app': 'privchat', 'v': 1, 'uid': userId, 'name': name, 'port': tcpPort}));
    final targets = <InternetAddress>{InternetAddress('255.255.255.255')};
    try {
      for (final iface in await NetworkInterface.list(type: InternetAddressType.IPv4)) {
        for (final a in iface.addresses) {
          final parts = a.address.split('.');
          if (parts.length == 4) targets.add(InternetAddress('${parts[0]}.${parts[1]}.${parts[2]}.255'));
        }
      }
    } catch (_) {}
    for (final t in targets) { try { _udp!.send(payload, t, udpPort); } catch (_) {} }
  }

  /// Called by Wi-Fi Direct / Multipeer glue when they learn of a peer.
  void addExternal(DiscoveredPeer p) => _add(p);

  void _add(DiscoveredPeer p) {
    final old = _peers[p.userId];
    // prefer mdns over udp info only if newer; always refresh seenAt
    if (old == null || old.host != p.host || old.name != p.name || old.port != p.port || p.seenAt - old.seenAt > 1000) {
      _peers[p.userId] = p;
      _emit();
    }
  }

  void _pruneStale() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final before = _peers.length;
    _peers.removeWhere((_, p) => now - p.seenAt > 20000);
    if (_peers.length != before) _emit();
  }

  void _emit() { if (!_ctrl.isClosed) _ctrl.add(current); }

  Future<void> updateName(String n) async {
    name = n;
    await _bcast?.stop();
    _bcast = null;
    await _startMdns();
  }

  Future<void> stop() async {
    _beacon?.cancel(); _prune?.cancel();
    for (final s in _resolved.values) { await s.cancel(); }
    await _bcast?.stop(); await _disc?.stop();
    _udp?.close();
    await _ctrl.close();
  }
}
