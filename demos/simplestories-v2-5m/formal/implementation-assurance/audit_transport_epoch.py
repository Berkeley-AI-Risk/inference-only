"""Close source contracts through the native full-size DDR transport.

Recheck assumption-free FIFO/source/reset premises, exact native connections,
the instrumented production bodies, compiler output and real solver queries.
No new solver run or hardware access is performed by this auditor.
"""
import argparse
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_epoch_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def norm(text):return re.sub(r'\s+','',text)


def encrypted_cover_supplement(run,work):
    query=load('audit_fifo');sha=query.sha
    evidence=HERE/'audit-probes/transport-epoch-encrypted-coverage-r2'
    raw=(evidence/'FINISHED.json').read_bytes();record=json.loads(raw)
    inp=json.loads((run/'INPUTS.json').read_bytes())
    if (record['proof_run']!=run.name or record['inputs_sha256']!=sha((run/'INPUTS.json').read_bytes())or
        record['emitted_smt_sha256']!=sha((run/'design.smt2').read_bytes())):
        raise ValueError('Separate encrypted coverage source or constraints changed')
    constraints=(run/'reset.smtc').read_text()+load('run_transport_epoch_cover').stimulus()
    if ((evidence/'cover-constraints.smtc').read_text()!=constraints or
        record['used_cover_constraints_sha256']!=sha(constraints.encode())or
        record['checker_sha256']!=sha((evidence/'checker.py').read_bytes())):
        raise ValueError('Separate encrypted reachability constraints changed')
    checked={}
    for solver,row in record['results'].items():
        log=(evidence/(solver+'.log')).read_bytes();responses=evidence/(solver+'.responses');command=row['command']
        timeout=command[command.index('--timeout')+1]
        recorded_directory=Path(command[command.index('--dump-smt2')+1]).parent
        if (not recorded_directory.is_absolute()or
            recorded_directory.parts[-2:]!=('audit-probes','transport-epoch-encrypted-coverage-r2')):
            raise ValueError('Separate coverage recorded path has an unexpected logical identity')
        wanted=['yosys-smtbmc','-s',solver,'--unroll','--timeout',timeout,'-t','80',
            '-m',inp['top'],'--smtc',str(recorded_directory/'cover-constraints.smtc'),'--presat','-c','--noprogress',
            '--dump-smt2',str(recorded_directory/(solver+'.smt2')),'--dummy',str(recorded_directory/(solver+'.responses')),'design.smt2']
        if command!=wanted or sha(log)!=row['log_sha256']or sha((evidence/(solver+'.smt2')).read_bytes())!=row['query_sha256']or sha(responses.read_bytes())!=row['real_solver_responses_sha256']:
            raise ValueError('Separate coverage real query, replies or command changed')
        if not row['passed']:
            if solver=='cvc5'and b'timeout'in log:
                checked[solver]=dict(proved=False,original_secondary_timeout_retained=True);continue
            if (solver=='cvc5'and row['exit']==1 and not responses.read_bytes()and
                b'Traceback (most recent call last):'in log and
                (b'IndexError: string index out of range'in log or b'BrokenPipeError: [Errno 32] Broken pipe'in log)and
                b'Assert failed in'not in log):
                checked[solver]=dict(proved=False,original_secondary_tool_error_retained=True,
                    error='SMTBMC/cvc5 backend failed before completing coverage; no secondary conclusion credited')
                continue
            raise ValueError('Required primary encrypted coverage incomplete')
        if row['exit']!=0 or re.findall(rb'Status: (\w+)',log)!=[b'PASSED']or len(re.findall(rb'Reached cover statement',log))!=4:
            raise ValueError('Missing encrypted physical/runtime reachability goal')
        relocated=dict(row,command=list(command))
        relocated['command'][command.index('--smtc')+1]=str(evidence/'cover-constraints.smtc')
        rebound=query.reproduce_query(run,solver+'-cover',relocated,False,work/(solver+'-separate-cover-query-binding'),
            actual_path=evidence/(solver+'.smt2'),recorded_replies=responses)
        checked[solver]=dict(four_goals_reached=True,query_binding=rebound)
    if not checked.get('z3',{}).get('four_goals_reached'):raise ValueError('No source-bound encrypted primary coverage')
    return dict(evidence_sha256=sha(raw),real_results=checked,no_register_value_export=True,
        original_timeout_retained=True,safety_proof_assumptions_added=False,
        helper_end_hash_not_used_as_executed_source_identity=True,
        only_hash_checked_constraint_path_relocated_for_query_reproduction=True,
        actual_constraints_commands_and_real_solver_queries_reconstructed=True)


def contract_join(run,variant,package,source,reset,top):
    common,runner,model,memory=map(load,('run_handoff','run_transport_epoch','control_model','run_memory_path'))
    pin,root,bound=common.binding(package,variant)
    source_variant='baseline'if variant=='seeded-sampling'else variant
    row=next(r for r in source['runs']if r['variant']==source_variant and r['kind']=='memory'and not r['mutant'])
    if (row['assertions']!=113 or row['assumptions'] or not row['both_solver_unbounded_safety']or
        not row['unconditional_lock_requires_source_reset_read_and_response']):
        raise ValueError('A source premise is incomplete or assumes a transport guarantee')
    if reset['native_joins'][variant]!=bound or not reset['both_solver_unbounded_safety']or reset['assumptions']:
        raise ValueError('Reset epoch substitution lacks an unconditional native proof')
    native_top=(root/'project/top.sv').read_text()
    _,mb=model.instance(native_top,memory.top_module((root/'project/booted_memory.sv').read_bytes()),'u_memory')
    _,tb=model.instance(native_top,runner.TOP,'u_transport')
    links={'app_cmd_o':'core_cmd_i','app_cmd_en_o':'core_cmd_en_i','app_addr_o':'core_addr_i',
        'app_rd_data_valid_i':'core_rd_valid_o'}
    if any(mb[a]!=tb[b]for a,b in links.items()):raise ValueError('Source contract signal substitution changed')
    if mb['app_clk_i']!=tb['core_clk_i']or mb['app_clk_i']!='core_clk':raise ValueError('Source history clock differs')
    if top['variants'][variant]['binding']!=bound:raise ValueError('Elaborated native wiring belongs to another image')
    proof=HERE/'runs'/row['run']
    a=(proof/'parent-monitor.inc.sv').read_text()
    b=(run/'parent-epoch.inc.sv').read_text()
    a1="if(f_path_read_seen_q&&app_cmd_en_o&&app_cmd_o==0)assert(app_addr_o[21:3]>=19'd227072&&app_addr_o[21:3]<19'd"+str(pin['kv_limit'])+");"
    b1="if(core_reset_n&&f_source_read_seen_q&&core_cmd_en_i&&core_cmd_i==0)assume(core_addr_i[21:3]>=19'd227072&&core_addr_i[21:3]<19'd"+str(pin['kv_limit'])+");"
    a2='always_combif(private_model_locked_o)assert(app_domain_reset_n&&f_path_read_seen_q&&f_path_return_seen_q);'
    b2='if(f_formal_runtime_locked_i)assume(core_reset_n&&f_source_read_seen_q&&f_source_return_seen_q);'
    # The complete source auditor reconstructs every monitor and production
    # body. These explicit statements pin the two contracted conclusions.
    complete=a
    if a1 not in norm(a)or b1 not in norm(b)or a2 not in norm(complete)or b2 not in norm(b):
        raise ValueError('A transport assumption differs from the proved source contract')
    histories=[
        ('if(app_cmd_en_o&&app_cmd_o==1)f_path_read_seen_q<=1;',
         'if(core_cmd_en_i&&core_cmd_i==1)f_source_read_seen_q<=1;'),
        ('if(app_rd_data_valid_i)f_path_return_seen_q<=1;',
         'if(core_rd_valid_o)f_source_return_seen_q<=1;')]
    if any(x not in norm(a)or y not in norm(b)for x,y in histories):
        raise ValueError('Source/transport observational histories differ')
    if ('always_ff@(posedgeapp_clk_iornegedgeapp_domain_reset_n)'not in norm(a)or
        'always_ff@(posedgecore_clk_iornegedgecore_reset_n)'not in norm(b)):
        raise ValueError('History clock/reset substitution changed')
    target="if((f_runtime_observed_q||f_formal_runtime_locked_i)&&app_cmd_en_o&&app_cmd_o==0)assert(app_addr_o[21:3]>=19'd227072&&app_addr_o[21:3]<19'd"+str(pin['kv_limit'])+");"
    if target not in norm(b):raise ValueError('Final physical write-address theorem was omitted')
    return dict(source_run=row['run'],source_assertions=113,source_assumptions=0,
        source_inputs_sha256=row['inputs_sha256'],source_finished_sha256=row['finished_sha256'],
        source_to_transport_signals=links,history_clock='core_clk',
        history_resets_equal_by_native_reset_proof=True,
        transport_epoch_cannot_reset_after_lock_without_actual_common_hard_reset=True,
        runtime_lock_observation_maps_to_memory_output=mb['private_model_locked_o'],
        source_guarantees_assumed=2,unproved_client_promises=0,
        source_proof_independent_of_transport_guarantees=True,
        theorem='After runtime LOCK, physical command writes target K/V until the actual common hard reset.')


def inspect(run,variant,package,fresh,work,*,mutant=None):
    common,runner,transport,fifo,query=map(load,('run_handoff','run_transport_epoch','run_transport','run_fifo','audit_fifo'))
    sha=query.sha
    inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
    inp,fin=json.loads(inp_raw),json.loads(fin_raw)
    if fin['inputs_sha256']!=sha(inp_raw)or inp['mutant']!=mutant or fin['mutant']!=mutant:
        raise ValueError('Epoch proof input or mutation receipt changed')
    if (inp['assertion_cells']!=105 or inp['assumption_cells']!=54 or inp['cover_cells']!=4 or
        inp['observer_constants']!=2 or inp['internal_cuts']or inp['changed_production_parameters']or not inp['multiclock']):
        raise ValueError('Epoch proof obligations, native geometry or scope changed')
    if fin['binding']!=inp['binding']or fin['assertion_cells']!=105 or fin['internal_cuts']:
        raise ValueError('Epoch result scope differs from its input receipt')
    if bool(inp['binding'].get('directed_negative_probe'))!=bool(mutant):raise ValueError('Directed positive safety proof')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A real solver phase was omitted')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Proof input changed: '+name)
    pin,root,bound=common.binding(package,variant)
    if any(inp['binding'].get(k)!=v for k,v in bound.items()):raise ValueError('Native source/image binding changed')
    fifo_raw=(root/'project/fifo.sv').read_bytes();parent_raw=(root/'project/thin_transport.sv').read_bytes()
    if (run/'production-fifo.sv').read_bytes()!=fifo_raw or(run/'production-transport.sv').read_bytes()!=parent_raw:
        raise ValueError('Native production source differs from the proved transport')
    old=json.loads((run/'discharged-fifo-lemma-audit.json').read_bytes())
    old_rows={r['run']:r for r in old['runs']};new_rows={r['run']:r for r in fresh['fifo']['runs']}
    if not old['passed']or old['current_native_source_and_image_joins']!=fresh['fifo']['current_native_source_and_image_joins']:
        raise ValueError('FIFO premise ledger source/image join changed')
    for name,row in old_rows.items():
        for field in ('inputs_sha256','finished_sha256','emitted_smt_sha256','primary_unbounded_safety','assertions','assumptions','internal_cuts'):
            if row[field]!=new_rows[name][field]:raise ValueError('Independent FIFO premise check disagrees')
    template=(HERE/'fifo-monitor.inc.sv').read_text()
    origins=transport.verify_fifo_lemma_inputs(old,variant,fifo_raw,parent_raw,template,common)
    if inp['binding']['fifo_lemma_origins']!=origins:raise ValueError('FIFO invariant discharge changed')
    expected_lemmas=('\n'.join(s for s in template.splitlines()if not s.strip().startswith('cover('))+'\n').replace('assert(','assume(')
    policy=transport.render_policy_monitor(pin['kv_limit'])
    epoch=(HERE/'transport-epoch-fifo-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    parent=transport.render_parent_monitor(pin['kv_limit'],field_identity=True)
    parent_epoch=(HERE/'transport-epoch-parent-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    snippets={'fifo-lemmas.inc.sv':expected_lemmas,'fifo-policy.inc.sv':policy,
        'fifo-epoch.inc.sv':epoch,'parent-monitor.inc.sv':parent,'parent-epoch.inc.sv':parent_epoch}
    if any((run/n).read_text()!=text for n,text in snippets.items()):raise ValueError('A monitor or assumption changed')
    rebuilt,module=runner.instrument(fifo_raw,parent_raw,expected_lemmas+policy,epoch,parent,parent_epoch,mutant=bool(mutant))
    if any((run/n).read_bytes()!=raw for n,raw in rebuilt.items()):
        raise ValueError('Production bodies differ beyond declared observers/view rename/mutation')
    source_raw,reset_raw,origin=runner.source_guarantees(package,variant,common)
    if ((run/'discharged-source-audit.json').read_bytes()!=source_raw or
        (run/'discharged-reset-audit.json').read_bytes()!=reset_raw or inp['binding']['source_guarantee_origin']!=origin):
        raise ValueError('Source or reset contract discharge changed')
    for old_record,kind in [(json.loads(source_raw),'source'),(json.loads(reset_raw),'reset')]:
        if kind=='source':
            for row in old_record['runs']:
                new=next(r for r in fresh[kind]['runs']if r['run']==row['run'])
                if row!=new:raise ValueError('Fresh source-path audit disagrees')
        elif any(old_record[k]!=fresh[kind][k]for k in ('inputs_sha256','finished_sha256','emitted_smt_sha256','native_joins')):
            raise ValueError('Fresh reset proof audit disagrees')
    joined=contract_join(run,variant,package,fresh['source'],fresh['reset'],fresh['top'])
    reset='initial\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\nstate 1\nassume (= [core_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
    if mutant:reset+=runner.cover_stimulus(80,negative=True)
    compact=bool(inp['binding'].get('compact_cover'))
    cover=runner.cover_stimulus(80,negative=True)if compact else runner.cover_stimulus()
    if (run/'reset.smtc').read_text()!=reset or(run/'cover.smtc').read_text()!=reset+cover:
        raise ValueError('Safety or coverage input constraints changed')
    recipe='\n'.join(['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer fifo-view.sv transport.sv',
        'prep -top '+runner.TOP+' -flatten','clk2fflogic','chformal -lower','opt_clean','dffunmap',
        'select -assert-count 105 t:$assert','select -assert-count 4 t:$cover','select -assert-count 54 t:$assume',
        'select -assert-none t:$anyseq','select -assert-count 2 t:$anyconst','check -assert',
        'write_json elaborated.json','write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if (run/'prove.ys').read_text()!=recipe or inp['compile_sources']!=['fifo-view.sv','transport.sv']:
        raise ValueError('Compiler recipe differs from the declared native composition')
    for tool,row in inp['tools'].items():
        if sha(Path(shutil.which(tool)).read_bytes())!=row['sha256']:raise ValueError('Exact compiler/query tool changed')
    work.mkdir()
    for name in inp['files']:(work/name).write_bytes((run/name).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(run/n).read_bytes()for n in ('design.smt2','elaborated.json')):
        raise ValueError('Native compiler output does not reproduce')
    top=json.loads((work/'elaborated.json').read_bytes())['modules'][runner.TOP]
    kinds=[c['type']for c in top['cells'].values()];block=module.endswith('_block')
    if any(kinds.count(k)!=v for k,v in {'$assert':105,'$assume':54,'$cover':4,'$anyconst':2,'$anyseq':0,'$mem_v2':0 if block else 2}.items()):
        raise ValueError('Elaborated formal cell inventory changed')
    geometry=[('u_commands',276,32),('u_returns',257,64)]
    if block:
        for name,width,size in geometry:
            rows=[top['netnames'].get(name+'.memory_q['+str(i)+']',{}).get('bits',[])for i in range(size)]
            bits=[b for row in rows for b in row]
            if any(len(r)!=width for r in rows)or any(not isinstance(b,int)for b in bits)or len(set(bits))!=width*size:
                raise ValueError('A full-width production register memory row was lost')
    elif sorted((int(c['parameters']['WIDTH'],2),int(c['parameters']['SIZE'],2))for c in top['cells'].values()if c['type']=='$mem_v2')!=[(257,64),(276,32)]:
        raise ValueError('A native FIFO was resized')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A real solver phase was omitted')
    checked={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command'];timeout=command[command.index('--timeout')+1]
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',timeout,'-t',str(depth),'-m',runner.TOP,
            '--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd',
            '--dummy',label+'.responses','--noprogress','--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','cover.smtc'if phase=='cover'else'reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('Solver command changes the theorem or adds constraints')
        log=(run/(label+'.log')).read_bytes();responses=run/(label+'.responses')
        if sha(log)!=row['log_sha256']or sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']or sha(responses.read_bytes())!=row['solver_responses_sha256']:
            raise ValueError('Real solver query/log/responses changed')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Real trace changed')
        if not row['passed']:
            if not mutant and variant=='encrypted-memory'and label=='z3-cover'and not row['status']and b'timeout'in log:
                checked[label]=encrypted_cover_supplement(run,work);continue
            if (not mutant and variant=='encrypted-memory'and label=='cvc5-cover'and
                not row['status']and row['exit']==1 and b'Traceback (most recent call last):'in log and
                b'IndexError: string index out of range'in log and not row['traces']and
                not responses.read_bytes()and b'Assert failed in'not in log):
                checked[label]=dict(proved=False,original_secondary_tool_error_retained=True,
                    error='SMTBMC failed while parsing a cvc5 model response; no completed coverage conclusion')
                continue
            if solver!='cvc5'or (phase=='bmc'and not mutant)or row['status']or b'timeout'not in log:
                raise ValueError('A required proof or semantic control is incomplete')
            checked[label]=dict(proved=False,original_secondary_timeout_retained=True);continue
        status=b'FAILED'if mutant else b'PASSED'
        if row['exit']!=(1 if mutant else 0)or re.findall(rb'Status: (\w+)',log)!=[status]:raise ValueError('Unexpected real solver conclusion')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded epoch result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=4:raise ValueError('Missing physical/runtime reachability goal')
        if mutant and(b'BMC failed!'not in log or b'Assert failed in'not in log or not row['traces']):raise ValueError('No real semantic counterexample')
        rebound=query.reproduce_query(run,label,row,bool(mutant),work/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
        checked[label]=dict(real_solver_status=status.decode(),query_binding=rebound)
    return dict(run=run.name,variant=variant,mutant=mutant,assertions=105,assumptions=54,
        primary_unbounded_safety=not bool(mutant),secondary_unbounded_safety=not mutant and fin['results']['cvc5-induction']['passed'],
        physical_write_epoch_composed=not bool(mutant),primary_semantic_counterexample=bool(mutant),full_native_geometry=geometry,
        internal_rtl_cuts=[],unproved_external_protocol_assumptions=[],fifo_premise_origins=origins,
        contract_substitution=joined,real_results=checked,inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),
        emitted_smt_sha256=sha((run/'design.smt2').read_bytes()))


def verify_reused_premise(kind,record,script,package):
    common,query=load('run_handoff'),load('audit_fifo');sha=query.sha
    if not record['passed']or record['checker_sha256']!=sha((HERE/script).read_bytes()):
        raise ValueError('Cached premise auditor differs from the current completed checker')
    if kind=='top':
        for variant,row in record['variants'].items():
            _,root,bound=common.binding(package,variant)
            if row['binding']!=bound or row['native_top_sha256']!=sha((root/'project/top.sv').read_bytes()):
                raise ValueError('Cached native top wiring changed')
        return
    rows=record['runs']if kind!='reset'else[dict(record,run='reset-correspondence-r1')]
    for row in rows:
        run=HERE/'runs'/row['run'];inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
        if (sha(inp_raw)!=row['inputs_sha256']or sha(fin_raw)!=row['finished_sha256']or
            sha((run/'design.smt2').read_bytes())!=row['emitted_smt_sha256']):raise ValueError('Cached premise proof identity changed')
        inp,fin=json.loads(inp_raw),json.loads(fin_raw)
        for name,r in inp['files'].items():
            raw=(run/name).read_bytes()
            if len(raw)!=r['bytes']or sha(raw)!=r['sha256']:raise ValueError('Cached premise input changed')
        for tool,r in inp['tools'].items():
            if sha(Path(shutil.which(tool)).read_bytes())!=r['sha256']:raise ValueError('Cached premise tool changed')
        for label,r in fin['results'].items():
            for suffix,field in [('log','log_sha256'),('smt2','query_sha256'),('responses','solver_responses_sha256')]:
                if r.get(field)and sha((run/(label+'.'+suffix)).read_bytes())!=r[field]:
                    raise ValueError('Cached premise real solver evidence changed')
            for name,digest in r.get('traces',{}).items():
                if sha((run/name).read_bytes())!=digest:raise ValueError('Cached premise witness changed')


def main():
    common,query=load('run_handoff'),load('audit_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--reuse-premises-from',type=Path,help='Reuse completed premise audits only after checking current source/tool/raw proof byte identities')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    fresh={}
    for kind,script,extra in [('fifo','audit_fifo.py',['--include-protected']),
        ('source','audit_boot_path.py',['--complete-source-contracts']),
        ('reset','audit_reset_correspondence.py',[]),('top','check_top_connections.py',[])]:
        target=out/(kind+'-premise-recheck')
        command=[sys.executable,'-I','-S','-B',str(HERE/script),'--package',str(args.package.resolve()),'--out',str(target)]+extra
        if args.reuse_premises_from:
            original=args.reuse_premises_from.resolve()/(kind+'-premise-recheck')
            record=json.loads((original/'FINISHED.json').read_bytes())
            verify_reused_premise(kind,record,script,args.package)
            shutil.copytree(original,target,copy_function=os.link)
            (out/(kind+'-audit-reused.json')).write_bytes(query.encode(dict(
                original=str(original),finished_sha256=query.sha((original/'FINISHED.json').read_bytes()),
                current_proof_source_tool_and_raw_solver_bytes_rechecked=True,
                compiler_and_query_generation_not_repeated=True)))
        else:
            with(out/(kind+'-audit.log')).open('w')as log:
                cp=subprocess.run(command,stdout=log,stderr=subprocess.STDOUT,timeout=300)
            if cp.returncode:raise ValueError('Independent premise check failed: '+kind)
        fresh[kind]=json.loads((target/'FINISHED.json').read_bytes())
        if not fresh[kind]['passed']:raise ValueError('Incomplete premise check: '+kind)
    selected={'baseline':'transport-epoch-baseline-r3-exact-kv-prefix',
        'kv-protected':'transport-epoch-kv-protected-r1-exact-kv-prefix',
        'encrypted-memory':'transport-epoch-encrypted-memory-r2-compact-cover'}
    records=[inspect(HERE/'runs'/name,variant,args.package,fresh,out/name)for variant,name in selected.items()]
    negative='transport-epoch-baseline-mutant-model-redirect-r1'
    records.append(inspect(HERE/'runs'/negative,'baseline',args.package,fresh,out/negative,mutant='redirect-physical-writes-to-model'))
    _,base,_=common.binding(args.package,'baseline');_,seed,seeded=common.binding(args.package,'seeded-sampling')
    if any((base/'project'/n).read_bytes()!=(seed/'project'/n).read_bytes()for n in ('fifo.sv','thin_transport.sv')):
        raise ValueError('Seeded transport differs from the proved baseline bodies')
    join=contract_join(HERE/'runs'/selected['baseline'],'seeded-sampling',args.package,fresh['source'],fresh['reset'],fresh['top'])
    result=dict(schema='current-native-physical-write-epoch-composition-audit-v1',passed=True,runs=records,
        seeded_identical_transport_join=seeded,seeded_contract_substitution=join,
        actual_source_to_physical_write_epoch_composed=True,unproved_client_protocol_promises=0,
        independently_discharged_fifo_invariants_per_transport=52,discharged_source_contracts_per_transport=2,
        cyclic_assume_guarantee_dependencies=False,whole_machine_theorem=False,
        premise_audits_reused_with_exact_current_byte_rechecks=bool(args.reuse_premises_from),
        vendor_persistence_read_order_or_physical_cdc_proved=False,sha_or_ciphertext_authentication_proved=False,
        source_to_bitstream_equivalence=False,hardware_access=False,solver_replay=False,
        checker_sha256=query.sha(Path(__file__).read_bytes()))
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());(out/'FINISHED.json').write_bytes(query.encode(result))
    print('PHYSICAL WRITE EPOCH AUDIT PASS: 3 native transports + seeded join; 105 assertions each; all 54 internal premises discharged')


if __name__=='__main__':main()
