"""Pure completed-current scoped replay record checks; no solver or I/O."""
import json
import hashlib
import re
SCHEMA='current-seeded-formal-replay-completion-v1'
COUNTS={'selector':35,'selector-buffer':57,'uart':63,'shell':94}
def need(ok,message):
    if not ok:raise ValueError(message)
def canonical(value):return json.dumps(value,sort_keys=True,separators=(',',':'),allow_nan=False)
def digest(value):need(type(value)is str and re.fullmatch('[0-9a-f]{64}',value)is not None,'Invalid digest')
def validate_record_binding(raw,origin,expected_sha256):
    digest(expected_sha256)
    need(set(origin)=={'path','sha256','bytes'}and origin['path']=='CURRENT-REPLAY.json','Wrong completed-record role')
    need(type(origin['bytes'])is int and origin['bytes']==len(raw),'Completed-record byte count differs')
    need(hashlib.sha256(raw).hexdigest()==origin['sha256']==expected_sha256,'Completed-record literal identity differs')

def validate_completion(row,binding):
    need(set(row)=={'schema','current_solver_replay_passed','source_binding','components','connected','lean','sensitivity','current_seeded_page_bank','limits','origins'},'Unexpected completion fields')
    need(row['schema']==SCHEMA and row['current_solver_replay_passed']is True,'Actual current replay is incomplete')
    need(canonical(row['source_binding'])==canonical(binding),'Current source/image binding differs')
    need(binding['distributed_inputs_verified']==87 and binding['current_native_inputs']==91 and binding['image_bytes_verified']is True,'Wrong current provenance census')
    for key in ('image_sha256','distributed_inventory_sha256','current_native_inventory_sha256','current_binding_sha256'):digest(binding[key])
    need(set(row['components'])==set(COUNTS),'Wrong component role census')
    for name,count in COUNTS.items():
        lane=row['components'][name]
        need(set(lane)=={'assertions','primary_passed','second_solver_complete','matches_recorded_model','model_sha256'},'Unexpected component fields')
        need(type(lane['assertions'])is int and lane['assertions']==count and lane['primary_passed']is True and lane['second_solver_complete']is True and lane['matches_recorded_model']is True,'Component proof scope/incompleteness')
        digest(lane['model_sha256'])
    c=row['connected'];need(set(c)=={'primary_passed','assertions','memories','assumptions','private_output_cuts','model_sha256','secondary'},'Unexpected connected fields');need(all(type(c[k])is int for k in ('assertions','memories','assumptions','private_output_cuts')),'Connected integer census types differ');need(c['primary_passed']is True and c['assertions']==196 and type(c['assertions'])is int and c['memories']==20 and c['assumptions']==0 and c['private_output_cuts']==37,'Connected primary/cut scope differs')
    digest(c['model_sha256']);s=c['secondary']
    need(s['base_passed']is True and s['attempted_conclusions']==196 and type(s['attempted_conclusions'])is int,'Complete same-scope secondary census required')
    need(set(s)=={'base_passed','attempted_conclusions','passed_conclusions','passed_conclusion_indexes','unresolved_conclusion_indexes','complete'},'Unexpected secondary fields')
    passed=s['passed_conclusion_indexes'];unresolved=s['unresolved_conclusion_indexes']
    need(type(passed)is list and type(unresolved)is list and all(type(i)is int for i in passed+unresolved),'Invalid secondary labels')
    need(passed==sorted(set(passed)) and unresolved==sorted(set(unresolved)) and set(passed).isdisjoint(unresolved) and set(passed)|set(unresolved)==set(range(196)),'Secondary partition differs')
    need(set(unresolved)<={38,73} and s['passed_conclusions']==len(passed) and s['complete']is(not unresolved),'Only existing same-scope CRC unknowns may remain')
    need(canonical(row['lean'])==canonical({'theorems':15,'passed':True,'toolchain':'leanprover/lean4:v4.33.1','rtl_refinement':False}),'Lean scope differs')
    need(canonical(row['sensitivity'])==canonical({'selector_reset_reachable_mutants':7,'buffer_reset_reachable_mutants':2,'serial_mutants':5,'actual_serial_cases':284}),'Sensitivity census differs')
    bank=row['current_seeded_page_bank']
    need(canonical(bank)==canonical(dict(assertions=42,both_solvers_complete=True,real_ram_bits=32768,sha_replies_unconstrained_bits=258,directed_scenarios=10,detected_faulty_variants=5,observer_drives_production=False,production_sha_elaborated=False,sha_correctness_proved=False,bank_source_sha256='ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1',sha_source_not_elaborated_sha256='d1b7785186aa486de41507e7a45876693690b52aff9eebe31ea8e31437bdff94')),'Current page-bank scope differs')
    need(canonical(row['limits'])==canonical(dict(assertion_counts_overlap=True,qualification_inherited=False,whole_machine_refinement=False,numerical_cdf_equivalence=False,mapped_implementation_equivalence=False,vendor_logic_elaborated=False,sha_compression_arithmetic_proved=False,private_sha_composition_proved=False,solver_replayed_by_registrar=False,independent_tool_execution_attested=False,hardware_access=False,network_access=False)),'Replay limits changed')
    need(set(row['origins'])=={'replay_finished','replay_results','bank_finished','bank_audit_finished','reviewed_policy'},'Missing actual origin role')
    for value in row['origins'].values():
        need(set(value)=={'sha256','bytes'} and type(value['bytes'])is int and value['bytes']>0,'Origin must be a hash/byte identity');digest(value['sha256'])
    raw=canonical(row)
    need(not any(x in raw for x in ('/Users/','/Volumes/','/private/','/opt/homebrew/')),'Private path leaked into public completion')
    return dict(current_solver_replay_passed=True,connected_secondary_complete=s['complete'],connected_secondary_unresolved=unresolved,hardware_access=False,whole_machine_refinement=False)
