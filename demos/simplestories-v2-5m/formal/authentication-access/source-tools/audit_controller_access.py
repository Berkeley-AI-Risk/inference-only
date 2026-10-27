"""Audit actual scheduler, operand routing and six-layer schedule evidence."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    s=importlib.util.spec_from_file_location('_controller_access_audit_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    checked=load('checked',HERE/'audit_service_digest.py');common=load('common',OLD/'run_handoff.py')
    observer=load('observer',OLD/'audit_boot_boundary.py');queries=load('queries',OLD/'audit_fifo.py')
    dp=load('dp',HERE/'run_datapath_access.py')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False);records=[]
    for kind,name in(('datapath','datapath-access-r3'),('sequence','semantic-schedule-r3')):
        root,inputs,result=checked.checked_run(name);joins={}
        relative=dp.REL if kind=='datapath'else dp.REL.replace('datapath.sv','sequence.sv')
        production_name='production-'+kind+'.sv'
        for variant in('baseline','kv-protected','encrypted-memory','seeded-sampling'):
            _,native,bound=common.binding(args.package,variant)
            if (native/relative).read_bytes()!=(root/production_name).read_bytes():
                raise ValueError('Actual controller differs in '+variant)
            joins[variant]=dict(image_sha256=bound['image_sha256'],source_path=relative,
                source_sha256=sha((native/relative).read_bytes()),native_inventory_sha256=bound['native_inventory_sha256'])
        monitor=(root/'monitor.inc.sv').read_text();observer.observer_writes_only(monitor)
        if kind=='datapath':
            expected,binding,cuts,_=dp.derive(args.package,'kv-protected')
            if cuts!=inputs['internal_cuts']or binding!=inputs['binding']:raise ValueError('Whole-child boundary inventory differs')
            for n in inputs['compile_sources']:
                if (root/n).read_bytes()!=expected[n]:raise ValueError('Native datapath source projection changed')
            if len({c['instance']for c in cuts})!=17 or any(c['assumptions']for c in cuts):
                raise ValueError('A complete child output or promise changed')
        else:
            original=(root/production_name).read_bytes();expected=b'`undef FORMAL\n'+original.replace(
                b'\nendmodule',b'\n'+monitor.encode()+b'\nendmodule',1)
            if (root/'sequence.sv').read_bytes()!=expected or inputs['internal_cuts']:
                raise ValueError('Native sequence reversal failed')
        if (root/'reset.smtc').read_text()!='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n':
            raise ValueError('An input protocol condition entered positive safety')
        if inputs['assumption_cells']or inputs['observer_constants']or inputs['changed_production_parameters']:
            raise ValueError('An assumption, observation selector or native geometry change entered the proof')
        module=json.loads((root/'elaborated.json').read_text())['modules'][inputs['top']]
        types=[c['type']for c in module['cells'].values()]
        if any(t in types for t in('$assume','$anyseq','$anyconst')):
            raise ValueError('Unreported assumption or arbitrary state')
        if kind=='datapath'and len(module['ports']['private_word_req_index_o']['bits'])!=19:
            raise ValueError('Native memory address width changed')
        work=out/kind;work.mkdir()
        for n in inputs['files']:
            p=work/n;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Controller model does not reproduce')
        if set(result['results'])!={s+'-'+p for s in('z3','cvc5')for p in('bmc','induction','cover')}:
            raise ValueError('A required solver phase is absent')
        phases={}
        for label,row in result['results'].items():
            if not row['passed']or row['exit']!=0 or row['status']!=['PASSED']:
                raise ValueError('Controller obligation incomplete')
            phases[label]=queries.reproduce_query(root,label,row,False,work/(label+'-query-binding'),
                recorded_replies=root/(label+'.responses'),keep_trace_outputs=label.endswith('cover'))
        records.append(dict(kind=kind,run=name,assertions=inputs['assertion_cells'],native_joins=joins,
            both_solver_satisfiable_base_unbounded_induction_and_covers=True,source_reversal=True,
            exact_reelaboration=True,exact_query_regeneration=phases,private_caller_and_child_assumptions=[],
            finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    controls=[]
    for positive,negative,file,before,after in(
        ('datapath-access-r3','datapath-access-mutant-head-r1','datapath.sv',
         b"wire [3:0] projection_job = projection_is_head ? 4'd7 :",b"wire [3:0] projection_job = projection_is_head ? 4'd6 :"),
        ('semantic-schedule-r3','semantic-schedule-mutant-skip-stage-r2','sequence.sv',
         b"stage_q <= stage_q + 1'b1;",b"stage_q <= stage_q + 2'd2;")):
        root,inputs,result=checked.checked_run(negative);base=HERE/'runs'/positive
        for n in inputs['compile_sources']:
            raw=(base/n).read_bytes()
            if n==file:
                if raw.count(before)!=1:raise ValueError('Native control mutation site changed')
                raw=raw.replace(before,after,1)
            if (root/n).read_bytes()!=raw:raise ValueError('Sensitivity changes more than one native expression')
        phases={};unresolved=[]
        for label,row in result['results'].items():
            if row['passed']and row['exit']==1 and row['status']==['FAILED']and row['traces']:
                log=(root/(label+'.log')).read_text()
                assertions=re.findall(r'Checking assertions in step (\d+)',log)
                assumptions=re.findall(r'Checking assumptions in step (\d+)',log)
                if not assertions or assertions!=assumptions:raise ValueError('Negative query satisfiability checks differ')
                # Only a negative witness may skip earlier safety questions.
                # Bind the entire generated transition/input prefix through
                # the first real failure, excluding later model-print queries.
                # Count actual checked steps, not the final step number.
                core=queries.core_query;limit=2*len(assertions)
                queries.core_query=lambda raw,ignored=None:core(raw,limit)
                try:
                    phases[label]=queries.reproduce_query(root,label,row,True,out/(negative+'-'+label+'-query-binding'),
                        recorded_replies=root/(label+'.responses'))
                finally:queries.core_query=core
            else:unresolved.append(label)
        if 'z3-bmc'not in phases:raise ValueError('No actual reset-reachable semantic counterexample')
        controls.append(dict(run=negative,actual_BMC_counterexamples=phases,unresolved_phases_not_credited=unresolved,
            finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    receipt=dict(schema='native-six-layer-and-datapath-access-audit-v1',passed=True,runs=records,semantic_controls=controls,
        native_hardware_modified=False,fixed_stage_layer_job_and_operand_muxes_proved=True,
        guarded_vector_writes_and_model_read_owner_routing_proved=True,
        scope='Source-bound controller/access facts for all four images. Complete numerical-child outputs remain unrestricted in the datapath model; the sequence has no cuts. No arithmetic correctness, complete RAM data provenance, public-interface composition, physical memory integrity or general training-capacity theorem is established by this component alone.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'CONTROLLER-ACCESS-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,components=2,variants=4)))


if __name__=='__main__':main()
