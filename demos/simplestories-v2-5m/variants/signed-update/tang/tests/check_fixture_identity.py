#!/usr/bin/env python3
"""Bind regenerated simulator text files to their signed binary packages."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su
import tang_image as tang

out=ROOT/'evidence/fixtures';records=json.loads((out/'fixtures.json').read_text())
keys=[su.DemoAuthority(i).public_key for i in range(3)]
checks=[];files={}
for rec in records:
    case=rec['case']
    for name in ['image','slot']:
        binary=out/f'case-{case}.{name}.bin';hexfile=binary.with_suffix('.hex')
        raw=binary.read_bytes();decoded=bytes.fromhex(hexfile.read_text())
        assert raw==decoded,(case,name)
        for p in [binary,hexfile]:files[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    image=(out/f'case-{case}.image.bin').read_bytes();slot=(out/f'case-{case}.slot.bin').read_bytes()
    count=int.from_bytes(slot[128:132],'big');frame_bytes=112804+count*1296
    assert count in (2,3) and slot[frame_bytes:]==b'\xff'*(tang.SLOT_BYTES-frame_bytes)
    info=tang.validate_tang(slot[:frame_bytes]+image,keys)
    assert info=={k:rec[k] for k in info},'fixture record differs from signed package'
    p=out/f'case-{case}.norm.hex';rows=[int(s,16) for s in p.read_text().split()]
    assert rows==tang.norm_rows(image)
    files[str(p.relative_to(ROOT))]=hashlib.sha256(p.read_bytes()).hexdigest()
    checks.append({'case':case,'image_sha256':hashlib.sha256(image).hexdigest(),'slot_sha256':hashlib.sha256(slot).hexdigest(),'normalization_rows':len(rows),'result':'PASS'})
badfile=out/'case-2.slot.hex';bad=bytes.fromhex(badfile.read_text());count=int.from_bytes(bad[128:132],'big')
try:tang.validate_tang(bad[:112804+count*1296]+(out/'case-0.image.bin').read_bytes(),keys)
except su.Reject:pass
else:raise AssertionError('bad signature accepted')
files[str(badfile.relative_to(ROOT))]=hashlib.sha256(badfile.read_bytes()).hexdigest()
files['evidence/fixtures/fixtures.json']=hashlib.sha256((out/'fixtures.json').read_bytes()).hexdigest()
(out/'INPUTS.json').write_text(json.dumps({'result':'PASS','checks':checks,'bad_signature_rejected':True,'files_sha256':files,
    'verifier_source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(),ROOT/'reference/tang_image.py',ROOT/'reference/signed_update.py']}},indent=2)+'\n')
print('PASS fixture identity: three signed images, exact simulator hex/norm bytes, rejected bad signature')
