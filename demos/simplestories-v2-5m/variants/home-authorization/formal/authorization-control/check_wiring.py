#!/usr/bin/env python3
"""Source-pinned static correspondence audit, not a solver proof of hierarchy."""
import hashlib,json,re
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
def clean(s):return re.sub(r'\s+','',re.sub(r'//[^\n]*|/\*.*?\*/','',s,flags=re.S))
def ports(s,instance):
    m=re.search(r'\b'+instance+r'\s*\(',s);assert m,instance
    i=m.end();d=1;end=i
    while d:
        if s[end]=='(':d+=1
        if s[end]==')':d-=1
        end+=1
    body=s[i:end-1];out={}
    for m in re.finditer(r'\.(\w+)\s*\(',body):
        a=m.end();j=a;d=1
        while d:
            if body[j]=='(':d+=1
            if body[j]==')':d-=1
            j+=1
        assert m[1] not in out
        out[m[1]]=clean(body[a:j-1])
    return out
def audit():
    pin=json.loads((HERE/'SOURCE-PINS.json').read_text())
    for f,h in pin['files'].items():assert sha(PROJECT/f)==h,f
    checks=[]
    def check(file,instance,expected):
        p=ports((PROJECT/file).read_text(),instance)
        for k,v in expected.items():
            assert p[k]==clean(v),(file,instance,k,p.get(k),v)
            checks.append({'file':file,'instance':instance,'port':k,'connection':p[k]})
    check('home/home_product_top.sv','u_core',{'private_nonce_i':'registered_nonce','private_nonce_valid_i':'nonce_valid','private_nonce_fault_i':'nonce_fault'})
    check('top.sv','u_home',{'clk':'core_clk','reset_n':'core_reset_n','admitted_root_valid_i':'model_locked','admitted_root_i':'model_commitment','model_fault_i':'memory_fault || source_fault || home_transport_fault','inference_enabled_o':'home_enabled','failed_o':'home_failed','new_lease_o':'home_accepted','publication_allowed_o':'home_publication_allowed','shared_reset_n_o':'lease_crypto_reset_n','shared_start_o':'lease_crypto_start','shared_message_byte_o':'lease_message_byte','shared_signature_byte_o':'lease_signature_byte','shared_signature_ready_o':'lease_signature_ready','shared_signature_address_i':'lease_signature_address','shared_message_address_i':'lease_message_address','shared_done_i':'lease_crypto_done','shared_valid_i':'lease_crypto_valid','shared_fault_i':'lease_crypto_fault'})
    check('top.sv','u_uart_core',{'core_clk_i':'core_clk','app_clk_i':'core_clk','reset_n_i':'token_reset_n','private_transport_pause_i':'home_mode_q','private_publication_allowed_i':'home_publication_allowed','uart_tx_o':'token_uart_tx','private_endpoint_req_valid_o':'request_valid'})
    check('uart_core.sv','u_fixed_uart',{'rst_n':'reset_n_i','publication_allowed_i':'private_publication_allowed_i','transport_pause_i':'private_transport_pause_i','uart_tx_o':'uart_tx_o'})
    check('uart_core.sv','u_machine',{'reset_n_i':'reset_n_i','app_clk_i':'app_clk_i','private_endpoint_req_valid_o':'private_endpoint_req_valid_o'})
    check('shared_token_probe.sv','u_shared',{'clk':'app_clk_i','reset_n':'app_runtime_reset_n','raw_req_valid_o':'private_endpoint_req_valid_o'})
    check('arbiter.sv','u_backend',{'clk':'clk','reset_n':'reset_n','raw_req_valid_o':'raw_req_valid_o'})
    check('top.sv','u_signed_boot',{'model_commitment_o':'model_commitment','lease_key_id_i':'HOME_KEY_ID','lease_key_root_i':'HOME_KEY_ROOT','lease_crypto_reset_n_i':'lease_crypto_reset_n','lease_crypto_start_i':'lease_crypto_start','lease_signature_byte_i':'lease_signature_byte','lease_signature_ready_i':'lease_signature_ready','lease_message_byte_i':'lease_message_byte','lease_signature_address_o':'lease_signature_address','lease_message_address_o':'lease_message_address','lease_crypto_done_o':'lease_crypto_done','lease_crypto_valid_o':'lease_crypto_valid','lease_crypto_fault_o':'lease_crypto_fault'})
    fields=['lease_crypto_reset_n_i','lease_crypto_start_i','lease_key_id_i','lease_key_root_i','lease_signature_byte_i','lease_signature_ready_i','lease_message_byte_i','lease_signature_address_o','lease_message_address_o','lease_crypto_done_o','lease_crypto_valid_o','lease_crypto_fault_o']
    check('swic/swic_boot_ingress.sv','u_admission',{k:k for k in fields})
    check('swic/swic_boot_admission.sv','u_lms',{'reset_n':'selected_lms_reset_n','start_i':'lease_owner ? lease_crypto_start_i : state_q==AUTH_START','public_i_i':'lease_owner ? lease_key_id_i : su_authority_identifier(key_q)','public_root_i':'lease_owner ? lease_key_root_i : su_authority_root(key_q)','message_length_i':"9'd128",'signature_byte_i':'lease_owner ? lease_signature_byte_i : signature_read_q','signature_ready_i':'lease_owner ? lease_signature_ready_i : signature_ready','message_byte_i':'lease_owner ? lease_message_byte_i : manifest_q[lms_message_address[6:0]]'})
    admission=clean((PROJECT/'swic/swic_boot_admission.sv').read_text())
    for expression in [
        'wire lease_owner=SHARE_VERIFIER && sealed_o;',
        'assign selected_lms_reset_n=lease_owner ? lease_crypto_reset_n_i : lms_reset_n;',
        'assign lease_crypto_done_o=lease_owner && lease_crypto_reset_n_i && lms_done;',
        'assign lease_crypto_valid_o=lease_owner && lease_crypto_reset_n_i && lms_valid;',
        'assign lease_crypto_fault_o=lease_owner && lease_crypto_reset_n_i && lms_fault;']:
        assert clean(expression) in admission,expression
    # Exact selected production timing values, independently compared with proof.
    product=clean((PROJECT/'home/home_product_top.sv').read_text())
    for name,value in [('HOME_RESPONSE_CYCLES','100000000'),('HOME_LEASE_CYCLES','250000000'),('HOME_RENEW_CYCLES','125000000')]:
        assert f'.{name}({value})' in product
    result={'result':'PASS','kind':'source-pinned-static-correspondence','checks':checks,'timer_values_verified':True,'source_pins_sha256':sha(HERE/'SOURCE-PINS.json'),'limitations':'Does not prove physical placement, CDC, clock/entropy integrity, authenticated boot, signature RAM freshness or LMS/SHA correctness.'}
    return result
if __name__=='__main__':
    r=audit();(HERE/'WIRING-AUDIT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps({'result':r['result'],'connections_checked':len(r['checks'])}))
