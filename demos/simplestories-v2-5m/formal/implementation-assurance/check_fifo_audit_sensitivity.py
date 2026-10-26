"""Require the FIFO auditor to reject refreshed-metadata tampering controls."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(x):return(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def load(name):
    spec=importlib.util.spec_from_file_location('_fifo_sensitivity_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def replace(path,raw):
    # Copies share original inodes. Never write into a hard link: replace it
    # atomically with a new inode, preserving the actual proof record.
    temporary=path.with_name(path.name+'.tampered-copy')
    with temporary.open('xb')as f:f.write(raw)
    os.replace(temporary,path)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    audit,common,runner=load('audit_fifo'),load('run_handoff'),load('run_fifo')
    original=HERE/'runs/fifo-commands-r5'
    inp=json.loads((original/'INPUTS.json').read_bytes())
    before={name:sha((original/name).read_bytes())for name in list(inp['files'])+['INPUTS.json','FINISHED.json']}
    _,root,bound=common.binding(common.DEFAULT_PACKAGE,'baseline')
    controls={
        'changed-production':('fifo.sv','Instrumentation changed production FIFO logic'),
        'compiler-clamp':('prove.ys','Compiler recipe or clock lowering changed'),
        'future-input-assumption':('reset.smtc','Base reset constraints changed'),
        'missing-secondary-induction':(None,'Required real-solver phases are missing or changed'),
        'wrong-image-epoch':(None,'Current native/image binding changed: image_sha256'),
    }
    results=[]
    for name,(member,expected)in controls.items():
        case=out/name;shutil.copytree(original,case,copy_function=os.link)
        current=json.loads((case/'INPUTS.json').read_bytes())
        finished=json.loads((case/'FINISHED.json').read_bytes())
        if name=='changed-production':
            raw=(case/member).read_bytes();old=b'm_data_q <= memory_q[m_binary_next_address];'
            if raw.count(old)!=1:raise ValueError('Control mutation site changed')
            replace(case/member,raw.replace(old,b'm_data_q <= 0;'))
        elif name=='compiler-clamp':
            raw=(case/member).read_bytes().replace(b'write_smt2 -wires',b'setundef -zero\nwrite_smt2 -wires')
            replace(case/member,raw)
        elif name=='future-input-assumption':
            replace(case/member,(case/member).read_bytes()+b'state 2:*\nassume (= [s_valid_i] false)\n')
        elif name=='missing-secondary-induction':del finished['results']['cvc5-induction']
        elif name=='wrong-image-epoch':current['binding']['image_sha256']='0'*64
        if member:
            raw=(case/member).read_bytes();current['files'][member]=dict(bytes=len(raw),sha256=sha(raw))
        current_raw=encode(current);replace(case/'INPUTS.json',current_raw)
        finished['inputs_sha256']=sha(current_raw);replace(case/'FINISHED.json',encode(finished))
        diagnostics=out/('diagnostics-'+name);diagnostics.mkdir()
        try:audit.inspect(case,common,runner,root,bound,diagnostics)
        except ValueError as error:
            if str(error)!=expected:raise ValueError('Control was refused for the wrong reason: '+str(error))from error
            if any(diagnostics.iterdir()):raise ValueError('Expected source-only rejection occurred after tool execution')
            results.append(dict(control=name,rejected=True,reason=str(error),metadata_hashes_refreshed=True))
        else:raise ValueError('Tampering was accepted: '+name)
    after={name:sha((original/name).read_bytes())for name in before}
    if before!=after:raise ValueError('Original proof record changed')
    result=dict(schema='fifo-auditor-refreshed-metadata-sensitivity-v1',passed=True,controls=results,
        original_proof_record_unchanged=True,no_compiler_solver_or_hardware_invoked=True,
        checker_sha256=sha(Path(__file__).read_bytes()),auditor_sha256=sha((HERE/'audit_fifo.py').read_bytes()))
    (out/'FINISHED.json').write_bytes(encode(result))
    print('FIFO audit sensitivity PASS:',len(results),'tampering controls; original proof bytes unchanged')


if __name__=='__main__':main()
