"""Audit the actual boot controller/FIFO/adapter ordering composition."""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_boundary_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def observer_writes_only(monitor):
    # Remove assertion/coverage expressions before identifying assignments:
    # a comparison inside assert(x <= y) is not an assignment to x.
    text=monitor
    for name in ('assert','cover'):
        while True:
            match=re.search(r'\b'+name+r'\s*\(',text)
            if not match:break
            cursor=match.end();depth=1
            while depth:
                if text[cursor]=='(':depth+=1
                elif text[cursor]==')':depth-=1
                cursor+=1
            text=text[:match.start()]+text[cursor:]
    text=re.sub(r'//[^\n]*','',text)
    for lhs in re.findall(r'\b(\w+)\s*(?:<=|=(?!=))',text):
        if not lhs.startswith('f_'):raise ValueError('An observer drives a native signal: '+lhs)
    if re.search(r'\b(?:force|release|assume)\b',text):raise ValueError('Observer contains an input restriction or force')


def inspect(run,package,work,mutant=None):
    common,runner,queries=load('run_handoff'),load('run_boot_boundary'),load('audit_fifo')
    sha=queries.sha
    inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
    inp,fin=json.loads(inp_raw),json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw)or inp['mutant']!=mutant or fin['mutant']!=mutant:
        raise ValueError('Boot boundary proof receipt scope changed')
    if (inp['assertion_cells']!=66 or inp['cover_cells']!=2 or inp['assumption_cells']!=0 or
        inp['observer_constants']!=0 or inp['internal_cuts']or inp['changed_production_parameters']or inp['multiclock']):
        raise ValueError('Boot boundary dimensions, properties, assumptions or cuts changed')
    if fin['binding']!=inp['binding']or fin['assertion_cells']!=66 or fin['internal_cuts']:
        raise ValueError('Boot boundary result scope differs from its inputs')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Frozen input changed: '+name)
    original=None;joins={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,root,bound=common.binding(package,variant)
        files={name:(root/path).read_bytes()for name,path in runner.SOURCES.items()}
        if original is not None and original!=files:raise ValueError('Native boot boundary differs across designs')
        original=files;joins[variant]=bound
    binding=dict(native_joins=joins,production_sources={n:dict(path=runner.SOURCES[n],sha256=sha(r))for n,r in original.items()},
        model_words=227062,address_width=19,request_fifo_depth=2,request_fifo_data_width=256,
        readonly_observer_exports={'boot.sv':{'f_observe_reads_o':19,'f_observe_final_return_o':1},
            'fifo.sv':{'f_observe_state_o':44},'adapter.sv':{'f_observe_read_owned_o':1}},
        internal_rtl_cuts=[],sha_engine_assumed_correct=False)
    if inp['binding']!=binding:raise ValueError('Native image/source/observer association changed')
    for name,raw in original.items():
        if(run/('production-'+name)).read_bytes()!=raw:raise ValueError('Production source changed: '+name)
    boot=(HERE/'boot-order-monitor.inc.sv').read_text();parent=(HERE/'boot-boundary-monitor.inc.sv').read_text()
    if(run/'boot-monitor.inc.sv').read_text()!=boot or(run/'parent-monitor.inc.sv').read_text()!=parent:
        raise ValueError('Boot boundary target/support monitor changed')
    observer_writes_only(boot);observer_writes_only(parent)
    sources=dict(original)
    if mutant:
        name,before,after=runner.MUTATIONS[mutant]
        sources[name]=runner.once(sources[name].decode(),before,after).encode()
    expected=runner.instrument(sources,boot,parent)
    if any((run/n).read_bytes()!=raw for n,raw in expected.items()):
        raise ValueError('Instrumentation does not recover exact native production logic')
    if(run/'boundary.sv').read_text().split('\n);',1)[0].removeprefix('`undef FORMAL\n')!=original['boundary.sv'].decode().split('\n);',1)[0]:
        raise ValueError('The actual external boundary ports changed')
    source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv']
    recipe='\n'.join(['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer '+' '.join(source_list),
        'prep -top '+runner.TOP+' -flatten','async2sync','chformal -lower','opt_clean','dffunmap',
        'select -assert-count 66 t:$assert','select -assert-count 2 t:$cover','select -assert-none t:$assume',
        'select -assert-none t:$anyseq','select -assert-count 0 t:$anyconst','check -assert',
        'write_json elaborated.json','write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if(run/'prove.ys').read_text()!=recipe or inp['compile_sources']!=source_list:raise ValueError('Compiler recipe/source selection changed')
    reset='initial\nassume (= [app_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\n'
    if(run/'reset.smtc').read_text()!=reset:raise ValueError('An external protocol input was constrained')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A required real-solver phase was omitted')
    for name,row in inp['tools'].items():
        if sha(Path(shutil.which(name)).read_bytes())!=row['sha256']:raise ValueError('Exact compiler/query tool changed')
    work.mkdir()
    for name in inp['files']:(work/name).write_bytes((run/name).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(run/n).read_bytes()for n in ('design.smt2','elaborated.json')):
        raise ValueError('Boot boundary compiler outputs do not reproduce')
    top=json.loads((work/'elaborated.json').read_bytes())['modules'][runner.TOP]
    kinds=[c['type']for c in top['cells'].values()]
    if any(kinds.count(k)!=v for k,v in {'$assert':66,'$cover':2,'$assume':0,'$anyseq':0,'$anyconst':0,'$mem_v2':0}.items()):
        raise ValueError('Elaborated obligation scope changed')
    bits=[]
    for prefix,width in [('write_q',1),('addr_q',19),('data_q',256)]:
        for i in range(2):
            row=top['netnames'].get('u_request_fifo.'+prefix+'['+str(i)+']',{}).get('bits',[])
            if len(row)!=width or not all(isinstance(b,int)for b in row):raise ValueError('A full-width native queue row is missing')
            bits+=row
    if len(set(bits))!=552:raise ValueError('Native queue fields were aliased or resized')
    results={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command'];timeout=command[command.index('--timeout')+1]
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',timeout,'-t',str(depth),'-m',runner.TOP,
            '--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd',
            '--dummy',label+'.responses','--noprogress']
        if solver=='cvc5':wanted+=['--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('A solver command or constraint changed')
        log=(run/(label+'.log')).read_bytes();responses=run/(label+'.responses')
        if (sha(log)!=row['log_sha256']or sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']or
            sha(responses.read_bytes())!=row['solver_responses_sha256']):raise ValueError('Raw real-solver evidence changed')
        expected_status=b'FAILED'if mutant else b'PASSED'
        if not row['passed']or row['exit']!=(1 if mutant else 0)or re.findall(rb'Status: (\w+)',log)!=[expected_status]:
            raise ValueError('A required solver result is incomplete')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('A real-solver witness changed')
        if mutant and(b'BMC failed!'not in log or b'Assert failed in'not in log or not row['traces']):raise ValueError('No semantic corruption counterexample')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=2:raise ValueError('An early legal-write reachability goal is missing')
        rebound=queries.reproduce_query(run,label,row,bool(mutant),work/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
        results[label]=dict(real_solver_status=expected_status.decode(),query_binding=rebound)
    if not fin['passed']:raise ValueError('The selected composition campaign is incomplete')
    return dict(run=run.name,mutant=mutant,assertions=66,assumptions=0,internal_cuts=[],
        exact_native_source_logic_recovered=True,observer_feedback_into_production=False,
        full_queue_register_bits=552,both_solver_inductive=not bool(mutant),
        model_write_output_prefix_proved=not bool(mutant),lock_requires_prior_boundary_read=not bool(mutant),
        local_queue_model_writes_drained_at_lock=not bool(mutant),
        whole_transport_or_machine_theorem=False,results=results,
        inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()))


def main():
    common,queries=load('run_handoff'),load('audit_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    cases={'boot-boundary-r3-owned-read-join':None,
        'boot-boundary-mutant-wrong-address-r1':'wrong-queued-address-row',
        'boot-boundary-mutant-bypass-response-fault-r1':'bypass-response-fault-command-gate'}
    records=[inspect(HERE/'runs'/name,args.package,out/name,mutant)for name,mutant in cases.items()]
    result=dict(schema='current-native-boot-boundary-ordering-audit-v1',passed=True,runs=records,
        checker_sha256=queries.sha(Path(__file__).read_bytes()),native_designs=4,
        hardware_access=False,solver_replay=False,source_to_bitstream_equivalence=False,
        outer_boot_runtime_and_async_transport_join_proved=False,whole_machine_theorem=False)
    (out/'FINISHED.json').write_bytes(queries.encode(result));print('BOOT BOUNDARY AUDIT PASS: 66 assertions, both solvers, 4 native joins, 2 semantic mutants')


if __name__=='__main__':main()
