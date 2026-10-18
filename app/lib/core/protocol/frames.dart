import 'dart:typed_data';
import '../crypto/crypto.dart';

const kindHello = 0x01;
const kindEnc = 0x02;
const maxFrame = 16 * 1024 * 1024;

class Frame {
  Frame(this.kind, this.payload);
  final int kind;
  final Uint8List payload;
}

Uint8List encodeFrame(int kind, Uint8List payload) {
  final len = payload.length + 1;
  if (len > maxFrame) throw ArgumentError('frame too large');
  return Crypto.concat([Crypto.u32be(len), [kind], payload]);
}

/// Incremental decoder for a byte stream.
class FrameDecoder {
  final BytesBuilder _buf = BytesBuilder(copy: true);
  Uint8List _pending = Uint8List(0);

  List<Frame> feed(Uint8List data) {
    _buf.add(data);
    _pending = Crypto.concat([_pending, _buf.takeBytes()]);
    final out = <Frame>[];
    var off = 0;
    while (_pending.length - off >= 4) {
      final n = Crypto.readU32be(_pending, off);
      if (n > maxFrame || n < 1) throw FormatException('bad frame length $n');
      if (_pending.length - off < 4 + n) break;
      out.add(Frame(_pending[off + 4], Uint8List.sublistView(_pending, off + 5, off + 4 + n)));
      off += 4 + n;
    }
    if (off > 0) _pending = Uint8List.fromList(_pending.sublist(off));
    return out;
  }
}
