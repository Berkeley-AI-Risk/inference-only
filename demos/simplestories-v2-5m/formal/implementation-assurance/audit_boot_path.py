"""Audit outer boot and complete source-side memory-path RTL proofs.

Recovers every retained production source, checks the four declared auth cuts,
re-elaborates the full model, and regenerates real solver queries. Original
secondary timeouts remain explicit; recorded replies establish no new theorem.
"""
import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_path_audit_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def inspect(run,variant,kind,package,work,mutant=None):
    common,boundary,wrapper,memory,query,observer=map(load,
        ('run_handoff','run_boot_boundary','run_boot_wrapper','run_memory_path','audit_fifo','audit_boot_boundary'))
    sha=query.sha;inp_raw=(run/'INPUTS.json').read_bytes();fin_raw=(run/'FINISHED.json').read_bytes()
    inp,fin=json.loads(inp_raw),json.loads(fin_raw)
    complete=bool(inp['binding'].get('complete_source_contract'))
    count,covers=(80,3)if kind=='wrapper'else(113 if complete else 112,4)
    if fin['inputs_sha256']!=sha(inp_raw)or inp['mutant']!=mutant or fin['mutant']!=mutant:
        raise ValueError('Source-path proof receipt changed')
    if (inp['assertion_cells']!=count or inp['cover_cells']!=covers or inp['assumption_cells']!=0 or
        inp['observer_constants']!=0 or inp['changed_production_parameters']or not inp['multiclock']):
        raise ValueError('Source-path assertion, dimension or assumption scope changed')
    if fin['binding']!=inp['binding']or fin['internal_cuts']!=inp['internal_cuts']or fin['assertion_cells']!=count:
        raise ValueError('Source-path result differs from its input scope')
    for name,row in inp['files'].items():
        raw=(run/name).read_bytes()
        if len(raw)!=row['bytes']or sha(raw)!=row['sha256']:raise ValueError('Frozen proof member changed: '+name)
    pin,root,bound=common.binding(package,variant)
    if any(inp['binding'].get(k)!=v for k,v in bound.items())or inp['binding']['variant']!=variant:
        raise ValueError('Current native/image association changed')
    paths=dict(boundary.SOURCES,**{'wrapper.sv':wrapper.WRAPPER,'async-fifo.sv':'project/fifo.sv'})
    if kind=='memory':paths.update({'handoff.sv':'project/handoff.sv','memory.sv':'project/booted_memory.sv'})
    original={n:(root/p).read_bytes()for n,p in paths.items()}
    if inp['binding']['production_sources']!={n:dict(path=paths[n],sha256=sha(r))for n,r in original.items()}:
        raise ValueError('Production source map changed')
    for name,raw in original.items():
        if(run/('production-'+name)).read_bytes()!=raw:raise ValueError('Native production source changed')
    auth=(root/wrapper.AUTH).read_bytes()
    if(run/'production-auth.sv').read_bytes()!=auth or inp['binding']['authentication_source_sha256']!=sha(auth):
        raise ValueError('Authenticator source provenance changed')
    cuts=[dict(r,instance=('u_boot.'if kind=='memory'else'')+'u_sole_readback_auth',
        replacement='unrestricted module input '+r['input'])for r in wrapper.AUTH_CUTS]
    if inp['internal_cuts']!=cuts or inp['binding']['authenticator_outputs_arbitrary']!=cuts:
        raise ValueError('The four unrestricted scalar authentication outputs changed')
    boot=wrapper.multiclock_boot_monitor((HERE/'boot-order-monitor.inc.sv').read_text())
    bmon=(HERE/'boot-boundary-monitor.inc.sv').read_text();wmon=(HERE/'boot-wrapper-monitor.inc.sv').read_text()
    monitors={'boot-monitor.inc.sv':boot,'boundary-monitor.inc.sv':bmon,'wrapper-monitor.inc.sv':wmon}
    native=dict(original)
    if mutant:
        if kind!='wrapper':raise ValueError('Unreviewed memory-path mutation')
        before,after=wrapper.MUTATIONS[mutant];native['wrapper.sv']=boundary.once(native['wrapper.sv'].decode(),before,after).encode()
    if kind=='wrapper':
        expected,auth_instance=wrapper.instrument(native,boot,bmon,wmon)
        top=wrapper.TOP;source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv','async-fifo.sv','wrapper.sv']
    else:
        hmon=(HERE/'handoff-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
        pmon=(HERE/'memory-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
        if complete:pmon+='\n'+(HERE/'memory-source-contract.inc.sv').read_text()
        monitors.update({'handoff-monitor.inc.sv':hmon,'parent-monitor.inc.sv':pmon})
        expected,auth_instance=memory.instrument(native,boot,bmon,wmon,hmon,pmon)
        top=memory.top_module(original['memory.sv']);source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv','async-fifo.sv','wrapper.sv','handoff.sv','memory.sv']
    for name,text in monitors.items():
        if(run/name).read_text()!=text:raise ValueError('Target/support monitor changed: '+name)
        observer.observer_writes_only(text)
    if any((run/n).read_bytes()!=raw for n,raw in expected.items()):raise ValueError('Observer/cut reversal does not recover actual production logic')
    if(run/'cut-auth-instance.sv.txt').read_text()!=auth_instance:raise ValueError('Removed auth instance differs from native source')
    if inp['top']!=top or inp['compile_sources']!=source_list:raise ValueError('Compiled source graph/top changed')
    recipe='\n'.join(['read_verilog -formal -sv -nosynthesis -D SYNTHESIS -defer '+' '.join(source_list),
        'prep -top '+top+' -flatten','clk2fflogic','chformal -lower','opt_clean','dffunmap',
        f'select -assert-count {count} t:$assert',f'select -assert-count {covers} t:$cover',
        'select -assert-none t:$assume','select -assert-none t:$anyseq','select -assert-count 0 t:$anyconst',
        'check -assert','write_json elaborated.json','write_rtlil elaborated.il','write_smt2 -wires design.smt2'])+'\n'
    if(run/'prove.ys').read_text()!=recipe:raise ValueError('Compiler recipe added a restriction or changed semantics')
    reset='initial\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\n'
    if mutant:reset+=wrapper.cover_stimulus(mutant=mutant)
    if(run/'reset.smtc').read_text()!=reset:raise ValueError('A positive safety input or negative stimulus was changed')
    if not mutant:
        cover=reset+(wrapper.cover_stimulus()if kind=='wrapper'else memory.cover_stimulus())
        if(run/'cover.smtc').read_text()!=cover:raise ValueError('Declared COVER-only stimulus changed')
    labels={s+'-'+p for s in ('z3','cvc5')for p in (('bmc',)if mutant else('bmc','induction','cover'))}
    if set(fin['results'])!=labels:raise ValueError('A real solver phase was omitted')
    for name,row in inp['tools'].items():
        if sha(Path(shutil.which(name)).read_bytes())!=row['sha256']:raise ValueError('Exact compiler/query tool changed')
    work.mkdir()
    for name in inp['files']:(work/name).write_bytes((run/name).read_bytes())
    with(work/'re-elaboration.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    if cp.returncode or any((work/n).read_bytes()!=(run/n).read_bytes()for n in ('design.smt2','elaborated.json')):
        raise ValueError('Full source-path compiler output does not reproduce')
    design=json.loads((work/'elaborated.json').read_bytes())['modules'][top];kinds=[c['type']for c in design['cells'].values()]
    if any(kinds.count(k)!=v for k,v in {'$assert':count,'$cover':covers,'$assume':0,'$anyseq':0,'$anyconst':0,'$mem_v2':0}.items()):
        raise ValueError('Elaborated source-path proof scope changed')
    prefix=('u_boot.'if kind=='memory'else'')+'u_locked_boundary.u_request_fifo.';bits=[]
    for field,width in [('write_q',1),('addr_q',19),('data_q',256)]:
        for slot in range(2):
            row=design['netnames'].get(prefix+field+'['+str(slot)+']',{}).get('bits',[])
            if len(row)!=width or not all(isinstance(b,int)for b in row):raise ValueError('Native full-width FIFO2 geometry was lost')
            bits+=row
    if len(set(bits))!=552:raise ValueError('Native FIFO2 fields were aliased')
    results={}
    for label,row in fin['results'].items():
        solver,phase=label.split('-',1);command=row['command'];timeout=command[command.index('--timeout')+1]
        depth=inp['induction_depth']if phase=='induction'else inp['cover_depth']if phase=='cover'else inp['base_depth']
        wanted=['yosys-smtbmc','-s',solver,'--timeout',timeout,'-t',str(depth),'-m',top,
            '--dump-smt2',label+'.smt2','--dump-yw',label+'-%.yw','--dump-vcd',label+'-%.vcd',
            '--dummy',label+'.responses','--noprogress','--unroll']
        wanted+=['-i']if phase=='induction'else['--smtc','cover.smtc'if phase=='cover'else'reset.smtc','--presat']
        if phase=='cover':wanted+=['-c']
        wanted+=['design.smt2']
        if command!=wanted:raise ValueError('Solver/constraint mode changed')
        log=(run/(label+'.log')).read_bytes();responses=run/(label+'.responses')
        if sha(log)!=row['log_sha256']or sha((run/(label+'.smt2')).read_bytes())!=row['query_sha256']or sha(responses.read_bytes())!=row['solver_responses_sha256']:
            raise ValueError('Real solver log/query/replies changed')
        for name,digest in row['traces'].items():
            if sha((run/name).read_bytes())!=digest:raise ValueError('Real witness changed')
        if not row['passed']:
            if mutant!='bypass-physical-suppression'or solver!='cvc5'or row['status']or b'timeout'not in log:
                raise ValueError('A required source-path result is incomplete')
            results[label]=dict(proved=False,original_secondary_search_timeout_retained=True);continue
        status=b'FAILED'if mutant else b'PASSED'
        if row['exit']!=(1 if mutant else 0)or re.findall(rb'Status: (\w+)',log)!=[status]:raise ValueError('Unexpected real solver conclusion')
        if phase=='induction'and b'Temporal induction successful.'not in log:raise ValueError('No unbounded result')
        if phase=='cover'and len(re.findall(rb'Reached cover statement',log))!=covers:raise ValueError('Missing early legal-write reachability')
        if mutant and(b'BMC failed!'not in log or b'Assert failed in'not in log or not row['traces']):raise ValueError('No semantic mutation counterexample')
        rebound=query.reproduce_query(run,label,row,bool(mutant),work/(label+'-query-binding'),
            recorded_replies=responses if phase=='cover'else None,keep_trace_outputs=phase=='cover')
        results[label]=dict(real_solver_status=status.decode(),query_binding=rebound)
    if not mutant and not fin['passed']:raise ValueError('Selected positive source-path campaign is incomplete')
    return dict(run=run.name,variant=variant,kind=kind,mutant=mutant,assertions=count,assumptions=0,
        declared_authenticator_output_cuts=cuts,full_production_logic_recovered=True,observer_feedback_into_production=False,
        full_queue_register_bits=552,unconsumed_readback_auth_payload_optimized_out=True,
        both_solver_unbounded_safety=not bool(mutant),primary_semantic_mutant_detected=bool(mutant),
        source_model_write_prefix_proved=not bool(mutant),lock_requires_prior_output_read_and_input_response=not bool(mutant),
        unconditional_lock_requires_source_reset_read_and_response=kind=='memory'and complete and not mutant,
        real_results=results,inputs_sha256=sha(inp_raw),finished_sha256=sha(fin_raw),emitted_smt_sha256=sha((run/'design.smt2').read_bytes()))


def main():
    common,query=load('run_handoff'),load('audit_fifo')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    parser.add_argument('--complete-source-contracts',action='store_true')
    args=parser.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    cases=[
        ('boot-wrapper-baseline-r4-directed-cover','baseline','wrapper',None),
        ('boot-wrapper-kv-protected-r1','kv-protected','wrapper',None),
        ('boot-wrapper-encrypted-memory-r2','encrypted-memory','wrapper',None),
        ('memory-path-baseline-r3-source-contract'if args.complete_source_contracts else'memory-path-baseline-r2-reset-correspondence','baseline','memory',None),
        ('memory-path-kv-protected-r2-source-contract'if args.complete_source_contracts else'memory-path-kv-protected-r1','kv-protected','memory',None),
        ('memory-path-encrypted-memory-r3-source-contract'if args.complete_source_contracts else'memory-path-encrypted-memory-r2-native-top','encrypted-memory','memory',None),
        ('boot-wrapper-baseline-mutant-suppression-r1','baseline','wrapper','bypass-physical-suppression'),
        ('boot-wrapper-baseline-mutant-early-digest-r1','baseline','wrapper','trust-early-digest-lock')]
    records=[inspect(HERE/'runs'/name,variant,kind,args.package,out/name,mutant)for name,variant,kind,mutant in cases]
    _,base,_=common.binding(args.package,'baseline');_,seed,seed_binding=common.binding(args.package,'seeded-sampling')
    names=set(load('run_boot_boundary').SOURCES.values())|{load('run_boot_wrapper').WRAPPER,load('run_boot_wrapper').AUTH,'project/fifo.sv','project/booted_memory.sv','project/handoff.sv'}
    if any((base/n).read_bytes()!=(seed/n).read_bytes()for n in names):raise ValueError('Seeded memory path differs from the proved baseline source')
    result=dict(schema='current-native-source-memory-path-audit-v1',passed=True,runs=records,
        complete_source_contracts=args.complete_source_contracts,
        seeded_identical_source_join=seed_binding,checker_sha256=query.sha(Path(__file__).read_bytes()),
        final_async_ddr_transport_composed=False,source_to_bitstream_equivalence=False,
        sha_or_ciphertext_authentication_proved=False,whole_machine_theorem=False,hardware_access=False,solver_replay=False)
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_bytes(query.encode(result));print('BOOT/MEMORY PATH AUDIT PASS: 6 actual positive compositions, 2 primary mutants, seeded native join; final DDR transport remains separate')


if __name__=='__main__':main()
