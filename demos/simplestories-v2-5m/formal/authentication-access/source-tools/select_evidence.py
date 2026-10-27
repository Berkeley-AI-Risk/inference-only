"""Freeze the current audited proof/premise/negative-control evidence closure."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
MANDATORY='''bank-interface-mutant-raw-valid-r1 modular-sum-regroup-r1 pool-loop-equivalence-r1
encrypted-bank-lifecycle-r6-owner-contract-r1 encrypted-bank-lifecycle-r6-ordered-all-k2-r2
service-consumer-baseline-projected-contract-r2 service-consumer-encrypted-projected-contract-r2
service-consumer-baseline-ordered-z3-k2-r1 service-consumer-encrypted-ordered-z3-k2-r1
service-consumer-baseline-cover-k14-r2 service-consumer-encrypted-cover-k14-r2
service-digest-mutant-order-cvc5-vcd-r3 service-digest-mutant-word-cvc5-witness-r1
kv-history-protected-mutant-clear-r2 kv-history-protected-mutant-write-r2
kv-history-encrypted-mutant-clear-r1 kv-history-encrypted-mutant-write-r1
current-kv-parent-lost-clear-r1 current-kv-parent-raw-read-bypass-r1
encrypted-kv-parent-lost-clear-r2 encrypted-kv-parent-raw-read-bypass-r2
audit-controller-access-r3 audit-model-addresses-r1 audit-kv-composition-r2 audit-machine-access-r1
audit-current-attention34-r1 audit-current-baseline-attention34-r1'''.split()


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    available={p.name:p for p in(HERE/'runs').iterdir()if p.is_dir()}
    selected=set(MANDATORY);audits={};audit_hashes={}
    def visit(value):
        if isinstance(value,dict):
            for v in value.values():visit(v)
        elif isinstance(value,list):
            for v in value:visit(v)
        elif isinstance(value,str):
            for part in value.split('/'):
                if part in available:selected.add(part)
    for path in sorted(HERE.glob('*AUDIT.json')):
        raw=path.read_bytes();data=json.loads(raw)
        if data.get('passed')is not True:raise ValueError('An advertised component audit is incomplete')
        audits[path.name]=dict(bytes=len(raw),sha256=sha(raw));audit_hashes[sha(raw)]=path.name;visit(data)
    if len(audits)!=22:raise ValueError('Reviewed current component inventory changed')
    # A canonical audit is also preserved with its full query/re-elaboration
    # outputs; exact digest equality identifies its successful original run.
    for name,path in available.items():
        f=path/'FINISHED.json'
        if f.is_file()and sha(f.read_bytes())in audit_hashes:selected.add(name)
    inspected=set()
    while selected-inspected:
        for name in sorted(selected-inspected):
            if name not in available:raise ValueError('Required evidence directory absent: '+name)
            for filename in('INPUTS.json','FINISHED.json'):
                path=available[name]/filename
                if path.is_file():visit(json.loads(path.read_bytes()))
            inspected.add(name)
    spec=importlib.util.spec_from_file_location('_selection_binding',HERE.parent/'formal-assurance/run_handoff.py')
    common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
    joins={v:common.binding(args.package,v)[2]for v in('baseline','kv-protected','encrypted-memory','seeded-sampling')}
    directories={name:dict(files=sum(p.is_file()for p in available[name].rglob('*')),
        bytes=sum(p.stat().st_size for p in available[name].rglob('*')if p.is_file()))for name in sorted(selected)}
    result=dict(schema='current-authentication-access-selected-evidence-v1',passed=True,
        canonical_component_audits=audits,selected_run_directories=directories,native_joins=joins,
        vendor_source_files_must_be_omitted=True,hardware_changed=False,hardware_access=False,
        raw_results_and_unknowns_preserved=True,counts_overlap=True,
        scope='Frozen evidence closure for current source-bound authentication/access facts; selected original partial aggregates and secondary timeouts remain unchanged. No obsolete hardware release or new numerical/physical theorem is introduced.')
    with args.out.open('x')as f:json.dump(result,f,indent=2,sort_keys=True);f.write('\n')
    print(json.dumps(dict(passed=True,component_audits=len(audits),directories=len(selected),raw_bytes=sum(r['bytes']for r in directories.values()))))


if __name__=='__main__':main()
