#!/usr/bin/env python3
"""Signature-only SimpleStories package reference. PUBLIC DEMO KEYS ONLY.

LMS_SHA256_M32_H5 / LMOTS_SHA256_N32_W8, RFC 8554. No update cap,
antirollback counter or intentional delay. Never use these keys in production.
"""
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import struct
from pathlib import Path

H = lambda x: hashlib.sha256(x).digest()
U32 = lambda x: struct.pack(">I", x)
U16 = lambda x: struct.pack(">H", x)
DOMAIN = b"SWIC-SS-UPD-v1".ljust(16, b"\0")
ROOT_DOMAIN = b"SWIC-SS-ROOT-v1".ljust(16, b"\0")
IMAGE_BYTES = 7265984
PAGE_BYTES = 4096
PAGES = (IMAGE_BYTES + PAGE_BYTES - 1) // PAGE_BYTES
META_BYTES = 55872
GEOMETRY_DESCRIPTION = (
    b"SimpleStories-V2-5M/W10-A16-KV16/v1;layers=6;width=256;ffn=682;"
    b"heads=4;kvheads=2;vocab=4019;context=2048;image=7265984;"
    b"pages=1774;pagebytes=4096;tail=zero;metadata=2328x192be;"
    b"imagewords=227062x256le;metadatawords=211920:214248;selector=greedy"
)
GEOMETRY = H(GEOMETRY_DESCRIPTION)
LMS_TYPE, OTS_TYPE, TREE_HEIGHT, P = 5, 4, 5, 34
SIG_BYTES = 4 + 4 + 32 + P * 32 + 4 + TREE_HEIGHT * 32
PAYLOAD_BYTES = 32 + PAGES * 32 + META_BYTES
MANIFEST_BYTES = 128
MIN_SIGNERS = 2


class Reject(ValueError):
    pass


def checksum(digest: bytes) -> bytes:
    return U16(sum(255 - b for b in digest))


def chain(identifier: bytes, q: int, i: int, value: bytes, start: int, stop: int) -> bytes:
    prefix = identifier + U32(q) + U16(i)
    for j in range(start, stop):
        value = H(prefix + bytes([j]) + value)
    return value


def lms_verify(public_key: bytes, message: bytes, signature: bytes) -> bool:
    if len(public_key) != 56 or len(signature) != SIG_BYTES:
        return False
    if public_key[:8] != U32(LMS_TYPE) + U32(OTS_TYPE):
        return False
    q = int.from_bytes(signature[:4], "big")
    if q >= 1 << TREE_HEIGHT or signature[4:8] != U32(OTS_TYPE):
        return False
    if signature[1128:1132] != U32(LMS_TYPE):
        return False
    identifier = public_key[8:24]
    digest = H(identifier + U32(q) + b"\x81\x81" + signature[8:40] + message)
    coefficients = digest + checksum(digest)
    z = [chain(identifier, q, i, signature[40 + 32*i:72 + 32*i], coefficients[i], 255)
         for i in range(P)]
    ots_key = H(identifier + U32(q) + b"\x80\x80" + b"".join(z))
    node = (1 << TREE_HEIGHT) + q
    value = H(identifier + U32(node) + b"\x82\x82" + ots_key)
    for level in range(TREE_HEIGHT):
        sibling = signature[1132 + 32*level:1164 + 32*level]
        left, right = (sibling, value) if node & 1 else (value, sibling)
        node //= 2
        value = H(identifier + U32(node) + b"\x83\x83" + left + right)
    return value == public_key[24:56]


class DemoAuthority:
    """Reproducible PUBLIC private material. Caller must reserve leaves durably."""
    def __init__(self, authority: int):
        self.authority = authority
        self.identifier = H(b"PUBLIC AWIC signed-update demo I " + U32(authority))[:16]
        self.seed = H(b"PUBLIC AWIC signed-update demo seed " + U32(authority))
        self.nodes: dict[int, bytes] = {}
        for q in range(1 << TREE_HEIGHT):
            z = [chain(self.identifier, q, i, self.private_element(q, i), 0, 255)
                 for i in range(P)]
            ots = H(self.identifier + U32(q) + b"\x80\x80" + b"".join(z))
            n = (1 << TREE_HEIGHT) + q
            self.nodes[n] = H(self.identifier + U32(n) + b"\x82\x82" + ots)
        for n in range((1 << TREE_HEIGHT) - 1, 0, -1):
            self.nodes[n] = H(self.identifier + U32(n) + b"\x83\x83" + self.nodes[2*n] + self.nodes[2*n+1])
        self.public_key = U32(LMS_TYPE) + U32(OTS_TYPE) + self.identifier + self.nodes[1]

    def private_element(self, q: int, i: int) -> bytes:
        return H(self.identifier + U32(q) + U16(i) + b"\xff" + self.seed)

    def sign_reserved_leaf(self, message: bytes, q: int) -> bytes:
        if not 0 <= q < 1 << TREE_HEIGHT:
            raise Reject("demo signer exhausted")
        randomizer = H(b"PUBLIC demo C" + self.seed + U32(q) + message)
        digest = H(self.identifier + U32(q) + b"\x81\x81" + randomizer + message)
        coefficients = digest + checksum(digest)
        y = [chain(self.identifier, q, i, self.private_element(q, i), 0, coefficients[i])
             for i in range(P)]
        node = (1 << TREE_HEIGHT) + q
        path = []
        for _ in range(TREE_HEIGHT):
            path.append(self.nodes[node ^ 1])
            node //= 2
        return U32(q) + U32(OTS_TYPE) + randomizer + b"".join(y) + U32(LMS_TYPE) + b"".join(path)


def digest_table(image: bytes) -> bytes:
    if len(image) != IMAGE_BYTES:
        raise Reject("wrong fixed image length")
    return b"".join(H(image[i:i+PAGE_BYTES].ljust(PAGE_BYTES, b"\0"))
                    for i in range(0, len(image), PAGE_BYTES))


def make_payload(image: bytes, metadata: bytes) -> bytes:
    if len(metadata) != META_BYTES:
        raise Reject("wrong fixed metadata length")
    return H(image) + digest_table(image) + metadata


def make_manifest(payload: bytes, version: int) -> bytes:
    if len(payload) != PAYLOAD_BYTES:
        raise Reject("wrong payload length")
    return (DOMAIN + GEOMETRY + struct.pack(">IIIIQ", IMAGE_BYTES, PAGES, META_BYTES, 0, version)
            + H(ROOT_DOMAIN + payload) + bytes(24))


def check_manifest(manifest: bytes) -> None:
    if len(manifest) != MANIFEST_BYTES:
        raise Reject("wrong manifest length")
    if manifest[:48] != DOMAIN + GEOMETRY:
        raise Reject("domain/geometry mismatch")
    if manifest[48:64] != struct.pack(">IIII", IMAGE_BYTES, PAGES, META_BYTES, 0):
        raise Reject("geometry/policy mismatch")
    if manifest[104:] != bytes(24):
        raise Reject("noncanonical reserved bytes")


def make_package(image: bytes, metadata: bytes, version: int, signers: list[DemoAuthority], leaves: list[int]) -> bytes:
    if not 2 <= len(signers) <= 3 or len(signers) != len(leaves):
        raise Reject("two or three signers required")
    if [s.authority for s in signers] != sorted(set(s.authority for s in signers)) or any(not 0 <= s.authority < 3 for s in signers):
        raise Reject("unknown, duplicate or unsorted demo authority")
    payload = make_payload(image, metadata)
    manifest = make_manifest(payload, version)
    records = b"".join(U32(signer.authority) + signer.sign_reserved_leaf(manifest, q)
                       for signer, q in zip(signers, leaves))
    return manifest + U32(len(signers)) + records + payload + image


def verify_package(package: bytes, public_keys: list[bytes]) -> dict:
    manifest = package[:MANIFEST_BYTES]
    check_manifest(manifest)
    if len(public_keys) != 3 or len(set(public_keys)) != 3:
        raise Reject("trust anchors must be three distinct fixed public keys")
    count = int.from_bytes(package[128:132], "big")
    if not 2 <= count <= 3:
        raise Reject("invalid signer count")
    payload_at = 132 + count * (4 + SIG_BYTES)
    if len(package) != payload_at + PAYLOAD_BYTES + IMAGE_BYTES:
        raise Reject("truncated or oversized package")
    previous = -1
    for slot in range(count):
        offset = 132 + slot * (4 + SIG_BYTES)
        key_id = int.from_bytes(package[offset:offset+4], "big")
        if not previous < key_id < 3:
            raise Reject("unknown, duplicate or noncanonical signer")
        if not lms_verify(public_keys[key_id], manifest, package[offset+4:offset+4+SIG_BYTES]):
            raise Reject("bad LMS signature")
        previous = key_id
    payload = package[payload_at:payload_at+PAYLOAD_BYTES]
    if H(ROOT_DOMAIN + payload) != manifest[72:104]:
        raise Reject("root mismatch")
    image = package[payload_at+PAYLOAD_BYTES:]
    if H(image) != payload[:32] or digest_table(image) != payload[32:32+32*PAGES]:
        raise Reject("image/page-table mismatch")
    return {"version": int.from_bytes(manifest[64:72], "big"), "signers": count,
            "model_root": manifest[72:104].hex(), "image_sha256": payload[:32].hex(),
            "package_bytes": len(package), "boot_frame_bytes": payload_at + PAYLOAD_BYTES}


def reserve_demo_leaves(path: Path, count: int) -> list[int]:
    """Burn leaf numbers before signing. Corrupt existing state fails closed.

    This is demo operational hygiene, not a protected signer implementation.
    Recreating/rolling back this file can reuse one-time keys.
    """
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
        fresh = True
    except FileExistsError:
        fd = os.open(path, os.O_RDWR)
        fresh = False
    with os.fdopen(fd, "r+", encoding="utf-8") as state_file:
        fcntl.flock(state_file, fcntl.LOCK_EX)
        state = {"PUBLIC_DEMO_ONLY": True, "next_leaf": [0, 0, 0]} if fresh else json.load(state_file)
        if state.get("PUBLIC_DEMO_ONLY") is not True or len(state.get("next_leaf", [])) != 3:
            raise Reject("invalid signer state")
        leaves = state["next_leaf"][:count]
        if any(type(q) is not int or not 0 <= q < 32 for q in leaves):
            raise Reject("demo signing capacity exhausted/invalid")
        for i in range(count):
            state["next_leaf"][i] += 1
        state_file.seek(0)
        json.dump(state, state_file)
        state_file.truncate()
        state_file.flush()
        os.fsync(state_file.fileno())
        return leaves


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    pack = sub.add_parser("pack-demo")
    pack.add_argument("image", type=Path)
    pack.add_argument("metadata_memh", type=Path)
    pack.add_argument("output", type=Path)
    pack.add_argument("--signer-state", required=True, type=Path)
    pack.add_argument("--version", type=int, required=True)
    verify = sub.add_parser("verify-demo")
    verify.add_argument("package", type=Path)
    args = parser.parse_args()
    authorities = [DemoAuthority(i) for i in range(3)]
    if args.command == "pack-demo":
        image = args.image.read_bytes()
        metadata = bytes.fromhex("".join(args.metadata_memh.read_text().split()))
        make_manifest(make_payload(image, metadata), args.version)  # validate before burning leaves
        leaves = reserve_demo_leaves(args.signer_state, 2)
        package = make_package(image, metadata, args.version, authorities[:2], leaves)
        with args.output.open("xb") as out:
            out.write(package)
    else:
        package = args.package.read_bytes()
    print(json.dumps(verify_package(package, [a.public_key for a in authorities]), indent=2))


if __name__ == "__main__":
    main()
