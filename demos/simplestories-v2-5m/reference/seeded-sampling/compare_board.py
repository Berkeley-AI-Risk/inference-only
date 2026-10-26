#!/usr/bin/env python3
"""Compare a sanitized physical case with a fixed whole-model numerical golden.

Input JSON has case, temperature, seed, prompt_tokens, generated_tokens,
image_sha256 and an ordered wire array of {direction,frame_hex}. Each request
must have exactly its observed reply. This program performs no hardware access.
"""
import argparse
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
FPGA_SHA='0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'
TEMPERATURES=('0','0.5','1','2')
def require(ok,message):
    if not ok:raise ValueError(message)
def crc8(data):
    c=0
    for byte in data:
        c^=byte
        for _ in range(8):c=((c<<1)^(7 if c&128 else 0))&255
    return c
def frame(data):return(data+bytes([crc8(data)])).hex()
def legacy(op,token=0):return frame(bytes([0xa5,op,token&255,token>>8]))
def response(kind,operand=0):return frame(bytes([0x5a,kind,operand&255,operand>>8]))

def compare_context(data,golden,around):
    """Full baseline-style recovery/capacity plan, one SETTINGS then three probes."""
    for key in('case','temperature','seed','prompt_tokens','generated_tokens'):
        require(data[key]==golden[key],'Physical/reference mismatch: '+key)
    require(data['image_sha256']==FPGA_SHA,'Physical image association differs')
    require(around['temperature']==golden['temperature']and around['seed']==golden['seed']
        and around['case']=='around128','Recovery probe reference settings differ')
    code=TEMPERATURES.index(golden['temperature']);seed=int(golden['seed'],16);pairs=[]
    def command(op,token=0,kind=None,operand=0):
        pairs.append((legacy(op,token),response(0x80+op if kind is None else kind,operand)))
    def probe():
        command(2);command(1,kind=0xc1);command(0,378)
        for token in around['generated_tokens'][:4]:command(1,operand=token)
    command(2);pairs.append((frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little')),response(0x83,code)))
    probe();command(2)
    for token in golden['prompt_tokens']:command(0,token)
    tape=len(golden['prompt_tokens'])
    for token in golden['generated_tokens']:
        if tape==2048:command(0,378,kind=0xc0)
        command(1,operand=token);tape+=1
    if tape==2049:command(0,378,kind=0xc0);command(1,kind=0xc1)
    probe();probe();command(2)
    expected=[dict(direction=d,frame_hex=raw)for pair in pairs for d,raw in zip(('tx','rx'),pair)]
    require(data['wire']==expected,'Physical recovery/context sequence, CRC, replay, bounds or outputs differ')
    for row in data['wire']:
        raw=bytes.fromhex(row['frame_hex']);require(crc8(raw[:-1])==raw[-1],'Physical context frame CRC differs')
    return dict(passed=True,long_outputs_compared=len(golden['generated_tokens']),
        recovery_outputs_compared=12,prompt_tokens=len(golden['prompt_tokens']),
        commands=len(pairs),settings_applied_once=True,replay_without_settings=True,
        capacity_boundary_checked=tape==2049,final_clear_acknowledged=True,
        hardware_access=False,physical_configuration_attested=False)

def compare(data,golden):
    for key in('case','temperature','seed','prompt_tokens','generated_tokens'):
        require(data[key]==golden[key],'Physical/reference mismatch: '+key)
    require(data['image_sha256']==FPGA_SHA,'Physical image association differs')
    code=TEMPERATURES.index(golden['temperature']);seed=int(golden['seed'],16)
    pairs=[(legacy(2),response(0x82))]
    if not data.get('replay_without_settings',False):
        pairs.append((frame(bytes([0xa5,3,code])+seed.to_bytes(16,'little')),response(0x83,code)))
    pairs +=[(legacy(0,t),response(0x80))for t in golden['prompt_tokens']]
    pairs +=[(legacy(1),response(0x81,t))for t in golden['generated_tokens']]
    pairs +=[(legacy(2),response(0x82))]
    expected=[dict(direction=direction,frame_hex=raw)for pair in pairs for direction,raw in zip(('tx','rx'),pair)]
    require(data['wire']==expected,'Physical frame sequence, CRC, settings or token differs')
    for row in data['wire']:
        raw=bytes.fromhex(row['frame_hex']);require(crc8(raw[:-1])==raw[-1],'Physical frame CRC differs')
    return dict(passed=True,outputs_compared=len(golden['generated_tokens']),prompt_tokens=len(golden['prompt_tokens']),
        final_clear_acknowledged=True,hardware_access=False,physical_configuration_attested=False)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--physical-case',type=Path,required=True)
    parser.add_argument('--context-matrix',action='store_true',help='three four-token recovery probes plus capacity rejection plan')
    parser.add_argument('--golden',type=Path,required=True);args=parser.parse_args()
    raw=args.golden.read_bytes();index=json.loads((HERE/'goldens/INDEX.json').read_bytes())['files']
    require(index.get(args.golden.name)==dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()),'Golden not pinned in package')
    physical=json.loads(args.physical_case.read_bytes());golden=json.loads(raw)
    if args.context_matrix:
        seed_name={'0x99aabbccddeeff001122334455667788':'a','0xfefdfcfbfaf9f8f70102030405060708':'b'}[golden['seed']]
        name=f'around128-t{TEMPERATURES.index(golden["temperature"])}-seed-{seed_name}.json'
        around_raw=(HERE/'goldens'/name).read_bytes()
        require(index[name]==dict(bytes=len(around_raw),sha256=hashlib.sha256(around_raw).hexdigest()),'Recovery golden differs')
        result=compare_context(physical,golden,json.loads(around_raw))
    else:result=compare(physical,golden)
    print(json.dumps(result,indent=2))
