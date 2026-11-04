#!/usr/bin/env python3
"""Read the entire tested Tang flash through a qualified openFPGALoader 1.1.1.

This resets/replaces volatile FPGA configuration to enter the GW5A SPI read
path. It never requests flash erase/program, unprotect, quad or security modes.
Qualify the installed binary against two independent maintenance-reader dumps
before relying on this transport. Keep raw captures and receipts private.
"""
from pathlib import Path
import argparse,datetime,hashlib,json,os,re,subprocess,time
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--openloader',required=True,type=Path);p.add_argument('--tool-sha256',required=True)
p.add_argument('--serial',required=True);p.add_argument('--output',required=True,type=Path)
p.add_argument('--expected-array',type=Path)
a=p.parse_args();receipt=a.output.with_name(a.output.name+'.json');logfile=a.output.with_name(a.output.name+'.log')
if any(os.path.lexists(x) for x in [a.output,receipt,logfile]):raise FileExistsError('preserve existing evidence')
if hashlib.sha256(a.openloader.read_bytes()).hexdigest()!=a.tool_sha256:raise ValueError('different openFPGALoader binary')
if 'v1.1.1' not in subprocess.check_output([str(a.openloader),'-V'],text=True):raise ValueError('unsupported tool version')
expected=a.expected_array.read_bytes() if a.expected_array else None
if expected is not None and len(expected)!=16777216:raise ValueError('expected array must be exactly 16 MiB')
cmd=[str(a.openloader),'-b','tangmega138k','--ftdi-serial',a.serial,'--ftdi-channel','0',
     '--freq','900000','-v','--dump-flash','--file-size','16777216','--offset','0',str(a.output)]
result={'status':'PENDING','array_write':False,'volatile_configuration_reset':True,'command':cmd,
        'tool_sha256':a.tool_sha256,'started_utc':datetime.datetime.now(datetime.timezone.utc).isoformat()}
with receipt.open('x') as f:json.dump(result,f,indent=2);f.write('\n')
t=time.time()
try:
    with logfile.open('xb') as log:
        child=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT)
        awake=subprocess.Popen(['/usr/bin/caffeinate','-i','-w',str(child.pid)])
        code=child.wait();awake.wait()
    text=logfile.read_text(errors='replace');plain=re.sub(r'\x1b\[[0-9;]*m','',text)
    if code!=0 or re.search(r'\b(?:ERROR|FAIL|FAILED|FAILURE)\b',plain,re.I):raise RuntimeError('read tool reported an error; preserve state and investigate')
    if not re.search(r'idcode\s+0x0*1081b',plain,re.I):raise ValueError('different FPGA identity')
    parts=[]
    for pattern in [r'Jedec ID\s*:\s*([0-9a-f]{2})',r'memory type\s*:\s*([0-9a-f]{2})',r'memory capacity\s*:\s*([0-9a-f]{2})']:
        match=re.search(pattern,plain,re.I)
        if not match:raise ValueError('missing flash identity field')
        parts.append(match.group(1).lower())
    if ''.join(parts)!='0b4018':raise ValueError('different flash identity')
    data=a.output.read_bytes()
    if len(data)!=16777216:raise ValueError('incomplete flash capture')
    if expected is not None and data!=expected:raise ValueError('complete-array readback differs from expected image')
    result.update(status='PASS',bytes=len(data),sha256=hashlib.sha256(data).hexdigest(),
                  expected_array_equal=True if expected is not None else None,elapsed_seconds=time.time()-t,
                  log_sha256=hashlib.sha256(logfile.read_bytes()).hexdigest())
except BaseException as exc:
    result.update(status='INCOMPLETE',error=str(exc),elapsed_seconds=time.time()-t)
    receipt.write_text(json.dumps(result,indent=2)+'\n');raise
receipt.write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ['status','bytes','expected_array_equal','elapsed_seconds','array_write']},indent=2))
