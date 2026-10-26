"""Reject composed-proof tampering even after its metadata is refreshed."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_transport_sensitivity_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    audit,common,helpers=load('audit_transport'),load('run_handoff'),load('check_fifo_audit_sensitivity')
    original=HERE/'runs/transport-baseline-r3-fields'
    fresh_path=HERE/'audit-probes/transport-source-audit-r2-fields/fifo-premise-recheck/FINISHED.json'
    fresh=json.loads(fresh_path.read_bytes())
    before={p.name:audit.sha(p.read_bytes())for p in original.iterdir()if p.is_file()}
    controls={
        'new-unproved-fifo-assumption':'A transport assumption is not an independently proved FIFO invariant',
        'missing-fifo-premise':'Required independently proved FIFO premise is missing',
        'new-field-became-assumption':'New transport/range obligations changed or became assumptions',
        'positive-future-input-constraint':'External reset/protocol assumptions changed',
        'missing-secondary-induction':'A real solver phase was omitted',
    }
    records=[]
    for name,expected in controls.items():
        case=out/name;shutil.copytree(original,case,copy_function=os.link)
        inp=json.loads((case/'INPUTS.json').read_bytes());fin=json.loads((case/'FINISHED.json').read_bytes())
        member=None
        if name=='new-unproved-fifo-assumption':
            member='fifo-monitor.inc.sv'
            helpers.replace(case/member,(case/member).read_bytes()+b'    always_comb assume(!s_valid_i);\n')
        elif name=='missing-fifo-premise':
            member='discharged-fifo-lemma-audit.json';d=json.loads((case/member).read_bytes())
            d['runs']=[r for r in d['runs']if r['run']!='fifo-commands-r5']
            raw=audit.encode(d);helpers.replace(case/member,raw)
            inp['binding']['fifo_lemma_audit_sha256']=audit.sha(raw)
        elif name=='new-field-became-assumption':
            member='parent-monitor.inc.sv';raw=(case/member).read_bytes()
            old=b'assert(core_write == (core_cmd_i == 0));'
            if raw.count(old)!=1:raise ValueError('Field control mutation site changed')
            helpers.replace(case/member,raw.replace(old,b'assume(core_write == (core_cmd_i == 0));'))
        elif name=='positive-future-input-constraint':
            member='reset.smtc';helpers.replace(case/member,(case/member).read_bytes()+b'state 2:*\nassume (= [core_cmd_en_i] false)\n')
        elif name=='missing-secondary-induction':del fin['results']['cvc5-induction']
        if member:
            raw=(case/member).read_bytes();inp['files'][member]=dict(bytes=len(raw),sha256=audit.sha(raw))
        raw=audit.encode(inp);helpers.replace(case/'INPUTS.json',raw)
        fin['inputs_sha256']=audit.sha(raw);fin['binding']=inp['binding']
        helpers.replace(case/'FINISHED.json',audit.encode(fin))
        diagnostics=out/('diagnostics-'+name)
        try:audit.inspect(case,'baseline',common.DEFAULT_PACKAGE,fresh,diagnostics)
        except ValueError as error:
            if str(error)!=expected:raise ValueError('Wrong rejection reason: '+str(error))from error
            if diagnostics.exists():raise ValueError('Source-only rejection occurred after tool execution')
            records.append(dict(control=name,rejected=True,reason=str(error),metadata_hashes_refreshed=True))
        else:raise ValueError('Tampering accepted: '+name)
    after={p.name:audit.sha(p.read_bytes())for p in original.iterdir()if p.is_file()}
    if before!=after:raise ValueError('Original transport proof bytes changed')
    result=dict(schema='compositional-transport-auditor-sensitivity-v1',passed=True,
        controls=records,original_proof_unchanged=True,no_compiler_solver_or_hardware_invoked=True,
        premise_recheck_sha256=audit.sha(fresh_path.read_bytes()),
        auditor_sha256=audit.sha((HERE/'audit_transport.py').read_bytes()),
        checker_sha256=audit.sha(Path(__file__).read_bytes()))
    (out/'FINISHED.json').write_bytes(audit.encode(result))
    print('TRANSPORT audit sensitivity PASS:',len(records),'refreshed-metadata controls')


if __name__=='__main__':main()
