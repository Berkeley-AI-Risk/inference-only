"""Bind the specific final-hidden reply permissions to actual caller wiring.

This is a source/receipt join for two permission premises, not an assembled
numerical subsystem theorem. Native RAM and other numerical-child histories
remain explicit independent obligations.
"""
import json
from pathlib import Path

from record_progress import audit, sha
from run_attention_ownership import HERE
from run_service_relational import port_connections
from audit_semantic_permissions import dense


def instance_connections(source,name):
    marker=name+' (';start=source.index(marker)+len(marker);end=start;depth=1
    while depth:depth+=(source[end]=='(')-(source[end]==')');end+=1
    return port_connections(source[start:end-1])


def main():
    parent_name='semantic-parent-clear-r15';caller_name='semantic-result-clear-r8';sequence_name='sequence-parent-clear-r2'
    receipts={n:audit(n,'final-hidden permission prerequisite')for n in(parent_name,caller_name,sequence_name)}
    if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('Incomplete selected proof')
    parent,caller,sequence=[HERE/'runs'/n for n in(parent_name,caller_name,sequence_name)]
    for filename in('production-datapath.sv',):
        if(caller/filename).read_bytes()!=(parent/filename).read_bytes():raise ValueError('Actual datapath source differs')
    if(caller/'production-sequence.sv').read_bytes()!=(sequence/'production-sequence.sv').read_bytes():
        raise ValueError('Actual sequence source differs')
    pi=json.loads((parent/'INPUTS.json').read_text());ci=json.loads((caller/'INPUTS.json').read_text())
    si=json.loads((sequence/'INPUTS.json').read_text())
    if ci['binding']['initial_hard_reset']or si['binding']['initial_hard_reset']:raise ValueError('Unexpected hard reset')
    metadata=(caller/'metadata-writer.inc.sv').read_text()
    if dense(metadata)not in dense((parent/'datapath.sv').read_text()):raise ValueError('Parent metadata owner writer differs')
    if dense(metadata)not in dense((caller/'datapath.sv').read_text()):raise ValueError('Caller metadata observer differs')
    read_update='if(!rst_n||clear_i)f_rel_live_u_hidden_state<=0;elseif(hidden_ram_read_enable)f_rel_live_u_hidden_state<=1;'
    for root in(parent,caller):
        if dense((root/'datapath.sv').read_text()).count(read_update)!=1:raise ValueError('Read ownership reset/writer differs')
    monitor=dense((caller/'result-monitor.inc.sv').read_text())
    if 'if(result_valid_o)beginassert(f_hidden_owned);assert(f_hidden_meta);assert(f_read_live);assert(f_parent_hidden_meta_o);assert(f_parent_hidden_read_live_o);'not in monitor:
        raise ValueError('Final result permission conclusion changed')
    capture='if(f_sequence_state_o==3&&f_sequence_stage_o==15&&f_sequence_layer_o==5&&stage_done)beginassert(f_hidden_meta);assert(f_parent_hidden_meta_o);end'
    if capture not in monitor:raise ValueError('Final exponent capture permission absent')
    required={
        'private_result_mantissa_i':'a_result_valid_o && !a_f_protocol_fault_o',
        'private_result_exponent_i':'!clear_i && !a_f_protocol_fault_o && !a_state_fault_q && (a_state_state_q==4 || (a_state_state_q==3 && a_state_stage_q==15 && a_state_layer_q==5 && private_stage_done_i))',
    }
    if si['binding']['reply_coupling_predicates']!=required:raise ValueError('Sequence consumption contracts changed')
    native=(caller/'production-layer.sv').read_text()
    con=instance_connections(native,'u_sequence');dp=instance_connections(native,'u_datapath')
    for output,input_port,net in [('private_result_mantissa_o','private_result_mantissa_i','private_result_mantissa'),
                                 ('private_result_exponent_o','private_result_exponent_i','private_result_exponent')]:
        if dp[output]!=net or con[input_port]!=net:raise ValueError('Final hidden reply not directly connected')
    if con['private_result_index_o']!=dp['private_result_index_i']:raise ValueError('Derived read index differs')
    if dense(con['upstream_fault_i'])!='upstream_fault_i||datapath_fault||service_start_collision_q':raise ValueError('Caller fault gate changed')
    if con['private_stage_fault_i']!='stage_fault'or dp['private_stage_fault_o']!='stage_fault':raise ValueError('Stage fault binding differs')
    # Each implication already has a complete SAT/UNSAT transcript. Check its
    # entire recorded source/model/query manifest, not just the positive flag.
    corollary=HERE/'runs/semantic-result-corollaries-r1';cr=json.loads((corollary/'FINISHED.json').read_text())
    if not cr['conditional_final_output_corollaries_passed']or cr['proved_parent_assertions']!=pi['assertion_cells']:
        raise ValueError('Final output corollaries incomplete')
    if cr['source_inputs_sha256']!=sha((parent/'INPUTS.json').read_bytes()):raise ValueError('Corollary binds a different parent')
    for path,digest in cr['artifact_manifest'].items():
        if sha(Path(path).read_bytes())!=digest:raise ValueError('Changed corollary artifact')
    if not cr['no_new_corollary_is_an_induction_premise']:raise ValueError('Unexpected circular premise')
    for row in cr['results'].values():
        if not row['passed']or row['answers']!=['sat','unsat']or row['exit']!=0:raise ValueError('Incomplete implication')
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    variants=set(joins['proof_module_joins'][parent_name]['active_variant_source_joins'])
    for name in(caller_name,sequence_name):variants.intersection_update(joins['proof_module_joins'][name]['active_variant_source_joins'])
    if variants!={'baseline','seeded-sampling','kv-protected','encrypted-memory'}:raise ValueError('Not all current source classes joined')
    result=dict(specific_final_hidden_reply_permissions_joined=True,variants=sorted(variants),
        parent_assertions=pi['assertion_cells'],caller_assertions=ci['assertion_cells'],sequence_assertions=si['assertion_cells'],
        assembled_semantic_subsystem_solver_proof=False,child_contracts_composed=False,session_milestone_complete=False,
        statement='At actual sequence result publication and final exponent capture, the joined native caller establishes the same read-history/metadata owners used by the conditional parent corollaries. The actual sequence tolerates unrelated hidden payloads outside those consumption phases.',
        proof_receipts=receipts,corollary_result_sha256=sha((corollary/'FINISHED.json').read_bytes()),
        instantiation_binding_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()),
        checker_sha256=sha(Path(__file__).read_bytes()),
        limits=['Source/receipt permission join; not an automatically assembled temporal composition theorem.',
                'Other native RAM histories, numerical services, protected cache and token publication remain separate.'])
    (HERE/'SEMANTIC-RESULT-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('specific_final_hidden_reply_permissions_joined','caller_assertions','sequence_assertions','session_milestone_complete')}))


if __name__=='__main__':main()
