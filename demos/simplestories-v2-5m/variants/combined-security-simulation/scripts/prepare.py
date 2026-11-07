"""Assemble the separately selected combined simulation source."""
from pathlib import Path
import difflib, hashlib, json, re, shutil, sys
sys.path.insert(0,str(Path(__file__).resolve().parent))
from pin_sources import HERE, CHECKOUT, DEMO, main as check_pins, sha

ENC = DEMO/'variants/encrypted-memory/hardware/project'
HOME = DEMO/'variants/home-authorization/hardware/project'

def replace(text, before, after):
    if text.count(before)!=1: raise ValueError('Nonunique source seam: '+before[:90])
    return text.replace(before,after)

def span(text, begin, end):
    a=text.index(begin); b=text.index(end,a)
    return text[a:b]

def key(label): return hashlib.sha256(('PUBLIC COMBINED TEST '+label).encode()).hexdigest()
KEYS={'weightA':'000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f',
      'macA':'404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f',
      'ctrA':'606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f',
      'weightB':key('weightB'),'macB':key('macB'),'ctrB':key('ctrB')}
NONCES=['112233445566778899aabbcc',key('nonceB')[:24]]

def slot_wrapper(original, name, params, slots):
    """Select fixed public test-vault engines; all AES/SIV internals stay exact."""
    module=re.search(r'\bmodule\s+(\w+)\s*#\(',original).group(1)
    ports=re.search(r'\)\s*\((.*?)\n\);',original,re.S).group(1)
    declarations=[]
    for part in re.split(r'(?=^\s*(?:input|output)\s)',ports,flags=re.M):
        part=' '.join(part.split()).rstrip(',')
        if not part: continue
        m=re.fullmatch(r'(input|output)\s+(?:wire|logic)\s*(\[[^]]+\])?\s*(.*)',part)
        if not m: raise ValueError('Unsupported port declaration '+part)
        direction,width,names=m.groups()
        for port in names.split(','):
            port=port.strip()
            if not re.fullmatch(r'\w+',port): raise ValueError('Unsupported port name '+port)
            declarations.append((direction,width or '',port))
    text='`timescale 1ns/1ps\n`default_nettype none\n'
    text+='// Modeled two-entry private test vault; public fixture keys, real inherited engines.\n'
    text+='module '+name+params+' (\n    input wire model_slot_i,'+ports+'\n);\n'
    for direction,width,port in declarations:
        if direction=='output':
            for slot in range(2): text+=f'    wire {width} {port}_m{slot};\n'
            text+=f'    assign {port}=model_slot_i ? {port}_m1 : {port}_m0;\n'
    for slot,values in enumerate(slots):
        text+='    '+module+' #('+','.join('.'+k+'('+v+')' for k,v in values.items())+f') u_model{slot} (\n'
        connections=[]
        for direction,width,port in declarations:
            value=port+f'_m{slot}' if direction=='output' else port
            if port=='reset_n': value=f'(reset_n && model_slot_i==1\'b{slot})'
            connections.append('.'+port+'('+value+')')
        text+='        '+',\n        '.join(connections)+'\n    );\n'
    return text+'endmodule\n`default_nettype wire\n'

def main():
    check_pins()
    out=HERE/'prepared-v1'
    out.mkdir(exist_ok=False)
    source=out/'source';source.mkdir()
    origins={}; edits={}
    pinned_inputs=json.loads((HERE/'SOURCE-INPUTS.json').read_text())['files']
    def copy(path,name):
        relative=str(path.relative_to(CHECKOUT))
        if relative not in pinned_inputs or sha(path)!=pinned_inputs[relative]['sha256']:
            raise ValueError('Unpinned compiler input '+relative)
        p=source/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,p)
        origins[name]={'origin':str(path),'sha256':sha(path)}
    def derive(name,text,reason):
        p=source/name
        before=p.read_text() if p.exists() else ''
        p.parent.mkdir(parents=True,exist_ok=True);p.write_text(text)
        edits[name]={'reason':reason,'before_sha256':hashlib.sha256(before.encode()).hexdigest(),
                     'after_sha256':sha(p)}
        (out/('diff-'+str(len(edits))+'.patch')).write_text(''.join(difflib.unified_diff(before.splitlines(True),text.splitlines(True),fromfile=name+'/pinned',tofile=name+'/private')))
    order=[]
    excluded={'top.sv','uart_core.sv','defines.v'}
    for name in (ENC/'production_sources.f').read_text().splitlines():
        name=name.strip()
        if not name or name.startswith('official/') or name in excluded or 'board1_gowin_ddr3_raw_controller_shell' in name: continue
        copy(ENC/name,name); order.append(name)
    # Recorded subdirectories are not compiler inputs. Copy only the selected
    # read-only initialization files in the public input inventory.
    enc_prefix=str(ENC.relative_to(CHECKOUT))+'/'
    for relative in sorted(pinned_inputs):
        if relative.startswith(enc_prefix) and relative.endswith('.memh'):
            copy(CHECKOUT/relative,relative[len(enc_prefix):])
    # Keep encrypted head-layout attention and atomic K/V unchanged. Only the
    # established signed-model normalization ports replace their fixed ROMs.
    norm_names=[n for n in order if any(x in n for x in ('board1_fixed_vector_rmsnorm_service.sv','board1_context2048_semantic_datapath.sv','board1_context2048_semantic_layer.sv','board1_context2048_token_shell.sv','board1_context2048_token_machine_core.sv'))]
    if len(norm_names)!=5: raise ValueError('Unexpected norm composition')
    for name in norm_names: copy(HOME/name,name)
    for p in sorted((HOME/'swic').glob('*.sv')):
        if p.name in ('swic_qspi_boot_source.sv','swic_read03_master.sv','swic_verified_memory.sv','swic_boot_ingress.sv','swic_ddr_boot.sv'): continue
        name='swic/'+p.name;copy(p,name);order.append(name)
    copy(HOME/'home/home_boot_gate.sv','home_boot_gate.sv');order.append('home_boot_gate.sv')
    # Runtime bank retains actual AES/SHA timing; nonce comes from the private
    # bound vault rather than a fixed-model elaboration constant.
    text=(source/'bank.sv').read_text()
    text=replace(text,'    input wire clk, reset_n, cancel_read_i,','    input wire clk, reset_n, cancel_read_i,\n    input wire [95:0] private_model_nonce_i,')
    text=replace(text,'{MODEL_NONCE,counter_index}','{private_model_nonce_i,counter_index}')
    derive('bank.sv',text,'Private admitted-model nonce at the existing absolute block counter')
    text=(source/'service.sv').read_text(); home=(HOME/'service.sv').read_text()
    private_ports=span(home,'    output wire private_digest_read_o,','\n);')
    text=replace(text,'    output wire fault_o\n);','    output wire fault_o,\n    input wire private_model_slot_i,\n    input wire [95:0] private_model_nonce_i,\n'+private_ports+'\n);')
    begin='    generate if(LOCAL_METADATA!=0) begin: g_metadata';end='    logic [10:0] fill_page_q;'
    text=replace(text,span(text,begin,end),span(home,begin,end))
    begin='    // Narrow synchronous ROM is never writable.';end='    always_ff @(posedge clk or negedge reset_n) begin\n        if(!reset_n) head_valid_q'
    text=replace(text,span(text,begin,end),span(home,begin,end))
    text=replace(text,'    tang_private_aes256_pool2 #(.BANKS(BANKS),.KEY_IS_PROVISIONED(KEY_IS_PROVISIONED),\n        .KEY(WEIGHT_KEY)) u_crypto_pool (','    combined_weight_pool #(.BANKS(BANKS)) u_crypto_pool (\n        .model_slot_i(private_model_slot_i),')
    text=replace(text,'.clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i),','.clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i),\n            .private_model_nonce_i(private_model_nonce_i),')
    text=replace(text,'        $readmemh(DIGEST_HEX,digest_rom);','        // Expected digests are read only from real sealed signed admission.')
    derive('service.sv',text,'Keep encrypted page service; use actual signed metadata/digest storage and private vault selector')
    text=(source/'shared_token_probe.sv').read_text();home=(HOME/'shared_token_probe.sv').read_text()
    text=replace(text,'module tang_confidential_context2048_token_probe #','module combined_token_probe #')
    ports=span(home,'    output wire private_digest_read_o,','\n);')
    text=replace(text,'    input  wire         private_endpoint_rsp_error_i\n);','    input  wire         private_endpoint_rsp_error_i,\n    input wire private_model_slot_i,\n    input wire [95:0] private_model_nonce_i,\n    input wire [31:0] private_session_epoch_i,\n'+ports+'\n);')
    text=replace(text,'.MODEL_NONCE(96\'h112233445566778899aabbcc)) u_auth (', '.MODEL_NONCE(96\'h112233445566778899aabbcc)) u_auth (\n        .private_model_slot_i(private_model_slot_i),.private_model_nonce_i(private_model_nonce_i),')
    text=replace(text,'.ddr_response_error_i(private_raw_rsp_error_i),.fault_o(auth_fault));','.ddr_response_error_i(private_raw_rsp_error_i),.fault_o(auth_fault),\n        .private_digest_read_o(private_digest_read_o),.private_digest_address_o(private_digest_address_o),.private_digest_data_i(private_digest_data_i),\n        .private_metadata_read_o(private_metadata_read_o),.private_metadata_address_o(private_metadata_address_o),.private_metadata_data_i(private_metadata_data_i));')
    text=replace(text,'.fail_closed_o(core_machine_fault)\n    );','.fail_closed_o(core_machine_fault),\n        .private_body_norm_read_o(private_body_norm_read_o),.private_head_norm_read_o(private_head_norm_read_o),\n        .private_body_norm_address_o(private_body_norm_address_o),.private_head_norm_address_o(private_head_norm_address_o),\n        .private_body_norm_data_i(private_body_norm_data_i),.private_head_norm_data_i(private_head_norm_data_i));')
    begin='    tang_private_kv_siv_bridge #(';end='        .clk(core_clk_i),.reset_n(reset_n_i),.clear_i(clear_i),.epoch_i(private_kv_epoch),'
    text=replace(text,span(text,begin,end),'    combined_kv_cipher u_kv_cipher (\n        .model_slot_i(private_model_slot_i),\n')
    text=replace(text,'.epoch_i(private_kv_epoch),','.epoch_i({private_session_epoch_i,private_kv_epoch[31:0]}),')
    text=replace(text,'assign kv_integrity_fault=guard_integrity_fault || kv_cipher_fault;','assign kv_integrity_fault=guard_integrity_fault || kv_cipher_fault || (|private_kv_epoch[63:32]);')
    derive('shared_token_probe.sv',text,'Join real signed norm/digest ports to encrypted inference; bind SIV to model-specific keys and non-wrapping session/CLEAR domain')
    wrappers=[('tang_private_aes256.sv','combined_weight_aes','',[
        {'KEY_IS_PROVISIONED':"1'b1",'KEY':"256'h"+KEYS['weight'+m]} for m in 'AB']),
        ('tang_private_aes256_pool2.sv','combined_weight_pool',' #(parameter integer BANKS=2)',[
        {'BANKS':'BANKS','KEY_IS_PROVISIONED':"1'b1",'KEY':"256'h"+KEYS['weight'+m]} for m in 'AB']),
        ('tang_private_kv_siv_bridge.sv','combined_kv_cipher','',[
        {'KEY_IS_PROVISIONED':"1'b1",'MAC_KEY':"256'h"+KEYS['mac'+m],'CTR_KEY':"256'h"+KEYS['ctr'+m]} for m in 'AB'])]
    for original,name,params,slots in wrappers:
        path=name+'.sv';derive(path,slot_wrapper((ENC/original).read_text(),name,params,slots),'Two-entry modeled private key vault selecting byte-identical full-round inherited engines');order.append(path)
    from lookup_binding import install
    install(source,order)
    (source/'sources.f').write_text('\n'.join(order)+'\n')
    (out/'PREPARED.json').write_text(json.dumps({'public_base':'6045f521d2f68eecf7caddd9e7df48522a718075','source':str(source),'origins':origins,'edits':edits,'compile_order':order,'keys_are_public_fixtures':True,'keys':KEYS,'nonces':NONCES,'physical_or_public_release_claim':False,'native_inference_run':False},indent=2,sort_keys=True)+'\n')
    print('PREPARED',len(order),'selected compile sources;',len(edits),'explicit derivations')

if __name__=='__main__': main()
