"""Long-term identity: one 32-byte seed -> Ed25519 signing key + X25519 DH key.

user_id       = base32(BLAKE2b-20(ed_pk))              (32 chars, no padding)
safety_number = 60 decimal digits derived from both parties' ed_pk (order independent)
"""
from dataclasses import dataclass
from nacl import bindings as b
from .kdf import blake2b, b32_nopad

def user_id_from_ed_pk(ed_pk: bytes) -> str:
    return b32_nopad(blake2b(ed_pk, 20))

def safety_number(ed_pk_a: bytes, ed_pk_b: bytes) -> str:
    lo, hi = sorted([ed_pk_a, ed_pk_b])
    h = blake2b(b"privchat-safety-v1" + lo + hi, 32)
    n = int.from_bytes(h, "big") % (10 ** 60)
    digits = str(n).zfill(60)
    return " ".join(digits[i:i + 5] for i in range(0, 60, 5))

@dataclass
class Identity:
    seed: bytes
    ed_pk: bytes
    ed_sk: bytes   # 64-byte libsodium secret key
    x_pk: bytes
    x_sk: bytes

    @classmethod
    def generate(cls) -> "Identity":
        return cls.from_seed(b.randombytes(32))

    @classmethod
    def from_seed(cls, seed: bytes) -> "Identity":
        assert len(seed) == 32
        ed_pk, ed_sk = b.crypto_sign_seed_keypair(seed)
        x_pk = b.crypto_sign_ed25519_pk_to_curve25519(ed_pk)
        x_sk = b.crypto_sign_ed25519_sk_to_curve25519(ed_sk)
        return cls(seed, ed_pk, ed_sk, x_pk, x_sk)

    @property
    def user_id(self) -> str:
        return user_id_from_ed_pk(self.ed_pk)

    def sign(self, msg: bytes) -> bytes:
        return b.crypto_sign(msg, self.ed_sk)[:64]

    @staticmethod
    def verify(ed_pk: bytes, msg: bytes, sig: bytes) -> bool:
        try:
            b.crypto_sign_open(sig + msg, ed_pk)
            return True
        except Exception:
            return False
