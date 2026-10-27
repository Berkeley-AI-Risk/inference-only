"""Audit native protected K/V header, payload and SHA-owner correspondence."""
import argparse
import hashlib
import importlib.util
import json
import re
from pathlib import Path
import struct
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_kv_hash_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--out',type=Path,required=True);args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    checked=load('checked',HERE/'audit_service_digest.py');common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py')
    queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py');modules=load('modules',HERE/'audit_hash_owners.py')
    compact=json.loads((HERE/'SHA-COMPACT-AUDIT.json').read_bytes());held=json.loads((HERE/'SHA-HELD-AUDIT.json').read_bytes())
    if not compact['passed']or not held['passed']:raise ValueError('Native compressor FIPS correspondence missing')
    domain=struct.pack('>16s',b'IO-KV-ROLE-v2')
    header=struct.pack('>16sQIIIIIII12x',b'IO-KV-ROLE-v2',0,0,0,0,0,1,16,32)
    correct_digest=hashlib.sha256(header+bytes(160)).hexdigest();records=[]
    for variant,name in(('kv-protected','kv-hash-protected-r2-support'),('encrypted-memory','kv-hash-encrypted-r1')):
        root,inputs,result=checked.checked_run(name);_,directory,bound=common.binding(args.package,variant)
        native=(directory/'project/kv_page_hash.sv').read_bytes();library=(directory/'project/sha.sv').read_bytes()
        if native!=(root/'production-kv_page_hash.sv').read_bytes()or library!=(root/'production-sha.sv').read_bytes():
            raise ValueError('Native wrapper/compressor source identity changed')
        monitor=(root/'monitor.inc.sv').read_bytes();source=(root/'kv_page_hash.sv').read_bytes();prefix=b'`undef FORMAL\n'
        # The shared lexical checker otherwise mistakes a relational <= for
        # a nonblocking assignment, and a function-local loop index for a
        # native state variable. Normalize only those analysis spellings;
        # the compiled proof source is unchanged and is reproduced below.
        readonly=monitor.decode().replace('positions_i<=16','positions_i<17')
        start=readonly.index('    function automatic [255:0] f_kv_bytes(')
        end=readonly.index('    endfunction',start)+len('    endfunction')
        readonly=readonly[:start]+re.sub(r'\bj\b','f_local_j',readonly[start:end])+readonly[end:]
        observer.observer_writes_only(readonly)
        if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1 or source[len(prefix):].replace(b'\n'+monitor,b'',1)!=native:
            raise ValueError('Native wrapper observer reversal failed')
        if (root/'sha.sv').read_bytes()!=prefix+library:raise ValueError('Actual SHA was replaced or edited')
        if inputs['assumption_cells']or inputs['observer_constants']or inputs['internal_cuts']or inputs['changed_production_parameters']:
            raise ValueError('A protocol promise, data cut or parameter change was added')
        child='board1_sha256_compact_compress'if variant=='kv-protected'else'board1_sha256_owner_held_kv_compress'
        body=modules.module(library,child)
        expected=compact['native_joins'][variant]['exact_compressor_module_sha256']if variant=='kv-protected'else held['kv_module_sha256']
        if sha(body)!=expected or ('    '+child+' u_sha (').encode()not in native:
            raise ValueError('Exact native FIPS module/instance join differs')
        for connection in(b'.clk_i(clk),.reset_n_i(reset_n && !clear_i),.start_i(sha_start)',
                b'.block_i(sha_block),.state_i(hash_q),.busy_o(sha_busy)',b'.done_o(sha_done),.state_o(sha_state)'):
            if connection not in native:raise ValueError('Native child block/chain/clock join changed')
        if inputs['binding']['reference_domain']!=domain.hex()or inputs['binding']['one_position_zero_payload_cover_digest']!=correct_digest:
            raise ValueError('Independent standard header/hash reference changed')
        if (root/'reset.smtc').read_text()!='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n':
            raise ValueError('A caller condition entered the safety base')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']];cells=list(graph['cells'].values())
        if any(c['type']in('$assume','$anyconst','$anyseq')for c in cells)or sum(c['type']=='$assert'for c in cells)!=monitor.count(b'assert('):
            raise ValueError('Native property/data-cut inventory changed')
        work=out/variant;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Actual native wrapper/child model does not reproduce')
        phases={}
        for phase,row in result['results'].items():
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Required wrapper solver phase incomplete')
            phases[phase]=queries.reproduce_query(root,phase,row,False,work/(phase+'-query-binding'),
                recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))
        records.append(dict(run=name,variant=variant,image_sha256=bound['image_sha256'],assertions=inputs['assertion_cells'],
            exact_native_child=child,exact_child_module_sha256=sha(body),
            both_solver_satisfiable_reset_bases_unbounded_induction_and_complete_correct_digest_cover=True,
            source_reversal=True,exact_model_reelaboration=True,exact_query_regeneration=phases,
            caller_protocol_assumptions=[],private_data_cuts=[],actual_live_chain_owner_premise_discharged=True,
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    positive=HERE/'runs/kv-hash-protected-r2-support';controls=[]
    for role,before,after in(('role',b"31'd0,role_i,",b"31'd0,(role_i^1'b1),"),
            ('byte-order',b'value[8*i +:8]',b'value[255-8*i -:8]')):
        root,inputs,result=checked.checked_run('kv-hash-mutant-'+role+'-r1')
        for n in inputs['compile_sources']:
            wanted=(positive/n).read_bytes()
            if n=='kv_page_hash.sv':
                if wanted.count(before)!=1:raise ValueError('Native sensitivity site changed')
                wanted=wanted.replace(before,after,1)
            if (root/n).read_bytes()!=wanted:raise ValueError('K/V sensitivity edits more than its one native expression')
        for row in result['results'].values():
            if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
                raise ValueError('Native K/V sensitivity lacks real bounded counterexamples')
        controls.append(dict(run=root.name,both_solver_real_BMC_counterexamples=True,finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    identities=[]
    for name,expected in(('kv-header-injectivity-r1',['sat','unsat']),('kv-header-injectivity-mutant-role-r1',['sat','sat'])):
        root=HERE/'runs'/name;result=json.loads((root/'FINISHED.json').read_bytes())
        if not result['passed']or result['domain']!=domain.hex()or result['format']!='>16sQIIIIIII12x':raise ValueError('Identity encoding lemma/reference changed')
        if sha((root/'query.smt2').read_bytes())!=result['query_sha256']or sha((root/'runner.py').read_bytes())!=result['runner_sha256']:
            raise ValueError('Identity lemma query/source changed')
        if any(not r['passed']or r['answers']!=expected or sha((root/(r['solver']+'.log')).read_bytes())!=r['log_sha256']for r in result['results']):
            raise ValueError('Identity lemma/control solver evidence changed')
        identities.append(dict(run=name,both_solver_answers=expected,finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    receipt=dict(schema='native-protected-KV-hash-framing-audit-v1',passed=True,runs=records,semantic_controls=controls,
        identity_encoding_lemma_and_dropped_role_control=identities,
        identity_header_payload_byte_order_odd_even_padding_and_exact_call_count_proved=True,
        native_SHA_FIPS_and_actual_chain_owner_composed=True,caller_protocol_and_digest_oracle_assumptions=[],
        compact_FIPS_audit_sha256=sha((HERE/'SHA-COMPACT-AUDIT.json').read_bytes()),
        held_FIPS_audit_sha256=sha((HERE/'SHA-HELD-AUDIT.json').read_bytes()),
        scope='Actual protected and encrypted K/V hash wrappers with complete native SHA engines. Every accepted job hashes the canonical identity header and accepted payload words with standard byte order, odd/even padding, chaining and final-only digest exposure; live-input owner conditions are proved. Equal canonical identity headers imply equal fields. No cryptographic collision/preimage resistance is claimed. Actual guard trusted-tag/stage/cache/capture use, internal arithmetic, physical faults, bitstream equivalence and whole-device training bounds remain separate obligations.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'KV-HASH-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,variants=2,both_solvers_all_phases=True)))


if __name__=='__main__':main()
