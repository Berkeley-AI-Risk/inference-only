#!/usr/bin/env python3
"""Verify proof result/log/source binding and the nonvacuity controls."""
import hashlib,json,re,shutil,subprocess
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
from check_wiring import audit
POSITIVE={'controller':'controller-v10','core':'core-v3','publication':'publication-v1','verifier':'verifier-v2'}
def expected(job):
    src=(PROJECT/('swic/su_lms_verify.sv' if job=='verifier' else 'home/home_boot_gate.sv')).read_text()
    extra='';prop=(HERE/(job+'_properties.sv')).read_text()
    if job=='core':
        top=(PROJECT/'top.sv').read_text();probe=(PROJECT/'shared_token_probe.sv').read_text()
        block=top[top.index('    logic home_mode_q'):top.index('    home_boot_gate #')]
        runtime=probe[probe.index('    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;'):probe.index('\n\n    // The existing typed endpoint')]
        prop=prop.replace('    // INSERT_ACTUAL_CORE_BLOCK',block).replace('    // INSERT_ACTUAL_RUNTIME_RESET',runtime)
        extra=(PROJECT/'arbiter.sv').read_text().split('\nendmodule')[0].split('\n`ifdef FORMAL\n')[0]+'\nendmodule\n'
    if job=='publication':
        u=PROJECT/'fpga/token_only_model0_mac_uart0/rtl';src=(u/'token_only_model0_uart_bridge.sv').read_text()
        extra='\n'+(u/'fixed_uart_tx.sv').read_text()+'\n'+(u/'fixed_uart_rx.sv').read_text()
    pos=src.index('\nendmodule')
    return src[:pos]+'\n'+prop+src[pos:]+extra
def audit_all():
    pins=json.loads((HERE/'SOURCE-PINS.json').read_text())
    # The public packet binds the adjacent hardware tree by exact SHA-256.
    for f,h in pins['files'].items(): assert sha(PROJECT/f)==h,f
    records=[]
    for job,name in POSITIVE.items():
        out=HERE/'runs'/name;r=json.loads((out/'RESULT.json').read_text())
        assert r['result']=='PASS' and r['exit_code']==0 and not r['memory_stopped'],name
        assert r['design_sha256']==sha(out/'design.sv') and r['proof_log_sha256']==sha(out/'proof.log'),name
        assert (out/'design.sv').read_text()==expected(job),name+' design/source correspondence'
        assert 'Induction step proven: SUCCESS!' in (out/'proof.log').read_text(),name
        steps=re.findall(r'\[induction step (\d+)\]',(out/'proof.log').read_text())
        records.append({'job':job,'run':name,'result':'PASS','induction_length':int(steps[-1]),'result_sha256':sha(out/'RESULT.json'),'design_sha256':r['design_sha256'],'proof_log_sha256':r['proof_log_sha256']})
    out=HERE/'runs/memory-v2';r=json.loads((out/'RESULT.json').read_text());assert r['result']=='PASS'
    src=(PROJECT/'home/home_boot_gate.sv').read_text();pos=src.index('\nendmodule')
    assert (out/'design.sv').read_text()==src[:pos]+'\n'+(HERE/'memory_properties.sv').read_text()+src[pos:]
    for name in ['prepare','base','induction']:
        assert r['records'][name]['exit_code']==0 and not r['records'][name]['memory_stopped']
        assert sha(out/(name+'.log'))==r['records'][name]['log_sha256']
        if name!='prepare':assert 'Status: PASSED' in (out/(name+'.log')).read_text()
    assert 'Temporal induction successful.' in (out/'induction.log').read_text()
    records.append({'job':'signature-memory','run':'memory-v2','result':'PASS','result_sha256':sha(out/'RESULT.json')})
    witness=HERE/'runs/witness-v3';r=json.loads((witness/'RESULT.json').read_text());assert r['result']=='PASS' and len(r['cases'])==4
    for case in r['cases']:
        p=witness/case['case'];assert case['expected_behavior_observed']
        for file,field in [('controller.sv','controller_sha256'),('compile.log','compile_log_sha256'),('simulation.log','simulation_log_sha256')]:assert sha(p/file)==case[field]
        assert (p/'witness.sv').read_bytes()==(HERE/'witness.sv').read_bytes()
    assert (witness/'actual/controller.sv').read_bytes()==(PROJECT/'home/home_boot_gate.sv').read_bytes()
    negatives=[]
    for name in ['negative-header-v1','negative-binding-v1','negative-permit-v1']:
        out=HERE/'runs'/name;r=json.loads((out/'RESULT.json').read_text());log=(out/'proof.log').read_text()
        assert r['result']=='NOT_PROVEN' and r['exit_code']==1 and not r['memory_stopped']
        assert 'proof did fail!' in log and (out/'failure.vcd').exists()
        assert r['proof_log_sha256']==sha(out/'proof.log') and r['design_sha256']==sha(out/'design.sv')
        negatives.append({'run':name,'detected':True,'kind':'base-counterexample' if 'model found for base case: FAIL!' in log else 'induction-rejected; reachable simulation control checked separately','result_sha256':sha(out/'RESULT.json')})
    wiring=audit();assert (HERE/'WIRING-AUDIT.json').read_text()==json.dumps(wiring,indent=2)+'\n'
    return {'result':'PASS','formal_jobs':records,'negative_controls':negatives,'witness_result_sha256':sha(witness/'RESULT.json'),'wiring_audit_sha256':sha(HERE/'WIRING-AUDIT.json'),'connections_checked':len(wiring['checks']),'source_pins_sha256':sha(HERE/'SOURCE-PINS.json'),'scope':'Five compositional authorization-control lemmas plus source-pinned static correspondence, three formal mutation controls, and reachable simulation controls. Not an unconditional whole-chip theorem.'}
if __name__=='__main__':
    r=audit_all();(HERE/'RESULTS-AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2))
