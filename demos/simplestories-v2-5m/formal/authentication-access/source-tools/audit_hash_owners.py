"""Audit stream/caller and bank/compressor source joins and selected proof phases.

Original aggregate receipts are retained, including unsuccessful secondary cover
searches. A safety theorem requires a satisfiable reset base and a completed
induction on that same model, not every cover search to finish on both solvers.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
PREFIX=b'`undef FORMAL\n'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_owner_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def module(raw,name):
    start=raw.index(('module '+name+' ').encode())
    end=raw.index(b'\nendmodule',start)+len(b'\nendmodule')
    return raw[start:end]


def verify_run(name,assumptions=0,constants=0):
    root=HERE/'runs'/name;raw=(root/'INPUTS.json').read_bytes()
    inputs=json.loads(raw);result=json.loads((root/'FINISHED.json').read_bytes())
    if result['inputs_sha256']!=sha(raw):raise ValueError('Input/result join changed')
    for n,row in inputs['files'].items():
        data=(root/n).read_bytes()
        if row!={'bytes':len(data),'sha256':sha(data)}:raise ValueError('Changed input: '+n)
    if inputs['changed_production_parameters']or inputs['internal_cuts']or result['internal_cuts']:
        raise ValueError('Native geometry or no-cut policy changed')
    graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
    cells=list(graph['cells'].values())
    for typ,count in(('$assume',assumptions),('$anyconst',constants),('$anyseq',0),
        ('$assert',inputs['assertion_cells']),('$cover',inputs['cover_cells'])):
        if sum(c['type']==typ for c in cells)!=count:raise ValueError('Property/cut inventory changed: '+typ)
    if inputs['assumption_cells']!=assumptions:raise ValueError('Assumption inventory changed')
    required={s+'-'+p for s in('z3','cvc5')for p in('bmc','induction')}
    required.add('z3-cover')
    for phase,row in result['results'].items():
        for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
            if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Solver evidence changed')
        for fn,digest in row['traces'].items():
            if sha((root/fn).read_bytes())!=digest:raise ValueError('Trace changed')
        if phase in required:
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0 or row['timed_out']:
                raise ValueError('Required phase incomplete: '+name+' '+phase)
            log=(root/(phase+'.log')).read_text()
            if phase.endswith('induction'):
                if 'Temporal induction successful.'not in log or '--smtc'in row['command']:
                    raise ValueError('Induction evidence/constraint policy changed')
            if phase.endswith('bmc')and '--presat'not in row['command']:
                raise ValueError('Reset base satisfiability check missing')
    record=dict(run=name,inputs_sha256=sha(raw),finished_sha256=sha((root/'FINISHED.json').read_bytes()),
        model_sha256=sha((root/'design.smt2').read_bytes()),assertions=inputs['assertion_cells'],
        both_solver_base_and_induction_passed=True,z3_all_component_covers_passed=True,
        secondary_cover_passed=result['results']['cvc5-cover']['passed'],
        original_aggregate_passed=result['passed'],no_internal_data_cuts=True)
    return root,inputs,result,graph,record


def top_frames(path):
    names={};scope=[];values={}
    for line in path.read_text().splitlines():
        parts=line.split()
        if parts and parts[0]=='$scope':scope.append(parts[2])
        elif parts and parts[0]=='$upscope':scope.pop()
        elif parts and parts[0]=='$var'and len(scope)==1:names[parts[3]]=parts[4]
        elif line.startswith('#'):
            if values:yield dict(values)
        elif line.startswith('b'):
            bits,ident=line[1:].split()
            if ident in names and set(bits)<=set('01'):values[names[ident]]=int(bits,2)
    if values:yield dict(values)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args();common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    native={};joins={}
    for variant in('baseline','seeded-sampling','kv-protected','encrypted-memory'):
        _,directory,binding=common.binding(args.package,variant)
        native[variant]={n:(directory/('project/'+n)).read_bytes()for n in('sha.sv','bank.sv')}
        joins[variant]=dict(image_sha256=binding['image_sha256'],
            sources={n:sha(data)for n,data in native[variant].items()})
    root,inputs,result,graph,stream=verify_run('sha-stream-chain-r3',assumptions=1)
    monitor=(root/'monitor.inc.sv').read_bytes();source=(root/'sha.sv').read_bytes()
    if not source.startswith(PREFIX)or source.count(b'\n'+monitor)!=1:
        raise ValueError('Stream observer insertion changed')
    production=(root/'production-sha.sv').read_bytes()
    if source[len(PREFIX):].replace(b'\n'+monitor,b'',1)!=production:
        raise ValueError('Stream observer reversal failed')
    for variant in('baseline','seeded-sampling','kv-protected'):
        raw=native[variant]
        for name in('board1_sha256_compact_padded_stream','board1_sha256_compact_compress'):
            if module(raw['sha.sv'],name)!=module(production,name):raise ValueError('Stream/child identity differs: '+variant)
    # Discharge the stream's one-BEGIN premise in every actual caller, with
    # the exact production clock/reset and BEGIN wires rather than labels alone.
    once=json.loads((HERE/'IMAGE-AUTH-ONCE-AUDIT.json').read_bytes())
    if not once['passed']or not once['one_BEGIN_per_reset_epoch_proved']:
        raise ValueError('Caller premise is not discharged')
    caller_records=[]
    for row in once['runs']:
        caller=HERE/'runs'/row['run']
        if sha((caller/'FINISHED.json').read_bytes())!=row['finished_sha256']:
            raise ValueError('Caller premise receipt changed')
        raw=(caller/'production-auth.sv').read_bytes()
        for port in(b'.clk_i(trusted_clk_i)',b'.reset_n_i(trusted_reset_n_i)',b'.begin_i(sha_begin)'):
            if raw.count(port)!=1:raise ValueError('Actual caller/stream join changed')
        for variant in row['variants']:
            if (caller/'production-sha.sv').read_bytes()!=native[variant]['sha.sv']:
                raise ValueError('Caller library/source association changed')
        caller_records.append(dict(run=row['run'],variants=row['variants'],one_begin_premise_discharged=True))
    compact=json.loads((HERE/'SHA-COMPACT-AUDIT.json').read_bytes())
    if not compact['passed']or not compact['cvc5_unbounded_induction_passed']:
        raise ValueError('Compressor arithmetic theorem is missing')
    valid=[]
    for path in sorted(root.glob('z3-cover-*.vcd')):
        valid.extend(f['digest_o']for f in top_frames(path)if f.get('digest_valid_o')==1)
    if not valid or any(v!=int(hashlib.sha256(b'abc').hexdigest(),16)for v in valid):
        raise ValueError('Complete stream ABC witness missing or incorrect')
    stream.update(one_begin_premise_discharged_in_actual_callers=True,
        fixed_padding_and_native_byte_count_proved_in_callers=True,
        compact_compression_arithmetic_independently_proved=True,
        completed_abc_message_witness=True,exact_stream_and_child_source_identity_variants=['baseline','seeded-sampling','kv-protected'])
    encrypted_root,encrypted_inputs,encrypted_result,encrypted_graph,encrypted_stream=verify_run('sha-stream-encrypted-r1',assumptions=1)
    encrypted_source=(encrypted_root/'sha.sv').read_bytes();encrypted_monitor=(encrypted_root/'monitor.inc.sv').read_bytes()
    encrypted_native=native['encrypted-memory']['sha.sv']
    if not encrypted_source.startswith(PREFIX)or encrypted_source.count(b'\n'+encrypted_monitor)!=1 or encrypted_source[len(PREFIX):].replace(b'\n'+encrypted_monitor,b'',1)!=encrypted_native:
        raise ValueError('Encrypted stream source reversal failed')
    held=json.loads((HERE/'SHA-HELD-AUDIT.json').read_bytes())
    if not held['passed']or held['library_sha256']!=sha(encrypted_native):raise ValueError('Actual encrypted compressor theorem missing')
    for property_text in('assert(f_child_owned_q);','assert(block_buffer_q==f_child_block_q);','assert(compress_state_q==f_child_chain_q);'):
        if encrypted_monitor.decode().count(property_text)!=1:raise ValueError('Encrypted actual owner premise is missing')
    valid=[]
    for path in sorted(encrypted_root.glob('z3-cover-*.vcd')):
        valid.extend(f['digest_o']for f in top_frames(path)if f.get('digest_valid_o')==1)
    if not valid or any(v!=int(hashlib.sha256(b'abc').hexdigest(),16)for v in valid):raise ValueError('Complete encrypted stream ABC witness missing or incorrect')
    encrypted_stream.update(variants=['encrypted-memory'],one_begin_premise_discharged_in_actual_caller=True,
        actual_owner_block_and_chain_preservation_proved=True,owner_held_compression_arithmetic_independently_proved=True,
        fixed_padding_and_native_byte_count_proved_in_caller=True,completed_abc_message_witness=True)
    banks=[]
    for variant,name,constants in(('baseline','bank-full-baseline-r3',1),('kv-protected','bank-full-protected-r3',1)):
        root,inputs,result,graph,record=verify_run(name,constants=constants)
        raw=(root/'bank.sv').read_bytes();monitor=(root/'monitor.inc.sv').read_bytes()
        if not raw.startswith(PREFIX)or raw.count(b'\n'+monitor)!=1:
            raise ValueError('Bank observer insertion changed')
        if raw[len(PREFIX):].replace(b'\n'+monitor,b'',1)!=(root/'production-bank.sv').read_bytes():
            raise ValueError('Bank observer reversal failed')
        if (root/'sha.sv').read_bytes()!=PREFIX+(root/'production-sha.sv').read_bytes():
            raise ValueError('Bank SHA child altered')
        group=('baseline','seeded-sampling')if variant=='baseline'else(variant,)
        for v in group:
            for n in('bank.sv','sha.sv'):
                if (root/('production-'+n)).read_bytes()!=native[v][n]:raise ValueError('Bank native source identity differs')
        # Preserve the entire physical page storage in the proof model.
        memories=[c for c in graph['cells'].values()if c['type']=='$mem_v2']
        if len(memories)!=1:raise ValueError('Native page RAM inventory changed')
        params=memories[0]['parameters']
        if int(params['WIDTH'],2)!=256 or int(params['SIZE'],2)!=128:
            raise ValueError('Native page RAM dimensions changed')
        record.update(variants=group,actual_sha_chain_preserved_through_return=True,
            actual_sha_child_and_full_page_ram_retained=True,
            existing_sealed_copy_lifecycle_included=constants==1,
            expected_digest_selection_in_parent_proved=False,
            page_to_service_consumer_composition_proved=False)
        if not inputs['binding']['all_64_data_blocks_and_one_padding_block_sequence_checked']:
            raise ValueError('Complete block sequencing invariant missing')
        lifecycle=(common.model_package(args.package)/'formal/current-seeded-page-bank/bank_monitor.inc.sv').read_bytes()
        if (root/'lifecycle-original.inc.sv').read_bytes()!=lifecycle:raise ValueError('Sealed-copy observer provenance changed')
        record.update(sealed_copy_lifecycle_included=True,all_64_data_blocks_and_one_padding_block_checked=True)
        banks.append(record)
    negatives=[]
    for name in('bank-mutant-digest-r1','bank-mutant-fill-r1'):
        root=HERE/'runs'/name;negative=json.loads((root/'FINISHED.json').read_bytes())
        if not negative['passed']or not negative['mutation_detected']or not all(row['passed']and row['status']==['FAILED']and row['traces']for row in negative['results'].values()):
            raise ValueError('Semantic data control lacks an actual BMC counterexample')
        negatives.append(dict(run=name,passed=True,result_sha256=sha((root/'FINISHED.json').read_bytes())))
    out=dict(schema='native-hash-caller-and-owner-composition-audit-v1',passed=True,
        streams=[stream,encrypted_stream],caller_premises=caller_records,bank_owners=banks,native_joins=joins,semantic_controls=negatives,
        sha_compact_audit_sha256=sha((HERE/'SHA-COMPACT-AUDIT.json').read_bytes()),
        image_auth_once_audit_sha256=sha((HERE/'IMAGE-AUTH-ONCE-AUDIT.json').read_bytes()),
        encrypted_pool_bank_owner_still_pending=True,
        scope='Source-level stream/caller composition and baseline/seeded plus K/V-protected bank SHA ownership. Native boot success reachability, parent LOCK, fixed page-digest selection, encrypted pool ownership and complete consumer/access composition remain separate obligations. No hash-hardness, bitstream or physical-security theorem.')
    (HERE/'HASH-OWNERS-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n')
    print(json.dumps(out))


if __name__=='__main__':main()
