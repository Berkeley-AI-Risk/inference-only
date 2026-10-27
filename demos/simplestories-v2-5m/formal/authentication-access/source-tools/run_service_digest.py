"""Native fixed digest ROM selection, independent of all private child replies.

Bank status/data and encrypted pool faults are unrestricted new top inputs.
No promise about those replies is assumed. Therefore the selection guarantee
holds for any implementation of those children; it makes no child theorem.
"""
import argparse
import hashlib
import importlib.util
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
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--mutant',choices=('wrong-rom-word','reverse-digest-order'))
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
        before,after=('digest_rom[{fill_page_q,digest_word_q}]',"digest_rom[{fill_page_q,(digest_word_q^3'd1)}]")if args.mutant=='wrong-rom-word'else(
            '{expected_digest_q[223:0],digest_data_q}','{digest_data_q,expected_digest_q[255:32]}')
        if source.count(before)!=1:raise ValueError('Native service mutation site changed')
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
    monitor=(HERE/'service-digest-monitor.inc.sv').read_text()
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
    for name in('digests32.memh','metadata192.memh','first192.memh','last192.memh'):
        path=directory/'project'/name
        if path.is_file():files[name]=path.read_bytes()
    cover=''
    for state in range(2,44):
        cover+=f'state {state}\nassume (= [reset_n] true)\nassume (= [cancel_i] false)\nassume (= [model_locked_i] true)\n'
        cover+='assume (= [request_valid_i] '+('true'if state==2 else'false')+')\nassume (= [request_word_i] (_ bv0 19))\n'
        cover+=f'assume (= [f_bank_begin_ready_i] (_ bv{(1<<banks)-1} {banks}))\n'
        for name in('assigned','fault'):cover+=f'assume (= [f_bank_{name}_i] (_ bv0 {banks}))\n'
        cover+='assume (= [ddr_response_valid_i] false)\n'
        if encrypted:cover+='assume (= [f_crypto_fault_i] false)\nassume (= [f_hash_fault_i] false)\n'
    binding=dict(native_joins=joins,variant=args.variant,native_banks=banks,native_address_width=19,
        production_source_sha256=hashlib.sha256(original).hexdigest(),child_outputs_unrestricted=True,
        child_output_assumptions=[],actual_complete_digest_rom_retained=True,
        proof_is_independent_of_child_behavior=True,child_authentication_not_claimed=True)
    return engine.check(args.run,files,top='service_digest_native',
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=monitor.count('assert('),covers=1,binding=binding,cuts=cuts,depth=32 if args.mutant else 5,induction_depth=3,
        cover_depth=44,cover_constraints=cover,timeout=args.timeout,source_list=['service.sv','native-parameters.sv'],
        observer_constants=1,optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},mutant=args.mutant,
        scope='Actual private service with native production bank/address parameters and complete digest ROM. Prove every allocated expected digest lane is selected and assembled from the fixed ROM for that exact page, independent of all private child replies. All cut child outputs are unrestricted inputs, with no assumptions. This is a parent selection theorem, not a bank/consumer, authentication, AES, residual training-capacity or physical theorem.')


if __name__=='__main__':raise SystemExit(main())
