#!/usr/bin/env python3
"""Prepare fixed-layout SWIC flash DATA files. Never accesses any hardware."""
from pathlib import Path
import argparse,hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su
import tang_image as tang

p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--package',required=True,type=Path);p.add_argument('--output',required=True,type=Path)
a=p.parse_args()
if a.package.stat().st_size not in [132+n*(4+su.SIG_BYTES)+su.PAYLOAD_BYTES+su.IMAGE_BYTES for n in (2,3)]:
    raise SystemExit('Wrong fixed-geometry package size')
package=a.package.read_bytes();keys=[su.DemoAuthority(i).public_key for i in range(3)]
info=tang.validate_tang(package,keys)
frame=package[:-su.IMAGE_BYTES];image=package[-su.IMAGE_BYTES:]
slot=frame.ljust(tang.SLOT_BYTES,b'\xff')
if a.output.exists():raise SystemExit('Output directory already exists; refusing overwrite')
a.output.mkdir(parents=True)
(a.output/'model.bin').write_bytes(image)
(a.output/'admission-slot.bin').write_bytes(slot)
plan={'kind':'SWIC flash data, not an FPGA configuration','geometry':'SimpleStories-V2-5M W10/A16/KV16',
      'device':'GW5AST-138C / PG484A non-Pro','flash_bytes':tang.FLASH_BYTES,'expected_jedec_id':'0b4018',
      'package_sha256':hashlib.sha256(package).hexdigest(),**info,
      'writes':[{'file':'model.bin','address':tang.MODEL_BASE,'bytes':len(image),'sha256':hashlib.sha256(image).hexdigest()},
                {'file':'admission-slot.bin','address':tang.SLOT_BASE,'bytes':len(slot),'sha256':hashlib.sha256(slot).hexdigest()}],
      'normalization_rows':3328,'fixed_lookup_sha256':tang.LUT_SHA,
      'policy':'two distinct fixed demo authorities; boot only; no deliberate delay, cap or antirollback'}
(a.output/'FLASH-PLAN.json').write_text(json.dumps(plan,indent=2)+'\n')
print(json.dumps(plan,indent=2))
