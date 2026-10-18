"""PrivChat reference protocol implementation (Python / libsodium via PyNaCl).

This is the *normative* reference. The Flutter/Dart implementation must
produce byte-identical results for the vectors in test_vectors.json.
"""
from .identity import Identity, user_id_from_ed_pk, safety_number
from .session import Session, Hello, build_hello, verify_hello
from .frames import Frame, KIND_HELLO, KIND_ENC, encode_frame, FrameDecoder
from .group import SenderKey, GroupState, encrypt_group_message, decrypt_group_message
from .files import FileKey, encrypt_chunk, decrypt_chunk, file_id_from_hash

__all__ = [
    "Identity", "user_id_from_ed_pk", "safety_number",
    "Session", "Hello", "build_hello", "verify_hello",
    "Frame", "KIND_HELLO", "KIND_ENC", "encode_frame", "FrameDecoder",
    "SenderKey", "GroupState", "encrypt_group_message", "decrypt_group_message",
    "FileKey", "encrypt_chunk", "decrypt_chunk", "file_id_from_hash",
]
