"""Check rejection of altered composed evidence with refreshed metadata."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_epoch_sensitivity_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(value):return(json.dumps(value,indent=2,sort_keys=True)+'\n').encode()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--audit',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    audit,common,helpers=map(load,('audit_transport_epoch','run_handoff','check_fifo_audit_sensitivity'))
    fresh={k:json.loads((args.audit/(k+'-premise-recheck/FINISHED.json')).read_bytes())for k in ('fifo','source','reset','top')}
    final=(args.audit/'FINISHED.json').read_bytes()
    if not json.loads(final)['passed']:raise ValueError('Original composition audit is incomplete')
    original=HERE/'runs/transport-epoch-baseline-r3-exact-kv-prefix'
    before={p.name:sha(p.read_bytes())for p in original.iterdir()if p.is_file()}
    controls={
        'unproved-source-assumption':'A monitor or assumption changed',
        'missing-fifo-premise':'Required independently proved FIFO premise is missing',
        'disabled-physical-target':'A monitor or assumption changed',
        'future-input-constraint':'Safety or coverage input constraints changed',
        'missing-primary-induction':'A real solver phase was omitted',
        'wrong-native-image':'Native source/image binding changed',
        'changed-production-address':'Production bodies differ beyond declared observers/view rename/mutation',
    }
    records=[]
    for name,expected in controls.items():
        case=out/name;shutil.copytree(original,case,copy_function=os.link)
        inp=json.loads((case/'INPUTS.json').read_bytes());fin=json.loads((case/'FINISHED.json').read_bytes())
        member=None
        if name=='unproved-source-assumption':
            member='parent-epoch.inc.sv'
            helpers.replace(case/member,(case/member).read_bytes()+b'    always_comb assume(!core_cmd_en_i);\n')
        elif name=='missing-fifo-premise':
            member='discharged-fifo-lemma-audit.json';d=json.loads((case/member).read_bytes())
            d['runs']=[r for r in d['runs']if r['run']!='fifo-commands-r5']
            helpers.replace(case/member,encode(d))
        elif name=='disabled-physical-target':
            member='parent-epoch.inc.sv';raw=(case/member).read_bytes()
            old=b'if ((f_runtime_observed_q || f_formal_runtime_locked_i) && app_cmd_en_o && app_cmd_o == 0)'
            if raw.count(old)!=1:raise ValueError('Target control site changed')
            helpers.replace(case/member,raw.replace(old,b'if (1\'b0)'))
        elif name=='future-input-constraint':
            member='reset.smtc';helpers.replace(case/member,(case/member).read_bytes()+b'state 2:*\nassume (= [core_cmd_en_i] false)\n')
        elif name=='missing-primary-induction':del fin['results']['z3-induction']
        elif name=='wrong-native-image':
            _,_,bound=common.binding(common.DEFAULT_PACKAGE,'baseline')
            key=next(k for k in bound if'image'in k and isinstance(bound[k],str)and len(bound[k])==64)
            inp['binding'][key]='0'*64
        elif name=='changed-production-address':
            member='transport.sv';raw=(case/member).read_bytes()
            old=b"assign app_addr_o = {7'd0,request_m_data[274:256],3'b000};"
            if raw.count(old)!=1:raise ValueError('Production mutation site changed')
            helpers.replace(case/member,raw.replace(old,b"assign app_addr_o = 29'd0;"))
        if member:
            raw=(case/member).read_bytes();inp['files'][member]=dict(bytes=len(raw),sha256=sha(raw))
        raw=encode(inp);helpers.replace(case/'INPUTS.json',raw)
        fin['inputs_sha256']=sha(raw);fin['binding']=inp['binding'];helpers.replace(case/'FINISHED.json',encode(fin))
        diagnostics=out/('diagnostics-'+name)
        try:audit.inspect(case,'baseline',common.DEFAULT_PACKAGE,fresh,diagnostics)
        except ValueError as error:
            if str(error)!=expected:raise ValueError('Wrong rejection reason: '+str(error))from error
            if diagnostics.exists():raise ValueError('A source-only rejection occurred after compiler execution')
            records.append(dict(control=name,rejected=True,reason=str(error),metadata_hashes_refreshed=True))
        else:raise ValueError('Tampered proof accepted: '+name)
    if before!={p.name:sha(p.read_bytes())for p in original.iterdir()if p.is_file()}:
        raise ValueError('Original proof bytes changed')
    result=dict(schema='physical-write-epoch-auditor-sensitivity-v1',passed=True,controls=records,
        original_proof_unchanged=True,no_compiler_solver_or_hardware_invoked=True,
        source_audit_sha256=sha(final),auditor_sha256=sha((HERE/'audit_transport_epoch.py').read_bytes()),
        checker_sha256=sha(Path(__file__).read_bytes()))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());(out/'FINISHED.json').write_bytes(encode(result))
    print('PHYSICAL WRITE EPOCH audit sensitivity PASS:',len(records),'refreshed-metadata controls')


if __name__=='__main__':main()
