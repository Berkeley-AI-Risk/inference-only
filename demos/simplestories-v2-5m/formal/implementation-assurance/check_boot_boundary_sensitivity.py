"""Require source-level rejection of refreshed boot-boundary proof tampering."""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import shutil

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_boundary_sensitivity_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    audit,common,util,query=load('audit_boot_boundary'),load('run_handoff'),load('check_fifo_audit_sensitivity'),load('audit_fifo')
    original=HERE/'runs/boot-boundary-r3-owned-read-join'
    before={p.name:query.sha(p.read_bytes())for p in original.iterdir()if p.is_file()}
    controls={
        'changed-queued-production-address':'Instrumentation does not recover exact native production logic',
        'hidden-future-input-restriction':'An external protocol input was constrained',
        'wrong-current-image':'Native image/source/observer association changed',
        'missing-secondary-induction':'A required real-solver phase was omitted',
        'disabled-lock-order-obligations':'Boot boundary target/support monitor changed',
    }
    results=[]
    for name,reason in controls.items():
        case=out/name;shutil.copytree(original,case,copy_function=os.link)
        inp=json.loads((case/'INPUTS.json').read_bytes());fin=json.loads((case/'FINISHED.json').read_bytes());member=None
        if name=='changed-queued-production-address':
            member='fifo.sv';raw=(case/member).read_bytes()
            old=b'assign out_addr_o = addr_q[rd_ptr_q];'
            if raw.count(old)!=1:raise ValueError('Production control mutation site changed')
            util.replace(case/member,raw.replace(old,b'assign out_addr_o = 0;'))
        elif name=='hidden-future-input-restriction':
            member='reset.smtc';util.replace(case/member,(case/member).read_bytes()+b'state 2:*\nassume (= [private_loader_valid_i] false)\n')
        elif name=='wrong-current-image':inp['binding']['native_joins']['baseline']['image_sha256']='0'*64
        elif name=='missing-secondary-induction':del fin['results']['cvc5-induction']
        elif name=='disabled-lock-order-obligations':
            member='parent-monitor.inc.sv';raw=(case/member).read_bytes()
            util.replace(case/member,raw.replace(b'if (model_locked_o) begin',b"if (1'b0) begin"))
        if member:
            raw=(case/member).read_bytes();inp['files'][member]=dict(bytes=len(raw),sha256=query.sha(raw))
        raw=query.encode(inp);util.replace(case/'INPUTS.json',raw)
        fin['inputs_sha256']=query.sha(raw);fin['binding']=inp['binding'];util.replace(case/'FINISHED.json',query.encode(fin))
        diagnostics=out/('diagnostics-'+name)
        try:audit.inspect(case,common.DEFAULT_PACKAGE,diagnostics)
        except ValueError as error:
            if str(error)!=reason:raise ValueError('Wrong tamper rejection: '+str(error))from error
            if diagnostics.exists():raise ValueError('A source-only guard ran after compiler/query execution')
            results.append(dict(control=name,rejected=True,reason=str(error),metadata_refreshed=True))
        else:raise ValueError('Tampering was accepted: '+name)
    after={p.name:query.sha(p.read_bytes())for p in original.iterdir()if p.is_file()}
    if before!=after:raise ValueError('Original proof record changed')
    result=dict(schema='current-boot-boundary-auditor-sensitivity-v1',passed=True,controls=results,
        original_proof_unchanged=True,no_compiler_solver_or_hardware_invoked=True,
        checker_sha256=query.sha(Path(__file__).read_bytes()),auditor_sha256=query.sha((HERE/'audit_boot_boundary.py').read_bytes()))
    (out/'FINISHED.json').write_bytes(query.encode(result));print('BOOT BOUNDARY sensitivity PASS:',len(results),'refreshed-metadata controls')


if __name__=='__main__':main()
