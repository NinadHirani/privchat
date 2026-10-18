import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'link.dart';

class TcpLink implements PeerLink {
  TcpLink(this._socket) {
    _socket.setOption(SocketOption.tcpNoDelay, true);
    _sub = _socket.listen(
      (d) => _ctrl.add(d is Uint8List ? d : Uint8List.fromList(d)),
      onError: (e) { _ctrl.addError(e); _finish(); },
      onDone: _finish,
      cancelOnError: true,
    );
    remoteHost = _socket.remoteAddress.address;
  }
  final Socket _socket;
  late final StreamSubscription _sub;
  final _ctrl = StreamController<Uint8List>();
  final _done = Completer<void>();
  @override
  late final String? remoteHost;

  static Future<TcpLink> connect(String host, int port, {Duration timeout = const Duration(seconds: 6)}) async =>
      TcpLink(await Socket.connect(host, port, timeout: timeout));

  void _finish() {
    if (!_done.isCompleted) _done.complete();
    if (!_ctrl.isClosed) _ctrl.close();
  }

  @override
  Stream<Uint8List> get data => _ctrl.stream;
  @override
  Future<void> get done => _done.future;
  @override
  void send(Uint8List bytes) { try { _socket.add(bytes); } catch (_) { _finish(); } }
  @override
  Future<void> flush() async { try { await _socket.flush(); } catch (_) { _finish(); } }
  @override
  Future<void> close() async { try { await _sub.cancel(); await _socket.close(); } catch (_) {} _socket.destroy(); _finish(); }
  @override
  String get describe => 'tcp://$remoteHost:${_socket.remotePort}';
  @override
  bool get isIp => true;
}
