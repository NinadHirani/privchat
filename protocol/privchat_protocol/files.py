"""Media / document transfer.

Every file gets a random 32-byte key. Chunks (256 KiB) are encrypted
independently so transfers are resumable and relayable by group members
without exposing content:

  nonce_i = BLAKE2b-24(key=file_key, "chunk" || u32be(i))     (deterministic, unique per i)
  ct_i    = XChaCha20-Poly1305(file_key, nonce_i, chunk_i, ad = file_id || u32be(i))
  file_id = BLAKE2b-16(plaintext_hash)      where plaintext_hash = BLAKE2b-32(whole plaintext)

The file meta message {id, name, size, mime, chunks, key, hash} travels inside
the pairwise/group E2EE channel; only ciphertext chunks hit the wire.
"""
import struct
from dataclasses import dataclass
from nacl import bindings as b
from .kdf import blake2b

CHUNK_SIZE = 256 * 1024

def file_id_from_hash(plaintext_hash: bytes) -> bytes:
    return blake2b(b"privchat-file-v1" + plaintext_hash, 16)

@dataclass
class FileKey:
    key: bytes
    file_id: bytes

    @classmethod
    def new(cls, plaintext_hash: bytes) -> "FileKey":
        return cls(b.randombytes(32), file_id_from_hash(plaintext_hash))

def _nonce(key: bytes, i: int) -> bytes:
    return blake2b(b"chunk" + struct.pack(">I", i), 24, key=key)

def encrypt_chunk(fk: FileKey, i: int, chunk: bytes) -> bytes:
    return b.crypto_aead_xchacha20poly1305_ietf_encrypt(chunk, fk.file_id + struct.pack(">I", i), _nonce(fk.key, i), fk.key)

def decrypt_chunk(fk: FileKey, i: int, ct: bytes) -> bytes:
    return b.crypto_aead_xchacha20poly1305_ietf_decrypt(ct, fk.file_id + struct.pack(">I", i), _nonce(fk.key, i), fk.key)

def hash_file(data: bytes) -> bytes:
    return blake2b(data, 32)
