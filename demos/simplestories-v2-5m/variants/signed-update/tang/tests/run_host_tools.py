#!/usr/bin/env python3
"""Offline checks of flash preparation/readback and the frozen UART protocol."""
from pathlib import Path
import hashlib,importlib.util,json,socket,subprocess,sys,tempfile,threading
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'evidence/host-tools';out.mkdir(exist_ok=False)
work=Path(tempfile.mkdtemp(prefix='swic-host-check-'))
slot=(ROOT/'evidence/fixtures/case-0.slot.bin').read_bytes()
image=(ROOT/'evidence/fixtures/case-0.image.bin').read_bytes()
package=slot[:115396]+image;(work/'base.swic').write_bytes(package)
rows=[]
def invoke(name,args,expect):
    r=subprocess.run([sys.executable,str(ROOT/'tools'/name)]+[str(x) for x in args],stdout=subprocess.PIPE,stderr=subprocess.STDOUT)
    (out/f'{len(rows):02d}.log').write_bytes(r.stdout)
    assert (r.returncode==0)==expect,(name,r.stdout[-1000:])
    rows.append({'tool':name,'expected_success':expect,'exit_code':r.returncode,'log_sha256':hashlib.sha256(r.stdout).hexdigest()})
invoke('prepare_flash.py',['--package',work/'base.swic','--output',work/'prepared'],True)
plan=work/'prepared/FLASH-PLAN.json'
assert (work/'prepared/model.bin').read_bytes()==image
assert (work/'prepared/admission-slot.bin').read_bytes()==slot
(out/'FLASH-PLAN.json').write_bytes(plan.read_bytes())
invoke('prepare_flash.py',['--package',work/'base.swic','--output',work/'prepared'],False)
bad=bytearray(package);bad[190]^=1;(work/'bad.swic').write_bytes(bad)
invoke('prepare_flash.py',['--package',work/'bad.swic','--output',work/'bad-prepared'],False)
assert not (work/'bad-prepared').exists()
full=bytearray(b'\xff'*16777216);full[0x801000:0x801000+len(image)]=image;full[0xf00000:0xf40000]=slot
(work/'full.bin').write_bytes(full)
invoke('check_flash.py',['--plan',plan,'--readback',work/'full.bin'],True)
for address in [0,0x801000,0xf00000,0xf3ffff,0xffffff]:
    full[address]^=1;(work/'full.bin').write_bytes(full)
    invoke('check_flash.py',['--plan',plan,'--readback',work/'full.bin'],False);full[address]^=1
baseline=bytes([0xa5])*16777216;(work/'baseline.bin').write_bytes(baseline)
invoke('prepare_preserving_flash.py',['--plan',plan,'--backup',work/'baseline.bin','--output',work/'preserved.bin'],True)
preserved=bytearray(baseline);preserved[0x801000:0x801000+len(image)]=image;preserved[0xf00000:0xf40000]=slot
assert (work/'preserved.bin').read_bytes()==preserved
invoke('prepare_preserving_flash.py',['--plan',plan,'--backup',work/'baseline.bin','--output',work/'preserved.bin'],False)
invoke('check_flash.py',['--plan',plan,'--readback',work/'preserved.bin','--baseline',work/'baseline.bin'],True)
invoke('check_flash.py',['--plan',plan,'--readback',work/'preserved.bin'],False)
preserved[0]^=1;(work/'preserved.bin').write_bytes(preserved)
invoke('check_flash.py',['--plan',plan,'--readback',work/'preserved.bin','--baseline',work/'baseline.bin'],False)
preserved[0]^=1;(work/'preserved.bin').write_bytes(preserved)
invoke('prepare_flash_blocks.py',['--before',work/'baseline.bin','--candidate',work/'preserved.bin','--output',work/'blocks'],True)
replayed=bytearray(baseline);block_plan=json.loads((work/'blocks/BLOCK-PLAN.json').read_text())
for row in block_plan['writes']:
    assert row['address']%65536==0 and row['bytes']%65536==0
    payload=(work/'blocks'/row['file']).read_bytes();assert len(payload)==row['bytes']
    replayed[row['address']:row['address']+len(payload)]=payload
assert replayed==preserved
invoke('prepare_flash_blocks.py',['--before',work/'baseline.bin','--candidate',work/'preserved.bin','--output',work/'blocks'],False)
preserved[0]^=1;(work/'preserved.bin').write_bytes(preserved)
invoke('prepare_flash_blocks.py',['--before',work/'baseline.bin','--candidate',work/'preserved.bin','--output',work/'bad-blocks'],False)
spec=importlib.util.spec_from_file_location('uart_check',ROOT/'tools/uart_check.py');uart=importlib.util.module_from_spec(spec);spec.loader.exec_module(uart)
uart_rows=[]
for op,tok,value,bad in [(2,0,0,None),(0,1,0,None),(1,0,108,None),(1,0,32,None),(0,1,1,'ack'),(1,0,108,'crc'),(1,0,108,'status')]:
    a,b=socket.socketpair();seen=[]
    def peer():
        request=b.recv(5);seen.append(request)
        payload=bytes([0x5a,0x80+op,value&255,value>>8]);reply=payload+bytes([uart.crc8(payload)])
        if bad=='crc':reply=reply[:-1]+bytes([reply[-1]^1])
        if bad=='status':
            payload=payload[:1]+b'\x90'+payload[2:];reply=payload+bytes([uart.crc8(payload)])
        b.sendall(reply[:2]);b.sendall(reply[2:]);b.close()
    t=threading.Thread(target=peer);t.start();accepted=False
    try:result=uart.transact(a.fileno(),op,tok,2);accepted=True
    except ValueError:pass
    finally:a.close();t.join()
    assert accepted==(bad is None)
    assert seen[0][:4]==bytes([0xa5,op,tok&255,tok>>8]) and seen[0][4]==uart.crc8(seen[0][:4])
    uart_rows.append({'opcode':op,'input':tok,'value':value,'corruption':bad,'accepted':accepted})
record={'result':'PASS','hardware_access':False,'cli_cases':rows,'uart_cases':uart_rows,
        'package_sha256':hashlib.sha256(package).hexdigest(),
        'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [Path(__file__).resolve(),ROOT/'tools/prepare_flash.py',ROOT/'tools/prepare_preserving_flash.py',ROOT/'tools/prepare_flash_blocks.py',ROOT/'tools/check_flash.py',ROOT/'tools/uart_check.py',ROOT/'reference/tang_image.py',ROOT/'reference/signed_update.py']}}
(out/'result.json').write_text(json.dumps(record,indent=2)+'\n');print(f'PASS host tools: {len(rows)} flash CLI cases, 7 UART protocol cases; no hardware access')
