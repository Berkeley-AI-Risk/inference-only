"""Audit native FIFO provenance, checked-bank routing and source joins."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_rom_audit_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def checked_run(name):
    root=HERE/'runs'/name;raw=(root/'INPUTS.json').read_bytes();inputs=json.loads(raw)
    result=json.loads((root/'FINISHED.json').read_bytes())
    if result['inputs_sha256']!=sha(raw):raise ValueError('Model/result binding changed')
    for n,row in inputs['files'].items():
        data=(root/n).read_bytes()
        if row!={'bytes':len(data),'sha256':sha(data)}:raise ValueError('Changed source: '+n)
    for phase,row in result['results'].items():
        for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
            if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Changed solver evidence')
        for n,digest in row['traces'].items():
            if sha((root/n).read_bytes())!=digest:raise ValueError('Changed witness')
    return root,inputs,result


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();out_dir=args.out.resolve();out_dir.mkdir(parents=True,exist_ok=False);common=load('bindings',HERE.parent/'formal-assurance/run_handoff.py')
    queries=load('queries',HERE.parent/'formal-assurance/audit_fifo.py')
    observer=load('observer',HERE.parent/'formal-assurance/audit_boot_boundary.py')
    records=[]
    for variant,name in(('baseline','service-routing-baseline-r2-wrap'),('encrypted-memory','service-routing-encrypted-r1')):
        root,inputs,result=checked_run(name);encrypted=variant=='encrypted-memory'
        if inputs['binding']['native_banks']!=4 or inputs['binding']['native_address_width']!=19:
            raise ValueError('Actual native parameters not selected')
        production=(root/'production-service.sv').read_bytes();source=(root/'service.sv').read_bytes();prefix=b'`undef FORMAL\n'
        monitor=(root/'monitor.inc.sv').read_bytes()
        if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1:raise ValueError('Observer insertion changed')
        observer.observer_writes_only(monitor.decode())
        source=source[len(prefix):].replace(b'\n'+monitor,b'',1).decode()
        ports=[('begin_ready','BANKS'),('fill_ready','BANKS'),('read_ready','BANKS'),
            ('assigned','BANKS'),('verified','BANKS'),('fault','BANKS'),('response_valid','BANKS'),
            ('page','BANKS*11'),('response_data','BANKS*256')]
        declarations=[f'    input wire [{width}-1:0] f_bank_{n}_i'for n,width in ports]
        if encrypted:declarations+=['    input wire f_crypto_fault_i,f_hash_fault_i']
        added=',\n'+',\n'.join(declarations)
        if source.count(added)!=1:raise ValueError('Unrestricted boundary input inventory changed')
        source=source.replace(added,'',1)
        replacement='\n'.join('    assign bank_'+n+'=f_bank_'+n+'_i;'for n,_ in ports if n not in('page','response_data'))
        replacement+='\n    for(genvar f_b=0;f_b<BANKS;f_b=f_b+1) begin: f_unrestricted_bank\n'
        replacement+='        assign bank_page[f_b]=f_bank_page_i[f_b*11 +: 11];\n'
        replacement+='        assign bank_response_data[f_b]=f_bank_response_data_i[f_b*256 +: 256];\n    end'
        if source.count(replacement)!=1:raise ValueError('Private bank reply replacement changed')
        source=source.replace(replacement,(root/'removed-bank-instance.sv.txt').read_text(),1)
        if encrypted:
            for instance,out,cut in(('u_crypto_pool','crypto_fault','f_crypto_fault_i'),('u_hash_pool','hash_fault','f_hash_fault_i')):
                text='    assign '+out+'='+cut+';'
                if source.count(text)!=1:raise ValueError('Private pool replacement changed')
                source=source.replace(text,(root/('removed-'+instance+'.sv.txt')).read_text(),1)
        if source.encode()!=production:raise ValueError('Source reversal failed')
        if inputs['assumption_cells']or inputs['changed_production_parameters']:
            raise ValueError('Assumption/native geometry policy changed')
        cuts=inputs['internal_cuts']
        if len(cuts)!=(11 if encrypted else 9)or any(c['assumptions']for c in cuts):
            raise ValueError('A child behavior restriction was introduced')
        graph=json.loads((root/'elaborated.json').read_bytes())['modules']['service_digest_native'];cells=list(graph['cells'].values())
        if any(c['type']in('$anyconst','$assume','$anyseq')for c in cells):
            raise ValueError('Unexpected formal assumption or state cut')
        if sum(c['type']=='$assert'for c in cells)!=monitor.count(b'assert('):raise ValueError('Selection property inventory changed')
        memories={n:c for n,c in graph['cells'].items()if c['type']=='$mem_v2'}
        for suffix,width,size in(('request_fifo',18,64),('response_fifo',3,32),('f_route_words',18,32)):
            selected=[c for n,c in memories.items()if n.endswith(suffix)]
            if len(selected)!=1 or int(selected[0]['parameters']['WIDTH'],2)!=width or int(selected[0]['parameters']['SIZE'],2)!=size:
                raise ValueError('Native/observer FIFO geometry changed: '+suffix)
        # The digest has no output fanout in this overapproximation. Its
        # separate native ROM-selection theorem supplies that composition.
        if any('digest_rom'in n for n in memories):raise ValueError('Routing model gained an unexplained digest dependency')
        required={'z3-bmc','z3-induction','z3-cover'}
        for phase in required:
            row=result['results'][phase]
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Required phase incomplete')
            if phase.endswith('induction')and('--smtc'in row['command']or'Temporal induction successful.'not in(root/(phase+'.log')).read_text()):
                raise ValueError('Induction constraint/evidence policy changed')
        work=out_dir/variant;work.mkdir()
        for n in inputs['files']:
            target=work/n;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((root/n).read_bytes())
        with(work/'re-elaboration.log').open('w')as log:
            cp=subprocess.run(['yosys','-Q','prove.ys'],cwd=work,stdout=log,stderr=subprocess.STDOUT,timeout=60)
        if cp.returncode or any((work/n).read_bytes()!=(root/n).read_bytes()for n in('design.smt2','elaborated.json','elaborated.il')):
            raise ValueError('Actual parent model does not reproduce')
        phases={phase:queries.reproduce_query(root,phase,result['results'][phase],False,work/(phase+'-query-binding'),
            recorded_replies=root/(phase+'.responses'),keep_trace_outputs=phase.endswith('cover'))for phase in sorted(required)}
        joins={};group=('encrypted-memory',)if encrypted else('baseline','seeded-sampling','kv-protected')
        harness=(root/'native-parameters.sv').read_text()
        if '#(.BANKS(4),.ADDR_W(19)'not in harness:raise ValueError('Harness parameters changed')
        for v in group:
            _,directory,bound=common.binding(args.package,v)
            if (directory/'project/service.sv').read_bytes()!=production:raise ValueError('Native service differs')
            uart=(directory/'project/uart_core.sv').read_bytes();shared=(directory/'project/shared_token_probe.sv').read_bytes()
            if re.findall(rb'\.AUTH_BANKS\((\d+)\)',uart)!=[b'4']or b'.BANKS(AUTH_BANKS),.ADDR_W(19)'not in shared:
                raise ValueError('Native parameter hierarchy changed')
            if encrypted:
                for literal in(".KEY_IS_PROVISIONED(1'b1)",".WEIGHT_KEY(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f)",".MODEL_NONCE(96'h112233445566778899aabbcc)"):
                    if literal not in shared.decode()or literal not in harness:raise ValueError('Actual confidential service parameters differ')
            joins[v]=dict(image_sha256=bound['image_sha256'],uart_source_sha256=sha(uart),shared_parent_sha256=sha(shared))
        records.append(dict(run=name,variants=group,native_joins=joins,source_reversal=True,native_banks=4,
            native_address_width=19,assertions=monitor.count(b'assert('),native_request_and_response_FIFOs_retained=True,unused_digest_ROM_eliminated_from_routing_cone=True,
            z3_satisfiable_base_and_unbounded_induction=True,z3_metadata_response_reachability=True,
            cvc5_reset_base_passed=result['results']['cvc5-bmc']['passed'],cvc5_unbounded_induction_passed=result['results']['cvc5-induction']['passed'],
            required_query_bindings=phases,exact_model_reelaboration=True,
            cvc5_cover_search_passed=result['results']['cvc5-cover']['passed'],
            child_behavior_assumptions=[],all_child_replies_unrestricted=True,
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    root,inputs,result=checked_run('service-routing-mutant-bank-r1')
    primary=result['results']['z3-bmc']
    if not primary['passed']or primary['status']!=['FAILED']or primary['exit']!=1 or not primary['traces']:
        raise ValueError('Wrong response-bank selector lacks a real bounded counterexample')
    positive=HERE/'runs/service-routing-baseline-r2-wrap'
    for n in inputs['compile_sources']:
        wanted=(positive/n).read_bytes()
        if n=='service.sv':wanted=wanted.replace(b'{metadata_read,head_bank}',b"{metadata_read,(head_bank^BANK_W'(1))}",1)
        if (root/n).read_bytes()!=wanted:raise ValueError('Response-bank control changes more than one intended native selector')
    negatives=[dict(run=root.name,primary_BMC_counterexample=True,
        cvc5_independent_search_passed=result['results']['cvc5-bmc']['passed'],
        finished_sha256=sha((root/'FINISHED.json').read_bytes()))]
    digest=json.loads((HERE/'SERVICE-DIGEST-AUDIT.json').read_bytes())
    if not digest['passed']:raise ValueError('Independent fixed digest selection theorem missing')
    constants=json.loads((HERE/'FIXED-DIGEST-ASSETS-AUDIT.json').read_bytes())
    if not constants['passed']:raise ValueError('Fixed asset validation missing')
    receipt=dict(schema='native-four-bank-private-service-routing-audit-v1',passed=True,runs=records,semantic_controls=negatives,
        digest_selection_audit_sha256=sha((HERE/'SERVICE-DIGEST-AUDIT.json').read_bytes()),
        fixed_assets_audit_sha256=sha((HERE/'FIXED-DIGEST-ASSETS-AUDIT.json').read_bytes()),
        scope='Actual native four-bank service request/response FIFOs and checked-bank routing for unrestricted private child replies. In-order initialized in-range descriptors, verified page/tag read gates and exact selected response source are proved. Child payload authenticity, metadata value correspondence, service-to-machine arithmetic and whole-device training bounds require their separate compositions.')
    (HERE/'SERVICE-ROUTING-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');(out_dir/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n');print(json.dumps(dict(passed=True,runs=len(records))))


if __name__=='__main__':main()
