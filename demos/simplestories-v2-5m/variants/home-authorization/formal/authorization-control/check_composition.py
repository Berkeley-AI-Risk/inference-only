#!/usr/bin/env python3
"""Recorded source/recipe/receipt replay and optional fresh formal engines."""
import argparse,ast,hashlib,json,re,shutil,subprocess,sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from run_proofs import HERE,PROJECT,sha
from run_next_proofs import uart_design,home_design
from run_verifier_join import design as verifier_design
from run_memory_proof import monitored
from audit_results import audit_all,POSITIVE
from check_boot_handoff import audit as audit_boot
NEXT={'uart-deadline':'uart-deadline-v2','renewal':'renewal-v3','composition':'composition-v7'}
def normalize_recipe(raw):
    lines=[]
    for line in raw.splitlines():
        tokens=line.split()
        if not tokens:continue
        if tokens[0]=='sat':
            kept=[];i=0
            while i<len(tokens):
                if tokens[i] in ['-show','-dump_vcd']:i+=2
                elif tokens[i] in ['-show-ports','-show-regs']:i+=1
                else:kept.append(tokens[i]);i+=1
            tokens=kept
        lines.append(' '.join(tokens))
    return lines
def check_recipe(job,out):
    if job in POSITIVE:
        constants=[n.value for n in ast.walk(ast.parse((HERE/'run_proofs.py').read_text())) if isinstance(n,ast.Constant) and isinstance(n.value,str) and n.value.startswith('read_verilog')]
        if job in ['controller','core']:wanted=next(s for s in constants if 'home_boot_gate' in s)
        elif job=='publication':wanted=next(s for s in constants if 'CLKS_PER_BIT' in s)
        else:wanted=next(s for s in constants if 'chparam -set USE_SHARED_HASH' in s)
        wanted=wanted.replace('MAXSTEPS','6').replace('SPECSHOW','')
    elif job in ['signature-memory','verifier-join','boot-handoff']:
        source={'signature-memory':'run_memory_proof.py','verifier-join':'run_verifier_join.py','boot-handoff':'run_boot_handoff.py'}[job]
        wanted=next(n.value for n in ast.walk(ast.parse((HERE/source).read_text())) if isinstance(n,ast.Constant) and isinstance(n.value,str) and n.value.startswith('read_verilog'))
    elif job in ['model-lock','owner-factor']:
        top='model_lock_origin' if job=='model-lock' else 'owner_factor'
        wanted=f'''read_verilog -formal -sv design.sv
prep -top {top} -flatten
chformal -lower
sat -verify -prove-asserts -set-def-inputs
'''
    else:
        top='token_only_model0_uart_bridge' if job=='uart-deadline' else 'home_boot_gate'
        config=f'chparam -set CLKS_PER_BIT 217 {top}' if job=='uart-deadline' else "chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 -set DEVICE_ID 128'h395c83e440d5252bfa59f6138e5ed3b8 -set GEOMETRY 256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078 home_boot_gate"
        cut='' if job=='uart-deadline' else 'delete home_boot_gate/shared_signature_byte_o'
        reset='rst_n' if job=='uart-deadline' else 'reset_n'
        binary=[]
        for m in re.finditer(r'\(\*\s*anyseq(?:,\s*keep)?\s*\*\)\s*(?:wire|logic)\s*(?:\[[^]]+\])?\s*([^;]+);',(out/'design.sv').read_text()):binary.extend(n.strip() for n in m[1].split(','))
        defs=' '.join('-set-def '+n for n in binary)
        wanted=f'''read_verilog -formal -D SYNTHESIS -sv design.sv
{config}
prep -top {top} -flatten
{cut}
async2sync
opt -full
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps 5 -set clk 1 -set-at 1 {reset} 0 -set-def-inputs {defs}
'''
    assert normalize_recipe((out/'prove.ys').read_text())==normalize_recipe(wanted),job+' proof recipe changed'
def inspect_sat(out,expected):
    r=json.loads((out/'RESULT.json').read_text());process=r.get('process',r)
    assert r['result']=='PASS' and process['exit_code']==0 and not process['memory_stopped'],out.name
    assert sha(out/'design.sv')==r['design_sha256'] and (out/'design.sv').read_text()==expected,out.name
    assert sha(out/'proof.log')==r['proof_log_sha256']
    log=(out/'proof.log').read_text();assert 'Induction step proven: SUCCESS!' in log
    return {'result':'PASS','run':out.name,'induction_length':int(re.findall(r'\[induction step (\d+)\]',log)[-1]),'result_sha256':sha(out/'RESULT.json')}
def recorded():
    prior=audit_all();jobs={r['job']:r for r in prior['formal_jobs']}
    for job,r in jobs.items():check_recipe(job,HERE/'runs'/r['run'])
    for job,name in NEXT.items():
        expected=uart_design((HERE/'uart_deadline_properties.sv').read_text()) if job=='uart-deadline' else home_design(job)
        out=HERE/'runs'/name;jobs[job]=inspect_sat(out,expected)
        check_recipe(job,out)
        recipe=(out/'prove.ys').read_text()
        if job!='uart-deadline':
            assert '-set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000' in recipe
            assert "-set DEVICE_ID 128'h395c83e440d5252bfa59f6138e5ed3b8" in recipe
        if job=='composition':
            binary=json.loads((out/'STARTED.json').read_text())['binary_private_seams']
            assert binary and all('-set-def '+n+' ' in recipe for n in binary)
    pair=HERE/'runs/verifier-join-v4';r=json.loads((pair/'RESULT.json').read_text());assert r['result']=='PASS'
    check_recipe('verifier-join',pair)
    assert (pair/'design.sv').read_text()==verifier_design() and sha(pair/'design.sv')==r['design_sha256']
    for label in ['prepare','base','induction']:
        q=r['records'][label];assert q['exit_code']==0 and not q['memory_stopped']
        assert sha(pair/(label+'.log'))==q['log_sha256']
        if label!='prepare':assert 'Status: PASSED' in (pair/(label+'.log')).read_text()
    assert 'Temporal induction successful.' in (pair/'induction.log').read_text()
    jobs['verifier-join']={'result':'PASS','run':pair.name,'result_sha256':sha(pair/'RESULT.json')}
    boot=audit_boot();jobs.update(boot['jobs'])
    for job,row in boot['jobs'].items():check_recipe(job,HERE/'runs'/row['run'])
    controls=[]
    for name in ['negative-uart-stall-v1','negative-midframe-pause-v1','negative-short-guard-v1']:
        p=HERE/'runs'/name;r=json.loads((p/'RESULT.json').read_text())
        assert r['result']=='NOT_PROVEN' and r['process']['exit_code']==1 and not r['process']['memory_stopped']
        assert 'proof did fail!' in (p/'proof.log').read_text() and (p/'failure.vcd').exists()
        assert sha(p/'proof.log')==r['proof_log_sha256'] and sha(p/'design.sv')==r['design_sha256']
        controls.append({'run':name,'detected':True,'kind':'induction mutation rejection; not counted as a new positive theorem'})
    witness=HERE/'runs/renewal-witness-v2';r=json.loads((witness/'RESULT.json').read_text());assert r['result']=='PASS' and r['exit_code']==0
    for f,k in [('controller.sv','controller_sha256'),('witness.cpp','witness_sha256'),('compile.log','compile_log_sha256'),('simulation.log','simulation_log_sha256')]:assert sha(witness/f)==r[k]
    assert (witness/'controller.sv').read_bytes()==(PROJECT/'home/home_boot_gate.sv').read_bytes()
    assert (witness/'witness.cpp').read_bytes()==(HERE/'renewal_witness.cpp').read_bytes()
    raw=(witness/'simulation.log').read_text();assert 'WITNESS PASS cycles=375000140 grants=2' in raw
    return {'result':'PASS','formal_jobs':jobs,'formal_job_count':len(jobs),'additional_negative_controls':controls,'earlier_audit':prior,'boot_handoff_audit':boot,'production_timer_witness_sha256':sha(witness/'RESULT.json'),'conditional_authorization_control_composition':True,'whole_machine_theorem':False,'cryptographic_algorithm_correctness_proved':False,'physical_power_cycle_tested':False}
def main():
    p=argparse.ArgumentParser();p.add_argument('--out',type=Path,required=True);p.add_argument('--fresh',action='store_true');p.add_argument('--jobs',help='comma-separated job subset for fresh replay');a=p.parse_args()
    out=a.out.resolve();out.mkdir(parents=True,exist_ok=False)
    package=HERE/'PACKAGE.json'
    if package.exists():
        manifest=json.loads(package.read_text())
        for f,h in manifest['files'].items():
            path=(HERE/f).resolve();assert path.is_relative_to(HERE) and not path.is_symlink(),f
            assert sha(path)==h,f+' packet member changed'
    result=recorded();result['fresh_engine_jobs']=[]
    if package.exists():
        expected_certificate=dict(result);del expected_certificate['fresh_engine_jobs']
        assert json.loads((HERE/'CERTIFICATE.json').read_text())==expected_certificate,'certificate does not match reconstructed receipts'
    if a.fresh:
        wanted=a.jobs.split(',') if a.jobs else list(result['formal_jobs'])
        assert len(wanted)==len(set(wanted)) and all(n in result['formal_jobs'] for n in wanted)
        for job in wanted:
            name=result['formal_jobs'][job]['run'];source=HERE/'runs'/name;dest=out/job;dest.mkdir()
            for f in ['design.sv','prove.ys']:shutil.copyfile(source/f,dest/f)
            r=monitored(['yosys','-Q','-T','prove.ys'],dest,'prepare')
            assert r['exit_code']==0 and not r['memory_stopped'],job
            if job in ['signature-memory','verifier-join','boot-handoff']:
                depth='8' if job=='signature-memory' else str(json.loads((source/'STARTED.json').read_text())['depth'])
                for label,flag in [('base',[]),('induction',['-i'])]:
                    r=monitored(['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t',depth]+flag+['model.smt2'],dest,label)
                    assert r['exit_code']==0 and not r['memory_stopped'] and 'Status: PASSED' in (dest/(label+'.log')).read_text(),job
            elif job in ['model-lock','owner-factor']:assert 'SAT proof finished - no model found: SUCCESS!' in (dest/'prepare.log').read_text(),job
            else:assert 'Induction step proven: SUCCESS!' in (dest/'prepare.log').read_text(),job
            result['fresh_engine_jobs'].append(job)
    result['recorded_only']=not a.fresh
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'result':result['result'],'formal_job_count':len(result['formal_jobs']),'fresh_engine_jobs':result['fresh_engine_jobs'],'whole_machine_theorem':False},indent=2))
if __name__=='__main__':main()
