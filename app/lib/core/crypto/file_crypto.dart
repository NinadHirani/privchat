import 'dart:typed_data';
import 'crypto.dart';

const chunkSize = 256 * 1024;

Uint8List fileIdFromHash(Uint8List plaintextHash) =>
    Crypto.I.blake2b(Crypto.concat([Crypto.utf8e('privchat-file-v1'), plaintextHash]), outLen: 16);

class FileKey {
  FileKey(this.key, this.fileId);
  final Uint8List key, fileId;
  factory FileKey.forHash(Uint8List hash) => FileKey(Crypto.I.random(32), fileIdFromHash(hash));
  String get fileIdB64 => Crypto.b64e(fileId);

  Uint8List _nonce(int i) =>
      Crypto.I.blake2b(Crypto.concat([Crypto.utf8e('chunk'), Crypto.u32be(i)]), outLen: 24, key: key);
  Uint8List _ad(int i) => Crypto.concat([fileId, Crypto.u32be(i)]);

  Uint8List encryptChunk(int i, Uint8List chunk) => Crypto.I.aeadEncrypt(chunk, _nonce(i), key, _ad(i));
  Uint8List decryptChunk(int i, Uint8List ct) => Crypto.I.aeadDecrypt(ct, _nonce(i), key, _ad(i));
}

/// Incremental BLAKE2b-32 over a whole file would need the streaming API; for
/// mobile-size files we hash in memory per chunk list. Keeps parity with reference.
Uint8List hashBytes(Uint8List data) => Crypto.I.blake2b(data, outLen: 32);
