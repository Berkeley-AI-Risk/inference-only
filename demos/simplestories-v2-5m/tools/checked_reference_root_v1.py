"""Read-only validation of a minimal original baseline source reference.

This is not a historical package or runnable inference design. Only traced
source dependencies are present; no extraction, old images, model weights,
old application, abstract specifications, process or network operation occurs.
"""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re
import stat

CONTEXT='reference/baseline-formal-354'
LEDGER='REFERENCE-SOURCES.json'
LEDGER_SHA='db49aa75151b8b1633779503af8cb5a46f754979cd330db194935e88bc998794'
ORIGINAL_MANIFEST=dict(bytes=366488,sha256='354b31bb70f1694784cc0264d0e0642495213c5f9c0303d4f04e0c1296980323')
MAX_MEMBER=1024*1024
MAX_TOTAL=2*1024*1024

def need(ok,message):
    if not ok:raise ValueError(message)
def unique_object(pairs):
    result={}
    for key,value in pairs:
        need(key not in result,'Duplicate reference JSON key');result[key]=value
    return result
def decode(raw):return json.loads(raw,object_pairs_hook=unique_object)
def no_links(path):
    path=Path(path).absolute()
    need('..'not in path.parts and not any(p.is_symlink()for p in(path,*path.parents)),
         'Reference path must be physical without parent traversal')
    return path
def member(root,name):
    relative=PurePosixPath(name)
    need(type(name)is str and name and str(relative)==name and not relative.is_absolute()
         and '..'not in relative.parts and '\\'not in name and ':'not in name,
         'Unsafe reference member')
    return no_links(root/relative)
def identity(path):
    path=no_links(path);before=path.lstat()
    need(stat.S_ISREG(before.st_mode)and before.st_size<=MAX_MEMBER,'Bounded regular reference file required')
    raw=path.read_bytes();after=path.lstat()
    attrs=('st_dev','st_ino','st_mode','st_size','st_mtime_ns','st_ctime_ns')
    need(tuple(getattr(before,k)for k in attrs)==tuple(getattr(after,k)for k in attrs),
         'Reference file changed during reading')
    return dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def expected(row):
    need(type(row)is dict and set(row)=={'bytes','sha256'}and type(row['bytes'])is int
         and 0<=row['bytes']<=MAX_MEMBER and type(row['sha256'])is str
         and re.fullmatch(r'[0-9a-f]{64}',row['sha256'])is not None,'Invalid reference identity')
    return row

def checked_reference_root(package):
    root=no_links(no_links(package)/CONTEXT);ledger_path=member(root,LEDGER)
    need(identity(ledger_path)['sha256']==LEDGER_SHA,'Reference ledger changed')
    ledger=decode(ledger_path.read_bytes())
    need(ledger['schema']=='minimal-original354-baseline-source-reference-v1'
         and ledger['fixture_only']is True and ledger['runnable_release']is False
         and ledger['FS_model_weight_Lean_or_old_app_payload_included']is False
         and ledger['original_manifest_is_provenance_not_full_package_validation']is True,
         'Only the minimal source reference context is supported')
    files=ledger['files'];need(type(files)is dict and len(files)==ledger['source_members']==98,
         'Exact traced reference source census required')
    need(sum(expected(row)['bytes']for row in files.values())==ledger['source_bytes']
         and ledger['source_bytes']+ledger_path.stat().st_size<=MAX_TOTAL,'Reference source byte bound differs')
    manifest_path=member(root,'MANIFEST.json')
    need(identity(manifest_path)==ORIGINAL_MANIFEST
         and files['MANIFEST.json']==ORIGINAL_MANIFEST
         and ledger['original_manifest']==dict(path='MANIFEST.json',**ORIGINAL_MANIFEST),
         'Original manifest provenance changed')
    original=decode(manifest_path.read_bytes())
    found=set()
    for path in root.rglob('*'):
        info=path.lstat();need(not path.is_symlink()and(stat.S_ISDIR(info.st_mode)or stat.S_ISREG(info.st_mode)),
                             'Linked or special reference member refused')
        if path.is_file():found.add(path.relative_to(root).as_posix())
    need(found==set(files)|{LEDGER},'Unlisted or missing reference source')
    for name,wanted in files.items():
        need(Path(name).suffix not in('.fs','.bin','.zip','.lean')and Path(name).name!='lean-toolchain',
             'Runnable image, weights, archive or abstract source is not a reference fixture')
        expected(wanted)
        if name!='MANIFEST.json':need(original['files'].get(name)==wanted,'Reference source lacks original manifest provenance')
        need(identity(member(root,name))==wanted,'Reference source changed: '+name)
    need(original['prebuilt_image_sha256']==ledger['original_baseline_image_identity_only']==
         '6ba3caa4f88ac58dd30336c3ff4478f836779db0d04309ff457ca065ec1f7f09',
         'Original baseline identity metadata changed')
    return root
