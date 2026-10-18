"""Generate deterministic test vectors for the Dart implementation."""
import json, os, struct
from privchat_protocol import *
from privchat_protocol.kdf import b64e
from privchat_protocol.files import hash_file
from privchat_protocol.session import PT_JSON

seedA, seedB = bytes([1]*32), bytes([2]*32)
A, B = Identity.from_seed(seedA), Identity.from_seed(seedB)
v = {"identity": [], "session": {}, "group": {}, "file": {}}

for name, ident in (("A", A), ("B", B)):
    v["identity"].append({"name": name, "seed": b64e(ident.seed), "ed_pk": b64e(ident.ed_pk), "x_pk": b64e(ident.x_pk),
                          "user_id": ident.user_id, "sig_of_hello_world": b64e(ident.sign(b"hello world"))})
v["safety_number"] = safety_number(A.ed_pk, B.ed_pk)

# Session with fixed ephemeral keys (derive eph from fixed seeds)
from nacl import bindings as nb
SA, SB = Session(A, "Alice"), Session(B, "Bob")
SA.eph_sk = bytes([3]*32); SA.eph_pk = nb.crypto_scalarmult_base(SA.eph_sk)
SB.eph_sk = bytes([4]*32); SB.eph_pk = nb.crypto_scalarmult_base(SB.eph_sk)
ha = SA.hello(ts=1700000000000, nonce=bytes([5]*16)); hb = SB.hello(ts=1700000000001, nonce=bytes([6]*16))
SA.accept(hb, now_ms=1700000000000); SB.accept(ha, now_ms=1700000000000)
v["session"] = {
    "eph_sk_A": b64e(bytes([3]*32)), "eph_sk_B": b64e(bytes([4]*32)),
    "hello_A": ha.decode(), "hello_B": hb.decode(),
    "sid": b64e(SA.sid), "ck_A_send": b64e(SA._send_ck), "ck_B_send": b64e(SB._send_ck),
    "messages": [],
}
for i in range(3):
    nonce = bytes([10 + i]*24); body = json.dumps({"type": "chat", "text": f"msg {i}"}, separators=(",", ":"), sort_keys=True).encode()
    payload = SA.encrypt(PT_JSON, body, nonce=nonce)
    assert SB.decrypt(payload) == (PT_JSON, body)
    v["session"]["messages"].append({"dir": "A->B", "n": i, "nonce": b64e(nonce), "plaintext_json": body.decode(), "payload": b64e(payload)})
nonce = bytes([20]*24); body = b'{"type":"ack"}'
payload = SB.encrypt(PT_JSON, body, nonce=nonce); SA.decrypt(payload)
v["session"]["messages"].append({"dir": "B->A", "n": 0, "nonce": b64e(nonce), "plaintext_json": body.decode(), "payload": b64e(payload)})

# Group
gid = bytes([7]*16)
spk, ssk = nb.crypto_sign_seed_keypair(bytes([8]*32))
sk = SenderKey(gid, A.user_id, bytes([9]*32), spk, ssk)
gm = sk.encrypt(b'{"text":"hi group"}', nonce=bytes([11]*24))
v["group"] = {"gid": b64e(gid), "sender_id": A.user_id, "chain_key": b64e(bytes([9]*32)), "sign_seed": b64e(bytes([8]*32)),
              "sign_pk": b64e(spk), "message": gm, "plaintext": '{"text":"hi group"}'}
st = GroupState(gid, "Family", 1, {A.user_id: A.ed_pk, B.user_id: B.ed_pk}, [A.user_id], 1700000000000)
v["group"]["state_v1"] = st.sign(A)
v["group"]["state_canonical"] = st.canonical().decode()

# File
data = bytes(range(256)) * 1100   # 281600 bytes -> 2 chunks
h = hash_file(data); fk = FileKey(bytes([12]*32), file_id_from_hash(h))
v["file"] = {"plaintext_hex_prefix": data[:16].hex(), "plaintext_len": len(data), "hash": b64e(h), "file_id": b64e(fk.file_id), "key": b64e(fk.key),
             "chunk0_ct_blake2b": b64e(__import__("privchat_protocol.kdf", fromlist=["blake2b"]).blake2b(encrypt_chunk(fk, 0, data[:262144]), 32)),
             "chunk1_ct": b64e(encrypt_chunk(fk, 1, data[262144:]))}
out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "test_vectors.json")
json.dump(v, open(out_path, "w"), indent=1)
app_asset = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "app", "assets", "test_vectors.json")
if os.path.exists(os.path.dirname(app_asset)):
    json.dump(v, open(app_asset, "w"), indent=1)
print("vectors written to", out_path, ";", os.path.getsize(out_path), "bytes")
