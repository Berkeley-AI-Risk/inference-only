"""Strict independent numerical transcript gate; no RTL or hardware execution."""
import hashlib
import importlib.util
import json
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
PUBLIC=ROOT
REFERENCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
INDEX_SHA='a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b'
SEED_A=0x99aabbccddeeff001122334455667788
SEED_B=0xfefdfcfbfaf9f8f70102030405060708

def need(ok,message):
    if not ok:raise ValueError(message)
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def canonical(value):return(json.dumps(value,sort_keys=True,separators=(',',':'))+'\n').encode()
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path);value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value
def sampler():
    path=PUBLIC/'variants/seeded-sampling/tools/sampler_oracle.py'
    need(sha(path)=='79102a2dfd67ba7f5287fd65595439c06504e4a3331009fe6c528bc8454ef97e','Independent sampler source changed')
    return module('_integration_independent_sampler',path)

def references():
    lane=PUBLIC/'reference/seeded-sampling';need(sha(lane/'SOURCE.json')==REFERENCE_SHA,'Numerical source inventory changed')
    need(sha(lane/'goldens/INDEX.json')==INDEX_SHA,'Numerical golden index changed')
    index=json.loads((lane/'goldens/INDEX.json').read_bytes());result={}
    for code in range(4):
        for seed in('a','b'):
            name=f'around128-t{code}-seed-{seed}.json';path=lane/'goldens'/name;raw=path.read_bytes()
            need(index['files'][name]==dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()),'Golden bytes changed')
            result[code,seed]=json.loads(raw)
    return result

def head(gold,index,temperature,seed):
    return dict(token=gold['generated_tokens'][index],head_rows_sha256=gold['head_rows_sha256'][index],
                temperature=temperature,seed=seed)

def plans():
    refs=references();greedy=refs[0,'a'];cases={}
    around=[head(greedy,i,0,None)for i in range(4)]+[head(greedy,0,0,None)]
    for label,flags in [('greedy-zero',['+ZERO_STALL']),('greedy-stalled',[])]:
        cases[label]=dict(flags=['+PROFILE_CASE=0',*flags],heads=around,pass_marker='PASS selective_reads_model case=0',kind='positive')
    for code in(1,2,3):
        expected=[head(refs[code,'a'],i,code,SEED_A)for i in range(3)]*2
        expected+=[head(refs[code,'b'],0,code,SEED_B),head(greedy,0,0,None)]
        cases[f'stochastic-{code}']=dict(flags=['+ZERO_STALL',f'+STOCH_T={code}','+PROFILE_CASE=0'],heads=expected,
            pass_marker=f'PASS stochastic_authenticated_model temperature={code}',kind='positive')
    for length in(16,32):
        for schedule,extra in [('zero',['+ZERO_STALL']),('stalled',[])]:
            expected=[head(greedy,i,0,None)for i in(length-1,length)]+[head(greedy,0,0,None)]
            cases[f'prefix{length}-{schedule}']=dict(flags=[f'+INTEGRATION_PREFIX={length}',*extra],heads=expected,
                pass_marker=f'PASS long_context_integration_prefill prompt={length}',kind='positive',
                prompt_tokens=[378]+greedy['generated_tokens'][:length-1])
    for label,flag in [('corrupt-boot','+CORRUPT_BOOT'),('corrupt-runtime','+CORRUPT_RUNTIME')]:
        cases[label]=dict(flags=['+ZERO_STALL',flag,'+PROFILE_CASE=0'],heads=[],kind='negative',
            pass_marker='PASS booted_semantic_negative mode='+('boot_corruption'if label=='corrupt-boot'else'post_boot_corruption'))
    for schedule,extra in [('zero',['+ZERO_STALL']),('stalled',[])]:
        cases[f'active-kv-clear-{schedule}']=dict(flags=['+INTEGRATION_CLEAR_KV',*extra],
            heads=[head(greedy,0,0,None),head(greedy,1,0,None),head(greedy,0,0,None)],
            pass_marker='PASS long_context_integration_kv_clear',kind='ownership')
        cases[f'bad-kv-padding-{schedule}']=dict(flags=['+INTEGRATION_BAD_KV_PADDING',*extra],
            heads=[head(greedy,0,0,None)],pass_marker='PASS long_context_integration_bad_kv_padding',kind='negative')
    return cases

def check_capture(text,expected):
    """Reject wrong rows even when a changed logit samples the same token."""
    oracle=sampler();temperature=0;seed=1;state=oracle.initial_state(seed)
    rows=[];ordinal=0;open_head=False;results=[]
    for line in text.splitlines():
        pieces=line.split();need(pieces,'Empty transcript line')
        if pieces[0]=='CONFIG':
            need(len(pieces)==3 and not open_head,'Configuration inside an open head')
            temperature=int(pieces[1]);seed=int(pieces[2],16);need(temperature in range(4)and 0<=seed<1<<128,'Invalid configuration')
            state=oracle.initial_state(seed)
        elif pieces[0]=='CLEAR':
            need(len(pieces)==1 and not open_head,'CLEAR discarded an uncommitted captured head');state=oracle.initial_state(seed)
        elif pieces[0]=='HEAD':
            need(len(pieces)==2 and not open_head and int(pieces[1])==ordinal+1,'Missing/repeated head ordinal')
            ordinal+=1;need(ordinal<=len(expected),'Unexpected extra head');open_head=True;rows=[]
        elif pieces[0]=='ROW':
            need(len(pieces)==4 and open_head and int(pieces[1])==len(rows)<4019,'Head row order/count differs')
            raw,exponent=int(pieces[2]),int(pieces[3]);need(-(1<<49)<=raw<1<<49 and -128<=exponent<128,'Head arithmetic width differs')
            rows.append((raw,exponent))
        elif pieces[0]=='PICK':
            need(len(pieces)==3 and open_head and int(pieces[1])==ordinal and len(rows)==4019,'Incomplete head committed')
            want=expected[ordinal-1];digest=hashlib.sha256(canonical(rows)).hexdigest()
            need(digest==want['head_rows_sha256'],'Numerical head rows differ from the independent exact model')
            need(temperature==want['temperature']and(want['seed']is None or seed==want['seed']),'Sampling configuration differs')
            token,state=oracle.sample(rows,temperature,state)
            need(int(pieces[2])==token==want['token'],'Sampled token differs from exact model/oracle')
            results.append(dict(head=ordinal,token=token,head_rows_sha256=digest,
                temperature=temperature,seed=f'0x{seed:032x}',oracle_prng_state=[f'0x{x:016x}'for x in state]))
            open_head=False;rows=[]
        else:raise ValueError('Unexpected transcript record: '+pieces[0])
    need(not open_head and len(results)==len(expected),'Missing numerical heads')
    return dict(passed=True,heads=len(results),head_rows_compared=4019*len(results),results=results)
