#!/usr/bin/env python3
"""
PrivChat desktop test peer — speaks the exact wire protocol of the mobile app.
Use it to debug a phone from a laptop on the same Wi-Fi/hotspot (no internet needed).

  python3 tools/peer_cli.py --name Laptop            # announce + accept connections
  python3 tools/peer_cli.py --name Laptop --dial 192.168.1.23:40123

Type a line + Enter to send it to every connected peer. Ctrl+C to quit.
Identity is kept in ~/.privchat_cli_seed (delete it for a fresh identity).
"""
import argparse, json, os, socket, sys, threading, time, uuid
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from privchat_protocol import Identity, Session, encode_frame, FrameDecoder, KIND_HELLO, KIND_ENC, safety_number

UDP_PORT = 47474

class Peer:
    def __init__(self, ident, name, sock, log):
        self.s, self.sess, self.log = sock, Session(ident, name), log
        self.lock = threading.Lock()
        self.ready = threading.Event()

    def run(self, on_env):
        self.s.sendall(encode_frame(KIND_HELLO, self.sess.hello()))
        dec = FrameDecoder()
        try:
            while True:
                d = self.s.recv(65536)
                if not d: break
                dec.feed(d)
                for f in dec.frames():
                    if f.kind == KIND_HELLO:
                        h = self.sess.accept(f.payload)
                        self.log(f"✔ secure session with {h.name} ({h.user_id[:8]}…)\n  safety number: "
                                 f"{safety_number(self.sess.ident.ed_pk, h.ed_pk)}")
                        self.ready.set()
                    else:
                        pt, body = self.sess.decrypt(f.payload)
                        if pt == 1: on_env(self, json.loads(body))
        except Exception as e:
            self.log(f"connection closed: {e}")
        finally:
            self.s.close()

    def send(self, env):
        with self.lock:
            self.s.sendall(encode_frame(KIND_ENC, self.sess.encrypt_json(env)))

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--name", default="Desktop")
    ap.add_argument("--port", type=int, default=0)
    ap.add_argument("--dial")
    ap.add_argument("--seed-file", default=os.path.expanduser("~/.privchat_cli_seed"))
    ap.add_argument("--no-beacon", action="store_true")
    ap.add_argument("--script", help="send these ';'-separated lines after connecting, then exit")
    a = ap.parse_args()

    if os.path.exists(a.seed_file): seed = open(a.seed_file, "rb").read()
    else:
        seed = os.urandom(32); open(a.seed_file, "wb").write(seed); os.chmod(a.seed_file, 0o600)
    ident = Identity.from_seed(seed)
    peers, plock = [], threading.Lock()
    log = lambda m: print(m, flush=True)

    def on_env(p, env):
        t = env.get("type")
        who = p.sess.peer.name
        if t == "chat":
            body = env.get("body", {})
            log(f"[{who}] {body.get('text') or env.get('kind')}")
            p.send({"type": "ack", "ids": [env["id"]], "state": "delivered"})
        elif t == "ack": log(f"  ✓ {env['state']}")
        elif t == "typing": pass
        else: log(f"  ({who} sent {t})")

    def adopt(sock):
        p = Peer(ident, a.name, sock, log)
        with plock: peers.append(p)
        threading.Thread(target=p.run, args=(on_env,), daemon=True).start()
        return p

    srv = socket.socket(); srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", a.port)); srv.listen(8)
    port = srv.getsockname()[1]
    log(f"PrivChat CLI  user_id={ident.user_id}  listening tcp/{port}")
    threading.Thread(target=lambda: [adopt(srv.accept()[0]) for _ in iter(int, 1)], daemon=True).start()

    if not a.no_beacon:
        def beacon():
            u = socket.socket(socket.AF_INET, socket.SOCK_DGRAM); u.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            msg = json.dumps({"app": "privchat", "v": 1, "uid": ident.user_id, "name": a.name, "port": port}).encode()
            while True:
                try: u.sendto(msg, ("255.255.255.255", UDP_PORT))
                except OSError: pass
                time.sleep(4)
        threading.Thread(target=beacon, daemon=True).start()

    if a.dial:
        h, pt = a.dial.rsplit(":", 1)
        adopt(socket.create_connection((h, int(pt)), timeout=6))

    def send_text(text):
        env = {"type": "chat", "id": str(uuid.uuid4()), "ts": int(time.time() * 1000), "kind": "text", "body": {"text": text}}
        with plock:
            for p in peers:
                if p.ready.is_set():
                    try: p.send(env)
                    except OSError: pass

    if a.script:
        deadline = time.time() + 10
        while time.time() < deadline and not any(p.ready.is_set() for p in peers): time.sleep(0.05)
        for line in a.script.split(";"): send_text(line)
        time.sleep(1); return
    try:
        for line in sys.stdin:
            if line.strip(): send_text(line.rstrip("\n"))
        while True: time.sleep(1)
    except KeyboardInterrupt:
        pass

if __name__ == "__main__":
    main()
