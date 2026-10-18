import json, os, socket, struct, threading, pytest
from nacl import bindings as b
from privchat_protocol import *
from privchat_protocol.session import PT_JSON, PT_FILE_CHUNK, HELLO_MAX_SKEW_MS
from privchat_protocol.files import CHUNK_SIZE, hash_file
from privchat_protocol.group import MAX_SKIP

# ---------- identity ----------
def test_identity_deterministic_from_seed():
    s = bytes(range(32))
    a, b2 = Identity.from_seed(s), Identity.from_seed(s)
    assert a.ed_pk == b2.ed_pk and a.x_pk == b2.x_pk and a.user_id == b2.user_id
    assert len(a.user_id) == 32 and a.user_id.isupper() or a.user_id.isalnum()

def test_safety_number_symmetric_and_format():
    a, c = Identity.generate(), Identity.generate()
    sn = safety_number(a.ed_pk, c.ed_pk)
    assert sn == safety_number(c.ed_pk, a.ed_pk)
    parts = sn.split(" ")
    assert len(parts) == 12 and all(len(p) == 5 and p.isdigit() for p in parts)
    assert sn != safety_number(a.ed_pk, Identity.generate().ed_pk)

def test_signature_roundtrip_and_tamper():
    a = Identity.generate()
    sig = a.sign(b"hi")
    assert Identity.verify(a.ed_pk, b"hi", sig)
    assert not Identity.verify(a.ed_pk, b"hi!", sig)
    assert not Identity.verify(Identity.generate().ed_pk, b"hi", sig)

# ---------- framing ----------
def test_frame_roundtrip_and_fragmentation():
    frames = [encode_frame(KIND_HELLO, b'{"x":1}'), encode_frame(KIND_ENC, os.urandom(1000)), encode_frame(KIND_ENC, b"")]
    blob = b"".join(frames)
    dec = FrameDecoder()
    out = []
    for i in range(0, len(blob), 7):          # feed in awkward pieces
        dec.feed(blob[i:i + 7]); out.extend(dec.frames())
    assert [f.kind for f in out] == [KIND_HELLO, KIND_ENC, KIND_ENC]
    assert out[1].payload == frames[1][5:]

def test_frame_rejects_oversize():
    with pytest.raises(ValueError):
        encode_frame(KIND_ENC, b"x" * (16 * 1024 * 1024))
    d = FrameDecoder(); d.feed(struct.pack(">I", 0xFFFFFFFF))
    with pytest.raises(ValueError):
        list(d.frames())

# ---------- session ----------
def make_pair(name_a="Alice", name_b="Bob"):
    A, B = Session(Identity.generate(), name_a), Session(Identity.generate(), name_b)
    ha, hb = A.hello(), B.hello()
    A.accept(hb); B.accept(ha)
    return A, B

def test_handshake_agrees():
    A, B = make_pair()
    assert A.sid == B.sid and A._send_ck == B._recv_ck and A._recv_ck == B._send_ck
    assert A.peer.name == "Bob" and B.peer.name == "Alice"
    assert A.eph_sk == b"\x00" * 32   # ephemeral erased

def test_messages_both_directions_many():
    A, B = make_pair()
    for i in range(200):
        assert B.decrypt_json(A.encrypt_json({"i": i})) == {"i": i}
        assert A.decrypt_json(B.encrypt_json({"r": i})) == {"r": i}

def test_tamper_detected():
    A, B = make_pair()
    p = bytearray(A.encrypt_json({"m": "x"})); p[-1] ^= 1
    with pytest.raises(Exception):
        B.decrypt(bytes(p))

def test_replay_and_reorder_rejected():
    A, B = make_pair()
    p1, p2 = A.encrypt_json({"a": 1}), A.encrypt_json({"a": 2})
    B.decrypt(p1)
    with pytest.raises(ValueError):
        B.decrypt(p1)            # replay
    A2, B2 = make_pair()
    q1, q2 = A2.encrypt_json({"a": 1}), A2.encrypt_json({"a": 2})
    with pytest.raises(ValueError):
        B2.decrypt(q2)           # out of order

def test_mitm_cannot_impersonate():
    """Mallory relays Alice's HELLO but substitutes her own ephemeral: signature must fail."""
    A = Session(Identity.generate(), "Alice")
    M = Session(Identity.generate(), "Mallory")
    d = json.loads(A.hello()); d["eph"] = json.loads(M.hello())["eph"]
    with pytest.raises(ValueError, match="signature"):
        verify_hello(json.dumps(d).encode())

def test_hello_rejects_stale_and_self():
    A = Session(Identity.generate(), "A")
    with pytest.raises(ValueError, match="skew"):
        verify_hello(A.hello(ts=1000), now_ms=1000 + HELLO_MAX_SKEW_MS + 1)
    with pytest.raises(ValueError, match="self"):
        A.accept(A.hello())

def test_forward_secrecy_keys_change():
    A, B = make_pair()
    k0 = A._send_ck; A.encrypt_json({}); assert A._send_ck != k0

def test_file_chunk_ptype():
    A, B = make_pair()
    body = os.urandom(16) + struct.pack(">I", 3) + b"data"
    pt, out = B.decrypt(A.encrypt(PT_FILE_CHUNK, body))
    assert pt == PT_FILE_CHUNK and out == body

# ---------- real TCP two-peer simulation ----------
def test_over_real_tcp_sockets():
    srv = socket.socket(); srv.bind(("127.0.0.1", 0)); srv.listen(1)
    port = srv.getsockname()[1]
    received = {}

    def server():
        conn, _ = srv.accept()
        S = Session(Identity.generate(), "Server")
        dec = FrameDecoder()
        conn.sendall(encode_frame(KIND_HELLO, S.hello()))
        while "done" not in received:
            data = conn.recv(65536)
            if not data: break
            dec.feed(data)
            for f in dec.frames():
                if f.kind == KIND_HELLO: S.accept(f.payload)
                else:
                    m = S.decrypt_json(f.payload); received[m["id"]] = m
                    conn.sendall(encode_frame(KIND_ENC, S.encrypt_json({"type": "ack", "id": m["id"]})))
                    if m.get("last"): received["done"] = True
        conn.close()

    t = threading.Thread(target=server, daemon=True); t.start()
    cli = socket.create_connection(("127.0.0.1", port))
    C = Session(Identity.generate(), "Client"); dec = FrameDecoder()
    cli.sendall(encode_frame(KIND_HELLO, C.hello()))
    acks = 0
    while not C.established:
        dec.feed(cli.recv(65536))
        for f in dec.frames():
            assert f.kind == KIND_HELLO; C.accept(f.payload)
    for i in range(50):
        cli.sendall(encode_frame(KIND_ENC, C.encrypt_json({"type": "chat", "id": i, "text": "hello %d" % i, "last": i == 49})))
    while acks < 50:
        dec.feed(cli.recv(65536))
        for f in dec.frames():
            assert C.decrypt_json(f.payload)["type"] == "ack"; acks += 1
    t.join(2)
    assert received[49]["text"] == "hello 49" and len([k for k in received if k != "done"]) == 50

# ---------- groups ----------
def test_group_sender_key_roundtrip_skip_and_replay():
    gid = os.urandom(16)
    alice = Identity.generate()
    mine = SenderKey.generate(gid, alice.user_id)
    theirs = SenderKey.from_distribution(alice.user_id, mine.distribution())
    msgs = [encrypt_group_message(mine, {"t": i}) for i in range(6)]
    assert decrypt_group_message(theirs, msgs[0]) == {"t": 0}
    assert decrypt_group_message(theirs, msgs[3]) == {"t": 3}   # skip 1,2
    assert decrypt_group_message(theirs, msgs[1]) == {"t": 1}   # late arrival OK
    with pytest.raises(ValueError):
        decrypt_group_message(theirs, msgs[1])                    # replay
    tampered = dict(msgs[4]); tampered["ct"] = msgs[5]["ct"]
    with pytest.raises(ValueError, match="signature"):
        decrypt_group_message(theirs, tampered)
    far = dict(msgs[5]); far["n"] = 10_000
    with pytest.raises(ValueError, match="signature"):             # sig covers n
        decrypt_group_message(theirs, far)

def test_group_state_admin_chain():
    a, c, m = Identity.generate(), Identity.generate(), Identity.generate()
    gid = os.urandom(16)
    s1 = GroupState(gid, "Family", 1, {a.user_id: a.ed_pk, c.user_id: c.ed_pk}, [a.user_id], 1700000000000)
    v1 = GroupState.verify(s1.sign(a), None)
    s2 = GroupState(gid, "Family", 2, {**s1.members, m.user_id: m.ed_pk}, [a.user_id], 1700000000000)
    v2 = GroupState.verify(s2.sign(a), v1)
    assert m.user_id in v2.members
    # non-admin cannot update
    s3 = GroupState(gid, "Hacked", 3, v2.members, [c.user_id, a.user_id], 1700000000000)
    with pytest.raises(ValueError, match="admin"):      # c self-promotes & signs: rejected
        GroupState.verify(s3.sign(c), v2)
    forged = s3.sign(a); forged["signer"] = c.user_id    # real admin sig, wrong signer claim
    with pytest.raises(ValueError, match="admin"):
        GroupState.verify(forged, v2)
    # version skip rejected
    s4 = GroupState(gid, "Family", 4, v2.members, [a.user_id], 1700000000000)
    with pytest.raises(ValueError, match="transition"):
        GroupState.verify(s4.sign(a), v2)

# ---------- files ----------
def test_file_chunks_roundtrip_and_binding():
    data = os.urandom(CHUNK_SIZE * 2 + 1234)
    fk = FileKey.new(hash_file(data))
    chunks = [data[i:i + CHUNK_SIZE] for i in range(0, len(data), CHUNK_SIZE)]
    cts = [encrypt_chunk(fk, i, c) for i, c in enumerate(chunks)]
    assert b"".join(decrypt_chunk(fk, i, ct) for i, ct in enumerate(cts)) == data
    with pytest.raises(Exception):
        decrypt_chunk(fk, 1, cts[0])     # chunk index swap detected
    with pytest.raises(Exception):
        decrypt_chunk(FileKey(fk.key, os.urandom(16)), 0, cts[0])   # wrong file id
