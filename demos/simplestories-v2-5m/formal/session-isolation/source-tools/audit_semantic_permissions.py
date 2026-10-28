"""Join the semantic caller's LUT/registered-read premises at native wiring.

The parent correspondence certificate remains conditional on its other RAM
and numerical children. This checks the two specific permission implications
supplied by the actual semantic/normalizer/compact-lane control proof.
"""
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE


def dense(raw):return re.sub(r'\s+','',raw)


def main():
    parent_name='semantic-parent-clear-r15';protocol_name='lut-protocol-join-r10'
    leaf_name='elementwise-relevant-ready-r2'
    receipts={n:audit(n,'semantic permission prerequisite')for n in(parent_name,protocol_name,leaf_name)}
    if any(v['status']!='proved_component'for v in receipts.values()):raise ValueError('A permission prerequisite is incomplete')
    parent,protocol,leaf=[HERE/'runs'/n for n in(parent_name,protocol_name,leaf_name)]
    pi=json.loads((parent/'INPUTS.json').read_text());qi=json.loads((protocol/'INPUTS.json').read_text())
    li=json.loads((leaf/'INPUTS.json').read_text())
    for root in(parent,protocol):
        if root.joinpath('production-datapath.sv').read_bytes()!=parent.joinpath('production-datapath.sv').read_bytes():
            raise ValueError('Semantic source class differs')
    if (protocol/'production-elementwise-compact.sv').read_bytes()!=(leaf/'production-scalar.sv').read_bytes():
        raise ValueError('Protocol and numerical child definitions differ')
    predicates=li['binding']['operand_coupling_predicates']
    if predicates['lut_value_i']!='lut_response_valid_i && a_state_state_q==6':raise ValueError('Leaf LUT-consumption contract differs')
    native=(leaf/'production-scalar.sv').read_text()
    if not re.search(r'ST_SILU_WAIT\s*=\s*4\x27d6',native):raise ValueError('Actual consumption state changed')
    if not li['binding']['arithmetic_product_congruence']:raise ValueError('Review changed numerical abstraction')
    parent_source=dense((parent/'datapath.sv').read_text())
    protocol_source=dense((protocol/'datapath.sv').read_text())
    gate_update='if(!rst_n||clear_i)f_rel_live_u_gate_scratch<=0;elseif(scratch_read_enable)f_rel_live_u_gate_scratch<=1;'
    fresh_update='if(!rst_n||clear_i)f_gate_read_seen<=0;elseif(scratch_read_enable)f_gate_read_seen<=1;'
    if parent_source.count(gate_update)!=1 or protocol_source.count(fresh_update)!=1:
        raise ValueError('Registered-read history observers do not have identical update/reset conditions')
    metadata=(HERE/'semantic-metadata-monitor.inc.sv').read_text()
    # The writer/reset part of the observer is unchanged; only its assertion
    # guard is adapted to each admission flag. No ghost drives RTL.
    writer=metadata.split('    always @*if(',1)[0]
    if dense(writer)not in parent_source or dense(writer)not in protocol_source:
        raise ValueError('SiLU ownership histories differ between the proof scopes')
    monitor=dense((protocol/'joined-monitor.inc.sv').read_text())
    global_header='always@*if(rst_n&&f_completed_clear&&!clear_i)begin'
    at=monitor.index(global_header);end=monitor.index('always@*',at+len(global_header))
    block=monitor[at:end]
    for conclusion in ('if(lane_lut_response_q&&f_lane_state==6)assert(f_silu_owned);',
                       'if(lane_lut_request)assert(f_gate_read_seen);'):
        if conclusion not in block:raise ValueError('Required unqualified post-CLEAR permission was not proved')
    reply=pi['binding']['reply_coupling_predicates']['f_child_u_gate_scratch_private_read_data_o']
    if reply!='(a_f_rel_live_u_gate_scratch || f_child_u_elementwise_lane_lut_request_o)':
        raise ValueError('Gate-RAM reply extension differs from the proved permission')
    actual=pi['binding']['actual_child_inputs']['u_elementwise_lane']['inputs']
    if dense(actual['lut_value_i']['guard'])!='(lane_lut_response_q)&&f_silu_owned':raise ValueError('Caller data comparison does not use the same ownership flag')
    if actual['lut_response_valid_i']['expression']!='lane_lut_response_q':raise ValueError('LUT valid wiring differs')
    if qi['binding']['retained_actual_children']!=['u_elementwise_lane','u_normalizer']:
        raise ValueError('Job sequencing controllers were not retained')
    joins=json.loads((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_text())
    if not joins['instantiation_audit_passed']:raise ValueError('Native instantiation binding incomplete')
    variants=set(joins['proof_module_joins'][parent_name]['active_variant_source_joins'])
    variants.intersection_update(joins['proof_module_joins'][protocol_name]['active_variant_source_joins'])
    variants.intersection_update(joins['proof_module_joins'][leaf_name]['active_variant_source_joins'])
    if variants!={'baseline','seeded-sampling','kv-protected','encrypted-memory'}:
        raise ValueError('Permission joins do not cover all current source classes')
    result=dict(specific_lut_and_gate_read_permissions_joined=True,
        assembled_semantic_subsystem_solver_proof=False,whole_device_token_output_theorem=False,
        session_milestone_complete=False,variants=sorted(variants),
        parent_assertions=receipts[parent_name]['assertions'],controller_protocol_assertions=receipts[protocol_name]['assertions'],
        proof_inputs={n:v['input_sha256']for n,v in receipts.items()},
        statement='The actual compact lane requires LUT data equality only in SiLU WAIT. The actual joined controllers prove ownership there on any post-CLEAR response, including fault paths. Their LUT request also implies the identical sticky gate-read flag, so the caller reply extension is redundant on concrete traces.',
        remaining=[
            'Join other native RAM histories and numerical-service response contracts.',
            'Join initial hidden ingress and final hidden-vector completion/read ownership.',
            'Join token-shell/sampler publication and completed device CLEAR/drain.',
            'Complete whole-device mutable-state classification and signoff.'
        ],instantiation_binding_sha256=sha((HERE/'PROOF-INSTANTIATION-BINDINGS.json').read_bytes()),
        checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'SEMANTIC-PERMISSION-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(specific_lut_and_gate_read_permissions_joined=True,variants=len(variants),
        parent_assertions=result['parent_assertions'],controller_protocol_assertions=result['controller_protocol_assertions'],
        session_milestone_complete=False)))


if __name__=='__main__':main()
