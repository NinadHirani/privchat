# PrivChat Protocol v1

Serverless, peer-to-peer, end-to-end encrypted messaging and calling over any local
IP network (Wi-Fi, hotspot, Wi-Fi Direct) or iOS Multipeer streams. No account,
no phone number, no cloud. Reference implementation: `protocol/` (Python, libsodium).
Test vectors: `protocol/test_vectors.json` — the Dart code must reproduce them exactly.

## Primitives (all libsodium)
| Purpose | Primitive |
|---|---|
| Identity signatures | Ed25519 |
| Key agreement | X25519 (identity key derived from Ed25519 seed) |
| Hash / KDF | BLAKE2b (keyed where noted) |
| AEAD | XChaCha20-Poly1305-IETF |
| Randomness | `randombytes` |

## Identity
- `seed` (32 B, in Keystore / Secure Enclave) → `ed_pk, ed_sk`; `x_pk, x_sk = ed→curve25519`.
- `user_id = base32_nopad(BLAKE2b-20(ed_pk))` (32 chars). Never changes. No PII.
- `safety_number = 60 digits` from `BLAKE2b-32("privchat-safety-v1" || min(pk) || max(pk)) mod 10^60`,
  shown as 12×5 digits and as QR. Users compare in person → defeats MITM permanently.

## Transport framing
`u32be(len) || kind(u8) || payload`, max 16 MiB.
`kind=1 HELLO` (JSON), `kind=2 ENC` (`u32be(counter) || nonce(24) || ciphertext`).

## Handshake (both online)
Each side sends exactly one HELLO:
`{"v":1,"ed":b64,"eph":b64,"ts":ms,"nonce":b64(16),"name":str,"sig":b64}`
`sig = Ed25519("privchat-hello-v1"||ed_pk||eph_pk||u64be(ts)||nonce||u16be(len(name))||name)`.
Reject: bad sig, |now−ts| > 10 min, name > 64 chars, own key.

Roles: A = smaller `user_id`. `dh1=DH(ephA,ephB) dh2=DH(ikA,ephB) dh3=DH(ephA,ikB)`.
`master=BLAKE2b-32("privchat-3dh-v1"||dh1||dh2||dh3)`, `sid=BLAKE2b-16("privchat-sid-v1"||ephA||ephB)`,
`ck_A2B=BLAKE2b-32(key=master,"A2B")`, `ck_B2A=BLAKE2b-32(key=master,"B2A")`. Ephemeral secrets erased.

Properties: mutual authentication, forward secrecy per connection, KCI-resistance (3DH),
identity hiding is **not** a goal on LAN (user_id is broadcast for discovery).

## Message ratchet
`mk=BLAKE2b-32(key=ck,0x01)`, `ck'=BLAKE2b-32(key=ck,0x02)`; old `ck` erased.
`ct = AEAD(mk, nonce=random24, ad = sid||u32be(n), pt)`; `pt = ptype(u8)||body`.
Counters strictly sequential per direction (TCP ordered) → replay/reorder rejected.
`ptype 1` = JSON envelope, `ptype 2` = file chunk `file_id(16)||u32be(i)||ct_i`.

## Envelopes (JSON, inside ptype 1)
`profile, chat, ack, typing, file.req, file.done, group.state, group.skey, group.msg,
status.sync, status.post, status.seen, call.offer, call.answer, call.ice, call.end, call.busy,
location.live, delete`. See `app/lib/core/protocol/envelope.dart`.

## Files (images / video / docs / voice notes / status media)
Random `key`(32); `file_id=BLAKE2b-16("privchat-file-v1"||BLAKE2b-32(plaintext))`.
Chunk 256 KiB: `nonce_i=BLAKE2b-24(key=key,"chunk"||u32be(i))`, `ad=file_id||u32be(i)`.
Meta (`key`, name, mime, size, hash) rides inside the E2EE channel; receiver verifies
full-file hash at the end. Resumable (`file.req from_chunk`). Relayable by group members.

## Groups (sender keys)
Per member per group: `chain_key`(32) + Ed25519 signing key, distributed pairwise (`group.skey`).
`ad=gid||sender_id||u32be(n)`, `sig=Ed25519("privchat-grp-v1"||gid||u32be(n)||nonce||ct)`.
Receivers tolerate ≤500 skipped messages. Membership doc signed by an admin; v+1 must be
signed by an admin of v. Leaving/removing a member ⇒ every remaining member rotates its sender key.

## Calls
WebRTC peer connection with **empty ICE server list** → host candidates only (works
offline on LAN/hotspot/Wi-Fi Direct). SDP/ICE carried inside the E2EE channel, so the
DTLS fingerprint is authenticated ⇒ no MITM on media. Opus audio, DTLS-SRTP.

## Storage
SQLCipher DB (key in Keystore/Secure Enclave), media encrypted at rest with per-file keys
stored in the DB, decrypted to a cache that is wiped on lock. Optional disappearing messages.

## Threat model summary
Protects against: network eavesdroppers, MITM (after safety-number check or TOFU pin),
replay, tampering, impersonation, non-admin group takeover, device-storage theft (locked).
Does **not** hide: that you are nearby and using PrivChat (user_id broadcast), message sizes/timing.
Does not protect a compromised/unlocked endpoint.
