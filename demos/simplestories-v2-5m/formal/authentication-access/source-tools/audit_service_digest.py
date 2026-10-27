"""Audit native four-bank digest selection and its exact overapproximation."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

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
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args();common=load('bindings',HERE.parent/'formal-assurance/run_handoff.py')
    records=[]
    for variant,name in(('baseline','service-digest-baseline-r3-native4'),('encrypted-memory','service-digest-encrypted-r3-native4')):
        root,inputs,result=checked_run(name);encrypted=variant=='encrypted-memory'
        if inputs['binding']['native_banks']!=4 or inputs['binding']['native_address_width']!=19:
            raise ValueError('Actual native parameters not selected')
        production=(root/'production-service.sv').read_bytes();source=(root/'service.sv').read_bytes();prefix=b'`undef FORMAL\n'
        monitor=(root/'monitor.inc.sv').read_bytes()
        if not source.startswith(prefix)or source.count(b'\n'+monitor)!=1:raise ValueError('Observer insertion changed')
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
        if sum(c['type']=='$anyconst'for c in cells)!=1 or any(c['type']in('$assume','$anyseq')for c in cells):
            raise ValueError('Unexpected formal assumption or state cut')
        if sum(c['type']=='$assert'for c in cells)!=8:raise ValueError('Selection property inventory changed')
        rom=[c for n,c in graph['cells'].items()if c['type']=='$mem_v2'and'digest_rom'in n]
        if len(rom)!=1:raise ValueError('Complete native digest ROM missing')
        params=rom[0]['parameters']
        if int(params['WIDTH'],2)!=32 or int(params['SIZE'],2)!=14192 or int(params['WR_PORTS'],2)!=0:
            raise ValueError('Digest ROM geometry/read-only policy changed')
        words=[int(w,16)for w in(root/'digests32.memh').read_text().split()]
        if params['INIT']!=''.join(f'{w:032b}'for w in reversed(words)):
            raise ValueError('Yosys ROM initialization differs from the fixed table')
        required={s+'-'+p for s in('z3','cvc5')for p in('bmc','induction')}|{'z3-cover'}
        for phase in required:
            row=result['results'][phase]
            if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('Required phase incomplete')
            if phase.endswith('induction')and('--smtc'in row['command']or'Temporal induction successful.'not in(root/(phase+'.log')).read_text()):
                raise ValueError('Induction constraint/evidence policy changed')
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
            native_address_width=19,assertions=8,full_readonly_fixed_ROM_initialization_checked=True,
            both_solver_base_and_induction_passed=True,z3_allocation_reachability=True,
            cvc5_cover_search_passed=result['results']['cvc5-cover']['passed'],
            child_behavior_assumptions=[],all_child_replies_unrestricted=True,
            inputs_sha256=sha((root/'INPUTS.json').read_bytes()),finished_sha256=sha((root/'FINISHED.json').read_bytes())))
    negatives=[]
    for role in('word','order'):
        name='service-digest-mutant-'+role+'-r1';root,inputs,result=checked_run(name)
        primary=result['results']['z3-bmc']
        if not primary['passed']or primary['status']!=['FAILED']or primary['exit']!=1 or not primary['traces']:
            raise ValueError('Semantic control lacks a real bounded counterexample')
        replay=HERE/'runs'/('service-digest-mutant-order-cvc5-vcd-r3'if role=='order'else'service-digest-mutant-word-cvc5-witness-r1')
        receipt=json.loads((replay/'FINISHED.json').read_bytes())
        conclusion_ok=receipt.get('answers')==['sat']and receipt.get('all_prior_safety_and_final_negated_safety_checked')if role=='order'else receipt.get('final_answers')==['sat','unsat']
        if not receipt['passed']or not conclusion_ok or receipt['independent_search']:
            raise ValueError('Secondary counterexample witness was not checked')
        if receipt['inputs_sha256']!=sha((root/'INPUTS.json').read_bytes())or receipt['original_finished_sha256']!=sha((root/'FINISHED.json').read_bytes()):
            raise ValueError('Secondary witness is not bound to the exact negative model')
        evidence=(('cvc5.log','log_sha256'),('witness.smt2','query_sha256'))if role=='order'else(('cvc5.log','log_sha256'),('query.smt2','query_sha256'),('responses.txt','solver_responses_sha256'))
        for fn,key in evidence:
            if sha((replay/fn).read_bytes())!=receipt[key]:raise ValueError('Witness evidence changed')
        negatives.append(dict(run=name,primary_BMC_counterexample=True,cvc5_complete_witness_checked=True,
            cvc5_independent_search_passed=result['results']['cvc5-bmc']['passed'],
            witness_receipt_sha256=sha((replay/'FINISHED.json').read_bytes())))
    constants=json.loads((HERE/'FIXED-DIGEST-ASSETS-AUDIT.json').read_bytes())
    if not constants['passed']:raise ValueError('Fixed asset validation missing')
    out=dict(schema='native-four-bank-fixed-digest-selection-audit-v1',passed=True,runs=records,semantic_controls=negatives,
        fixed_assets_audit_sha256=sha((HERE/'FIXED-DIGEST-ASSETS-AUDIT.json').read_bytes()),
        scope='Actual parent service selection of the complete fixed expected digest for each allocated page, under exact native four-bank/address parameters, independent of all child replies. Complete fixed ROM bytes are also checked. Sealed bank lifecycle, encrypted SHA pool, actual consumer provenance and arithmetic/access composition require their separate proofs. No whole-device training, cryptographic-hardness, bitstream or physical theorem.')
    (HERE/'SERVICE-DIGEST-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');print(json.dumps(out))


if __name__=='__main__':main()
