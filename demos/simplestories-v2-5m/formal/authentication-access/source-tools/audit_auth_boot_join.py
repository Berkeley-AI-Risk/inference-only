"""Audit actual authentication-to-LOCK composition and reproduce emitted models."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_joined_boot_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def nonblank(raw):return[b for b in raw.splitlines()if b.strip()]


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    common=load('binding',OLD/'run_handoff.py');builder=load('wrapper',OLD/'run_boot_wrapper.py')
    observer=load('observer',OLD/'audit_boot_boundary.py');queries=load('query',OLD/'audit_fifo.py')
    boundary=builder.load('run_boot_boundary');records=[]
    cases=(('baseline','auth-boot-baseline-r6-release-invariants'),('seeded-sampling','auth-boot-seeded-r1'),
        ('kv-protected','auth-boot-protected-r1'),('encrypted-memory','auth-boot-encrypted-r1'))
    strip_cover=lambda text:re.sub(r'^\s*cover\([^\n]*\);\n','\n',text,flags=re.M)
    remove_checks=lambda text:re.sub(r'assert\([^;]*\);',';',text)
    for variant,name in cases:
        root=HERE/'runs'/name;inputs_raw=(root/'INPUTS.json').read_bytes();inputs=json.loads(inputs_raw)
        finished_raw=(root/'FINISHED.json').read_bytes();result=json.loads(finished_raw)
        if not result['passed']or result['inputs_sha256']!=sha(inputs_raw):raise ValueError('Required composed proof incomplete')
        if inputs['internal_cuts']or inputs['assumption_cells']or inputs['observer_constants']or inputs['changed_production_parameters']or not inputs['multiclock']:
            raise ValueError('Cut/assumption/native geometry/clock policy changed')
        if inputs['binding']['authentication_flags_arbitrary']or not inputs['binding']['complete_actual_image_auth_and_sha']:
            raise ValueError('Actual authenticator was not composed')
        for n,row in inputs['files'].items():
            raw=(root/n).read_bytes()
            if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Changed frozen input: '+n)
        _,directory,bound=common.binding(args.package,variant)
        paths=dict(boundary.SOURCES,**{'wrapper.sv':builder.WRAPPER,'async-fifo.sv':'project/fifo.sv',
            'auth.sv':builder.AUTH,'sha.sv':'project/sha.sv'})
        original={n:(directory/path).read_bytes()for n,path in paths.items()}
        for n,raw in original.items():
            if (root/('production-'+n)).read_bytes()!=raw:raise ValueError('Current native source/image association differs')
        if (root/'sha.sv').read_bytes()!=b'`undef FORMAL\n'+original['sha.sv']:raise ValueError('Actual SHA child was changed')
        # Recover the exact native auth lines, apart from blank lines introduced
        # at observer boundaries. Every native nonblank byte/line is retained.
        auth=(root/'auth.sv').read_bytes().removeprefix(b'`undef FORMAL\n')
        port=b',\n    output wire f_observe_admitted_o'
        if auth.count(port)!=1:raise ValueError('Auth observation port changed')
        auth=auth.replace(port,b'',1)
        a=auth.index(b'\n    // Read-only histories of accepted input');b=auth.index(b'\n`ifdef FORMAL',a)
        auth_observer=auth[a:b].decode();observer.observer_writes_only(auth_observer)
        auth=auth[:a]+auth[b:]
        a=auth.index(b'\n    logic f_failure_epoch_q');b=auth.index(b'\nendmodule',a)
        extra=auth[a:b].decode();observer.observer_writes_only(extra)
        auth=auth[:a]+auth[b:]
        if nonblank(auth)!=nonblank(original['auth.sv']):raise ValueError('Auth observer reversal changed native code')
        for text in('if(state_q==ST_INIT) assert(!word_buffer_valid_q && word_byte_q==0 && !word_buffer_final_q);',
            'f_words_q==19\'d227062 && f_payload_bytes_q==24\'d7265984 && f_padding_bytes_q==7\'d64'):
            if text not in extra:raise ValueError('Admission/reset origin property changed')
        # Independently reconstruct the old reviewed read-only observers, then
        # restore its arbitrary flags to the complete native auth instance.
        boot=builder.multiclock_boot_monitor((OLD/'boot-order-monitor.inc.sv').read_text())
        bmon=(OLD/'boot-boundary-monitor.inc.sv').read_text();wmon=(OLD/'boot-wrapper-monitor.inc.sv').read_text()
        boot,bmon,wmon=[remove_checks(strip_cover(t))for t in(boot,bmon,wmon)]
        for text in(boot,bmon,wmon):observer.observer_writes_only(text)
        expected,instance=builder.instrument(original,boot,bmon,wmon)
        wrapper=expected['wrapper.sv'].decode()
        header=',\n'+',\n'.join('    input wire '+r['input']for r in builder.AUTH_CUTS)
        assignments='\n'.join('    assign '+r['connected_net']+' = '+r['input']+';'for r in builder.AUTH_CUTS)
        if wrapper.count(header)!=1 or wrapper.count(assignments)!=1:raise ValueError('Prior observer boundary changed')
        wrapper=wrapper.replace(header,'',1)
        wrapper=wrapper.replace(assignments,'    wire f_actual_auth_admitted;\n'+instance[:-2]+',\n        .f_observe_admitted_o(f_actual_auth_admitted)\n    );',1)
        join=(root/'join-monitor.inc.sv').read_text();observer.observer_writes_only(join)
        wrapper=wrapper.replace('\nendmodule','\n'+join+'\nendmodule',1)
        if wrapper.encode()!=(root/'wrapper.sv').read_bytes():raise ValueError('Native wrapper/actual auth join differs')
        for n,raw in expected.items():
            if n!='wrapper.sv'and(root/n).read_bytes()!=raw:raise ValueError('An actual native boot dependency changed')
        if any(row['input']in wrapper for row in builder.AUTH_CUTS):raise ValueError('An arbitrary authentication flag remains')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']];cells=list(graph['cells'].values())
        if sum(c['type']=='$assert'for c in cells)!=45 or sum(c['type']=='$cover'for c in cells)!=1 or any(c['type']in('$assume','$anyseq','$anyconst')for c in cells):
            raise ValueError('Composed property/abstraction inventory changed')
        prefix='u_sole_readback_auth.u_sole_compact_sha.u_compress.schedule_q['
        bits=[bit for n in range(16)for bit in graph['netnames'][prefix+str(n)+']']['bits']]
        if len(bits)!=512 or len(set(bits))!=512:raise ValueError('Full actual SHA schedule storage not retained')
        reset='initial\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\n'
        if (root/'reset.smtc').read_text()!=reset:raise ValueError('Positive reset constraints changed')
        work=out/variant;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Fresh elaboration does not reproduce the exact model')
        phase_records={}
        for phase,row in result['results'].items():
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('A solver phase is incomplete')
            for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
                if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Solver evidence changed')
            if phase.endswith('induction')and('--smtc'in row['command']or'Temporal induction successful.'not in(root/(phase+'.log')).read_text()):
                raise ValueError('Induction/reset policy changed')
            phase_records[phase]=queries.reproduce_query(root,phase,row,False,work/(phase+'-query-binding'),
                recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))
        records.append(dict(run=name,variant=variant,image_sha256=bound['image_sha256'],assertions=45,
            actual_authenticator_flags_and_SHA_retained=True,arbitrary_authentication_flags=False,
            native_code_recovered=True,observer_writes_only=True,exact_reelaboration=True,
            both_solver_base_unbounded_induction_and_early_boot_cover=True,phase_query_bindings=phase_records,
            inputs_sha256=sha(inputs_raw),finished_sha256=sha(finished_raw)))
    negative=HERE/'runs/auth-boot-mutant-fake-success-r1'
    negative_inputs=json.loads((negative/'INPUTS.json').read_bytes());negative_result=json.loads((negative/'FINISHED.json').read_bytes())
    if not negative_result['passed']or not negative_result['mutation_detected']:
        raise ValueError('Counterfeit authentication success was not detected')
    positive=HERE/'runs/auth-boot-baseline-r6-release-invariants'
    for n in negative_inputs['compile_sources']:
        expected=(positive/n).read_bytes()
        if n=='auth.sv':
            expected=expected.replace(b'assign digest_done_o = done_q;',b"assign digest_done_o = 1'b1;",1)
            expected=expected.replace(b'assign digest_ok_o = done_q && ok_q && !fail_q;',b'assign digest_ok_o = !fail_q;',1)
        if (negative/n).read_bytes()!=expected:raise ValueError('Semantic authentication mutant has an extra source change')
    for phase,row in negative_result['results'].items():
        if not row['passed']or row['status']!=['FAILED']or row['exit']!=1 or not row['traces']:
            raise ValueError('Counterfeit authentication success lacks a real BMC counterexample')
        for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
            if sha((negative/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Semantic control evidence changed')
    out_record=dict(schema='actual-authentication-to-LOCK-composition-audit-v1',passed=True,runs=records,
        semantic_counterfeit_success_control=dict(run=negative.name,both_solver_actual_BMC_counterexamples=True,
            exactly_two_native_output_assignments_mutated=True,finished_sha256=sha((negative/'FINISHED.json').read_bytes())),
        scope='Actual native boot wrapper/controller/readback CDC and image authenticator/SHA: LOCK requires prior native-length, fixed-padding and matching-digest admission in the common reset epoch. No arbitrary authentication outputs, fairness, host/data promises or arithmetic oracles. Early boot reachability only; full native-length successful LOCK reachability is not searched. SHA algorithm correctness and stream composition have their own independent source-bound audits; no cryptographic-hardness, physical CDC, bitstream or whole-device training-capacity theorem.')
    (out/'FINISHED.json').write_text(json.dumps(out_record,indent=2,sort_keys=True)+'\n')
    (HERE/'AUTH-BOOT-JOIN-AUDIT.json').write_text(json.dumps(out_record,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,variants=len(records),assertions_per_variant=45)))


if __name__=='__main__':main()
