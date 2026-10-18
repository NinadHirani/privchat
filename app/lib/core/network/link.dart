import 'dart:async';
import 'dart:typed_data';

/// A reliable, ordered byte pipe to one peer. TCP socket, or an iOS Multipeer stream.
abstract class PeerLink {
  Stream<Uint8List> get data;
  Future<void> get done;
  void send(Uint8List bytes);
  /// Resolves when buffered data has been handed to the OS (back-pressure for file streaming).
  Future<void> flush();
  Future<void> close();
  String get describe;
  /// True if this link carries IP traffic (WebRTC calls possible).
  bool get isIp;
  String? get remoteHost;
}
