#!/usr/bin/env python3
"""Additional synthetic changed-matrix acceptance case; requires NumPy."""
from pathlib import Path
import json,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su
import tang_image as tang

if len(sys.argv)!=2:raise SystemExit('usage: make_weight_fixture.py DEMO')
demo=Path(sys.argv[1]);out=ROOT/'evidence/fixtures'
assert not any(out.glob('case-3.*')),'preserve existing fixture'
image=bytearray((out/'case-0.image.bin').read_bytes());image[:211800*32]=bytes(211800*32)
slot=(out/'case-0.slot.bin').read_bytes();start=132+2*(4+su.SIG_BYTES)
metadata=slot[start+32+32*su.PAGES:start+su.PAYLOAD_BYTES]
authorities=[su.DemoAuthority(i) for i in range(3)]
package=su.make_package(bytes(image),metadata,3,authorities[:2],[6,6])
info=tang.validate_tang(package,[a.public_key for a in authorities])
model=tang.integer_model(bytes(image),demo)
sys.path.insert(0,str(demo/'reference'))
from quantization.oracle import IntegerLlama
oracle=IntegerLlama(model);t0,_=oracle.forward_token(1);t1,_=oracle.forward_token(t0)
assert (t0,t1)==(0,0)
slot=package[:-su.IMAGE_BYTES].ljust(tang.SLOT_BYTES,b'\xff')
for name,data in [('image',image),('slot',slot)]:
    (out/f'case-3.{name}.bin').write_bytes(data)
    (out/f'case-3.{name}.hex').write_text(''.join(f'{b:02x}\n' for b in data))
(out/'case-3.norm.hex').write_text(''.join(f'{x:09x}\n' for x in tang.norm_rows(image)))
records=json.loads((out/'fixtures.json').read_text());records.append({'case':3,'name':'zero-matrix-weights-synthetic','prompt':[1],'tokens':[t0,t1],**info})
(out/'fixtures.json').write_text(json.dumps(records,indent=2)+'\n');print('PASS image-derived zero-matrix oracle: [0, 0]')
