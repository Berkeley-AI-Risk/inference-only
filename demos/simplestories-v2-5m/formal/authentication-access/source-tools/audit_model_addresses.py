"""Audit native model read addresses, retained children and real solver queries."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent


def load(name,path):
    s=importlib.util.spec_from_file_location('_address_audit_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    generator=load('generator',HERE/'run_model_addresses.py');queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py')
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py');records=[]
    for kind,name in(('group-stream','model-address-group-stream-r4-base-support'),('lookup','model-address-lookup-r2')):
        root,inputs,result=checked.checked_run(name);expected,binding,count,covers=generator.derive(args.package,'kv-protected',kind)
        if binding!=inputs['binding']or count!=inputs['assertion_cells']or covers!=inputs['cover_cells']:
            raise ValueError('Actual generator/module/property inventory changed')
        for n in inputs['compile_sources']:
            if expected[n]!=(root/n).read_bytes():raise ValueError('Native isolated module reversal changed: '+n)
        for n in inputs['files']:
            if n.endswith('.inc.sv'):observer.observer_writes_only((root/n).read_text())
        joins={}
        for variant in('baseline','kv-protected','encrypted-memory','seeded-sampling'):
            _,directory,bound=common.binding(args.package,variant)
            for module,row in binding['isolated_native_modules'].items():
                raw=(directory/row['native_path']).read_bytes()
                if sha(raw)!=row['source_sha256']or raw!=(root/('production-'+module+'.sv')).read_bytes():
                    raise ValueError('Native dependency differs in '+variant)
            joins[variant]=dict(image_sha256=bound['image_sha256'],native_inventory_sha256=bound['native_inventory_sha256'])
        if inputs['internal_cuts']or inputs['assumption_cells']or inputs['observer_constants']or inputs['changed_production_parameters']:
            raise ValueError('Native address theorem gained a cut, promise or dimension change')
        if (root/'reset.smtc').read_text()!='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n':
            raise ValueError('Positive caller/response inputs were restricted')
        if kind=='group-stream'and not inputs['literal_roms_mapped']:
            raise ValueError('Constant job/geometry tables must retain their exact initialization in induction')
        work=out/kind;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Address model does not reproduce')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
        types=[c['type']for c in graph['cells'].values()]
        if any(t in types for t in('$assume','$anyseq','$anyconst'))or len(graph['ports']['private_word_req_index_o']['bits'])!=19:
            raise ValueError('Unexpected assumption/arbitrary state/native address width')
        phases={}
        for label,row in result['results'].items():
            if not row['passed']or row['exit']!=0 or row['status']!=['PASSED']:raise ValueError('Unresolved address obligation')
            phases[label]=queries.reproduce_query(root,label,row,False,work/(label+'-query-binding'),
                recorded_replies=root/(label+'.responses'),keep_trace_outputs=label.endswith('cover'))
        if len(phases)!=6:raise ValueError('Both solver phases required')
        records.append(dict(run=name,kind=kind,assertions=count,retained_native_modules=list(binding['isolated_native_modules']),
            native_joins=joins,source_reversal=True,exact_reelaboration=True,both_solver_base_induction_and_covers=True,
            exact_query_regeneration=phases,finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    controls=[]
    for positive,negative in(('model-address-group-stream-r4-base-support','model-address-group-stream-mutant-base-r1'),
            ('model-address-lookup-r2','model-address-lookup-mutant-index-r1')):
        root,inputs,result=checked.checked_run(negative);kind=inputs['binding']['kind']
        expected,_,_,_=generator.derive(args.package,'kv-protected',kind,True)
        for n in inputs['compile_sources']:
            if (root/n).read_bytes()!=expected[n]:raise ValueError('Sensitivity changes beyond its one native address expression')
        phases={}
        for label,row in result['results'].items():
            if not row['passed']or row['exit']!=1 or row['status']!=['FAILED']or not row['traces']:
                raise ValueError('Native address sensitivity lacks both real bounded counterexamples')
            steps=re.findall(r'Checking assertions in step (\d+)',(root/(label+'.log')).read_text())
            core=queries.core_query;limit=2*len(steps)
            queries.core_query=lambda raw,ignored=None:core(raw,limit)
            try:phases[label]=queries.reproduce_query(root,label,row,True,out/(negative+'-'+label+'-query-binding'),
                    recorded_replies=root/(label+'.responses'))
            finally:queries.core_query=core
        controls.append(dict(run=negative,both_solver_real_counterexamples=True,exact_query_regeneration=phases))
    receipt=dict(schema='native-model-read-address-provenance-audit-v1',passed=True,runs=records,semantic_controls=controls,
        no_child_reply_or_arithmetic_cuts=True,private_descriptors_and_external_word_replies_unrestricted=True,
        scope='Actual fixed group/metadata and semantic lookup model-address generators for all four images. All reachable reader/adapter/FIFO children retained. Fixed named regions, descriptor ownership and selected lookup reply lane are proved. Public descriptor ownership and authenticated service-to-consumer data come from their separate components; no numerical transformer or bitstream theorem.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'MODEL-ADDRESS-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,components=2,variants=4)))


if __name__=='__main__':main()
