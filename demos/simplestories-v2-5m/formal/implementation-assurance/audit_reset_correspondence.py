"""Reproduce native reset-fragment and real solver-query correspondence."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_reset_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    common,runner,query=map(load,('run_handoff','run_reset_correspondence','audit_fifo'));sha=query.sha
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--proof',type=Path,default=HERE/'runs/reset-correspondence-r1')
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();run=args.proof.resolve();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes();inp,fin=json.loads(inp_raw),json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw)or not fin['passed']or inp['mutant']:
        raise ValueError('Reset proof receipt changed or incomplete')
    if (inp['assertion_cells']!=11 or inp['assumption_cells']!=0 or inp['cover_cells']!=1 or inp['observer_constants']!=0 or
        inp['internal_cuts']or inp['changed_production_parameters']or not inp['multiclock']):raise ValueError('Reset theorem scope changed')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Reset proof input changed')
    paths={'top.sv':'project/top.sv','memory.sv':'project/booted_memory.sv','transport.sv':'project/thin_transport.sv'}
    reference=None;joins={};native_sources={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,root,bound=common.binding(args.package,variant);native={n:(root/p).read_bytes()for n,p in paths.items()}
        derived=runner.derive(native)
        if reference is not None and derived!=reference:raise ValueError('Reset source/binding differs across native designs')
        reference=derived;joins[variant]=bound
        native_sources[variant]={n:dict(path=paths[n],sha256=sha(raw))for n,raw in native.items()}
    source,fragments,bindings=reference
    bound=dict(native_joins=joins,native_sources=native_sources,actual_clock_reset_connections=bindings,
        source_history_reset_equals_transport_core_reset=True,transport_common_reset_equals_actual_top_core_reset=True,
        top_core_release_does_not_reassert_without_common_hard_reset=True)
    if inp['binding']!=bound or fin['binding']!=bound or(run/'reset.sv').read_text()!=source:
        raise ValueError('Native reset fragments or clock/reset association changed')
    for name,text in fragments.items():
        if(run/('native-fragment-'+name)).read_text()!=text:raise ValueError('Recorded native fragment changed')
    recipe='\n'.join(['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer reset.sv',
        'prep -top '+runner.TOP+' -flatten','clk2fflogic','chformal -lower','opt_clean','dffunmap',
        'select -assert-count 11 t:$assert','select -assert-count 1 t:$cover','select -assert-none t:$assume',
        'select -assert-none t:$anyseq','select -assert-count 0 t:$anyconst','check -assert',
        'write_json elaborated.json','write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    reset='initial\nassume (= [board_reset_n] false)\nassume (= [trusted_reset_n] false)\nassume (= [app_reset_n] false)\nstate 1\nassume (= [board_reset_n] false)\nassume (= [trusted_reset_n] false)\nassume (= [app_reset_n] false)\n'
    if(run/'prove.ys').read_text()!=recipe or(run/'reset.smtc').read_text()!=reset:
        raise ValueError('Reset compiler or input assumptions changed')
    for name,row in inp['tools'].items():
        if sha(Path(shutil.which(name)).read_bytes())!=row['sha256']:raise ValueError('Exact reset compiler/query tool changed')
    for name in inp['files']:(out/name).write_bytes((run/name).read_bytes())
    with(out/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=out,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((out/n).read_bytes()!=(run/n).read_bytes()for n in ('design.smt2','elaborated.json')):
        raise ValueError('Native reset compiler outputs do not reproduce')
    labels={s+'-'+p for s in ('z3','cvc5')for p in ('bmc','induction','cover')}
    if set(fin['results'])!=labels:raise ValueError('Reset proof phase omitted')
    results={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command'];timeout=command[command.index('--timeout')+1]
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',timeout,'-t',str(depth),'-m',runner.TOP,
            '--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd',
            '--dummy',label+'.responses','--noprogress','--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('Reset solver command changed')
        log=(run/(label+'.log')).read_bytes();responses=run/(label+'.responses')
        if (not row['passed']or row['exit']!=0 or re.findall(rb'Status: (\w+)',log)!=[b'PASSED']or
            sha(log)!=row['log_sha256']or sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']or sha(responses.read_bytes())!=row['solver_responses_sha256']):
            raise ValueError('Incomplete or altered reset solver evidence')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Reset release witness changed')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded reset result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=1:raise ValueError('Reset release goal not reached')
        results[label]=query.reproduce_query(run,label,row,False,out/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
    result=dict(schema='native-reset-correspondence-source-audit-v1',passed=True,assertions=11,assumptions=0,
        native_joins=joins,actual_clock_reset_connections=bindings,both_solver_unbounded_safety=True,
        inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()),
        query_bindings=results,checker_sha256=sha(Path(__file__).read_bytes()),hardware_access=False,
        solver_replay=False,physical_reset_generator_proved=False)
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());(out/'FINISHED.json').write_bytes(query.encode(result))
    print('RESET CORRESPONDENCE AUDIT PASS: 11 native assertions, both solvers, 4 native/image joins')


if __name__=='__main__':main()
