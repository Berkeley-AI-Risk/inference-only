"""Grounded joint-induction conclusions sharing one real solver premise.

The prefix is checked SAT once. Each conclusion is negated under a fresh push
and then popped; no conclusion is assumed for another conclusion. The only
same-state imported facts are the 38 independently proved owner invariants.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys
import time

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--contract',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);p.add_argument('--indices',type=int,nargs='+')
    p.add_argument('--skip',type=int,default=0);p.add_argument('--max-conclusions',type=int,default=25)
    p.add_argument('--timeout',type=int,default=30)
    args=p.parse_args();run=args.run.resolve();contract_path=args.contract.resolve();out=args.out.resolve()
    out.mkdir(parents=True,exist_ok=False)
    runner_raw=Path(__file__).read_bytes();(out/'runner.py').write_bytes(runner_raw)
    inputs_raw=(run/'INPUTS.json').read_bytes();inputs=json.loads(inputs_raw)
    contract_raw=(contract_path/'INPUTS.json').read_bytes();contract=json.loads(contract_raw)
    if contract['source_inputs_sha256']!=sha(inputs_raw)or not contract['all_imported_invariants_independently_discharged']or not contract['exact_native_and_owner_projection_checked']:
        raise ValueError('Source-proved contract differs from this native model')
    audit_raw=(HERE/'ENCRYPTED-HASH-OWNER-AUDIT.json').read_bytes()
    if sha(audit_raw)!=contract['owner_audit_sha256']or not json.loads(audit_raw)['passed']:
        raise ValueError('Native owner theorem evidence changed')
    for n,row in inputs['files'].items():
        raw=(run/n).read_bytes()
        if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Source input changed')
    original=(run/'design.smt2').read_text();top=inputs['top'];k=inputs['induction_depth']
    imported=contract['imported_current_state_assertion_indices']
    old_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool true)'
    new_u=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool (and true '+ ' '.join(f'(|{top}_a {i}| state)'for i in imported)+'))'
    if original.count(old_u)!=1:raise ValueError('Original input assumptions changed')
    model=original.replace(old_u,new_u,1)
    if sha(model.encode())!=contract['derived_model_sha256']or(contract_path/'design.smt2').read_text()!=model:
        raise ValueError('Contract derivation changes more than the proved facts')
    base=json.loads((run/'FINISHED.json').read_bytes());base_row=base['results']['z3-bmc']
    if base['inputs_sha256']!=sha(inputs_raw)or not base_row['passed']or base_row['status']!=['PASSED']or inputs['base_depth']<k:
        raise ValueError('Unmodified native model lacks a complete reset base')
    for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
        if sha((run/('z3-bmc'+ext)).read_bytes())!=base_row[key]:raise ValueError('Native reset base evidence changed')
    all_new=[i for i in range(inputs['assertion_cells'])if i not in imported]
    selected=args.indices or all_new[args.skip:args.skip+args.max_conclusions]
    if not selected or len(set(selected))!=len(selected)or any(i not in all_new for i in selected):
        raise ValueError('Invalid/new conclusion inventory')
    library=Path('/opt/homebrew/share/yosys/python3/smtio.py').resolve()
    sys.path.insert(0,str(library.parent));from smtio import SmtIo,SmtOpts
    options=SmtOpts();options.solver='cvc5';options.unroll=True;options.timeinfo=False
    options.solver_opts=[f'--tlimit-per={args.timeout*1000}']
    options.debug_file=(out/'query.smt2').open('w');options.dummy_file=str(out/'responses.txt')
    smt=SmtIo(opts=options);smt.produce_models=True
    for line in model.splitlines():smt.write(line)
    for i in range(k+1):
        smt.write(f'(declare-fun s{i} () |{top}_s|)')
        smt.write(f'(assert (|{top}_h| s{i}))');smt.write(f'(assert (|{top}_u| s{i}))')
        smt.write(f'(assert (not (|{top}_is| s{i})))')
        if i:smt.write(f'(assert (|{top}_t| s{i-1} s{i}))')
        if i<k:smt.write(f'(assert (|{top}_a| s{i}))')
    started=time.monotonic();prefix_answer=smt.check_sat();rows=[]
    print(json.dumps(dict(shared_premise=prefix_answer,seconds=time.monotonic()-started)),flush=True)
    if prefix_answer=='sat':
        for index in selected:
            smt.write('(push 1)');smt.write(f'(assert (not (|{top}_a {index}| s{k})))')
            begin=time.monotonic();answer=smt.check_sat();row=dict(index=index,answer=answer,passed=answer=='unsat',seconds=time.monotonic()-begin)
            if answer=='sat':
                declarations=re.findall(r'^; yosys-smt2-assert '+str(index)+r' (\S+) (\S+)',original,re.M)
                row['source']=declarations
                match=re.search(r'g_bank\[(\d+)\]',declarations[0][0])if declarations else None
                bank=int(match[1])if match else 0
                fields=('state_q','all_plaintext_q','fill_count_q','valid_words_q','crypto_word_q','block_q','hash_pending_i',
                    'hash_response_valid_i','f_hash_owned_q','f_life_written_q','f_life_plain_q','f_life_hashed_q',
                    'f_life_address','f_life_calls_q','f_life_returns_q','f_life_epoch_q','f_life_checked_q',
                    'f_life_equal_q','f_life_consumer_pending_q','f_life_read_seen_q','f_life_read_target_q',
                    'f_life_consumer_address_q','f_life_read_value_q','f_life_word_q','read_data_q',
                    'memory_write','memory_read','f_life_write_address','memory_read_address','begin_fire','read_fire','crypto_done')
                expressions=[];labels=[]
                for step in range(k+1):
                    for name in fields:
                        full=f'g_bank[{bank}].u_bank.'+name
                        if f'(define-fun |{top}_n {full}|'in original:
                            expressions.append(f'(|{top}_n {full}| s{step})');labels.append((step,name))
                row['counterexample_values']=[dict(step=label[0],field=label[1],value=value)for label,value in zip(labels,smt.get_list(expressions))]
            rows.append(row);print(json.dumps({key:value for key,value in row.items()if key!='counterexample_values'}),flush=True)
            smt.write('(pop 1)')
            if answer!='unsat':break
    smt.write('(exit)');smt.wait();options.debug_file.close()
    smt.dummy_fd.flush();smt.dummy_fd.close()
    receipt=dict(schema='shared-premise-grounded-joint-induction-v1',passed=prefix_answer=='sat'and len(rows)==len(selected)and all(r['passed']for r in rows),
        source_run=run.name,source_inputs_sha256=sha(inputs_raw),original_model_sha256=sha(original.encode()),
        derived_model_sha256=sha(model.encode()),owner_contract_inputs_sha256=sha(contract_raw),owner_audit_sha256=sha(audit_raw),
        imported_source_proved_invariants=imported,selected_new_assertions=selected,results=rows,shared_premise_answer=prefix_answer,
        no_conclusion_assumed_for_another=True,unmodified_Z3_reset_base_passed=True,depth=k,
        response_log_flushed_before_digest=True,
        query_sha256=sha((out/'query.smt2').read_bytes()),responses_sha256=sha((out/'responses.txt').read_bytes()),
        grounding_library_sha256=sha(library.read_bytes()),runner_sha256=sha(runner_raw),seconds=time.monotonic()-started,
        protocol_input_promises_added=False,arbitrary_internal_data_values_added=False)
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=receipt['passed'],conclusions=len(rows),seconds=receipt['seconds'])),flush=True)
    return 0 if receipt['passed']else 1


if __name__=='__main__':raise SystemExit(main())
