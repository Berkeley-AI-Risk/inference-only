"""Recover pre-speed-up text for checking explicitly historical evidence.

The current release is checked separately. An old physical test remains a
test of its named old image; it is never relabelled as a test of this release.
The three replaced images are not duplicated here: their recorded identifiers
are retained, but their original bytes are not bundled in this release.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath

OLD_IMAGES = {
    'prebuilt/inference/project/impl/pnr/shared_product.fs':
        '44a7fb18131e07bdb39ccdead1083f8224822a44a2ec36f1455e2d12acb566ed',
    'prebuilt/kv-protected/project/impl/pnr/shared_product.fs':
        'e22079c855cdf6cfb983c73850db15b1b5010f0511fa62f98f3d040ae0654ea2',
    'prebuilt/encrypted-memory/project/impl/pnr/shared_product.fs':
        '32970712a318f605d5822bb7ac2234f080df15341103e0a78bad8863b5c9361e',
}
NEW_IMAGES = {
    'prebuilt/inference/project/impl/pnr/shared_product.fs':
        '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09',
    'prebuilt/kv-protected/project/impl/pnr/shared_product.fs':
        '72d5a54e06ed2017e653122f3daecf073f239a917b79f24d1e7b886d68a21a2f',
    'prebuilt/encrypted-memory/project/impl/pnr/shared_product.fs':
        '865e74e692d5978815fe921f11e4fa1b8e2c080401a8be05508dd9775823aecc',
}


def sha(raw): return hashlib.sha256(raw).hexdigest()
def need(ok, why):
    if not ok: raise ValueError(why)


def previous_bytes(package, name, raw):
    record = json.loads((Path(package)/'evidence/speed-2026-10-02/source-revision.json').read_bytes())
    need(record['schema']=='tang-speed-source-revision-v1'
         and record['old_board_tests_apply_to_new_images'] is False, 'Wrong speed history')
    path = PurePosixPath(name)
    need(not path.is_absolute() and '..' not in path.parts,'Unsafe history path')
    change = record['changes'].get(name)
    if change is None: return raw
    need(name not in OLD_IMAGES and sha(raw)==change['after_sha256'],'Changed current history source')
    lines = raw.decode().splitlines(keepends=True); boundary = len(lines)
    for edit in reversed(change['reverse_edits']):
        start,end = edit['start'],edit['end']
        need(type(start) is int and type(end) is int and 0<=start<=end<=boundary
             and lines[start:end]==edit['after'],'Changed reverse-edit bytes or range')
        lines[start:end] = edit['before']; boundary = start
    old = ''.join(lines).encode()
    need(sha(old)==change['before_sha256'],'Historical text reconstruction failed')
    return old


def previous_digest(package, name, raw):
    if name in OLD_IMAGES:
        need(sha(raw)==NEW_IMAGES[name],'Changed replacement image')
        return OLD_IMAGES[name]  # Recorded historical identity, not reread old image bytes.
    return sha(previous_bytes(package,name,raw))
