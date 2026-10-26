"""Recover current FIFO sources and audit actual two-clock safety queries.

Re-elaborates frozen proof inputs, without a solver. For unrolled SMT queries,
reproduces SMTBMC's query generation using recorded branch outcomes as replies.
Those replies are not new solver evidence: only the original real Z3/cvc5
results establish safety. Query reproduction binds that evidence to the RTL.
"""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(x):return (json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def load(name):
    spec=importlib.util.spec_from_file_location('_fifo_audit_'+name,HERE/(name+'.py'))
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module


def normalized(raw):
    return [s.strip()for s in raw.splitlines()if s.strip() and not s.startswith((';','(set-option ','(set-logic '))]


def core_query(raw,limit=None):
    lines=normalized(raw)
    checks=[i for i,s in enumerate(lines)if s=='(check-sat)']
    if not checks:raise ValueError('No solver query')
    if limit is not None:
        if len(checks)<limit:raise ValueError('Missing main safety query')
        checks=checks[:limit]
    return lines[:checks[-1]+1],len(checks)


def reproduce_query(run,label,row,mutant,out,actual_path=None,recorded_replies=None,keep_trace_outputs=False):
    actual=(actual_path or run/(label+'.smt2')).read_text()
    # After a mutant failure, SMTBMC asks additional diagnostic questions to
    # identify the failed assertion and print its trace. Bind the actual main
    # safety query through its first failure, not those later model queries.
    limit=None
    if mutant:
        steps=re.findall(r'Checking assertions in step (\d+)',(run/(label+'.log')).read_text())
        if not steps:raise ValueError('Mutant failed without a bounded safety query')
        limit=2*(int(steps[-1])+1)
    wanted,checks=core_query(actual,limit)
    if recorded_replies is not None:
        replies=None
    elif label.endswith('induction'):
        if '--smtc' in row['command'] or '-i' not in row['command']:
            raise ValueError('Induction constraints or proof mode changed')
        replies=['sat']*(checks-1)+['unsat']
    else:
        if '--presat' not in row['command'] or checks%2:
            raise ValueError('Bounded satisfiability checks changed')
        replies=['sat','unsat']*(checks//2)
        if mutant:replies[-1]='sat'
    out.mkdir()
    reply_path=out/'recorded-branch-replies.txt'
    reply_path.write_bytes(recorded_replies.read_bytes()if recorded_replies is not None else ('\n'.join(replies)+'\n').encode())
    argv=row['command'];command=[];i=0
    while i<len(argv):
        word=argv[i]
        if word=='-s':command += [word,argv[i+1]if recorded_replies is not None else'dummy'];i+=2
        elif word in ('--dump-yw','--dump-vcd')and keep_trace_outputs:
            command += [word,str(out/Path(argv[i+1]).name)];i+=2
        elif word in ('--timeout','--dump-yw','--dump-vcd','--dummy'):i+=2
        elif word=='--dump-smt2':command += [word,str(out/'reproduced.smt2')];i+=2
        else:command.append(word);i+=1
    env=None
    if recorded_replies is None:
        command[-1:-1]=['--dummy',str(reply_path),'--noprogress','--noinfo']
    else:
        # Keep SMTIO's original backend behavior, including Boolean/model
        # response formatting. Replace only the solver process with a finite
        # recorded-response player; no answers here establish a new theorem.
        player=out/'recorded-response-backend';player.mkdir()
        executable=player/argv[argv.index('-s')+1]
        program='#!'+sys.executable+'\n'+'''import os,sys
from pathlib import Path
messages=[];pending=[];depth=0
for line in Path(os.environ['FIFO_AUDIT_REPLIES']).read_text().splitlines():
    if not line.strip():continue
    pending.append(line);depth+=line.count('(')-line.count(')')
    if depth==0:messages.append('\\n'.join(pending));pending=[]
if pending or depth:raise SystemExit('Incomplete recorded solver response')
cursor=0
for line in sys.stdin:
    if line.startswith(('(check-sat','(get-value','(get-model','(get-unsat')):
        if cursor>=len(messages):raise SystemExit('Recorded solver responses exhausted')
        sys.stdout.write(messages[cursor]+'\\n');sys.stdout.flush();cursor+=1
    if line.strip()=='(exit)':break
'''
        executable.write_text(program);executable.chmod(0o700)
        env=dict(os.environ,PATH=str(player)+os.pathsep+os.environ['PATH'],FIFO_AUDIT_REPLIES=str(reply_path))
        command[-1:-1]=['--dummy',str(out/'replayed-real-responses.txt'),'--noprogress']
    with (out/'generation.log').open('w')as log:
        cp=subprocess.run(command,cwd=run,env=env,stdout=log,stderr=subprocess.STDOUT,timeout=90 if recorded_replies is not None else 30)
    if cp.returncode!=(1 if mutant else 0):
        raise ValueError('Query generation could not reproduce the recorded branch outcomes')
    reproduced,count=core_query((out/'reproduced.smt2').read_text())
    if count!=checks or reproduced!=wanted:
        raise ValueError('Recorded unrolled safety query differs from source-bound generation: '+label)
    (out/'COMMAND.json').write_bytes(encode(command))
    return dict(checks=checks,original_core_query_sha256=sha('\n'.join(wanted).encode()),
        regenerated_core_query_identical=True,solver_replay=False,
        synthetic_replies_used_only_to_reproduce_query_generation=recorded_replies is None,
        real_recorded_solver_replies_used=recorded_replies is not None)


def cover_supplement(run,work):
    channel=json.loads((run/'INPUTS.json').read_bytes())['binding']['channel']
    evidence=HERE/('audit-probes/fifo-encrypted-'+channel+'-cover-r2')
    raw=(evidence/'FINISHED.json').read_bytes();record=json.loads(raw)
    if (record['proof_run']!=run.name or record['inputs_sha256']!=sha((run/'INPUTS.json').read_bytes())or
            record['emitted_smt_sha256']!=sha((run/'design.smt2').read_bytes())or
            record['cover_constraints_sha256']!=sha((run/'cover.smtc').read_bytes())):
        raise ValueError('Separate coverage does not bind the same source/query constraints')
    row=record['results']['cvc5'];log=(evidence/'cvc5.log').read_bytes()
    if (not row['passed']or row['exit']!=0 or re.findall(rb'Status: (\w+)',log)!=[b'PASSED']or
            len(re.findall(rb'Reached cover statement',log))!=4 or sha(log)!=row['log_sha256']or
            sha((evidence/'cvc5.smt2').read_bytes())!=row['query_sha256']or
            sha((evidence/'cvc5.responses').read_bytes())!=row['real_solver_responses_sha256']):
        raise ValueError('No completed source-bound separate four-goal coverage result')
    inp=json.loads((run/'INPUTS.json').read_bytes());timeout=row['command'][row['command'].index('--timeout')+1]
    expected=['yosys-smtbmc','-s','cvc5','--unroll','--timeout',timeout,'-t',str(inp['cover_depth']),
        '-m','fifo_harness','--smtc','cover.smtc','--presat','-c','--noprogress',
        '--dump-smt2',str(evidence/'cvc5.smt2'),'--dummy',str(evidence/'cvc5.responses'),'design.smt2']
    if row['command']!=expected:raise ValueError('Separate coverage command/scope changed')
    binding=reproduce_query(run,'cvc5-cover',row,False,work/'separate-cover-query-binding',
        actual_path=evidence/'cvc5.smt2',recorded_replies=evidence/'cvc5.responses')
    return dict(passed=True,evidence_sha256=sha(raw),solver='cvc5',four_goals_reached=True,
        actual_board_frequency_ratio_stimulus=True,query_binding=binding,
        original_z3_coverage_timeout_retained=True,helper_end_hash_not_used_as_executed_source_identity=True)


def inspect(run,common,runner,root,bound,out):
    inp_raw=(run/'INPUTS.json').read_bytes();inp=json.loads(inp_raw)
    fin_raw=(run/'FINISHED.json').read_bytes();fin=json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw):raise ValueError('Proof input receipt changed')
    expected_labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if inp.get('mutant')else('bmc','induction','cover'))}
    if set(fin['results'])!=expected_labels:raise ValueError('Required real-solver phases are missing or changed')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Proof input changed: '+name)
    for tool,row in inp['tools'].items():
        if sha(Path(shutil.which(tool)).read_bytes())!=row['sha256']:
            raise ValueError('Tool changed; exact re-elaboration is unavailable: '+tool)
    channel=inp['binding']['channel'];width,bits=(276,5)if channel=='commands'else(257,6)
    if inp['binding']['width']!=width or inp['binding']['depth']!=1<<bits:
        raise ValueError('Actual channel geometry changed')
    for key,value in bound.items():
        if inp['binding'].get(key)!=value:raise ValueError('Current native/image binding changed: '+key)
    original=(root/'project/fifo.sv').read_bytes();transport=(root/'project/thin_transport.sv').read_bytes()
    if (run/'production-fifo.sv').read_bytes()!=original or(run/'production-transport.sv').read_bytes()!=transport:
        raise ValueError('Current distributed source differs from proof source')
    text=transport.decode();start=text.index('    wire common_reset_n = ')
    release=text[start:text.index('\n    logic core_fault_q,',start)]
    actual_width,actual_bits,module,override=runner.channel_binding(transport,channel)
    if (actual_width,actual_bits)!=(width,bits):raise ValueError('Actual transport geometry differs from proof')
    if (run/'harness.sv').read_text()!=runner.harness(release,width,bits,channel,module,override):
        raise ValueError('Clock/reset wrapper or channel connection changed')
    monitor=(HERE/'fifo-monitor.inc.sv').read_text()
    source=(run/'fifo.sv').read_text()
    marker='\n'+monitor+'\nendmodule'
    if not source.startswith('`undef FORMAL\n')or source.count(marker)!=1:
        raise ValueError('Unexpected FIFO instrumentation')
    source=source.removeprefix('`undef FORMAL\n').replace(marker,'\nendmodule')
    mutant=inp.get('mutant')
    mutations={
        'flip-operation-bit':('memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i;',
            'memory_q[write_binary_q[ADDR_BITS-1:0]] <= s_data_i ^ (WIDTH\'(1) << (WIDTH-1));'),
        'wrong-prefetch-row':('m_data_q <= memory_q[m_binary_next_address];',
            'm_data_q <= memory_q[m_binary_next_address ^ {{(ADDR_BITS-1){1\'b0}},1\'b1}];'),
    }
    if mutant:
        before,after=mutations[mutant]
        if source.count(after)!=1:raise ValueError('Mutation site changed')
        source=source.replace(after,before)
    if source.encode()!=original:raise ValueError('Instrumentation changed production FIFO logic')
    if inp['internal_cuts']or inp['changed_production_parameters']or not inp['multiclock']:
        raise ValueError('FIFO is abstracted, resized or not using independent clocks')
    if inp['compile_sources']!=['fifo.sv','harness.sv']:
        raise ValueError('Compiled source graph changed')
    expected_recipe='\n'.join([
        'read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer fifo.sv harness.sv',
        'prep -top fifo_harness -flatten','clk2fflogic','chformal -lower','opt_clean',
        'dffunmap','select -assert-count 28 t:$assert','select -assert-count 4 t:$cover',
        'select -assert-none t:$assume','select -assert-none t:$anyseq',
        'select -assert-count 1 t:$anyconst','check -assert','write_json elaborated.json',
        'write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if (run/'prove.ys').read_text()!=expected_recipe:raise ValueError('Compiler recipe or clock lowering changed')
    reset=('initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
        'state 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n')
    if (run/'reset.smtc').read_text()!=reset:raise ValueError('Base reset constraints changed')
    work=out/run.name;work.mkdir()
    for name in inp['files']:
        dest=work/name;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes((run/name).read_bytes())
    with (work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or(work/'design.smt2').read_bytes()!=(run/'design.smt2').read_bytes():
        raise ValueError('Emitted SMT does not reproduce from the frozen source graph')
    if (work/'elaborated.json').read_bytes()!=(run/'elaborated.json').read_bytes():
        raise ValueError('Elaborated source/cell graph changed')
    design=json.loads((work/'elaborated.json').read_bytes())
    cells=[c for m in design['modules'].values()for c in m.get('cells',{}).values()]
    kinds=[c['type']for c in cells]
    block=module.endswith('_block')
    if any(kinds.count(k)!=n for k,n in {'$assert':28,'$cover':4,'$anyconst':1,'$mem_v2':0 if block else 1,'$assume':0,'$anyseq':0}.items()):
        raise ValueError('Proof/assertion/assumption/memory geometry changed')
    if block:
        names=design['modules']['fifo_harness']['netnames']
        rows=[names.get('dut.memory_q['+str(i)+']',{}).get('bits',[])for i in range(1<<bits)]
        flattened=[b for row in rows for b in row]
        if (any(len(row)!=width for row in rows)or any(not isinstance(b,int)for b in flattened)or
                len(set(flattened))!=width*(1<<bits)):
            raise ValueError('Literal register-array rows were lost, aliased or resized')
        geometry=dict(WIDTH=width,SIZE=1<<bits,ABITS=bits,representation='actual array lowered to distinct register rows')
    else:
        memory=next(c for c in cells if c['type']=='$mem_v2')
        geometry={k:int(memory['parameters'][k],2)for k in ('WIDTH','SIZE','ABITS','WR_CLK_ENABLE','RD_CLK_ENABLE')}
        if geometry!={'WIDTH':width,'SIZE':1<<bits,'ABITS':bits,'WR_CLK_ENABLE':0,'RD_CLK_ENABLE':0}:
            raise ValueError('Literal payload/memory or multiclock lowering changed')
    results={};separate_cover=None
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1)
        timeout=int(row['command'][row['command'].index('--timeout')+1])
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        expected_command=['yosys-smtbmc','-s',solver,'--timeout',str(timeout),'-t',str(depth),
            '-m','fifo_harness','--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd']
        if row.get('solver_responses_sha256')is not None:
            expected_command+=['--dummy',label+'.responses','--noprogress']
            if sha((run/(label+'.responses')).read_bytes())!=row['solver_responses_sha256']:
                raise ValueError('Real solver response stream changed')
        expected_command+=['--unroll']
        if phase!='induction':expected_command+=['--smtc','cover.smtc'if phase=='cover'else'reset.smtc','--presat']
        if phase=='induction':expected_command+=['-i']
        if phase=='cover':expected_command+=['-c']
        expected_command+=['design.smt2']
        if row['command']!=expected_command:raise ValueError('Safety/cover solver command scope changed')
        raw=(run/(label+'.log')).read_bytes()
        if sha(raw)!=row['log_sha256']:raise ValueError('Solver log changed')
        if row.get('query_sha256')and sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']:
            raise ValueError('Raw solver query changed')
        for name,digest in row.get('traces',{}).items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Trace changed')
        if not row['passed']:
            if mutant=='wrong-prefetch-row'and label=='cvc5-bmc'and not row['status']:
                results[label]=dict(passed=False,unresolved_search=True);continue
            if block and label=='cvc5-induction'and not row['status']and b'timeout'in raw:
                results[label]=dict(passed=False,secondary_induction_unresolved=True,primary_theorem_not_changed=True);continue
            if block and label.endswith('cover')and not row['status']and b'timeout'in raw:
                if separate_cover is None:separate_cover=cover_supplement(run,work)
                results[label]=dict(passed=False,original_search_or_trace_timeout_retained=True,
                    completed_separate_cvc5_coverage=separate_cover);continue
            raise ValueError('Unresolved selected solver result: '+label)
        wanted=['FAILED']if mutant else['PASSED']
        if re.findall(rb'Status: (\w+)',raw)!=[s.encode()for s in wanted]:
            raise ValueError('Solver status does not match its claimed result')
        if label.endswith('induction')and b'Temporal induction successful.'not in raw:
            raise ValueError('No inductive safety result')
        if mutant and(not row['traces']or b'Assert failed in 'not in raw or b'BMC failed!'not in raw):
            raise ValueError('No semantic mutation counterexample')
        if label.endswith('cover'):
            if len(re.findall(rb'Reached cover statement',raw))!=4:raise ValueError('Missing traffic goals')
            results[label]=dict(passed=True,raw_cover_logs_and_witness_identities_checked=True)
        else:results[label]=dict(passed=True,query_binding=reproduce_query(run,label,row,mutant,work/(label+'-query-binding')))
    return dict(run=run.name,mutant=mutant,channel=channel,memory=geometry,
        primary_unbounded_safety=not mutant,secondary_unbounded_safety=bool(not mutant and fin['results']['cvc5-induction']['passed']),
        exact_production_logic_recovered=True,exact_compiler_outputs_reproduced=True,
        assertions=28,assumptions=0,observer_constants=1,internal_cuts=[],results=results,
        inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()))


def main():
    common,runner=load('run_handoff'),load('run_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--include-protected',action='store_true')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    pin,root,bound=common.binding(args.package,'baseline')
    joined={}
    for variant in ('baseline','seeded-sampling'):
        pin,r,b=common.binding(args.package,variant)
        for name in ('fifo.sv','thin_transport.sv'):
            if (r/'project'/name).read_bytes()!=(root/'project'/name).read_bytes():raise ValueError('Transport/FIFO differs: '+variant)
        joined[variant]=b
    selected=('fifo-commands-r5','fifo-returns-r1','fifo-commands-mutant-flip-operation-bit-r1','fifo-commands-mutant-wrong-prefetch-row-r1')
    records=[inspect(HERE/'runs'/name,common,runner,root,bound,out)for name in selected]
    if args.include_protected:
        for variant in ('kv-protected','encrypted-memory'):
            pin,r,b=common.binding(args.package,variant)
            for channel in ('commands','returns'):
                epoch='r2'if variant=='encrypted-memory'else'r1'
                records.append(inspect(HERE/'runs'/('fifo-'+variant+'-'+channel+'-'+epoch),common,runner,r,b,out))
            joined[variant]=b
    witness_path=HERE/'FIFO-PREFETCH-SECONDARY-WITNESS-r2.json';witness=json.loads(witness_path.read_bytes())
    evidence=HERE/'audit-probes/fifo-prefetch-cvc5-witness-r1'
    raw=(evidence/'cvc5.log').read_bytes();replies=(evidence/'responses.txt').read_text().splitlines()
    if not witness['passed']or sha(raw)!=witness['log_sha256']or not raw.rstrip().endswith(b'Status: PASSED'):
        raise ValueError('Secondary sufficient-witness result changed')
    if b'BMC failed!'not in raw or b'Checking witness constraints...'not in raw or replies[-2:]!=['sat','unsat']:
        raise ValueError('Secondary witness does not force a safety failure')
    if sha((evidence/'query.smt2').read_bytes())!=witness['query_sha256']or sha((evidence/'responses.txt').read_bytes())!=witness['solver_responses_sha256']:
        raise ValueError('Secondary sufficient-witness query/responses changed')
    mutant=HERE/'runs/fifo-commands-mutant-wrong-prefetch-row-r1'
    if (witness['emitted_design_sha256']!=sha((mutant/'design.smt2').read_bytes())or
            witness['witness_sha256']!=sha((mutant/'z3-bmc-%.yw').read_bytes())or
            '--check-witness'not in witness['command']):
        raise ValueError('Secondary sufficient-witness source/mode binding changed')
    result=dict(schema='current-native-two-clock-fifo-audit-v1',passed=True,runs=records,
        current_native_source_and_image_joins=joined,secondary_prefetch_witness_sha256=sha(witness_path.read_bytes()),
        whole_transport_composition_proved=False,physical_metastability_or_gray_bus_skew_proved=False,
        source_to_bitstream_equivalence=False,whole_machine_theorem=False,hardware_access=False,solver_replay=False,
        checker_sha256=sha(Path(__file__).read_bytes()),harness_generator_sha256=sha((HERE/'run_fifo.py').read_bytes()))
    (out/'FINISHED.json').write_bytes(encode(result))
    print('FIFO AUDIT PASS:',len(records)-2,'literal channel proofs, 28 assertions each;',
        sum(r['secondary_unbounded_safety']for r in records),'also inductive in the secondary solver;',
        len(joined),'native/image joins; 2 semantic mutants')


if __name__=='__main__':main()
