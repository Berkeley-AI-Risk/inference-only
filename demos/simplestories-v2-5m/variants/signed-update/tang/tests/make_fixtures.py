#!/usr/bin/env python3
from pathlib import Path
import argparse,json,hashlib,sys
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su
import tang_image as tang

p=argparse.ArgumentParser();p.add_argument('demo',type=Path);p.add_argument('--output',type=Path,required=True)
a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
image=(a.demo/'assets/board1-real-semantic-image2048.bin').read_bytes()
metadata=bytes.fromhex(''.join((a.demo/'hardware/project/metadata192.memh').read_text().split()))
zero=bytearray(image);zero[214250*32:214260*32]=bytes(320)
authorities=[su.DemoAuthority(i) for i in range(3)];keys=[x.public_key for x in authorities]
records=[]
for case,data in enumerate((image,bytes(zero))):
    package=su.make_package(data,metadata,case+1,authorities[:2],[case+4]*2)
    info=tang.validate_tang(package,keys)
    frame=package[:-su.IMAGE_BYTES];slot=frame.ljust(tang.SLOT_BYTES,b'\xff')
    (a.output/f'case-{case}.image.bin').write_bytes(data)
    (a.output/f'case-{case}.slot.bin').write_bytes(slot)
    (a.output/f'case-{case}.image.hex').write_text(''.join(f'{b:02x}\n' for b in data))
    (a.output/f'case-{case}.slot.hex').write_text(''.join(f'{b:02x}\n' for b in slot))
    rows=tang.norm_rows(data)
    (a.output/f'case-{case}.norm.hex').write_text(''.join(f'{x:09x}\n' for x in rows))
    model=tang.integer_model(data,a.demo)
    sys.path.insert(0,str(a.demo/'reference'))
    from quantization.oracle import IntegerLlama
    oracle=IntegerLlama(model);t0,_=oracle.forward_token(1);t1,_=oracle.forward_token(t0)
    if case==1:assert t0==0 and t1==0
    records.append({'case':case,'name':'base' if case==0 else 'zero-final-norm-synthetic',
                    'prompt':[1],'tokens':[t0,t1],**info})
    print(json.dumps(records[-1]),flush=True)
bad=bytearray((a.output/'case-0.slot.bin').read_bytes());bad[190]^=1
(a.output/'case-2.slot.hex').write_text(''.join(f'{b:02x}\n' for b in bad))
(a.output/'fixtures.json').write_text(json.dumps(records,indent=2)+'\n')
