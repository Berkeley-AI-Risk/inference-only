"""Audit actual transport proofs and discharge every reused FIFO invariant.

Recover the production sources, reproduce compiler outputs and proof queries,
and recheck the separately proved, assumption-free FIFO premises. Solver
timeouts retain their original status. No solver is invoked by this audit.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(x):return(json.dumps(x,indent=2,sort_keys=True)+'\n').encode()
def load(name):
    spec=importlib.util.spec_from_file_location('_transport_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def once(text,old,new):
    if text.count(old)!=1:raise ValueError('Transport instrumentation boundary changed')
    return text.replace(old,new)


def inspect(run,variant,package,fresh_premises,work,*,legacy=False,expected_mutant=None):
    common,runner,fifo,queries=load('run_handoff'),load('run_transport'),load('run_fifo'),load('audit_fifo')
    inp_raw=(run/'INPUTS.json').read_bytes();inp=json.loads(inp_raw)
    fin_raw=(run/'FINISHED.json').read_bytes();fin=json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw):raise ValueError('Transport input receipt changed')
    count=51 if legacy else 56
    mutant=inp['mutant']
    if mutant!=expected_mutant or fin['mutant']!=expected_mutant:
        raise ValueError('Unexpected transport mutation or missing positive proof')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A real solver phase was omitted')
    if (inp['assertion_cells']!=count or inp['assumption_cells']!=52 or inp['cover_cells']!=3 or
            inp['observer_constants']!=2 or inp['internal_cuts']or inp['changed_production_parameters']or not inp['multiclock']):
        raise ValueError('Transport property/assumption/source scope changed')
    if not legacy and inp['binding'].get('field_identity_assertions')!=5:
        raise ValueError('Exact physical operation/address/data obligations omitted')
    if fin['binding']!=inp['binding'] or fin['assertion_cells']!=count or fin['internal_cuts']:
        raise ValueError('Transport result scope differs from its input receipt')
    if bool(inp['binding'].get('directed_negative_probe'))!=bool(mutant):
        raise ValueError('A positive proof gained a directed stimulus or a negative probe lost it')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Transport proof input changed: '+name)
    pin,root,bound=common.binding(package,variant)
    for key,value in bound.items():
        if inp['binding'].get(key)!=value:raise ValueError('Transport native/image binding changed: '+key)
    fifo_raw=(root/'project/fifo.sv').read_bytes();parent_raw=(root/'project/thin_transport.sv').read_bytes()
    if (run/'production-fifo.sv').read_bytes()!=fifo_raw or(run/'production-transport.sv').read_bytes()!=parent_raw:
        raise ValueError('Transport proof is not the current production RTL')
    lemma_raw=(run/'discharged-fifo-lemma-audit.json').read_bytes();lemma=json.loads(lemma_raw)
    if not lemma['passed']or sha(lemma_raw)!=inp['binding']['fifo_lemma_audit_sha256']:
        raise ValueError('FIFO premise ledger changed')
    if lemma['current_native_source_and_image_joins']!=fresh_premises['current_native_source_and_image_joins']:
        raise ValueError('FIFO premise native/image join no longer holds')
    old_rows={r['run']:r for r in lemma['runs']}
    new_rows={r['run']:r for r in fresh_premises['runs']}
    for name,row in old_rows.items():
        for field in ('inputs_sha256','finished_sha256','emitted_smt_sha256','primary_unbounded_safety','assertions','assumptions','internal_cuts'):
            if row[field]!=new_rows[name][field]:raise ValueError('Fresh FIFO premise check disagrees: '+name+'/'+field)
    template=(HERE/'fifo-monitor.inc.sv').read_text()
    origins=runner.verify_fifo_lemma_inputs(lemma,variant,fifo_raw,parent_raw,template,common)
    if not legacy and inp['binding'].get('discharged_fifo_lemma_origins')!=origins:
        raise ValueError('Recorded FIFO discharge differs from the independently checked premises')
    expected_lemmas='\n'.join(s for s in template.splitlines()if not s.strip().startswith('cover('))+'\n'
    expected_lemmas=expected_lemmas.replace('assert(','assume(')
    if (run/'fifo-monitor.inc.sv').read_text()!=expected_lemmas:
        raise ValueError('A transport assumption is not an independently proved FIFO invariant')
    limit=pin['kv_limit'];policy=runner.render_policy_monitor(limit)
    parent_monitor=runner.render_parent_monitor(limit,field_identity=not legacy)
    if (run/'policy-monitor.inc.sv').read_text()!=policy or(run/'parent-monitor.inc.sv').read_text()!=parent_monitor:
        raise ValueError('New transport/range obligations changed or became assumptions')
    src=(run/'fifo.sv').read_text()
    if not src.startswith('`undef FORMAL\n'):raise ValueError('Unexpected original assertion selection')
    recovered=once(src.removeprefix('`undef FORMAL\n'),'\n'+expected_lemmas+policy+'\nendmodule','\nendmodule')
    if recovered.encode()!=fifo_raw:raise ValueError('Production FIFO logic changed beyond observers')
    src=(run/'transport.sv').read_text()
    if not src.startswith('`undef FORMAL\n'):raise ValueError('Unexpected transport assertion selection')
    recovered=once(src.removeprefix('`undef FORMAL\n'),'\n'+parent_monitor+'\nendmodule','\nendmodule')
    if mutant:
        old,new=runner.MUTATIONS[mutant]
        recovered=once(recovered,new,old)
    if recovered.encode()!=parent_raw:
        raise ValueError('Production transport logic changed beyond observers')
    module=fifo.channel_binding(parent_raw,'commands')[2]
    if fifo.channel_binding(parent_raw,'returns')[2]!=module:raise ValueError('Mixed FIFO source context')
    if inp['compile_sources']!=['fifo.sv','transport.sv']:raise ValueError('Transport compilation inputs changed')
    recipe='\n'.join([
        'read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer fifo.sv transport.sv',
        'prep -top board1_thin_ddr_app_transport -flatten','clk2fflogic','chformal -lower','opt_clean',
        'dffunmap',f'select -assert-count {count} t:$assert','select -assert-count 3 t:$cover',
        'select -assert-count 52 t:$assume','select -assert-none t:$anyseq',
        'select -assert-count 2 t:$anyconst','check -assert','write_json elaborated.json',
        'write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if(run/'prove.ys').read_text()!=recipe:raise ValueError('Compiler recipe changed or hidden constraints added')
    reset=('initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
        'state 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n')
    if mutant:reset+=runner.render_mutant_stimulus(mutant)
    if(run/'reset.smtc').read_text()!=reset:raise ValueError('External reset/protocol assumptions changed')
    for tool,row in inp['tools'].items():
        if sha(Path(shutil.which(tool)).read_bytes())!=row['sha256']:raise ValueError('Exact compiler/query tool identity changed')
    work.mkdir()
    for name in inp['files']:
        p=work/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((run/name).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or(work/'design.smt2').read_bytes()!=(run/'design.smt2').read_bytes()or(work/'elaborated.json').read_bytes()!=(run/'elaborated.json').read_bytes():
        raise ValueError('Transport compiler outputs do not reproduce from exact RTL')
    design=json.loads((work/'elaborated.json').read_bytes());top=design['modules']['board1_thin_ddr_app_transport']
    kinds=[c['type']for c in top['cells'].values()];block=module.endswith('_block')
    expected={'$assert':count,'$assume':52,'$cover':3,'$anyconst':2,'$anyseq':0,'$mem_v2':0 if block else 2}
    if any(kinds.count(k)!=v for k,v in expected.items()):raise ValueError('Transport elaborated obligation counts changed')
    if block:
        geometry={}
        for prefix,width,size in [('u_commands',276,32),('u_returns',257,64)]:
            rows=[top['netnames'].get(prefix+'.memory_q['+str(i)+']',{}).get('bits',[])for i in range(size)]
            bits=[b for row in rows for b in row]
            if any(len(row)!=width for row in rows)or any(not isinstance(b,int)for b in bits)or len(set(bits))!=width*size:
                raise ValueError('A production register-array row was lost or aliased')
            geometry[prefix]=dict(width=width,size=size)
    else:
        geometry=sorted((int(c['parameters']['WIDTH'],2),int(c['parameters']['SIZE'],2))for c in top['cells'].values()if c['type']=='$mem_v2')
        if geometry!=[(257,64),(276,32)]:raise ValueError('A production FIFO was resized')
    checked={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command'];timeout=int(command[command.index('--timeout')+1])
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',str(timeout),'-t',str(depth),
            '-m','board1_thin_ddr_app_transport','--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw',
            '--dump-vcd',label+'-%.vcd','--dummy',label+'.responses','--noprogress','--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('Solver command adds a constraint or changes the scope')
        log=(run/(label+'.log')).read_bytes();query=run/(label+'.smt2');responses=run/(label+'.responses')
        if sha(log)!=row['log_sha256']or sha(query.read_bytes())!=row['query_sha256']or sha(responses.read_bytes())!=row['solver_responses_sha256']:
            raise ValueError('Solver log/query/response record changed')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Traffic witness changed')
        if mutant:
            if (not row['passed']or row['exit']!=1 or row['status']!=['FAILED']or
                    b'BMC failed!'not in log or b'Assert failed in'not in log or
                    not any(n.endswith('.yw')for n in row['traces'])or
                    not any(n.endswith('.vcd')for n in row['traces'])):
                raise ValueError('A semantic transport mutation lacks a real solver counterexample')
            generated=queries.reproduce_query(run,label,row,True,work/(label+'-query-binding'))
            checked[label]=dict(counterexample=True,directed_negative_probe=True,query_binding=generated)
            continue
        if not row['passed']:
            if solver!='cvc5'or phase=='bmc'or row['status']or b'timeout'not in log:
                raise ValueError('Required primary safety/coverage result is incomplete')
            checked[label]=dict(proved=False,timeout_retained=True);continue
        if row['exit']!=0 or re.findall(rb'Status: (\w+)',log)!=[b'PASSED']:
            raise ValueError('A completed solver result is not a pass')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded transport result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=3:raise ValueError('Missing transport traffic goals')
        generated=queries.reproduce_query(run,label,row,False,work/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
        checked[label]=dict(proved=True,query_binding=generated)
    if mutant and(not fin['passed']or not fin['mutation_detected']):
        raise ValueError('Mutant receipt does not record the expected failure')
    return dict(run=run.name,variant=variant,mutant=mutant,primary_unbounded_parent_proof=not bool(mutant),
        proved_parent_and_range_assertions=count if not mutant else 0,
        checked_assertion_cells=count,discharged_internal_fifo_invariants=52,
        premise_proofs=origins,source_logic_unchanged=True,external_protocol_assumptions=[],
        directed_negative_probe=bool(mutant),both_solvers_detect_mutant=bool(mutant),
        internal_rtl_cuts=[],memory_geometry=geometry,real_results=checked,
        secondary_unbounded_result=False if mutant else fin['results']['cvc5-induction']['passed'],
        primary_three_goals_reached=not bool(mutant),inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),
        emitted_smt_sha256=sha((run/'design.smt2').read_bytes()))


def main():
    common=load('run_handoff')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--legacy',action='store_true',help='Audit the earlier 51-obligation compositions')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    # Independently recheck the premise ledger and its source/real-solver
    # evidence once for this complete composition audit. No solver rerun.
    premise_out=out/'fifo-premise-recheck'
    cmd=[sys.executable,'-I','-S','-B',str(HERE/'audit_fifo.py'),'--include-protected',
        '--package',str(args.package.resolve()),'--out',str(premise_out)]
    with(out/'fifo-premise-audit.log').open('w')as log:
        cp=subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,timeout=240)
    if cp.returncode:raise ValueError('Independent FIFO premise audit failed')
    fresh=json.loads((premise_out/'FINISHED.json').read_bytes())
    selected={'baseline':'transport-baseline-r2-compositional',
        'kv-protected':'transport-kv-protected-r1-compositional',
        'encrypted-memory':'transport-encrypted-memory-r1-compositional'}if args.legacy else{
        'baseline':'transport-baseline-r3-fields','kv-protected':'transport-kv-protected-r2-fields',
        'encrypted-memory':'transport-encrypted-memory-r2-fields'}
    records=[inspect(HERE/'runs'/name,variant,args.package,fresh,out/name,legacy=args.legacy)for variant,name in selected.items()]
    if not args.legacy:
        mutants={'transport-baseline-mutant-operation-r2-directed':'invert-physical-operation',
            'transport-baseline-mutant-address-r2-directed':'flip-physical-address-bit',
            'transport-baseline-mutant-write-data-r2-directed':'flip-physical-write-data-bit'}
        records += [inspect(HERE/'runs'/name,'baseline',args.package,fresh,out/name,
            expected_mutant=mutant)for name,mutant in mutants.items()]
    _,baseline_root,base=common.binding(args.package,'baseline')
    _,seeded_root,seeded=common.binding(args.package,'seeded-sampling')
    if any((baseline_root/'project'/n).read_bytes()!=(seeded_root/'project'/n).read_bytes()for n in ('fifo.sv','thin_transport.sv')):
        raise ValueError('Seeded transport is not byte-identical to the proved baseline composition')
    result=dict(schema='current-native-compositional-transport-source-audit-v1',passed=True,runs=records,
        seeded_identical_transport_join=seeded,component_premise_audit_sha256=sha((premise_out/'FINISHED.json').read_bytes()),
        boot_runtime_policy_join_proved=False,vendor_controller_or_physical_cdc_proved=False,
        whole_machine_theorem=False,source_to_bitstream_equivalence=False,hardware_access=False,
        solver_replay=False,checker_sha256=sha(Path(__file__).read_bytes()))
    (out/'FINISHED.json').write_bytes(encode(result))
    print(f'TRANSPORT AUDIT PASS: 3 actual compositions + seeded source join; {51 if args.legacy else 56} new assertions each; 52 independently discharged FIFO premises each; {0 if args.legacy else 3} semantic mutants')


if __name__=='__main__':main()
