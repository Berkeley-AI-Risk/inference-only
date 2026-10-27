"""Join native K/V history, actual SHA, current cache and attention proofs.

This is a source-bound assume/guarantee composition of universal component
facts. It is not a monolithic numerical-attention or cryptographic-hardness
theorem. Every hash reply in the old history/cache scope was unrestricted;
the real, separately proved SHA implementation is a permitted refinement.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    s=importlib.util.spec_from_file_location('_KV_composition_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def checked_audit(path):
    raw=path.read_bytes();d=json.loads(raw)
    if d.get('passed')is not True:raise ValueError('Incomplete prerequisite: '+str(path))
    for name,digest in d.get('checked_sha256',{}).items():
        if sha(Path(name).read_bytes())!=digest:raise ValueError('A source/query/log consumed by the prerequisite changed')
    for name,digest in d.get('outputs_sha256',{}).items():
        if sha((path.parent/name).read_bytes())!=digest:raise ValueError('A source audit output changed')
    return d,dict(path=str(path),sha256=sha(raw),bytes=len(raw))


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    common=load('bindings',HERE.parent/'formal-assurance/run_handoff.py')
    hash_audit,hash_pin=checked_audit(HERE/'KV-HASH-AUDIT.json')
    compact,compact_pin=checked_audit(HERE/'SHA-COMPACT-AUDIT.json')
    held,held_pin=checked_audit(HERE/'SHA-HELD-AUDIT.json')
    rows=[]
    for variant,history_name,history_audit,parent_name,parent_audit,source in(
        ('kv-protected','kv-history-protected-split-r1','audit-kv-history-protected-r2',
         'current-kv-parent-positive-r1','audit-current-kv-parent-r1',
         HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1'),
        ('encrypted-memory','kv-history-encrypted-split-r1','audit-kv-history-encrypted-r1',
         'encrypted-kv-parent-positive-r2','audit-encrypted-kv-parent-r2',HERE/'encrypted-kv-parent-source-r2')):
        _,native,bound=common.binding(args.package,variant)
        history=HERE/'runs'/history_name;parent=HERE/'runs'/parent_name
        h,history_pin=checked_audit(HERE/'runs'/history_audit/'FINISHED.json')
        c,parent_pin=checked_audit(HERE/'runs'/parent_audit/'FINISHED.json')
        hi=json.loads((history/'INPUTS.json').read_bytes());hf=json.loads((history/'FINISHED.json').read_bytes())
        pi=json.loads((parent/'INPUTS.json').read_bytes());pf=json.loads((parent/'FINISHED.json').read_bytes())
        if hi['assertions']!=221 or not hf['passed']or len(hf['solver_results'])!=446:
            raise ValueError('Full guard history theorem absent')
        if pi['assertions']!=357 or not pf['passed']or len(pf['solver_results'])!=736:
            raise ValueError('Full current joint cache theorem absent')
        if any(not row['passed']for row in hf['solver_results'].values())or any(not row['passed']for row in pf['solver_results'].values()):
            raise ValueError('An unresolved solver result was imported')
        report=c['reports'][parent_name]
        if not report['byte_identical_elaboration']or report['queries_checked']!=736 or report['observers']['memory_bits']!=1253376:
            raise ValueError('Current cache audit scope differs')
        if pi['payload_cutpoints']or pi['old_guard_or_cache_results_assumed']:
            raise ValueError('A payload oracle or old pass was imported')
        for key,relative in(('guard','project/kv_integrity_guard.sv'),('page_hash','project/kv_page_hash.sv')):
            raw=(native/relative).read_bytes()
            if raw!=(source/'production'/relative).read_bytes()or raw!=(parent/('production-'+key+'.sv')).read_bytes():
                raise ValueError('Actual guard/hash differs in the joined cache scope')
            if sha(raw)!=(hi['production_guard_sha256']if key=='guard'else hi['page_hash_source_sha256']):
                raise ValueError('History scope uses another native guard/hash')
        kv_hash_row=next(row for row in hash_audit['runs']if row['variant']==variant)
        real_hash=HERE/'runs'/kv_hash_row['run']
        if (real_hash/'production-kv_page_hash.sv').read_bytes()!=(native/'project/kv_page_hash.sv').read_bytes():
            raise ValueError('Actual real-SHA wrapper differs from the history/cache wrapper')
        if not kv_hash_row['actual_live_chain_owner_premise_discharged']or not kv_hash_row['both_solver_satisfiable_reset_bases_unbounded_induction_and_complete_correct_digest_cover']:
            raise ValueError('Actual wrapper algorithm/ownership premise incomplete')
        for relative,row in json.loads((source/'SOURCE-ORIGINS.json').read_bytes())['sources'].items():
            if (native/relative.removeprefix('production/')).read_bytes()!=(source/relative).read_bytes():
                raise ValueError('Current native parent source association failed')
        rows.append(dict(variant=variant,image_sha256=bound['image_sha256'],native_inventory_sha256=bound['native_inventory_sha256'],
            history_proof=history_name,history_assertions=221,history_audit=history_pin,
            current_cache_proof=parent_name,current_cache_assertions=357,current_cache_audit=parent_pin,
            real_hash_proof=kv_hash_row['run'],real_hash_assertions=kv_hash_row['assertions'],
            arithmetic_and_hash_replies_unrestricted_in_cache_theorem=True,
            source_identical_guard_hash_and_all_ten_parent_inputs=True,
            checked_RAM_and_persisted_pending_copy_scope=True))
    # Independently reproduce the two narrowly scoped encrypted source ports.
    history_out=out/'reprepared-encrypted-history'
    parent_out=out/'reprepared-encrypted-parent'
    commands=[['prepare_encrypted_kv_history.py','--package',str(args.package.resolve()),'--out',str(history_out)],
        ['prepare_encrypted_kv_parent.py','--package',str(args.package.resolve()),'--out',str(parent_out),'--revision','composition-'+out.name]]
    for command in commands:
        cp=subprocess.run(['python3.12','-I','-S','-B',str(HERE/command[0])]+command[1:],capture_output=True,text=True,timeout=60)
        (out/(command[0]+'.log')).write_text(cp.stdout+cp.stderr)
        if cp.returncode:raise ValueError('Encrypted source preparation does not reproduce')
    old=HERE/'encrypted-kv-history-r1'
    for path in old.iterdir():
        if path.is_file()and (history_out/path.name).read_bytes()!=path.read_bytes():
            raise ValueError('Encrypted history observer adaptation changed: '+path.name)
    old=HERE/'encrypted-kv-parent-source-r2'
    if (old/'MANIFEST.json').read_bytes()!=(parent_out/'MANIFEST.json').read_bytes():
        raise ValueError('Current encrypted parent source-manifest does not reproduce')
    for relative,pin in json.loads((old/'MANIFEST.json').read_bytes())['files'].items():
        if (old/relative).read_bytes()!=(parent_out/relative).read_bytes():raise ValueError('Encrypted parent port differs: '+relative)
    receipt=dict(schema='native-KV-history-real-hash-current-cache-composition-audit-v1',passed=True,
        hash_wrapper_audit=hash_pin,compact_SHA_FIPS_audit=compact_pin,held_SHA_FIPS_audit=held_pin,runs=rows,
        encrypted_guard_pipeline_observer_and_parent_fault_OR_ports_reproduced=True,
        no_cryptographic_or_caller_protocol_or_RAM_payload_oracles_assumed=True,
        cryptographic_hardness_proved=False,
        cryptographic_interpretation='RTL proves exact typed header/payload hashing, trusted tag publication/comparison, same verified staging RAM and current cache ownership. Treating a successful matching hash as an adversary-infeasible substitution requires SHA-256 collision/second-preimage resistance and trusted on-chip state. Cryptographic resistance is not an SMT theorem.',
        scope='Source-bound component composition through the actual protected/encrypted guard and current cache. Numerical attention, SIV confidentiality/correctness, attention capture/use, physical faults, mapped-bitstream equivalence and practical training capacity are separate. No assertion counts from overlapping scopes are added.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'KV-HISTORY-CACHE-COMPOSITION-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,variants=2)))


if __name__=='__main__':main()
