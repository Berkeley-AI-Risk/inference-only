"""Recover native full-size boot RTL and bind its real safety evidence.

Re-elaborates the frozen inputs and regenerates the exact solver queries.
Recorded replies are used only for query generation, never as a new proof.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
TOP='board1_context2048_private_ddr_lock_bridge'


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_order_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def inspect(run,package,work,expected_mutant=None):
    common,runner,query=load('run_handoff'),load('run_boot_order'),load('audit_fifo')
    sha,encode=query.sha,query.encode
    inp_raw=(run/'INPUTS.json').read_bytes();inp=json.loads(inp_raw)
    fin_raw=(run/'FINISHED.json').read_bytes();fin=json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw):raise ValueError('Boot input receipt changed')
    if inp['mutant']!=expected_mutant or fin['mutant']!=expected_mutant:raise ValueError('Boot mutant scope changed')
    if (inp['assertion_cells']!=41 or inp['assumption_cells']!=0 or inp['cover_cells']!=1 or
        inp['observer_constants']!=0 or inp['internal_cuts']or inp['changed_production_parameters']or inp['multiclock']):
        raise ValueError('Boot proof dimensions, constraints or cuts changed')
    if fin['binding']!=inp['binding']or fin['assertion_cells']!=41 or fin['internal_cuts']:
        raise ValueError('Boot result does not match its input scope')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Boot proof input changed: '+name)
    original=None;joins={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,root,bound=common.binding(package,variant);raw=(root/runner.SOURCE).read_bytes()
        if original is not None and original!=raw:raise ValueError('Native boot controller differs across variants')
        original=raw;joins[variant]=bound
    binding=dict(native_joins=joins,production_source=runner.SOURCE,production_sha256=sha(original),
        model_words=227062,address_width=19,sha_engine_assumed_correct=False)
    if inp['binding']!=binding:raise ValueError('Boot source/image/native-parameter binding changed')
    if (run/'production-boot.sv').read_bytes()!=original:raise ValueError('Boot source is not native production RTL')
    monitor=(HERE/'boot-order-monitor.inc.sv').read_text()
    if(run/'monitor.inc.sv').read_text()!=monitor:raise ValueError('Boot target/count obligations changed')
    src=(run/'boot.sv').read_text();needle='\n'+monitor+'\nendmodule'
    if not src.startswith('`undef FORMAL\n')or src.count(needle)!=1:raise ValueError('Boot observer boundary changed')
    recovered=src.removeprefix('`undef FORMAL\n').replace(needle,'\nendmodule')
    if expected_mutant:
        old,new=runner.MUTATIONS[expected_mutant]
        # A mutated target state may also occur elsewhere in the original
        # controller. Reconstruct the exact expected single-site source.
        if original.decode().count(old)!=1:raise ValueError('Boot mutation site changed')
        if recovered!=original.decode().replace(old,new):raise ValueError('Boot mutation changed additional production logic')
    elif recovered.encode()!=original:raise ValueError('Boot instrumentation changed production logic')
    recipe='\n'.join(['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer boot.sv',
        'prep -top '+TOP+' -flatten','async2sync','chformal -lower','opt_clean','dffunmap',
        'select -assert-count 41 t:$assert','select -assert-count 1 t:$cover',
        'select -assert-none t:$assume','select -assert-none t:$anyseq','select -assert-count 0 t:$anyconst',
        'check -assert','write_json elaborated.json','write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if (run/'prove.ys').read_text()!=recipe or inp['compile_sources']!=['boot.sv']:
        raise ValueError('Boot compiler recipe changed')
    reset='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    if(run/'reset.smtc').read_text()!=reset:raise ValueError('Boot proof gained an input protocol assumption')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if expected_mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A real boot solver phase was omitted')
    for name,row in inp['tools'].items():
        if sha(Path(shutil.which(name)).read_bytes())!=row['sha256']:raise ValueError('Boot compiler/query tool identity changed')
    work.mkdir()
    for name in inp['files']:(work/name).write_bytes((run/name).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(run/n).read_bytes()for n in ('design.smt2','elaborated.json')):
        raise ValueError('Boot compiler outputs do not reproduce')
    design=json.loads((work/'elaborated.json').read_bytes());kinds=[c['type']for c in design['modules'][TOP]['cells'].values()]
    if any(kinds.count(k)!=v for k,v in {'$assert':41,'$cover':1,'$assume':0,'$anyseq':0,'$anyconst':0,'$mem_v2':0}.items()):
        raise ValueError('Boot elaborated proof scope changed')
    results={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command']
        timeout=command[command.index('--timeout')+1]
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',timeout,'-t',str(depth),'-m',TOP,
            '--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd',
            '--dummy',label+'.responses','--noprogress']
        if solver=='cvc5':wanted+=['--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('Boot solver command/constraint changed')
        log=(run/(label+'.log')).read_bytes();responses=run/(label+'.responses')
        if (sha(log)!=row['log_sha256']or sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']or
            sha(responses.read_bytes())!=row['solver_responses_sha256']):raise ValueError('Real boot solver evidence changed')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Boot witness changed')
        status='FAILED'if expected_mutant else'PASSED'
        if not row['passed']or row['exit']!=(1 if expected_mutant else 0)or re.findall(rb'Status: (\w+)',log)!=[status.encode()]:
            raise ValueError('A required boot safety/coverage/mutant phase is incomplete')
        if expected_mutant and(b'BMC failed!'not in log or b'Assert failed in'not in log or not row['traces']):
            raise ValueError('Boot mutant lacks a semantic counterexample')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded boot result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=1:raise ValueError('No early boot-write reachability witness')
        rebound=query.reproduce_query(run,label,row,bool(expected_mutant),work/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
        results[label]=dict(real_solver_result=status,query_binding=rebound)
    if not fin['passed']:raise ValueError('Boot aggregate result is not complete')
    return dict(run=run.name,mutant=expected_mutant,assertion_cells=41,assumptions=0,internal_cuts=[],
        native_production_source_recovered=True,model_words=227062,address_width=19,
        both_solvers_inductive=not bool(expected_mutant),full_lock_reachability_proved=False,
        only_early_boot_write_coverage=not bool(expected_mutant),both_solvers_detect_mutant=bool(expected_mutant),
        input_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()),results=results)


def main():
    common,query=load('run_handoff'),load('audit_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    cases={'boot-order-r5-held-last-support':None,'boot-order-mutant-skip-model-load-r1':'skip-model-load',
        'boot-order-mutant-early-lock-r1':'early-lock'}
    records=[inspect(HERE/'runs'/name,args.package,out/name,mutant)for name,mutant in cases.items()]
    result=dict(schema='native-full-size-boot-order-source-audit-v1',passed=True,runs=records,
        checker_sha256=query.sha(Path(__file__).read_bytes()),hardware_access=False,solver_replay=False,
        source_to_bitstream_equivalence=False,physical_ddr_proved=False,boot_transport_composed=False,
        sha_algorithm_proved=False,whole_machine_theorem=False,
        isolated_state_lock_corner_retained='audit-probes/boot-order-corner-r1',
        connected_boundary_corner_simulation='audit-probes/boot-order-boundary-corner-r1')
    (out/'FINISHED.json').write_bytes(query.encode(result));print('BOOT ORDER AUDIT PASS: 41 assertions, both solvers, all 4 native source/image joins, 2 semantic mutants')


if __name__=='__main__':main()
