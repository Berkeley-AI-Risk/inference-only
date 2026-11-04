#!/usr/bin/env python3
"""Split a baseline-preserving candidate into changed aligned 64 KiB blocks.

Offline only: this neither signs an update nor accesses any hardware.
The complete candidate remains the expected independent readback image.
"""
from pathlib import Path
import argparse,hashlib,json,os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import tang_image as tang
import signed_update as su
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--before',required=True,type=Path);p.add_argument('--candidate',required=True,type=Path)
p.add_argument('--output',required=True,type=Path);a=p.parse_args()
before=a.before.read_bytes();candidate=a.candidate.read_bytes()
if len(before)!=tang.FLASH_BYTES or len(candidate)!=tang.FLASH_BYTES:raise ValueError('two complete 16 MiB arrays required')
for lo,hi in [(0,tang.MODEL_BASE),(tang.MODEL_BASE+su.IMAGE_BYTES,tang.SLOT_BASE),(tang.SLOT_BASE+tang.SLOT_BYTES,tang.FLASH_BYTES)]:
    if before[lo:hi]!=candidate[lo:hi]:raise ValueError('candidate changes bytes outside model/admission regions')
block=65536;ranges=[]
for start in range(0,len(before),block):
    if before[start:start+block]!=candidate[start:start+block]:
        if ranges and ranges[-1][1]==start:ranges[-1][1]+=block
        else:ranges.append([start,start+block])
a.output.mkdir(parents=True,mode=0o700,exist_ok=False)
writes=[];replayed=bytearray(before)
for start,end in ranges:
    name=f'block-{start:06x}-{end-start:06x}.bin';data=candidate[start:end]
    fd=os.open(a.output/name,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    with os.fdopen(fd,'wb') as f:f.write(data);f.flush();os.fsync(f.fileno())
    writes.append({'file':name,'address':start,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()})
    replayed[start:end]=data
if replayed!=candidate:raise RuntimeError('block replay differs from complete candidate')
plan={'kind':'offline aligned flash block plan','hardware_access':False,'block_bytes':block,
      'before_sha256':hashlib.sha256(before).hexdigest(),'candidate_sha256':hashlib.sha256(candidate).hexdigest(),
      'outside_update_regions_preserved':True,'writes':writes}
(a.output/'BLOCK-PLAN.json').write_text(json.dumps(plan,indent=2)+'\n');print(json.dumps(plan,indent=2))
