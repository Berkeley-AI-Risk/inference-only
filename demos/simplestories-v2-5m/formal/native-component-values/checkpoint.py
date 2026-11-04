"""Atomic reproduction receipts; no development campaign or token ledger."""
import json
import os
from pathlib import Path
import tempfile


def atomic_bytes(path,raw):
    path=Path(path);path.parent.mkdir(parents=True,exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent,delete=False) as f:
        temporary=f.name;f.write(raw);f.flush();os.fsync(f.fileno())
    os.replace(temporary,path)


def atomic_json(path,value):atomic_bytes(path,(json.dumps(value,indent=2,sort_keys=True)+'\n').encode())
def snapshot(reason):
    # Full inputs already have a checked PACKAGE.json. Fresh result receipts
    # are written atomically by the verifier in the separate --out directory.
    return None
