"""Project audited service invariants into the additional consumer proof.

The earlier service theorem permits every child reply. The new model preserves
that native circuit and those observers, adds only fresh observer state, and
restricts child handshakes by separately proved bank-interface guarantees.
Thus every earlier invariant remains true. This records that source projection
and strengthens only SMT _u by the corresponding proved invariant conjunction.
It does not prove the remaining consumer conclusions.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_consumer_contract_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def assertion_map(model):
    found={}
    for index,cell,a,ac,b,bc in re.findall(r'^; yosys-smt2-assert (\d+) (\S+) service\.sv:(\d+)\.(\d+)-(\d+)\.(\d+)$',model,re.M):
        key=(cell.rsplit('$assert$',1)[0],int(a),int(ac),int(b),int(bc))
        found.setdefault(key,[]).append(int(index))
    return found


def remove_assumptions(text):
    expected=['bank_response_valid[f_b]==f_parent_bank_pending_q[f_b]',
        '!f_parent_bank_pending_q[f_b] || bank_response_ready[f_b]']
    for expression in expected:
        clause='assume('+expression+');'
        if text.count(clause)!=1:raise ValueError('Discharged child contract expression changed')
        text=text.replace(clause,';',1)
    if re.search(r'\bassume\b',re.sub(r'//[^\n]*','',text)):raise ValueError('Another input promise was introduced')
    return text



def assumption_definition(model,prefix):
    if model.count(prefix)!=1:raise ValueError('Input assumption definition is ambiguous')
    start=model.index(prefix);depth=0;quoted=False
    for cursor in range(start,len(model)):
        char=model[cursor]
        if char=='|':quoted=not quoted
        if not quoted:
            if char=='(':depth+=1
            elif char==')':
                depth-=1
                if depth==0:return model[start:cursor+1]
    raise ValueError('Incomplete input assumption definition')

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--variant',choices=('baseline','encrypted'),required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py')
    name='service-consumer-'+args.variant+'-r1';root,inputs,result=checked.checked_run(name)
    old_name='service-routing-baseline-r3-metadata'if args.variant=='baseline'else'service-routing-encrypted-r2-metadata'
    prior,prior_inputs,prior_result=checked.checked_run(old_name)
    audit_raw=(HERE/'SERVICE-METADATA-AUDIT.json').read_bytes();audit=json.loads(audit_raw)
    entry=[r for r in audit['runs']if r['run']==old_name]
    if not audit['passed']or len(entry)!=1 or entry[0]['finished_sha256']!=sha((prior/'FINISHED.json').read_bytes()):
        raise ValueError('Earlier source theorem is not independently audited')
    interface_raw=(root/'bank-interface-premise-audit.json').read_bytes();interface=json.loads(interface_raw)
    if interface_raw!=(HERE/'BANK-INTERFACE-AUDIT.json').read_bytes()or not interface['passed']or inputs['binding']['bank_interface_premise_audit_sha256']!=sha(interface_raw):
        raise ValueError('Native bank handshake premises are not discharged')
    if inputs['top']!=prior_inputs['top']or inputs['changed_production_parameters']or inputs['assumption_cells']!=8 or prior_inputs['assumption_cells']:
        raise ValueError('Native geometry or interface-premise inventory changed')
    old_monitor=(prior/'monitor.inc.sv').read_bytes();monitor=(root/'monitor.inc.sv').read_bytes()
    if not monitor.startswith(old_monitor+b'\n'):raise ValueError('Earlier service observers changed')
    extra=monitor[len(old_monitor)+1:]
    observer.observer_writes_only(remove_assumptions(extra.decode()))
    writes=re.findall(r'\b(\w+)\s*(?:\[[^\]]*\]\s*)*(?:<=|=(?!=))',re.sub(r'//[^\n]*','',remove_assumptions(extra.decode())))
    if any(not n.startswith('f_')for n in writes):raise ValueError('Consumer observer changes native or earlier state')
    source=(root/'service.sv').read_bytes()
    if source.count(b'\n'+extra)!=1 or source.replace(b'\n'+extra,b'',1)!=(prior/'service.sv').read_bytes():
        raise ValueError('Native service and original observer projection does not reverse exactly')
    for n in('native-parameters.sv','production-service.sv','metadata-monitor.inc.sv'):
        if (root/n).read_bytes()!=(prior/n).read_bytes():raise ValueError('Native source/parameter identity differs')
    # Map the proved reference recurrence to the actual bank's port events.
    # Payload registers are extra observations and never drive pending/control.
    for literal in('if(!reset_n)', 'else if(cancel_i) f_parent_bank_pending_q[f_b]<=0;',
            'else if(bank_read_valid[f_b] && bank_read_ready[f_b])',
            'else if(bank_response_valid[f_b] && bank_response_ready[f_b])'):
        if literal not in extra.decode():raise ValueError('Reference bank event mapping changed')
    native=(root/'production-service.sv').read_bytes()
    for literal in(b'.clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i)',
            b'.read_valid_i(bank_read_valid[b]),.read_ready_o(bank_read_ready[b])',
            b'.read_word_i(head_word[6:0]),.response_valid_o(bank_response_valid[b])',
            b'.response_ready_i(bank_response_ready[b]),.response_data_o(bank_response_data[b])'):
        if literal not in native:raise ValueError('Actual bank/interface event join differs')
    model=(root/'design.smt2').read_text();old_model=(prior/'design.smt2').read_text();top=inputs['top']
    previous=assertion_map(old_model);current=assertion_map(model)
    if sum(map(len,previous.values()))!=prior_inputs['assertion_cells']or not set(previous)<=set(current)or any(len(previous[k])!=len(current[k])for k in previous):
        raise ValueError('Previously proved assertion conjunction cannot be associated exactly')
    indices=sorted(i for k in previous for i in current[k])
    prefix=f'(define-fun |{top}_u| ((state |{top}_s|)) Bool '
    before=assumption_definition(model,prefix);body=before[len(prefix):-1]
    after=prefix+'(and '+body+' '+' '.join(f'(|{top}_a {i}| state)'for i in indices)+'))'
    derived=model.replace(before,after,1)
    (out/'design.smt2').write_text(derived)
    receipt=dict(schema='source-proved-service-projection-consumer-contract-v1',passed=True,
        source_inputs_sha256=sha((root/'INPUTS.json').read_bytes()),source_model=str(root),
        original_model_sha256=sha(model.encode()),derived_model_sha256=sha(derived.encode()),
        owner_audit_sha256=sha(audit_raw),prior_run=old_name,prior_finished_sha256=sha((prior/'FINISHED.json').read_bytes()),
        bank_interface_audit_sha256=sha(interface_raw),imported_current_state_assertion_indices=indices,
        all_imported_invariants_independently_discharged=True,exact_native_and_owner_projection_checked=True,
        new_observer_writes_only_fresh_consumer_state=True,existing_eight_source_proved_child_assumptions_preserved=True,
        caller_protocol_assumptions_added=False,payload_value_assumptions_added=False,
        source_assertions=inputs['assertion_cells'],new_conclusions=inputs['assertion_cells']-len(indices),
        note='Source projection and premise discharge only. Remaining joint-induction conclusions still require real solver checks.')
    (out/'INPUTS.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    print(json.dumps(dict(passed=True,imported=len(indices),new_conclusions=receipt['new_conclusions'])))


if __name__=='__main__':main()
