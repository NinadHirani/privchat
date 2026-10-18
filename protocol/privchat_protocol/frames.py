"""Wire framing over a reliable byte stream (TCP or Multipeer stream).

frame      := u32be(len) || kind(u8) || payload
kind 0x01  := HELLO, payload = UTF-8 JSON
kind 0x02  := ENC,   payload = u32be(counter) || nonce(24) || ciphertext

Maximum frame size 16 MiB (file chunks are 256 KiB so this is generous).
"""
import struct
from dataclasses import dataclass

KIND_HELLO = 0x01
KIND_ENC = 0x02
MAX_FRAME = 16 * 1024 * 1024

@dataclass
class Frame:
    kind: int
    payload: bytes

def encode_frame(kind: int, payload: bytes) -> bytes:
    body = bytes([kind]) + payload
    if len(body) > MAX_FRAME:
        raise ValueError("frame too large")
    return struct.pack(">I", len(body)) + body

class FrameDecoder:
    """Incremental decoder: feed() bytes, iterate frames()."""
    def __init__(self):
        self.buf = bytearray()

    def feed(self, data: bytes):
        self.buf += data

    def frames(self):
        while True:
            if len(self.buf) < 4:
                return
            (n,) = struct.unpack(">I", self.buf[:4])
            if n > MAX_FRAME or n < 1:
                raise ValueError("bad frame length")
            if len(self.buf) < 4 + n:
                return
            body = bytes(self.buf[4:4 + n])
            del self.buf[:4 + n]
            yield Frame(body[0], body[1:])
