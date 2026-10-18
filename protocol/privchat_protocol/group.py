"""Group messaging with sender keys (Signal-style), fully offline.

Each member owns a SenderKey per group: (chain_key, Ed25519 signing key).
It is distributed to every other member over their pairwise E2EE session.

  mk  = BLAKE2b-32(key=ck, 0x01)      ck' = BLAKE2b-32(key=ck, 0x02)
  ad  = gid(16) || sender_user_id(utf8) || u32be(n)
  ct  = XChaCha20-Poly1305(mk, nonce, pt, ad)
  sig = Ed25519(sign_sk, "privchat-grp-v1" || gid || u32be(n) || nonce || ct)

Group state (name, members, admins) is a JSON document signed by an admin;
members accept version N+1 only if signed by an admin of version N.
Receivers tolerate up to MAX_SKIP missed messages (keys cached, then erased).
"""
import json, struct
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Tuple
from nacl import bindings as b
from .kdf import blake2b, b64e, b64d
from .identity import Identity, user_id_from_ed_pk

GRP_CONTEXT = b"privchat-grp-v1"
GRP_STATE_CONTEXT = b"privchat-grpstate-v1"
MAX_SKIP = 500

@dataclass
class SenderKey:
    gid: bytes
    sender_id: str
    chain_key: bytes
    sign_pk: bytes
    sign_sk: Optional[bytes] = None       # only present for our own key
    n: int = 0
    skipped: Dict[int, bytes] = field(default_factory=dict)

    @classmethod
    def generate(cls, gid: bytes, sender_id: str) -> "SenderKey":
        pk, sk = b.crypto_sign_keypair()
        return cls(gid, sender_id, b.randombytes(32), pk, sk)

    def distribution(self) -> dict:
        """What we send to other members (over pairwise E2EE)."""
        return {"gid": b64e(self.gid), "ck": b64e(self.chain_key), "spk": b64e(self.sign_pk), "n": self.n}

    @classmethod
    def from_distribution(cls, sender_id: str, d: dict) -> "SenderKey":
        return cls(b64d(d["gid"]), sender_id, b64d(d["ck"]), b64d(d["spk"]), None, int(d["n"]))

    @staticmethod
    def _step(ck):
        return blake2b(b"\x01", 32, key=ck), blake2b(b"\x02", 32, key=ck)

    def _ad(self, n):
        return self.gid + self.sender_id.encode() + struct.pack(">I", n)

    def encrypt(self, plaintext: bytes, nonce: Optional[bytes] = None) -> dict:
        assert self.sign_sk is not None
        mk, self.chain_key = self._step(self.chain_key)
        n = self.n
        self.n += 1
        nonce = b.randombytes(24) if nonce is None else nonce
        ct = b.crypto_aead_xchacha20poly1305_ietf_encrypt(plaintext, self._ad(n), nonce, mk)
        sig = b.crypto_sign(GRP_CONTEXT + self.gid + struct.pack(">I", n) + nonce + ct, self.sign_sk)[:64]
        return {"gid": b64e(self.gid), "n": n, "nonce": b64e(nonce), "ct": b64e(ct), "sig": b64e(sig)}

    def _key_for(self, n: int) -> bytes:
        if n in self.skipped:
            return self.skipped.pop(n)
        if n < self.n:
            raise ValueError("replayed or too-old group message")
        if n - self.n > MAX_SKIP:
            raise ValueError("too many skipped group messages")
        while self.n < n:
            mk, self.chain_key = self._step(self.chain_key)
            self.skipped[self.n] = mk
            self.n += 1
        mk, self.chain_key = self._step(self.chain_key)
        self.n += 1
        return mk

    def decrypt(self, msg: dict) -> bytes:
        n, nonce, ct, sig = int(msg["n"]), b64d(msg["nonce"]), b64d(msg["ct"]), b64d(msg["sig"])
        if b64d(msg["gid"]) != self.gid:
            raise ValueError("gid mismatch")
        if not Identity.verify(self.sign_pk, GRP_CONTEXT + self.gid + struct.pack(">I", n) + nonce + ct, sig):
            raise ValueError("bad group signature")
        mk = self._key_for(n)
        return b.crypto_aead_xchacha20poly1305_ietf_decrypt(ct, self._ad(n), nonce, mk)

def encrypt_group_message(sk: SenderKey, obj: dict) -> dict:
    return sk.encrypt(json.dumps(obj, separators=(",", ":"), sort_keys=True).encode())

def decrypt_group_message(sk: SenderKey, msg: dict) -> dict:
    return json.loads(sk.decrypt(msg).decode())

@dataclass
class GroupState:
    gid: bytes
    name: str
    version: int
    members: Dict[str, bytes]      # user_id -> ed_pk
    admins: List[str]
    created: int

    def canonical(self) -> bytes:
        return GRP_STATE_CONTEXT + json.dumps({
            "gid": b64e(self.gid), "name": self.name, "version": self.version,
            "members": {k: b64e(v) for k, v in sorted(self.members.items())},
            "admins": sorted(self.admins), "created": self.created,
        }, separators=(",", ":"), sort_keys=True).encode()

    def sign(self, admin: Identity) -> dict:
        assert admin.user_id in self.admins
        sig = admin.sign(self.canonical())
        return {"gid": b64e(self.gid), "name": self.name, "version": self.version,
                "members": {k: b64e(v) for k, v in sorted(self.members.items())},
                "admins": sorted(self.admins), "created": self.created,
                "signer": admin.user_id, "sig": b64e(sig)}

    @classmethod
    def verify(cls, doc: dict, previous: Optional["GroupState"]) -> "GroupState":
        st = cls(b64d(doc["gid"]), doc["name"], int(doc["version"]),
                 {k: b64d(v) for k, v in doc["members"].items()}, list(doc["admins"]), int(doc["created"]))
        signer = doc["signer"]
        if not set(st.admins) <= set(st.members):
            raise ValueError("admin not a member")
        for uid, pk in st.members.items():
            if user_id_from_ed_pk(pk) != uid:
                raise ValueError("member id/key mismatch")
        if previous is None:
            if st.version != 1 or signer not in st.admins:
                raise ValueError("initial state must be v1 signed by an admin")
            signer_pk = st.members[signer]
        else:
            if st.gid != previous.gid or st.version != previous.version + 1 or st.created != previous.created:
                raise ValueError("bad state transition")
            if signer not in previous.admins:
                raise ValueError("signer was not an admin")
            signer_pk = previous.members[signer]
        if not Identity.verify(signer_pk, st.canonical(), b64d(doc["sig"])):
            raise ValueError("bad group state signature")
        return st
