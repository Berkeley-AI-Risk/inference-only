#!/usr/bin/env python3
"""Connected real-signature/full-image/native-page-bank regression, one core."""
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'reference'))
import signed_update as su

def main():
    p=argparse.ArgumentParser();p.add_argument('demo',type=Path);args=p.parse_args()
    out=ROOT/'evidence/rtl-memory';out.mkdir(parents=True,exist_ok=True)
    base=(ROOT/'evidence/generated/model-1.boot').read_bytes()
    second=(ROOT/'evidence/generated/model-2.boot').read_bytes()
    third=(ROOT/'evidence/generated/model-3.boot').read_bytes()
    image=(args.demo/'assets/board1-real-semantic-image2048.bin').read_bytes()
    metadata=bytes.fromhex(''.join((args.demo/'hardware/project/metadata192.memh').read_text().split()))
    def hexfile(name,data):
        path=out/name;path.write_text(''.join(f'{b:02x}\n' for b in data));return path
    hexfile('image.hex',image)
    (out/'metadata.hex').write_text(''.join(metadata[i:i+24].hex()+'\n' for i in range(0,len(metadata),24)))
    frames=[('base',base,True),('changed-weight',second,True),('changed-metadata',third,True)]
    for name,at,value in [('domain',0,None),('geometry',16,None),('reserved',104,None),
                          ('policy',63,None),('version-without-signature',71,None),('root',72,None),
                          ('zero-signers',131,0),('one-signer',131,1),('four-signers',131,4),
                          ('unknown-signer',135,3),('duplicate-signer',1431,0),
                          ('ots-type',143,3),('lms-type',1267,6),
                          ('signature-chain',190,None),('signature-path',1290,None),
                          ('image-hash',2724,None),('digest-table',2756,None),
                          ('metadata',59524,None)]:
        b=bytearray(base);b[at]=b[at]^1 if value is None else value
        frames.append((name,bytes(b),False))
    frames += [('truncated',base[:-1],False),('oversized',base+b'\0',False)]
    authorities=[su.DemoAuthority(i) for i in range(3)]
    for ids in ([0,2],[1,2],[0,1,2]):
        package=su.make_package(image,metadata,1,[authorities[i] for i in ids],[0]*len(ids))
        su.verify_package(package,[a.public_key for a in authorities])
        frames.append(('authorities-'+''.join(map(str,ids)),package[:-su.IMAGE_BYTES],True))
    calls=[]
    for i,(name,frame,expected) in enumerate(frames):
        hexfile(f'frame-{i}.hex',frame)
        calls.append(f'boot_case({i},{len(frame)},1\'b{int(expected)});')
    tb=(ROOT/'tests/tb_memory.sv').read_text().replace('@@OUT@@',str(out)).replace('@@CASES@@','\n'.join(calls))
    (out/'tb_memory.sv').write_text(tb)
    build=Path(tempfile.mkdtemp(prefix='swic-memory-'))
    sources=[ROOT/'hardware/project/sha.sv',ROOT/'hardware/project/bank.sv',ROOT/'hardware/project/swic/su_sha256.sv',
             ROOT/'hardware/project/swic/su_lms_verify.sv',ROOT/'hardware/project/swic/swic_boot_admission.sv',ROOT/'hardware/project/swic/su_image_check.sv',
             ROOT/'hardware/project/swic/su_page_table_check.sv',
             ROOT/'hardware/project/swic/swic_verified_memory.sv',ROOT/'hardware/project/swic/su_policy.svh',out/'tb_memory.sv']
    for s in sources:shutil.copyfile(s,build/s.name)
    inputs=sorted(out.glob('frame-*.hex'))+[out/'image.hex',out/'metadata.hex']
    source_hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}
    input_hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in inputs}
    cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_memory','-j','1','--Mdir','obj']+[s.name for s in sources if s.suffix=='.sv']
    t=time.time()
    with (out/'build.log').open('w') as log:subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
    with (out/'run.log').open('w') as log:subprocess.run([str(build/'obj/Vtb_memory')],stdout=log,stderr=subprocess.STDOUT,check=True)
    for name,digest in {**source_hashes,**input_hashes}.items():
        assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'input changed during run: '+name
    result={'result':'PASS','boot_cases':[{'name':n,'accepted':e} for n,_,e in frames],
            'image_bytes_each':len(image),'native_page_bytes':4096,'elapsed_seconds':time.time()-t,
            'build_directory':str(build),'build_command':cmd,
            'source_sha256':source_hashes,'input_sha256':input_hashes}
    (out/'result.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'result':'PASS','boot_cases':len(frames),'elapsed_seconds':result['elapsed_seconds']},indent=2))

if __name__=='__main__':main()
