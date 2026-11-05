"""Boot-fresh, model-specific renewable home authorization. PUBLIC DEMO KEY ONLY.

The Python device is a protocol reference, not a boundary against a hostile
host. The RTL consumes a private trusted nonce input; its physical entropy
source is a separate, unqualified dependency.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import secrets
import threading
import time

from vendor import signed_update as su

DOMAIN = b"SAWIC-HOME-v1".ljust(16, b"\0")
DEVICE_ID = hashlib.sha256(b"PUBLIC S-AWIC home authorization demo device").digest()[:16]
REQUEST_BYTES = 128
GRANT_BYTES = REQUEST_BYTES + su.SIG_BYTES
HOME_AUTHORITY = 17


class Reject(ValueError):
    pass


def request_bytes(device_id: bytes, nonce: bytes, model_root: bytes) -> bytes:
    if len(device_id) != 16 or len(nonce) != 32 or len(model_root) != 32 or not any(nonce):
        raise Reject("invalid device, nonce or model commitment")
    return DOMAIN + device_id + nonce + model_root + su.GEOMETRY


def parse_request(data: bytes) -> dict:
    if len(data) != REQUEST_BYTES or data[:16] != DOMAIN or data[96:] != su.GEOMETRY:
        raise Reject("noncanonical request/domain/geometry")
    if not any(data[32:64]):
        raise Reject("zero nonce")
    return {"device": data[16:32].hex(), "nonce": data[32:64].hex(),
            "model_root": data[64:96].hex()}


class BootDevice:
    """Executable lease protocol model; reset clears all authorization.

    Call boot_package for a software end-to-end check of the actual signed
    SimpleStories package. boot_verified_root is the explicit hardware seam:
    its caller must supply the commitment from completed model admission.
    """
    def __init__(self, home_public_key: bytes, *, device_id=DEVICE_ID,
                 timeout=10.0, lease=60.0, clock=time.monotonic, nonce_source=secrets.token_bytes):
        if len(home_public_key) != 56 or len(device_id) != 16 or not 0 < timeout < lease:
            raise Reject("invalid fixed configuration")
        self.key, self.device_id, self.timeout = home_public_key, device_id, timeout
        self.lease = lease
        self.clock, self.nonce_source = clock, nonce_source
        self.reset()

    def reset(self):
        self.request = None
        self.started = None
        self.authorized = False
        self.failed = False
        self.current_root = None
        self.lease_until = None
        self.previous_nonce = None

    def boot_package(self, package: bytes, weight_public_keys: list[bytes]) -> bytes:
        self.reset()
        try:
            result = su.verify_package(package, weight_public_keys)
            return self.boot_verified_root(bytes.fromhex(result["model_root"]))
        except Exception:
            self.failed = True
            raise

    def boot_verified_root(self, root: bytes) -> bytes:
        self.reset()
        self.current_root = root
        return self.renew()

    def renew(self) -> bytes:
        self._expire()
        if self.failed or self.current_root is None or self.request is not None:
            raise Reject("cannot begin another challenge")
        try:
            nonce = self.nonce_source(32)
            if nonce == self.previous_nonce:
                raise Reject("nonce source repeated its previous output")
            self.request = request_bytes(self.device_id, nonce, self.current_root)
            self.previous_nonce = nonce
            self.started = self.clock()
            return self.request
        except Exception:
            self.failed = True
            raise

    def accept(self, grant: bytes):
        try:
            self._expire()
            if self.failed or self.request is None:
                raise Reject("no outstanding challenge")
            if self.clock() - self.started >= self.timeout:
                raise Reject("boot challenge expired")
            if len(grant) != GRANT_BYTES or grant[:REQUEST_BYTES] != self.request:
                raise Reject("grant is for another boot/device/model or has wrong size")
            if not su.lms_verify(self.key, self.request, grant[REQUEST_BYTES:]):
                raise Reject("invalid home signature")
            self.authorized = True
            # Anchor at challenge issue, not delayed response delivery.
            self.lease_until = self.started + self.lease
            self.request = None
        except Exception:
            self.authorized = False
            self.failed = True
            raise

    def require_inference(self) -> bytes:
        self._expire()
        if (not self.authorized or self.failed or self.lease_until is None
                or self.clock() >= self.lease_until):
            raise Reject("inference is disabled")
        return self.current_root

    def _expire(self):
        if self.authorized and self.lease_until is not None and self.clock() >= self.lease_until:
            self.authorized = False
            self.failed = True


def _hex(value, size):
    if not isinstance(value, str) or len(value) != 2 * size or value.lower() != value:
        raise Reject("policy IDs must be canonical lowercase hex")
    try:
        return bytes.fromhex(value)
    except ValueError as exc:
        raise Reject("invalid policy hex") from exc


def load_policy(path: Path) -> dict:
    try:
        value = json.loads(path.read_text())
        if set(value) != {"schema", "geometry", "devices"} or value["schema"] != 1:
            raise Reject("unknown policy schema")
        if _hex(value["geometry"], 32) != su.GEOMETRY or not isinstance(value["devices"], dict):
            raise Reject("invalid policy geometry/devices")
        for device, roots in value["devices"].items():
            _hex(device, 16)
            if not isinstance(roots, list) or len(roots) != len(set(roots)):
                raise Reject("invalid/duplicate allowed roots")
            for root in roots:
                _hex(root, 32)
        return value
    except (ValueError, TypeError, KeyError, OSError) as exc:
        raise Reject("policy unavailable or invalid") from exc


class HomeBase:
    """Local demonstration authority; no production credential management.

    The live allowlist is read on each request, including cache hits. Signing
    leaves are durably reserved before signing. The deliberately public H5
    demo tree allows 32 unique grants, then fails closed.
    """
    def __init__(self, policy_path: Path, signer_state: Path):
        self.policy_path, self.signer_state = Path(policy_path), Path(signer_state)
        self.authority = su.DemoAuthority(HOME_AUTHORITY)
        self.public_key = self.authority.public_key
        self.lock = threading.Lock()
        self.cache = {}

    def _reserve_leaf(self):
        self.signer_state.parent.mkdir(parents=True, exist_ok=True)
        key_hash = hashlib.sha256(self.public_key).hexdigest()
        try:
            fd = os.open(self.signer_state, os.O_RDWR | os.O_CREAT | os.O_EXCL, 0o600)
            fresh = True
        except FileExistsError:
            fd = os.open(self.signer_state, os.O_RDWR)
            fresh = False
        with os.fdopen(fd, "r+", encoding="utf-8") as f:
            fcntl.flock(f, fcntl.LOCK_EX)
            value = {"schema": 1, "PUBLIC_DEMO_ONLY": True,
                     "key_sha256": key_hash, "next_leaf": 0} if fresh else json.load(f)
            if (set(value) != {"schema", "PUBLIC_DEMO_ONLY", "key_sha256", "next_leaf"}
                    or value["schema"] != 1 or value["PUBLIC_DEMO_ONLY"] is not True
                    or value["key_sha256"] != key_hash
                    or type(value["next_leaf"]) is not int or not 0 <= value["next_leaf"] < 32):
                raise Reject("demo signer exhausted or state invalid")
            leaf = value["next_leaf"]
            value["next_leaf"] += 1
            f.seek(0)
            json.dump(value, f)
            f.truncate()
            f.flush()
            os.fsync(f.fileno())
            return leaf

    def authorize(self, request: bytes) -> bytes:
        fields = parse_request(request)
        with self.lock:
            policy = load_policy(self.policy_path)
            if fields["model_root"] not in policy["devices"].get(fields["device"], []):
                raise Reject("device/model is not currently authorized")
            if request not in self.cache:
                q = self._reserve_leaf()
                self.cache[request] = request + self.authority.sign_reserved_leaf(request, q)
            return self.cache[request]


def policy_for(roots, device_id=DEVICE_ID):
    return {"schema": 1, "geometry": su.GEOMETRY.hex(),
            "devices": {device_id.hex(): [r.hex() for r in roots]}}
