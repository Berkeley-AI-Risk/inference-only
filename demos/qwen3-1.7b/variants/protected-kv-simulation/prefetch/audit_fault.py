"""Independent review of existing component logs; no native child execution."""
if not __debug__:
    raise RuntimeError('Run the prefetch auditors with Python assertions enabled')
from pathlib import Path
from datetime import datetime, timezone
from collections import defaultdict
import copy
import hashlib
import json

HERE=Path(__file__).resolve().parent

def need(ok,message):
    if not ok:raise ValueError(message)
def pin(path):
    digest=hashlib.sha256()
    with path.open('rb') as stream:
        for block in iter(lambda:stream.read(65536),b''):digest.update(block)
    return dict(bytes=path.stat().st_size,sha256=digest.hexdigest())
def read(path):return json.loads(path.read_bytes())
def save(path,value):path.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n')
def expected(role,coordinate,generation):
    m=(coordinate*17+role*67+generation*29)&511
    return (0x3e00+m)|(0x8000 if (coordinate+generation)%5==0 else 0)

def read_rows(path):
    lines=path.read_text().splitlines()
    need(lines[-1:]==['PASS operand_integrity_observation protected=1'],'Missing or malformed fault terminal PASS')
    need(all(line.startswith('{') for line in lines[:-1]),'Unexpected non-JSON native diagnostic')
    rows=[json.loads(line) for line in lines[:-1]]
    need(rows and all(isinstance(row,dict) for row in rows),'Native events must be JSON objects')
    return rows

def check_case(rows,scenario,stall):
    results=[r for r in rows if r['event']=='result'];need(len(results)==1,'Missing result')
    result=results[0];need(result['protected_build'] and result['stall_mode']==stall,'Wrong selection')
    cert=defaultdict(set);bad=set();operands=[];verifications=[];cache=[];requests=[]
    clear=next((r['cycle'] for r in rows if r['event']=='session_clear_asserted_with_outstanding_read'),None)
    for r in rows:
        event=r['event']
        if event=='actual_verification':
            key=(r['generation'],r['role']);need(r['epoch']==r['generation'],'Wrong live verification epoch')
            if r['ok']:
                kind='root' if r['root'] else 'leaf'
                if kind=='leaf':need('root' in cert[key],'Leaf pass without own root pass')
                cert[key].add(kind)
            else:bad.add(key)
            verifications.append(r)
        if event in ['operand_handshake','actual_cache_ready']:
            key=(r['generation'],r['role']);need(cert[key]=={'root','leaf'},'Use/cache without own root and leaf passes')
            need(key not in bad,'Use after failed role comparison')
            if event=='operand_handshake':
                need(not r['changed'],'Changed protected operand consumed')
                start=r['group']*64 if r['role'] else 0
                count=64 if r['role'] else 128
                need(r['BF16']==[expected(r['role'],i,r['generation']) for i in range(start,start+count)],'Actual operand differs from fixed independent source values')
                if clear is not None and r['cycle']>=clear:need(r['generation']==1,'Old-generation operand after CLEAR')
                operands.append(r)
            else:cache.append(r)
        if event=='raw_request':requests.append(r)
    if scenario in [0,3,4]:
        need(result['fault_cycle']==0 and result['outcome']=='original_operand_used','Healthy result refused or changed')
        need(any(r['event']=='attention_pair_success_result' for r in rows),'No real pair success')
        generation=1 if scenario==4 else 0
        need([sum(r['generation']==generation and r['role']==role for r in operands) for role in [0,1]]==[1,2],'Missing fresh real K/V handshakes')
    if scenario in [1,2]:
        role=scenario-1;need((0,role) in bad,'No actual failed targeted comparison')
        need(not any(r['role']==role for r in operands),'Affected role consumed')
        need(result['fault_cycle']>0 and result['outcome']=='fault_prevents_target_use','No fail-closed outcome')
        need(not any(r['event']=='attention_pair_success_result' for r in rows),'False healthy pair result')
    if scenario==4:
        need(0<result['clear_cycle']<result['old_return_cycle']<result['reopen_cycle'],'CLEAR did not drain real delayed return')
        need(result['blocked_clear_checks']>0,'No held-drain checks')
        need(not any(result['clear_cycle']<=r['cycle']<=result['reopen_cycle'] for r in operands),'Operand consumed during CLEAR/drain')
        old_v=[r for r in requests if r['address']==(1<<32)+8*4096 and r['cycle']<result['clear_cycle']]
        need(len(old_v)==1 and old_v[0]['initial_delay']==100,'CLEAR was not on the held V fetch')
    traffic=defaultdict(lambda:dict(requests=0,bytes=0))
    for r in requests:
        key=('update' if r['update'] else 'attention')+('_write' if r['write'] else '_read')+('_payload' if r['address']<(1<<33) else '_manifest')
        traffic[key]['requests']+=1;traffic[key]['bytes']+=r['bytes']
    # Normalize actual accepted read-beat offsets to each accepted request.
    # This distinguishes equal supplied stalls from different wall-clock starts.
    normalized=[];current=None
    for r in rows:
        if r['event']=='raw_request' and not r['update']:
            current=dict(address=r['address'],bytes=r['bytes'],initial_delay=r['initial_delay'],request_cycle=r['cycle'],beat_offsets=[])
            normalized.append(current)
        elif r['event']=='raw_read':
            need(current is not None and r['address']==current['address'],'Unowned observed read beat')
            current['beat_offsets'].append((r['beat'],r['cycle']-current['request_cycle']))
    for r in normalized:del r['request_cycle']
    return dict(result=result,requests=requests,traffic=dict(traffic),verifications=verifications,cache_ready=cache,actual_operands=operands,actual_relative_read_schedule=normalized)

