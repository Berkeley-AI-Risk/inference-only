"""Native request/response FIFO provenance and checked-bank routing.

All private child replies remain unrestricted. The parent theorem proves FIFO
ordering, initialized in-range descriptors, checked page/tag gates and exact
response selection. It does not assume that arbitrary child data authenticate.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_digest_service_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--variant',choices=('baseline','encrypted-memory'),default='baseline')
    p.add_argument('--bank-composition',action='store_true')
    p.add_argument('--metadata',action='store_true')
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--mutant',choices=('wrong-response-bank','wrong-metadata-row'))
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    group=('baseline','seeded-sampling','kv-protected')if args.variant=='baseline'else('encrypted-memory',)
    original=None;joins={};native_banks=None;parent_files={}
    for variant in group:
        _,directory,bound=common.binding(args.package,variant)
        raw=(directory/'project/service.sv').read_bytes()
        if original is not None and original!=raw:raise ValueError('Claimed service source identity changed')
        original=raw;joins[variant]=bound
        uart=(directory/'project/uart_core.sv').read_bytes()
        configured=re.findall(rb'\.AUTH_BANKS\((\d+)\)',uart)
        if len(configured)!=1:raise ValueError('Actual UART bank configuration changed')
        count=int(configured[0])
        if native_banks is not None and count!=native_banks:raise ValueError('Source-identical service has differing production parameters')
        native_banks=count
        shared=(directory/'project/shared_token_probe.sv').read_bytes()
        if b'.BANKS(AUTH_BANKS),.ADDR_W(19)'not in shared:raise ValueError('Actual service parameter wiring changed')
        parent_files['production-'+variant+'-uart_core.sv']=uart
        parent_files['production-'+variant+'-shared_token_probe.sv']=shared
    encrypted=args.variant=='encrypted-memory'
    source=original.decode();top='tang_pooled_confidential_ddr_page_service'if encrypted else'board1_verified_ddr_page_service'
    if args.mutant:
        if args.mutant=='wrong-response-bank':
            before='{metadata_read,head_bank}'
            after="{metadata_read,(head_bank^BANK_W'(1))}"
        else:
            if not args.metadata or encrypted:raise ValueError('The metadata row control targets the complete plaintext metadata-ROM proof')
            before='data_q<=memory[address];'
            after="data_q<=memory[address^12'd1];"
        if source.count(before)!=1:raise ValueError('Native response descriptor write changed')
        source=source.replace(before,after,1)
    # Widen only the observer boundary; native parent code and parameters stay.
    ports=[('begin_ready','BANKS'),('fill_ready','BANKS'),('read_ready','BANKS'),
        ('assigned','BANKS'),('verified','BANKS'),('fault','BANKS'),('response_valid','BANKS'),
        ('page','BANKS*11'),('response_data','BANKS*256')]
    declarations=[f'    input wire [{width}-1:0] f_bank_{name}_i'for name,width in ports]
    if encrypted:declarations+=['    input wire f_crypto_fault_i,f_hash_fault_i']
    a=source.index('    genvar b;\n');b=source.index('    end endgenerate',a)+len('    end endgenerate')
    bank_instance=source[a:b]
    assignments='\n'.join('    assign bank_'+name+'=f_bank_'+name+'_i;'for name,_ in ports if name not in('page','response_data'))
    assignments+='\n    for(genvar f_b=0;f_b<BANKS;f_b=f_b+1) begin: f_unrestricted_bank\n'
    assignments+='        assign bank_page[f_b]=f_bank_page_i[f_b*11 +: 11];\n'
    assignments+='        assign bank_response_data[f_b]=f_bank_response_data_i[f_b*256 +: 256];\n    end'
    source=source[:a]+assignments+source[b:]
    cuts=[dict(instance='g_bank.u_bank',output=name,width=width,replacement='unrestricted module input f_bank_'+name+'_i',assumptions=[])for name,width in ports]
    removed={'removed-bank-instance.sv.txt':bank_instance.encode()}
    if encrypted:
        for child,instance,out,cut in(('tang_private_aes256_pool2','u_crypto_pool','crypto_fault','f_crypto_fault_i'),('tang_private_sha256_pool2','u_hash_pool','hash_fault','f_hash_fault_i')):
            a=source.index('    '+child+' #(');pos=source.index(' '+instance+' (',a);b=source.index(');',pos)+2
            text=source[a:b];removed['removed-'+instance+'.sv.txt']=text.encode()
            source=source[:a]+'    assign '+out+'='+cut+';'+source[b:]
            cuts.append(dict(instance=instance,output=out,width=1,replacement='unrestricted module input '+cut,assumptions=[]))
    source=source.replace('\n);',',\n'+',\n'.join(declarations)+'\n);',1)
    monitor=(HERE/'service-routing-monitor.inc.sv').read_text()
    metadata_monitor=''
    if args.metadata:
        monitor+='\n'+(HERE/'service-metadata-routing-monitor.inc.sv').read_text()
        metadata_monitor=(HERE/('service-metadata-encrypted-monitor.inc.sv'if encrypted else'service-metadata-plain-monitor.inc.sv')).read_text()
        marker='        initial begin\n            $readmemh("first192.memh",first_rows);'if encrypted else'        initial $readmemh(METADATA_HEX,memory);'
        if source.count(marker)!=1:raise ValueError('Native metadata observer insertion changed')
        source=source.replace(marker,metadata_monitor+'\n'+marker,1)
    interface_audit=None
    if args.bank_composition:
        if not args.metadata:raise ValueError('Consumer composition includes the actual metadata path')
        interface_audit=(HERE/'BANK-INTERFACE-AUDIT.json').read_bytes()
        if not json.loads(interface_audit)['passed']:raise ValueError('Child interface contracts are not discharged')
        monitor+='\n'+(HERE/'service-bank-consumer-monitor.inc.sv').read_text()
        for row in cuts:
            if row['output']in('response_valid','read_ready'):
                row['assumptions']=['source-proved single-pending bank interface; BANK-INTERFACE-AUDIT.json']
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    banks=native_banks
    native_params='.BANKS('+str(banks)+'),.ADDR_W(19)'
    if encrypted:native_params+=",.KEY_IS_PROVISIONED(1'b1),.WEIGHT_KEY(256'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f),.MODEL_NONCE(96'h112233445566778899aabbcc)"
    # A small exact-parameter wrapper avoids changing defaults in the service.
    # Its inputs include every service input; its outputs are the service outputs.
    header=source[source.index(') (')+3:source.index('\n);')]
    header=re.sub(r'\bADDR_W\b','19',header);header=re.sub(r'\bBANKS\b',str(banks),header)
    names=[]
    for line in header.splitlines():
        if 'input wire' in line or 'output wire' in line:
            tail=re.sub(r'^.*?\b(?:input|output)\s+wire\s*(?:\[[^]]+\])?\s*','',line).rstrip(',')
            names.extend(x.strip()for x in tail.split(','))
    harness='module service_digest_native('+header+'\n);\n    '+top+' #('+native_params+') u_service (\n'
    harness+=',\n'.join('        .'+n+'('+n+')'for n in names)+'\n    );\nendmodule\n'
    files={'service.sv':b'`undef FORMAL\n'+source.encode(),'native-parameters.sv':harness.encode(),
        'production-service.sv':original,'monitor.inc.sv':monitor.encode(),**removed,
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    files.update(parent_files)
    if args.metadata:files['metadata-monitor.inc.sv']=metadata_monitor.encode()
    if args.bank_composition:files['bank-interface-premise-audit.json']=interface_audit
    for name in('digests32.memh','metadata192.memh','first192.memh','last192.memh'):
        path=directory/'project'/name
        if path.is_file():files[name]=path.read_bytes()
    cover=''
    for state in range(2,14):
        cover+=f'state {state}\nassume (= [reset_n] true)\nassume (= [cancel_i] false)\nassume (= [model_locked_i] true)\n'
        cover+='assume (= [request_valid_i] '+('true'if state==2 or(args.bank_composition and state==7)else'false')+')\n'
        cover+=f'assume (= [request_word_i] (_ bv{0 if args.bank_composition and state<7 else 211920} 19))\n'
        cover+=f'assume (= [f_bank_begin_ready_i] (_ bv{(1<<banks)-1} {banks}))\n'
        for name in('assigned','fault'):cover+=f'assume (= [f_bank_{name}_i] (_ bv0 {banks}))\n'
        cover+='assume (= [ddr_response_valid_i] false)\n'
        if encrypted:cover+='assume (= [f_crypto_fault_i] false)\nassume (= [f_hash_fault_i] false)\n'
    binding=dict(native_joins=joins,variant=args.variant,native_banks=banks,native_address_width=19,
        production_source_sha256=hashlib.sha256(original).hexdigest(),child_outputs_unrestricted=not args.bank_composition,
        child_output_assumptions=['BANK-INTERFACE-AUDIT.json response-valid and capacity contracts']if args.bank_composition else [],unused_compiled_digest_ROM_not_required=True,fixed_digest_selection_proved_separately=True,actual_request_and_response_fifos_retained=True,metadata_transaction_and_ROM_value_composition=args.metadata,
        proof_is_independent_of_child_behavior=not args.bank_composition,bank_consumer_composition_included=args.bank_composition,
        bank_interface_premise_audit_sha256=hashlib.sha256(interface_audit).hexdigest()if interface_audit else None,child_authentication_not_claimed=True)
    return engine.check(args.run,files,top='service_digest_native',
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=monitor.count('assert(')+metadata_monitor.count('assert(')+(18 if args.bank_composition else 0),covers=2 if args.bank_composition else 1,binding=binding,cuts=cuts,depth=32 if args.mutant else 5,induction_depth=3,
        cover_depth=14,cover_constraints=cover,timeout=args.timeout,source_list=['service.sv','native-parameters.sv'],
        observer_constants=0,expected_assumptions=8 if args.bank_composition else 0,optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},mutant=args.mutant,
        scope='Actual native four-bank service request/response FIFO and private routing. Prove descriptor initialization, range, FIFO ordering, checked-bank page/tag gates and exact response selection for arbitrary child replies without assumptions. Child payload authenticity, full service-to-consumer composition and whole-device training bounds are separate obligations.')


if __name__=='__main__':raise SystemExit(main())
