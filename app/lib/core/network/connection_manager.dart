import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import '../crypto/identity.dart';
import '../storage/db.dart';
import '../../models/models.dart';
import 'discovery.dart';
import 'link.dart';
import 'multipeer_link.dart';
import 'peer_connection.dart';
import 'tcp_link.dart';
import 'wifi_direct.dart';

class PeerEvent {
  PeerEvent(this.type, this.peerId, {this.name});
  final String type; // online | offline
  final String peerId;
  final String? name;
}

/// Owns the TCP listener, discovery, all live PeerConnections, and the
/// store-and-forward outbox. Services talk to peers only through here.
class ConnectionManager {
  ConnectionManager({required this.identity, required this.displayName});
  final Identity identity;
  String displayName;

  ServerSocket? _server;
  Discovery? discovery;
  final Map<String, PeerConnection> _conns = {};
  final Set<String> _dialing = {};
  final Map<String, int> _lastDialAttempt = {};
  final _events = StreamController<PeerEvent>.broadcast();
  final _envelopes = StreamController<(PeerConnection, Map<String, dynamic>)>.broadcast();
  final _chunks = StreamController<(PeerConnection, Uint8List, int, Uint8List)>.broadcast();
  Timer? _tick;
  StreamSubscription? _discSub, _mpSub, _mpFound;

  Stream<PeerEvent> get events => _events.stream;
  Stream<(PeerConnection, Map<String, dynamic>)> get envelopes => _envelopes.stream;
  Stream<(PeerConnection, Uint8List, int, Uint8List)> get chunks => _chunks.stream;
  Set<String> get online => _conns.keys.toSet();
  bool isOnline(String uid) => _conns.containsKey(uid);
  PeerConnection? connection(String uid) => _conns[uid];
  int get port => _server?.port ?? 0;
  bool Function(String userId)? isBlocked;

  Future<void> start() async {
    _server = await ServerSocket.bind(InternetAddress.anyIPv4, 0, shared: true);
    _server!.listen((s) => _adopt(TcpLink(s), outgoing: false), onError: (_) {});
    discovery = Discovery(userId: identity.userId, name: displayName, tcpPort: _server!.port);
    await discovery!.start();
    _discSub = discovery!.peers.listen(_onPeers);
    _tick = Timer.periodic(const Duration(seconds: 5), (_) { _onPeers(discovery!.current); _flushAll(); });

    // iOS Multipeer (no-op elsewhere)
    if (await Multipeer.start(identity.userId, displayName)) {
      _mpSub = Multipeer.connected.listen((l) => _adopt(l, outgoing: false));
      _mpFound = Multipeer.peerFound.listen((m) {
        final uid = m['userId'] as String?;
        if (uid == null || _conns.containsKey(uid)) return;
        discovery!.addExternal(DiscoveredPeer(userId: uid, name: m['name'] ?? 'iPhone', via: 'multipeer',
            seenAt: DateTime.now().millisecondsSinceEpoch));
        if (identity.userId.compareTo(uid) < 0) Multipeer.invite(uid);
      });
    }
    // Android Wi-Fi Direct: when a group forms we get IP connectivity; discovery handles the rest.
    if (await WifiDirect.init()) {
      WifiDirect.events.listen((e) { if (e['type'] == 'connected') discovery!.updateName(displayName); });
    }
  }

  // ---- dialing -------------------------------------------------------------
  void _onPeers(List<DiscoveredPeer> peers) {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final p in peers) {
      if (p.host == null || p.port == null) continue;
      if (_conns.containsKey(p.userId) || _dialing.contains(p.userId)) continue;
      if (isBlocked?.call(p.userId) == true) continue;
      final iDial = identity.userId.compareTo(p.userId) < 0;
      final last = _lastDialAttempt[p.userId] ?? 0;
      // Lower id dials immediately; higher id waits 6 s then dials anyway (one-way reachability).
      if (!iDial && now - p.seenAt < 6000) continue;
      if (now - last < 5000) continue;
      _lastDialAttempt[p.userId] = now;
      _dial(p);
    }
  }

  Future<void> _dial(DiscoveredPeer p) async {
    _dialing.add(p.userId);
    try {
      final link = await TcpLink.connect(p.host!, p.port!);
      await _adopt(link, outgoing: true, expect: p.userId);
    } catch (_) {
    } finally {
      _dialing.remove(p.userId);
    }
  }

  Future<void> connectTo(String host, int port) async {
    final link = await TcpLink.connect(host, port);
    await _adopt(link, outgoing: true);
  }

  Future<void> _adopt(PeerLink link, {required bool outgoing, String? expect}) async {
    final c = PeerConnection(link: link, identity: identity, myName: displayName, outgoing: outgoing);
    c.onEnvelope = (conn, env) => _envelopes.add((conn, env));
    c.onChunk = (conn, fid, i, ct) => _chunks.add((conn, fid, i, ct));
    c.start();
    try {
      final hello = await c.established;
      if (expect != null && hello.userId != expect) { await c.close(); return; }
      if (isBlocked?.call(hello.userId) == true) { await c.close(); return; }
      final existing = _conns[hello.userId];
      if (existing != null && !existing.closed) {
        // Deterministic de-dup: keep the connection initiated by the lower user id.
        final keepNew = (identity.userId.compareTo(hello.userId) < 0) == c.outgoing;
        if (!keepNew) { await c.close(); return; }
        existing.onClosed = null;
        await existing.close();
      }
      _conns[hello.userId] = c;
      c.onClosed = (conn) {
        if (_conns[conn.peerId] == conn) {
          _conns.remove(conn.peerId);
          _events.add(PeerEvent('offline', conn.peerId));
        }
      };
      final db = AppDb.I;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final existingContact = db.contact(hello.userId);
      if (existingContact == null) {
        db.upsertContact(Contact(userId: hello.userId, edPk: hello.edPk, name: hello.name, lastSeen: ts, added: 0));
      } else {
        existingContact.lastSeen = ts;
        // Name from HELLO is self-asserted; keep user-edited names if they differ from our stored one.
        if (existingContact.added == 0) existingContact.name = hello.name;
        db.upsertContact(existingContact);
      }
      _events.add(PeerEvent('online', hello.userId, name: hello.name));
      _flush(hello.userId);
    } catch (_) {
      // handshake failed / closed
    }
  }

  // ---- sending -------------------------------------------------------------
  /// Send now if the peer is connected, otherwise queue (store & forward).
  Future<bool> send(String userId, Map<String, dynamic> env, {bool queueIfOffline = true, String? refMsg}) async {
    final c = _conns[userId];
    if (c != null && !c.closed) {
      try { await c.sendEnvelope(env); return true; } catch (_) {}
    }
    if (queueIfOffline) AppDb.I.enqueue(userId, env, refMsg: refMsg);
    return false;
  }

  Future<void> _flushAll() async { for (final uid in _conns.keys.toList()) { await _flush(uid); } }

  Future<void> _flush(String userId) async {
    final c = _conns[userId];
    if (c == null || c.closed) return;
    for (final (id, env, _) in AppDb.I.outboxFor(userId)) {
      try { await c.sendEnvelope(env); AppDb.I.dequeue(id); } catch (_) { return; }
    }
  }

  Future<void> updateDisplayName(String n) async {
    displayName = n;
    await discovery?.updateName(n);
  }

  Future<void> disconnect(String userId) async => _conns[userId]?.close();

  Future<void> stop() async {
    _tick?.cancel();
    await _discSub?.cancel(); await _mpSub?.cancel(); await _mpFound?.cancel();
    for (final c in _conns.values.toList()) { await c.close(); }
    await discovery?.stop();
    await _server?.close();
    await Multipeer.stop();
  }
}
