import 'dart:async';
import 'dart:typed_data';
import '../crypto/crypto.dart';
import '../crypto/identity.dart';
import '../crypto/session.dart';
import '../protocol/frames.dart';
import 'link.dart';

typedef EnvelopeHandler = void Function(PeerConnection c, Map<String, dynamic> env);
typedef ChunkHandler = void Function(PeerConnection c, Uint8List fileId, int index, Uint8List ct);

/// One authenticated, encrypted connection to one peer over any PeerLink.
class PeerConnection {
  PeerConnection({required this.link, required Identity identity, required String myName, required this.outgoing})
      : _session = Session(identity, myName);
  final PeerLink link;
  final bool outgoing;
  final Session _session;
  final _decoder = FrameDecoder();
  final _established = Completer<Hello>();
  StreamSubscription? _sub;
  bool _closed = false;
  int lastActivity = DateTime.now().millisecondsSinceEpoch;

  Future<Hello> get established => _established.future;
  bool get isEstablished => _session.established;
  Hello? get peer => _session.peer;
  String get peerId => _session.peer!.userId;
  String get peerName => _session.peer!.name;
  Uint8List get peerEdPk => _session.peer!.edPk;
  bool get isIp => link.isIp;
  String? get remoteHost => link.remoteHost;

  EnvelopeHandler? onEnvelope;
  ChunkHandler? onChunk;
  void Function(PeerConnection c)? onClosed;

  // Serialize all sends: the ratchet counter must match wire order.
  Future<void> _sendLock = Future.value();

  void start() {
    link.send(encodeFrame(kindHello, _session.hello()));
    _sub = link.data.listen(_onData, onError: (_) => close(), onDone: close);
    link.done.then((_) => close());
    // handshake timeout
    Future.delayed(const Duration(seconds: 8), () { if (!isEstablished) close(); });
  }

  void _onData(Uint8List d) {
    lastActivity = DateTime.now().millisecondsSinceEpoch;
    List<Frame> frames;
    try { frames = _decoder.feed(d); } catch (_) { close(); return; }
    for (final f in frames) {
      try {
        if (f.kind == kindHello) {
          if (isEstablished) throw ProtocolException('duplicate hello');
          final h = _session.accept(f.payload);
          if (!_established.isCompleted) _established.complete(h);
        } else if (f.kind == kindEnc) {
          if (!isEstablished) throw ProtocolException('data before handshake');
          final (pt, body) = _session.decrypt(f.payload);
          if (pt == ptJson) {
            onEnvelope?.call(this, Session.decodeJson(body));
          } else if (pt == ptFileChunk) {
            if (body.length < 20) throw ProtocolException('short chunk');
            onChunk?.call(this, body.sublist(0, 16), Crypto.readU32be(body, 16), body.sublist(20));
          }
        }
      } catch (e) {
        // Any protocol violation = tear down. Never try to "recover" a broken ratchet.
        if (!_established.isCompleted) _established.completeError(e);
        close();
        return;
      }
    }
  }

  Future<void> sendEnvelope(Map<String, dynamic> env) => _enqueue(() async {
        if (_closed || !isEstablished) throw StateError('connection not ready');
        link.send(encodeFrame(kindEnc, _session.encryptJson(env)));
      });

  Future<void> sendChunk(Uint8List fileId, int index, Uint8List ct) => _enqueue(() async {
        if (_closed || !isEstablished) throw StateError('connection not ready');
        link.send(encodeFrame(kindEnc, _session.encrypt(ptFileChunk, Crypto.concat([fileId, Crypto.u32be(index), ct]))));
        await link.flush();
      });

  Future<void> _enqueue(Future<void> Function() op) {
    final next = _sendLock.then((_) => op());
    _sendLock = next.catchError((_) {});
    return next;
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _sub?.cancel();
    await link.close();
    if (!_established.isCompleted) _established.completeError(StateError('closed'));
    onClosed?.call(this);
  }

  bool get closed => _closed;
}
