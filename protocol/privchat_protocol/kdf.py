"""Thin wrappers around libsodium primitives so every derivation is in one place."""
import base64
from nacl import bindings as b

PROTOCOL_VERSION = 1

def blake2b(data: bytes, outlen: int = 32, key: bytes = b"") -> bytes:
    return b.crypto_generichash_blake2b_salt_personal(data, digest_size=outlen, key=key)

def b64e(x: bytes) -> str:
    return base64.b64encode(x).decode("ascii")

def b64d(s: str) -> bytes:
    return base64.b64decode(s)

def b32_nopad(x: bytes) -> str:
    return base64.b32encode(x).decode("ascii").rstrip("=")
