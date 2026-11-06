#!/usr/bin/env python3
"""Check actual boot-ownership proofs and their source/trace correspondence."""
import json,importlib.util
from run_proofs import HERE,PROJECT,sha
from run_boot_handoff import lock_design,owner_design,handoff_design
from check_wiring import ports,clean
RUNS={'model-lock':'model-lock-origin-v4','owner-factor':'owner-factor-v1','boot-handoff':'boot-handoff-v4'}
def audit():
    wrapper_equivalence=None
    for manifest in ['SOURCE-PINS.json','BOOT-SOURCE-PINS.json']:
        for f,h in json.loads((HERE/manifest).read_text())['files'].items():
            if sha(PROJECT/f)==h:continue
            # The solver jobs abstract shared-SHA responses. Preserve their
            # original source context, then consume the separately proved exact
            # wrapper substitution; do not rehash an older query or receipt.
            assert f=='swic/su_sha256.sv' and h=='f5a2b98f77924c37f80314bd2812fab5bb15d6fd75b016886be57cde579e6f33',f
            assert sha(PROJECT/f)=='d004ab01cf7faa75a48a7e2ff59e7fe8dd28a53cc7113ae8575774300a55b117'
            packet=HERE.parents[2]/'signed-update/formal/stream-assembly'
            spec=importlib.util.spec_from_file_location('selected_stream_equivalence',packet/'check_recorded.py')
            checker=importlib.util.module_from_spec(spec);spec.loader.exec_module(checker)
            checker.check(HERE.parents[2]/'signed-update')
            assert sha(packet/'baseline.sv')==h and sha(packet/'candidate.sv')==sha(PROJECT/f)
            wrapper_equivalence={'result':'PASS','baseline_sha256':h,'selected_sha256':sha(PROJECT/f),'package_sha256':sha(packet/'PACKAGE.json')}
    checks=[]
    def check(file,instance,mapping):
        p=ports((PROJECT/file).read_text(),instance)
        for name,value in mapping.items():
            assert p[name]==clean(value),(file,instance,name)
            checks.append({'file':file,'instance':instance,'port':name,'connection':p[name]})
    check('top.sv','u_signed_boot',{'allow_model_o':'source_ready','model_commitment_o':'model_commitment'})
    check('top.sv','u_memory',{'private_signed_admitted_i':'source_ready','private_model_locked_o':'model_locked'})
    check('top.sv','u_home',{'admitted_root_valid_i':'model_locked','admitted_root_i':'model_commitment'})
    check('swic/swic_boot_ingress.sv','u_admission',{'sealed_o':'admitted'})
    check('booted_memory.sv','u_boot',{'admitted_i':'private_signed_admitted_i','boot_locked_o':'boot_locked'})
    check('booted_memory.sv','u_handoff',{'boot_locked_i':'boot_locked','runtime_locked_o':'handoff_locked'})
    check('top.sv','u_signed_boot',{
        'digest_read_i':'swic_boot_digest_read || swic_digest_read',
        'digest_address_i':'swic_boot_digest_read ? swic_boot_digest_address : swic_digest_address',
        'digest_data_o':'swic_digest_data'})
    check('top.sv','u_memory',{
        'private_boot_digest_read_o':'swic_boot_digest_read',
        'private_boot_digest_address_o':'swic_boot_digest_address',
        'private_boot_digest_data_i':'swic_digest_data'})
    check('booted_memory.sv','u_boot',{
        'digest_read_o':'private_boot_digest_read_o',
        'digest_address_o':'private_boot_digest_address_o',
        'digest_data_i':'private_boot_digest_data_i'})
    check('swic/swic_ddr_boot.sv','u_pages',{
        'digest_read_o':'digest_read_o','digest_address_o':'digest_address_o',
        'digest_data_i':'digest_data_i','verified_o':'page_verified',
        'readback_valid_i':'byte_valid && image_ready && (!in_lut || lut_ready)',
        'readback_byte_i':'readback_byte','readback_last_i':'last_byte'})
    check('swic/swic_ddr_boot.sv','u_image',{
        'readback_valid_i':'byte_valid && page_ready && (!in_lut || lut_ready)',
        'readback_byte_i':'readback_byte','readback_last_i':'last_byte'})
    check('swic/swic_ddr_boot.sv','u_fixed_luts',{
        'byte_valid_i':'byte_valid && in_lut && image_ready && page_ready',
        'byte_i':'readback_byte'})
    parent=clean((PROJECT/'swic/swic_boot_admission.sv').read_text())
    assert 'AUTH_WAIT=7,RUN=8,FAILED=15' in parent
    assert 'assignfail_closed_o=fault_q||root_fault||(state_q==AUTH_WAIT&&lms_fault);' in parent
    expected={'model-lock':lock_design(),'owner-factor':owner_design(),'boot-handoff':handoff_design()[0]};jobs={}
    for job,name in RUNS.items():
        p=HERE/'runs'/name;r=json.loads((p/'RESULT.json').read_text());assert r['result']=='PASS'
        assert (p/'design.sv').read_text()==expected[job] and sha(p/'design.sv')==r['design_sha256']
        for label,q in r['records'].items():
            assert q['exit_code']==0 and not q['memory_stopped']
            assert sha(p/(label+'.log'))==q['log_sha256']
            if label!='prepare':assert 'Status: PASSED' in (p/(label+'.log')).read_text()
        if job=='boot-handoff':assert 'Temporal induction successful.' in (p/'induction.log').read_text()
        else:assert 'SAT proof finished - no model found: SUCCESS!' in (p/'prepare.log').read_text()
        jobs[job]={'result':'PASS','run':name,'result_sha256':sha(p/'RESULT.json'),'kind':'temporal-induction' if job=='boot-handoff' else 'combinational-all-inputs'}
    controls=[]
    for name in ['negative-model-lock-v1','negative-boot-reset-v1']:
        p=HERE/'runs'/name;r=json.loads((p/'RESULT.json').read_text());assert r['result']=='NOT_PROVEN'
        last='prepare' if name=='negative-model-lock-v1' else 'induction';q=r['records'][last]
        assert q['exit_code']==1 and not q['memory_stopped']
        assert sha(p/(last+'.log'))==q['log_sha256']
        assert ('model found: FAIL!' if last=='prepare' else 'Status: FAILED') in (p/(last+'.log')).read_text()
        controls.append({'run':name,'detected':True,'kind':'combinational counterexample' if last=='prepare' else 'induction rejection; reachable simulation also detects reset bypass'})
    p=HERE/'runs/boot-witness-v2';r=json.loads((p/'RESULT.json').read_text());assert r['result']=='PASS' and len(r['cases'])==2
    assert sha(p/'model-prefix.bin')==r['model_prefix_sha256'] and sha(p/'grant.bin')==r['grant_sha256']
    assert (p/'model-prefix.bin').read_bytes()==(PROJECT.parents[1]/'evidence/model-replacement-v2/model-A-signed-prefix.bin').read_bytes()
    for case in r['cases']:
        c=p/case['case'];assert case['expected_behavior_observed']
        for f,key in [('design.sv','design_sha256'),('witness.cpp','witness_sha256'),('simulation.log','simulation_log_sha256'),('compile.log','compile_log_sha256')]:assert sha(c/f)==case[key]
        assert (c/'witness.cpp').read_bytes()==(HERE/'boot_handoff_witness.cpp').read_bytes()
        assert (c/'design.sv').read_text()==handoff_design(observe=True,mutant=None if case['case']=='actual' else 'reset-bypass')[0]
    return {'result':'PASS','jobs':jobs,'additional_connections':checks,'auxiliary_boolean_factorization_checked':True,'controls':controls,'witness_result_sha256':sha(p/'RESULT.json'),'boot_owner_handoff_assumed':False,'cryptographic_algorithm_correctness_proved':False,'complete_boot_payload_correctness_proved':False,'selected_wrapper_equivalence':wrapper_equivalence}
if __name__=='__main__':
    r=audit();(HERE/'BOOT-HANDOFF-AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'result':r['result'],'jobs':len(r['jobs']),'additional_connections':len(r['additional_connections'])}))
