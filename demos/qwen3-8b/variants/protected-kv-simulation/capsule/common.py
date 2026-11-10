"""Portable source identity and exclusive output helpers, standard library only."""
import hashlib,json
from pathlib import Path
ROOT=Path(__file__).resolve().parent
def need(ok,message):
    if not ok:raise ValueError(message)
def identity(path):
    with Path(path).open('rb') as stream:digest=hashlib.file_digest(stream,'sha256').hexdigest()
    return dict(bytes=Path(path).stat().st_size,sha256=digest)
def save(path,value):
    with Path(path).open('x') as stream:json.dump(value,stream,indent=2,sort_keys=True);stream.write('\n')
def verify(root=ROOT):
    manifest=json.loads((root/'MANIFEST.json').read_text())
    for name,wanted in manifest['files'].items():
        rel=Path(name);path=root/rel
        need(not rel.is_absolute() and '..' not in rel.parts and not path.is_symlink() and path.resolve().is_relative_to(root.resolve()),'Unsafe input '+name)
        need(identity(path)==wanted,'Changed source '+name)
    return manifest
