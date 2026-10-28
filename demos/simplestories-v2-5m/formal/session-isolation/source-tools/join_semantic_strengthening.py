"""Check joint induction when two pure auxiliary assertions strengthen a harness.

The hardware, observers, inputs, reset policy and compilation recipe must be
identical after removing exactly the whitelisted two nondriving assertions.
Old successful step implications used FEWER prior-state premises. They remain
valid with the added premises. New checked queries close the old missing steps
and both added auxiliaries. No old complete theorem is assumed, and no current
state corollary is an induction premise. All raw queries are reconstructed.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from join_parent_conclusions import checked_query, query_templates, template_text


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--old-run',type=Path,required=True);ap.add_argument('--old-part',type=Path,required=True)
    ap.add_argument('--new-run',type=Path,required=True);ap.add_argument('--new-part',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    manifest={}
    def pinned(path,digest=None):
        raw=path.read_bytes();actual=sha(raw)
        if digest is not None and actual!=digest:raise ValueError('Changed artifact: '+str(path))
        manifest[str(path.resolve())]=actual;return raw
    (out/'checker.py').write_bytes(Path(__file__).read_bytes());pinned(out/'checker.py')
    dependency=Path(query_templates.__code__.co_filename)
    if dependency!=Path(checked_query.__code__.co_filename)or dependency!=Path(template_text.__code__.co_filename):
        raise ValueError('Query checker dependency identity changed')
    (out/'query_checker.py').write_bytes(dependency.read_bytes());pinned(out/'query_checker.py')
    def inputs(run):
        d=json.loads(pinned(run/'INPUTS.json'))
        for n,row in d['files'].items():
            raw=pinned(run/n,row['sha256'])
            if len(raw)!=row['bytes']:raise ValueError('Input length changed')
        if d['assumption_cells']or d['changed_production_parameters']:raise ValueError('Unexpected assumptions/parameter changes')
        graph=json.loads(pinned(run/'elaborated.json'))
        cells=[c['type']for m in graph['modules'].values()for c in m['cells'].values()]
        if '$assume'in cells or '$anyseq'in cells or cells.count('$assert')!=d['assertion_cells']or cells.count('$anyconst')!=d['observer_constants']:
            raise ValueError('Elaborated assumption/property census differs')
        return d
    old=args.old_run.resolve();new=args.new_run.resolve();oi=inputs(old);ni=inputs(new)
    if oi['top']!=ni['top']or oi['compile_sources']!=ni['compile_sources']:raise ValueError('Different design/compilation inputs')
    top=ni['top']
    if pinned(old/'reset.smtc')!=pinned(new/'reset.smtc'):raise ValueError('Entry policy changed')
    allowed=[('        if(!clear_i && !'+c+'_state_fault_q && '+c+'_state_engine_state_q==6 && ('+
        c+'_state_elem_phase_q==2 || '+c+'_state_elem_phase_q==3))assert('+c+'_state_current_stage_q==13);\n').encode()for c in('a','b')]
    for name in oi['compile_sources']:
        a=pinned(old/name);b=pinned(new/name)
        if name=='wrapper.sv':
            for line in allowed:
                if b.count(line)!=1:raise ValueError('Missing/ambiguous pure auxiliary assertion')
                b=b.replace(line,b'',1)
        if a!=b:raise ValueError('Source projection changed functional RTL or old observers: '+name)
    def recipe(run):
        return re.sub(r'select -assert-count \d+ t:\$assert','select -assert-count PROPERTY_COUNT t:$assert',
            pinned(run/'prove.ys').decode())
    if recipe(old)!=recipe(new):raise ValueError('Compilation semantics changed')
    for key in ('semantics','multiclock','observer_constants','literal_roms_mapped','full_constant_optimization'):
        if oi[key]!=ni[key]:raise ValueError('Model policy differs: '+key)
    if oi['tools']['yosys']['sha256']!=ni['tools']['yosys']['sha256']:raise ValueError('Frontend binary changed')
    for key in ('native_join','per_field_relation','reply_coupling_predicates','actual_child_inputs',
                'observed_native_outputs','unobserved_native_outputs','entry_policy'):
        if oi['binding'][key]!=ni['binding'][key]:raise ValueError('Interface/observation contract changed: '+key)

    def part(run,path,label):
        d=json.loads(pinned(path/'FINISHED.json'))
        if d['source_inputs_sha256']!=sha(pinned(run/'INPUTS.json')):raise ValueError('Wrong source input identity')
        if d['assertion_count']!=json.loads((run/'INPUTS.json').read_text())['assertion_cells']:raise ValueError('Assertion census differs')
        rtl=pinned(run/'elaborated.il',d['rtlil_sha256'])
        model=pinned(path/'model.smt2',d['model_sha256']).decode()
        if d['state_encoding']!='bitvector':raise ValueError('Expected exact finite-state encoding')
        replay=out/(label+'-encoding');replay.mkdir();(replay/'elaborated.il').write_bytes(rtl)
        text=('read_rtlil elaborated.il\n'+('memory_map\ndffunmap\nopt_clean\n'if d['exact_finite_memories_mapped']else'')+
            'write_json encoded.json\nwrite_smt2 -stbv -wires model.smt2\n')
        (replay/'encode.ys').write_text(text)
        with(replay/'yosys.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','encode.ys'],cwd=replay,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        if cp.returncode or sha((replay/'model.smt2').read_bytes())!=d['model_sha256']:raise ValueError('SMT model replay differs')
        pinned(replay/'encode.ys');pinned(replay/'yosys.log');pinned(replay/'model.smt2',d['model_sha256'])
        expected=query_templates(model,d,top,d['assertion_count'],compact=True)
        if d['base_constraint_text']!=(run/'reset.smtc').read_text():raise ValueError('Partition entry constraints changed')
        for name,row in d['results'].items():
            q=checked_query(path/(name+'.smt2'),row)
            if name not in expected or q!=template_text(expected[name]).encode():raise ValueError('Unexpected proof premises: '+name)
            if row.get('query_artifact_format')=='gzip':pinned(path/row['query_artifact'],row['query_artifact_sha256'])
            else:pinned(path/(name+'.smt2'),row['query_sha256'])
            raw=pinned(path/(name+'.log'),row['reply_sha256']);answers=[s for s in raw.decode().splitlines()if s in('sat','unsat','unknown')]
            if row['passed']and(row['exit']!=0 or answers!=['sat','unsat']or b'(error 'in raw):raise ValueError('Invalid successful solver receipt')
        metadata={int(m[1]):m[2]for m in re.finditer(r'^; yosys-smt2-assert (\d+) (.*)$',model,re.M)}
        if set(metadata)!=set(range(d['assertion_count'])):raise ValueError('Incomplete property map')
        return d,metadata
    op,om=part(old,args.old_part.resolve(),'old');np,nm=part(new,args.new_part.resolve(),'new')
    if op['depth']!=np['depth']:raise ValueError('Different induction depths')
    def origin(value):
        cell,src=value.split(' ',1)
        prefix=cell.split('$assert$',1)[0]
        return prefix,src
    old_keys={origin(v):i for i,v in om.items()};new_keys={origin(v):i for i,v in nm.items()}
    if len(old_keys)!=len(om)or len(new_keys)!=len(nm):raise ValueError('Ambiguous source property origin')
    if not set(old_keys).issubset(new_keys):raise ValueError('An old assertion was removed/changed')
    mapping={i:new_keys[key]for key,i in old_keys.items()}
    extras=set(nm)-set(mapping.values())
    if len(extras)!=2 or ni['assertion_cells']!=oi['assertion_cells']+2:raise ValueError('Unexpected strengthening inventory')
    nw=(new/'wrapper.sv').read_text().splitlines(True)
    for i in extras:
        m=re.search(r'wrapper.sv:(\d+)\.',nm[i])
        if m is None or nw[int(m[1])-1].encode()not in allowed:raise ValueError('New property is not a whitelisted auxiliary')
    old_inv=set(op['inductive_conclusions']);new_inv=set(np['inductive_conclusions'])
    if new_inv!={mapping[i]for i in old_inv}|extras:raise ValueError('Induction premise strengthening is not monotone')
    if set(np['corollary_conclusions'])!={mapping[i]for i in op['corollary_conclusions']}:raise ValueError('Corollary policy changed')
    conclusions={};inherited=0
    for i in old_inv:
        label='induction-'+str(i).zfill(3)
        if op['results'].get(label,{}).get('passed'):
            conclusions[mapping[i]]=dict(method='same source step under weaker prior-state premises',part=str(args.old_part.resolve()),label=label)
            inherited+=1
    for i in new_inv:
        label='induction-'+str(i).zfill(3)
        if np['results'].get(label,{}).get('passed'):
            conclusions[i]=dict(method='strengthened prior-state induction step',part=str(args.new_part.resolve()),label=label)
    for i in op['corollary_conclusions']:
        label='corollary-'+str(i).zfill(3)
        if not op['results'].get(label,{}).get('passed'):raise ValueError('Old combinational implication incomplete')
        conclusions[mapping[i]]=dict(method='same current-state implication from the independently closed invariant subset',part=str(args.old_part.resolve()),label=label)
    missing=sorted(set(nm)-set(conclusions))
    if not np['results']['base']['passed']:raise ValueError('New full satisfiable base incomplete')
    result_raw=pinned(new/'FINISHED.json');source_result=json.loads(result_raw);covers={}
    for solver in('z3','cvc5'):
        label=solver+'-cover';row=source_result['results'].get(label,{})
        if row.get('passed'):
            pinned(new/(label+'.log'),row['log_sha256']);pinned(new/(label+'.smt2'),row['query_sha256'])
            if row.get('solver_responses_sha256'):pinned(new/(label+'.responses'),row['solver_responses_sha256'])
            for n,h in row['traces'].items():pinned(new/n,h)
            covers[solver]=ni['cover_cells']
    result=dict(conditional_parent_proof_passed=not missing and bool(covers),assertions=ni['assertion_cells'],
        source_input_sha256=sha((new/'INPUTS.json').read_bytes()),source_result_sha256=sha(result_raw),
        source_projection='Only the two exactly whitelisted pure wrapper assertions were added; every implementation/observer source byte and compilation policy otherwise identical.',
        reused_weaker_premise_steps=inherited,stronger_premise_steps=len(new_inv)-inherited,
        closed_inductive_conclusions=len(new_inv),current_state_corollaries=len(np['corollary_conclusions']),
        no_current_state_corollary_is_an_induction_premise=True,property_projection=mapping,new_auxiliary_indices=sorted(extras),
        missing=missing,per_conclusion_evidence=conclusions,covers=covers,
        complete_backend_lanes={s:all(json.loads((Path(v['part'])/'FINISHED.json').read_text())['solver']==s for v in conclusions.values())
            and bool(covers.get(s))and not missing for s in('z3','cvc5')},
        artifact_manifest=manifest,checker_sha256=sha(Path(__file__).read_bytes()),
        child_contracts_composed=False,whole_device_token_output_theorem=False,
        unobserved_native_outputs=ni['binding']['unobserved_native_outputs'])
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    (out/'CERTIFICATE.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:result[k]for k in('conditional_parent_proof_passed','assertions','reused_weaker_premise_steps','stronger_premise_steps','missing')}))


if __name__=='__main__':main()
