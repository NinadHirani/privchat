import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../crypto/crypto.dart';
import '../crypto/file_crypto.dart';
import '../../models/models.dart';

/// Media is stored encrypted at rest (same per-file key as on the wire).
/// Decrypted copies only ever live in the cache dir, which is wiped on lock/exit.
class MediaStore {
  static Directory? _vault, _cache;

  static Future<void> init() async {
    _vault = Directory(p.join((await getApplicationSupportDirectory()).path, 'vault'))..createSync(recursive: true);
    _cache = Directory(p.join((await getTemporaryDirectory()).path, 'pc_open'))..createSync(recursive: true);
  }

  static String vaultPath(String attId) => p.join(_vault!.path, attId.replaceAll('/', '_').replaceAll('+', '-'));

  /// Encrypt plaintext bytes into the vault as sequential ciphertext chunks. Returns (attachment, chunkCount).
  static Future<Attachment> importBytes(Uint8List data, {required String name, required String mime, Uint8List? thumb}) async {
    final hash = hashBytes(data);
    final fk = FileKey.forHash(hash);
    final chunks = (data.length + chunkSize - 1) ~/ chunkSize;
    final att = Attachment(id: fk.fileIdB64, fileId: fk.fileId, name: name, mime: mime, size: data.length, key: fk.key,
        hash: hash, chunks: chunks == 0 ? 1 : chunks, localPath: vaultPath(fk.fileIdB64), receivedChunks: chunks == 0 ? 1 : chunks,
        state: 'done', thumb: thumb);
    final sink = File(att.localPath!).openWrite();
    for (var i = 0; i < att.chunks; i++) {
      final ct = fk.encryptChunk(i, Uint8List.sublistView(data, i * chunkSize, ((i + 1) * chunkSize).clamp(0, data.length)));
      sink.add(Crypto.u32be(ct.length));
      sink.add(ct);
    }
    await sink.close();
    return att;
  }

  static Future<Attachment> importFile(File f, {required String name, required String mime, Uint8List? thumb}) async =>
      importBytes(await f.readAsBytes(), name: name, mime: mime, thumb: thumb);

  /// Read ciphertext chunk i from vault (for sending). Null if missing.
  static Future<Uint8List?> readCipherChunk(Attachment a, int i) async {
    final f = File(a.localPath ?? vaultPath(a.id));
    if (!f.existsSync()) return null;
    final raf = await f.open();
    try {
      var idx = 0;
      while (true) {
        final lenB = await raf.read(4);
        if (lenB.length < 4) return null;
        final len = Crypto.readU32be(Uint8List.fromList(lenB));
        if (idx == i) return Uint8List.fromList(await raf.read(len));
        await raf.setPosition(await raf.position() + len);
        idx++;
      }
    } finally {
      await raf.close();
    }
  }

  /// Receiver side: append ciphertext chunks in order into a .part file, then finalise.
  static Future<void> appendCipherChunk(Attachment a, int i, Uint8List ct) async {
    final f = File('${vaultPath(a.id)}.part');
    await f.writeAsBytes(Crypto.concat([Crypto.u32be(ct.length), ct]), mode: FileMode.append, flush: true);
  }

  /// Verify whole-file hash and move .part -> vault. Returns false if hash mismatch.
  static Future<bool> finalize(Attachment a) async {
    final part = File('${vaultPath(a.id)}.part');
    if (!part.existsSync()) return false;
    final fk = FileKey(a.key, a.fileId);
    final raf = await part.open();
    final plain = BytesBuilder(copy: false);
    try {
      for (var i = 0; i < a.chunks; i++) {
        final lenB = await raf.read(4);
        if (lenB.length < 4) return false;
        final ct = Uint8List.fromList(await raf.read(Crypto.readU32be(Uint8List.fromList(lenB))));
        plain.add(fk.decryptChunk(i, ct));
      }
    } catch (_) {
      return false;
    } finally {
      await raf.close();
    }
    final ok = Crypto.constEq(hashBytes(plain.takeBytes()), a.hash);
    if (ok) await part.rename(vaultPath(a.id));
    else part.deleteSync();
    return ok;
  }

  static Future<void> discardPartial(Attachment a) async {
    final part = File('${vaultPath(a.id)}.part');
    if (part.existsSync()) part.deleteSync();
  }

  static int partialChunkCount(Attachment a) {
    final part = File('${vaultPath(a.id)}.part');
    if (!part.existsSync()) return 0;
    final bytes = part.readAsBytesSync();
    var off = 0, n = 0;
    while (off + 4 <= bytes.length) {
      final len = Crypto.readU32be(bytes, off);
      if (off + 4 + len > bytes.length) break;
      off += 4 + len; n++;
    }
    return n;
  }

  /// Decrypt whole attachment into memory.
  static Future<Uint8List?> readPlain(Attachment a) async {
    final f = File(a.localPath ?? vaultPath(a.id));
    if (!f.existsSync()) return null;
    final fk = FileKey(a.key, a.fileId);
    final bytes = await f.readAsBytes();
    final out = BytesBuilder(copy: false);
    var off = 0, i = 0;
    while (off + 4 <= bytes.length) {
      final len = Crypto.readU32be(bytes, off);
      out.add(fk.decryptChunk(i++, Uint8List.sublistView(bytes, off + 4, off + 4 + len)));
      off += 4 + len;
    }
    return out.takeBytes();
  }

  /// Decrypt to cache and return a real file path (for video_player / open_filex / share).
  static Future<File?> openPlain(Attachment a) async {
    final ext = p.extension(a.name).isEmpty ? '' : p.extension(a.name);
    final out = File(p.join(_cache!.path, '${a.id.replaceAll('/', '_').replaceAll('+', '-')}$ext'));
    if (out.existsSync() && out.lengthSync() == a.size) return out;
    final plain = await readPlain(a);
    if (plain == null) return null;
    await out.writeAsBytes(plain, flush: true);
    return out;
  }

  static Future<void> wipeCache() async {
    if (_cache == null) return;
    for (final f in _cache!.listSync()) { try { f.deleteSync(recursive: true); } catch (_) {} }
  }

  static Future<void> wipeAll() async {
    await wipeCache();
    if (_vault != null && _vault!.existsSync()) _vault!.deleteSync(recursive: true);
  }

  static Future<void> deleteAttachment(Attachment a) async {
    final f = File(a.localPath ?? vaultPath(a.id));
    if (f.existsSync()) f.deleteSync();
    await discardPartial(a);
  }

  static Future<int> vaultSize() async {
    var n = 0;
    for (final f in _vault!.listSync()) { if (f is File) n += f.lengthSync(); }
    return n;
  }
}
