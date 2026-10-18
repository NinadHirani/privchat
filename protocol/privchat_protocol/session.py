"""Authenticated, forward-secret pairwise session (both peers online, P2P).

Handshake: each side sends one signed HELLO carrying its identity (ed_pk) and a
fresh ephemeral X25519 key. Roles: A = lexicographically smaller user_id.

  dh1 = DH(ephA, ephB)       forward secrecy
  dh2 = DH(ikA,  ephB)       authenticates A
  dh3 = DH(ephA, ikB)        authenticates B
  master  = BLAKE2b-32("privchat-3dh-v1" || dh1 || dh2 || dh3)
  sid     = BLAKE2b-16("privchat-sid-v1" || ephA_pk || ephB_pk)
  ck_A2B  = BLAKE2b-32(key=master, "A2B")     ck_B2A = BLAKE2b-32(key=master, "B2A")

Per message (symmetric hash ratchet, old keys erased):
  mk = BLAKE2b-32(key=ck, 0x01)    ck' = BLAKE2b-32(key=ck, 0x02)
  ct = XChaCha20-Poly1305-IETF(mk, nonce=random24, ad = sid || u32be(counter), pt)

Plaintext := ptype(u8) || body.   ptype 0x01 = JSON control/chat, 0x02 = file chunk.
Counters are strictly increasing per direction; anything else is rejected.
"""
import json, struct, time
from dataclasses import dataclass
from typing import Optional, Tuple
from nacl import bindings as b
from .kdf import blake2b, b64e, b64d, PROTOCOL_VERSION
from .identity import Identity, user_id_from_ed_pk

HELLO_CONTEXT = b"privchat-hello-v1"
HELLO_MAX_SKEW_MS = 10 * 60 * 1000   # 10 minutes (devices offline often have bad clocks; generous)
PT_JSON = 0x01
PT_FILE_CHUNK = 0x02

@dataclass
class Hello:
    ed_pk: bytes
    eph_pk: bytes
    ts: int
    nonce: bytes
    name: str
    sig: bytes

    @property
    def user_id(self) -> str:
        return user_id_from_ed_pk(self.ed_pk)

def _hello_signing_bytes(ed_pk, eph_pk, ts, nonce, name) -> bytes:
    nb = name.encode("utf-8")
    return HELLO_CONTEXT + ed_pk + eph_pk + struct.pack(">Q", ts) + nonce + struct.pack(">H", len(nb)) + nb

def build_hello(ident: Identity, eph_pk: bytes, name: str, ts: Optional[int] = None, nonce: Optional[bytes] = None) -> Tuple[Hello, bytes]:
    ts = int(time.time() * 1000) if ts is None else ts
    nonce = b.randombytes(16) if nonce is None else nonce
    sig = ident.sign(_hello_signing_bytes(ident.ed_pk, eph_pk, ts, nonce, name))
    h = Hello(ident.ed_pk, eph_pk, ts, nonce, name, sig)
    payload = json.dumps({
        "v": PROTOCOL_VERSION, "ed": b64e(h.ed_pk), "eph": b64e(h.eph_pk),
        "ts": ts, "nonce": b64e(nonce), "name": name, "sig": b64e(sig),
    }, separators=(",", ":"), sort_keys=True).encode()
    return h, payload

def verify_hello(payload: bytes, now_ms: Optional[int] = None) -> Hello:
    d = json.loads(payload.decode("utf-8"))
    if d.get("v") != PROTOCOL_VERSION:
        raise ValueError("unsupported protocol version")
    h = Hello(b64d(d["ed"]), b64d(d["eph"]), int(d["ts"]), b64d(d["nonce"]), str(d["name"]), b64d(d["sig"]))
    if len(h.ed_pk) != 32 or len(h.eph_pk) != 32 or len(h.nonce) != 16 or len(h.sig) != 64:
        raise ValueError("bad hello field lengths")
    if len(h.name) > 64:
        raise ValueError("name too long")
    if not Identity.verify(h.ed_pk, _hello_signing_bytes(h.ed_pk, h.eph_pk, h.ts, h.nonce, h.name), h.sig):
        raise ValueError("bad hello signature")
    now = int(time.time() * 1000) if now_ms is None else now_ms
    if abs(now - h.ts) > HELLO_MAX_SKEW_MS:
        raise ValueError("hello timestamp outside allowed skew")
    return h

class Session:
    def __init__(self, ident: Identity, name: str = ""):
        self.ident = ident
        self.name = name
        self.eph_pk, self.eph_sk = b.crypto_box_keypair()
        self.peer: Optional[Hello] = None
        self.sid: Optional[bytes] = None
        self._send_ck: Optional[bytes] = None
        self._recv_ck: Optional[bytes] = None
        self.send_n = 0
        self.recv_n = 0

    # --- handshake -------------------------------------------------------
    def hello(self, ts=None, nonce=None) -> bytes:
        _, payload = build_hello(self.ident, self.eph_pk, self.name, ts, nonce)
        return payload

    def accept(self, peer_hello_payload: bytes, now_ms=None) -> Hello:
        h = verify_hello(peer_hello_payload, now_ms)
        if h.ed_pk == self.ident.ed_pk:
            raise ValueError("refusing to talk to self")
        self.peer = h
        self._derive(h)
        return h

    def _derive(self, h: Hello):
        my_id, peer_id = self.ident.user_id, h.user_id
        i_am_a = my_id < peer_id
        peer_ik = b.crypto_sign_ed25519_pk_to_curve25519(h.ed_pk)
        dh1 = b.crypto_scalarmult(self.eph_sk, h.eph_pk)
        if i_am_a:
            dh2 = b.crypto_scalarmult(self.ident.x_sk, h.eph_pk)   # DH(ikA, ephB)
            dh3 = b.crypto_scalarmult(self.eph_sk, peer_ik)        # DH(ephA, ikB)
            eph_a, eph_b = self.eph_pk, h.eph_pk
        else:
            dh2 = b.crypto_scalarmult(self.eph_sk, peer_ik)        # DH(ephB, ikA) == DH(ikA, ephB)
            dh3 = b.crypto_scalarmult(self.ident.x_sk, h.eph_pk)   # DH(ikB, ephA) == DH(ephA, ikB)
            eph_a, eph_b = h.eph_pk, self.eph_pk
        master = blake2b(b"privchat-3dh-v1" + dh1 + dh2 + dh3, 32)
        self.sid = blake2b(b"privchat-sid-v1" + eph_a + eph_b, 16)
        ck_a2b = blake2b(b"A2B", 32, key=master)
        ck_b2a = blake2b(b"B2A", 32, key=master)
        self._send_ck, self._recv_ck = (ck_a2b, ck_b2a) if i_am_a else (ck_b2a, ck_a2b)
        # erase ephemeral secret: forward secrecy from here on
        self.eph_sk = b"\x00" * 32

    @property
    def established(self) -> bool:
        return self.sid is not None

    # --- ratchet ---------------------------------------------------------
    @staticmethod
    def _step(ck: bytes) -> Tuple[bytes, bytes]:
        mk = blake2b(b"\x01", 32, key=ck)
        nck = blake2b(b"\x02", 32, key=ck)
        return mk, nck

    def _ad(self, n: int) -> bytes:
        return self.sid + struct.pack(">I", n)

    def encrypt(self, ptype: int, body: bytes, nonce: Optional[bytes] = None) -> bytes:
        """Returns ENC frame payload: u32 counter || nonce || ct."""
        assert self.established
        mk, self._send_ck = self._step(self._send_ck)
        n = self.send_n
        self.send_n += 1
        nonce = b.randombytes(24) if nonce is None else nonce
        ct = b.crypto_aead_xchacha20poly1305_ietf_encrypt(bytes([ptype]) + body, self._ad(n), nonce, mk)
        return struct.pack(">I", n) + nonce + ct

    def decrypt(self, payload: bytes) -> Tuple[int, bytes]:
        assert self.established
        if len(payload) < 4 + 24 + 16:
            raise ValueError("short payload")
        (n,) = struct.unpack(">I", payload[:4])
        if n != self.recv_n:
            raise ValueError(f"counter mismatch: expected {self.recv_n}, got {n}")
        nonce, ct = payload[4:28], payload[28:]
        mk, next_ck = self._step(self._recv_ck)
        pt = b.crypto_aead_xchacha20poly1305_ietf_decrypt(ct, self._ad(n), nonce, mk)  # raises on tamper
        self._recv_ck = next_ck
        self.recv_n += 1
        return pt[0], pt[1:]

    # --- convenience -----------------------------------------------------
    def encrypt_json(self, obj: dict) -> bytes:
        return self.encrypt(PT_JSON, json.dumps(obj, separators=(",", ":"), sort_keys=True).encode())

    def decrypt_json(self, payload: bytes) -> dict:
        pt, body = self.decrypt(payload)
        if pt != PT_JSON:
            raise ValueError("not a JSON plaintext")
        return json.loads(body.decode("utf-8"))
