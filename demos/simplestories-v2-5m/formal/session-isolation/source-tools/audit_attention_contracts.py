"""Audit actual attention interfaces against independently checked contracts.

This source/receipt checker is not a new whole-subsystem solver invocation.
It verifies the caller conclusions, child proof identities, full parent state
coverage, every production port and the explicit temporal composition premises.
"""
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE, load
from run_attention_relational import CONTROL, COUPLING
from run_interface_corollaries import deflate
from run_memory_isolation import SPECS
from audit_proof_instantiations import body
from join_parent_conclusions import query_templates


CONTRACTS={
    'u_score_lane':'stateless-unified-modes-r1','u_value_lane':'stateless-unified-modes-r1',
    'u_accumulator_bram':'accumulator-clear-r1','u_norm_stage':'concrete-norm-candidate-clear-r3',
    'u_value_prefix':'prefix-session-valid-r1','u_query_bram':'query-clear-r1',
    'u_output_bram':'native-leaf-clear-r1-output','u_workspace_bram':'native-leaf-clear-r1-workspace',
    'u_align8':'concrete-align8-clear-r1','u_shift':'scalar-attention-shift-valid-r1',
    'u_exp_lut':'exp-session-valid-r1','u_divider':'scalar-attention-divider-valid-r1',
}
CLASSES={
    'baseline':('attention-all-inputs-baseline-r1','attention-clear-baseline-r2','attention-interface-baseline-r1','attention-ownership-clear-baseline-r1','native-hierarchy-r1'),
    'kv-protected':('attention-all-inputs-protected-r1','attention-clear-kv-protected-r2','attention-interface-protected-r1','attention-ownership-clear-kv-protected-r1','native-hierarchy-kv-protected-r1'),
}


def check_interface(new,old,derived):
    d=json.loads((derived/'FINISHED.json').read_text())
    fresh=json.loads((new/'INPUTS.json').read_text());prior=json.loads((old/'INPUTS.json').read_text())
    if not d['interface_corollaries_passed']or not d['no_new_interface_assertion_is_a_premise']:
        raise ValueError('Interface derivations incomplete')
    if d['source_input_sha256']!=sha((new/'INPUTS.json').read_bytes())or d['original_input_sha256']!=sha((old/'INPUTS.json').read_bytes()):
        raise ValueError('Wrong projected source')
    for p,h in d['source_files'].items():
        if sha(Path(p).read_bytes())!=h:raise ValueError('Frozen source changed')
    for n in ('attention.sv','wrapper.sv'):
        if deflate((new/n).read_bytes(),n)!=(old/n).read_bytes():raise ValueError('Driving change in observation projection')
    cert_raw=(derived/'rechecked-parent-certificate.json').read_bytes();cert=json.loads(cert_raw)
    if sha(cert_raw)!=d['original_certificate_sha256']or not cert['conditional_parent_proof_passed']:
        raise ValueError('Parent certificate changed/incomplete')
    # Recheck the selected parent transcripts too. A certificate hash does not
    # authorize trusting missing or subsequently edited raw solver artifacts.
    part_metadata={}
    for row in cert['part_results']:
        part=Path(row['path']);raw=(part/'FINISHED.json').read_bytes()
        if sha(raw)!=row['result_sha256']:raise ValueError('Parent partition receipt changed')
        part_metadata[str(part)]=json.loads(raw)
    for label,evidence in cert['per_conclusion_evidence'].items():
        part=Path(evidence['part']);meta=part_metadata[str(part)];row=meta['results'][label]
        model_path=part/'model.smt2'if meta['state_encoding']=='bitvector'else old/'design.smt2'
        model=model_path.read_bytes()
        if sha(model)!=meta['model_sha256']:raise ValueError('Parent partition model changed')
        expected=query_templates(model.decode(),meta,prior['top'],prior['assertion_cells'])[label]
        query=(part/(label+'.smt2')).read_bytes();reply=(part/(label+'.log')).read_bytes()
        if query!=expected.encode()or sha(query)!=evidence['query_sha256']or sha(reply)!=evidence['reply_sha256']:
            raise ValueError('Parent transcript or proof premises changed')
        if not row['passed']or row['exit']or reply.decode().splitlines()!=['sat','unsat']:
            raise ValueError('Invalid parent conclusion receipt')
    if sha((derived/'model.smt2').read_bytes())!=d['model_sha256']or sha((new/'elaborated.il').read_bytes())!=d['rtlil_sha256']:
        raise ValueError('Encoded model changed')
    top=fresh['top'];oldcount=prior['assertion_cells'];count=fresh['assertion_cells'];model=(derived/'model.smt2').read_text()
    prefix='\n'.join(['(set-logic QF_BV)',model,f'(declare-fun c0 () {top}_s)',
        f'(assert ({top}_h c0))',f'(assert ({top}_u c0))',f'(assert (not ({top}_is c0)))',
        '(assert (and '+' '.join(f'(|{top}_a {i}| c0)'for i in range(oldcount))+'))','(check-sat)'])+'\n'
    if set(d['results'])!={str(i)for i in range(oldcount,count)}:raise ValueError('Missing interface conclusion')
    for i in range(oldcount,count):
        row=d['results'][str(i)];query=(derived/(str(i)+'.smt2')).read_bytes();reply=(derived/(str(i)+'.log')).read_bytes()
        expected=prefix+f'(assert (not (|{top}_a {i}| c0)))\n(check-sat)\n'
        if query!=expected.encode()or sha(query)!=row['query_sha256']or sha(reply)!=row['reply_sha256']:
            raise ValueError('Changed query or premises')
        if not row['passed']or row['exit']or reply.decode().splitlines()!=['sat','unsat']:
            raise ValueError('Missing nonvacuous derivation')
    return fresh,d


def main():
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    package=HERE.parents[1]/'fpga-demo/public-release'
    encoding=json.loads((HERE/'ENCODING-REPLAY.json').read_text())
    if not encoding['exact_encoding_replay_passed']:raise ValueError('Encoding replay incomplete')
    for row in encoding['models'].values():
        if sha(Path(row['original_model']).read_bytes())!=row['exact_model_sha256']:
            raise ValueError('Replayed source model changed')
    encoded_models={row['exact_model_sha256']for row in encoding['models'].values()}
    source_classes={};leaf_records={name:audit(name,'attention child contract')for name in set(CONTRACTS.values())}
    if any(x['status']!='proved_component'for x in leaf_records.values()):raise ValueError('Incomplete child contract')
    for variant,(newname,oldname,derivedname,ownername,censusname)in CLASSES.items():
        new,old,derived=[HERE/'runs'/n for n in (newname,oldname,derivedname)]
        inputs,interfaces=check_interface(new,old,derived)
        if interfaces['model_sha256']not in encoded_models:raise ValueError('Interface model encoding not replayed')
        certificate=json.loads((derived/'rechecked-parent-certificate.json').read_text())
        for part in certificate['part_results']:
            proof=json.loads((Path(part['path'])/'FINISHED.json').read_text())
            if proof['model_sha256']not in encoded_models:raise ValueError('Parent encoding not replayed')
        owner=audit(ownername,'attention parent ownership after CLEAR')
        if owner['status']!='proved_component':raise ValueError('Ownership incomplete')
        ownership=json.loads((HERE/'runs'/ownername/'INPUTS.json').read_text())
        parent=(new/'production-attention.sv').read_bytes()
        if parent!=(HERE/'runs'/ownername/'production-attention.sv').read_bytes():raise ValueError('Caller source classes differ')
        manifest=inputs['binding']['actual_child_input_obligations']
        if set(manifest)!=set(CONTRACTS)or sum(x['generated_instances']for x in manifest.values())!=26:
            raise ValueError('Missing actual child input contract')
        if inputs['binding']['payload_coupling_predicates']!=COUPLING:raise ValueError('Reply condition changed')
        rows={}
        for instance,name in CONTRACTS.items():
            leaf=HERE/'runs'/name;meta=json.loads((leaf/'INPUTS.json').read_text());module=manifest[instance]['module']
            caller=new/('production-child-'+module+'.sv')
            originals=[]
            for filename in meta['files']:
                if filename.endswith('.sv')and(filename.startswith('production')or filename=='rom.sv'):
                    raw=(leaf/filename).read_bytes()
                    if re.search(r'^module '+re.escape(module)+r'\b',raw.decode(),re.M):originals.append(body(raw,module))
            if not originals or any(x!=body(caller.read_bytes(),module)for x in originals):
                raise ValueError('Actual child differs from proved definition: '+instance)
            for port,row in manifest[instance]['inputs'].items():
                if row['kind']not in('common_clock_or_reset','proved_admission_equality'):
                    raise ValueError('Uncovered child input')
            rows[instance]=dict(module=module,proof_run=name,original_module_sha256=sha(originals[0]),
                generated_instances=manifest[instance]['generated_instances'],input_ports=len(manifest[instance]['inputs']),
                proof_input_sha256=leaf_records[name]['input_sha256'])
        census=HERE/'runs'/censusname;graph=json.loads((census/'hierarchy.json').read_text())['modules']
        members=[m for n,m in graph.items()if n=='board1_context2048_attention']
        if len(members)!=1:raise ValueError('Native attention module not unique')
        graph=members[0]
        qbits={bit for cell in graph['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',cell['type'])
               for bit in cell['connections']['Q']if isinstance(bit,int)}
        fields=CONTROL+[('query_buffer_q',1024),('captured_cache_vector_q',1024),('result_buffer_q',1024),('score_key_group_q',128)]
        observed=set()
        for name,width in fields:
            bits=graph['netnames'][name]['bits']
            if len(bits)!=width:raise ValueError('Native parent field width changed')
            observed.update(bit for bit in bits if isinstance(bit,int))
        if qbits!=observed or len(qbits)!=3536:raise ValueError('Unobserved native parent sequential state')
        for v in ([variant,'seeded-sampling']if variant=='baseline'else[variant,'encrypted-memory']):
            _,root,bound=binder.binding(package,v);relative=inputs['binding']['production_path']
            if(root/relative).read_bytes()!=parent:raise ValueError('Parent differs in associated image')
            source_classes[v]=dict(image_sha256=bound['image_sha256'],production_sha256=sha(parent),
                parent_sequential_bits=3536,parent_aligned_ram_geometry=dict(words=8,width=128),
                actual_children=rows,interface_conclusions=146,transported_parent_conclusions=138,
                conditional_parent_inputs_sha256=sha((new/'INPUTS.json').read_bytes()),
                interface_result_sha256=sha((derived/'FINISHED.json').read_bytes()),
                ownership_result_sha256=owner['result_sha256'])
    result=dict(structural_contract_join_checked=True,assembled_subsystem_solver_proof=False,
        whole_device_token_output_theorem=False,session_milestone_complete=False,variants=source_classes,
        exact_encoding_replay_sha256=sha((HERE/'ENCODING-REPLAY.json').read_bytes()),
        temporal_composition_obligations=[
            'Start comparison after common completed CLEAR/drain, with native attention IDLE and healthy sticky accumulator/prefix faults.',
            'Caller ownership at each RAM read plus matching actual writes instantiates the symbolic native-word/read-history lemmas; read-live replies are shared only while owned.',
            'Numerical valid/control replies follow common cancellation and matched admitted operands. Norm-candidate observer cancellation maps to CLEAR, interface loss and new start; fresh matched capture is required before use.',
            'Stateless DSP outputs use matching mode-relevant operands at consumption; native vendor bypass/no-feedback function semantics remain an explicit premise.',
            'Private cache response values, current query inputs, model identity and external controls are matched subsystem inputs. Their enclosing device session correspondence is not discharged here.'
        ],checker_sha256=sha(Path(__file__).read_bytes()))
    (HERE/'ATTENTION-CONTRACT-JOIN.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(structural_contract_join_checked=True,variants=len(source_classes),children_per_variant=26,
        parent_sequential_bits=3536,assembled_subsystem_solver_proof=False,session_milestone_complete=False)))


if __name__=='__main__':main()
