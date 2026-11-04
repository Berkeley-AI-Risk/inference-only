#!/usr/bin/env python3
"""Prepare a complete raw Tang flash candidate, preserving all other bytes.

Offline only. Two independently verified complete backups and separately
qualified hardware/tools remain prerequisites for any actual flash write.
"""
from pathlib import Path
import argparse,hashlib,json,os,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su
import tang_image as tang

def require(condition,message):
    if not condition:raise ValueError(message)

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--plan',required=True,type=Path);p.add_argument('--backup',required=True,type=Path)
p.add_argument('--output',required=True,type=Path);a=p.parse_args()
plan_bytes=a.plan.read_bytes();plan=json.loads(plan_bytes)
require(a.backup.stat().st_size==tang.FLASH_BYTES,'complete 16 MiB backup required')
baseline=a.backup.read_bytes();candidate=bytearray(baseline)
expected={'model.bin':(tang.MODEL_BASE,su.IMAGE_BYTES),'admission-slot.bin':(tang.SLOT_BASE,tang.SLOT_BYTES)}
require(len(plan['writes'])==2 and {r['file'] for r in plan['writes']}==set(expected),'unexpected flash plan')
data={}
for r in plan['writes']:
    require((r['address'],r['bytes'])==expected[r['file']],'unexpected flash geometry')
    payload=(a.plan.parent/r['file']).read_bytes()
    require(len(payload)==r['bytes'] and hashlib.sha256(payload).hexdigest()==r['sha256'],'prepared data changed')
    data[r['file']]=payload;candidate[r['address']:r['address']+len(payload)]=payload
slot=data['admission-slot.bin'];count=int.from_bytes(slot[128:132],'big')
require(count in (2,3),'wrong signer count')
frame_bytes=112804+count*1296
require(slot[frame_bytes:]==b'\xff'*(tang.SLOT_BYTES-frame_bytes),'non-erased slot padding')
package=slot[:frame_bytes]+data['model.bin']
require(hashlib.sha256(package).hexdigest()==plan['package_sha256'],'package differs from plan')
tang.validate_tang(package,[su.DemoAuthority(i).public_key for i in range(3)])
receipt=a.output.with_name(a.output.name+'.json')
partial=a.output.with_name(a.output.name+'.partial')
require(not any(os.path.lexists(p) for p in [a.output,receipt,partial]),'preserve existing candidate/evidence')
meta={'result':'PREPARED','hardware_access':False,'format':'complete raw 16 MiB array at offset zero, not FPGA configuration',
      'baseline_sha256':hashlib.sha256(baseline).hexdigest(),'candidate_sha256':hashlib.sha256(candidate).hexdigest(),
      'plan_sha256':hashlib.sha256(plan_bytes).hexdigest(),'package_sha256':plan['package_sha256'],
      'bytes':len(candidate),'changed_bytes':sum(x!=y for x,y in zip(baseline,candidate)),
      'preservation':'every byte outside the fixed model and signed-admission slot equals the baseline'}
for name,content in [(partial,candidate),(receipt,(json.dumps(meta,indent=2)+'\n').encode())]:
    fd=os.open(name,os.O_WRONLY|os.O_CREAT|os.O_EXCL|getattr(os,'O_NOFOLLOW',0),0o600)
    with os.fdopen(fd,'wb') as stream:stream.write(content);stream.flush();os.fsync(stream.fileno())
os.link(partial,a.output,follow_symlinks=False);partial.unlink()
print(json.dumps(meta,indent=2))
