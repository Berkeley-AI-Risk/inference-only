#!/usr/bin/env python3
"""Source-derived model-lock guard cone and real boot-to-home verifier handoff."""
import argparse,json,re
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
from run_memory_proof import monitored
from run_next_proofs import inject
ADDED=['booted_memory.sv','handoff.sv','swic/swic_ddr_boot.sv',
       'swic/su_page_table_check.sv','swic/su_image_check.sv','swic/su_sha256.sv']
def extract_instance(s,name):
    m=re.search(r'\b'+name+r'\s*\(',s);assert m,name
    i=m.end();d=1
    while d:
        if s[i]=='(':d+=1
        if s[i]==')':d-=1
        i+=1
    assert s[i]==';';return m.end(),i-1,i+1
def assign(file,name):
    s=(PROJECT/file).read_text();m=re.search(r'assign\s+'+name+r'\s*=([^;]+);',s);assert m
    return m[1].strip()
def lock_design():
    ingress=assign('swic/swic_boot_ingress.sv','allow_model_o').replace('admitted','sealed_i').replace('fault_o','ingress_fault_i')
    boot=assign('swic/swic_ddr_boot.sv','boot_locked_o').replace('state_q==LOCKED','boot_state_locked_i').replace('admitted_i','source_ready').replace('fault_o','boot_fault_i')
    handoff=assign('handoff.sv','runtime_locked_o').replace('runtime_q','runtime_owned_i').replace('boot_locked_i','boot_locked').replace('fault_o','handoff_fault_i')
    memory=assign('booted_memory.sv','private_model_locked_o').replace('fault_q','memory_fault_i')
    return f'''module model_lock_origin(
      input wire sealed_i,slot_done_q,ingress_fault_i,boot_state_locked_i,
      input wire image_verified,page_verified,lut_ok_q,norm_loaded,boot_fault_i,runtime_owned_i,handoff_fault_i,reset_n,memory_fault_i);
      wire source_ready={ingress};
      wire boot_locked={boot};
      wire handoff_locked={handoff};
      wire private_model_locked_o={memory};
      always_comb begin
        if(private_model_locked_o) assert(sealed_i && source_ready && boot_locked && reset_n && page_verified);
        if(!sealed_i) assert(!private_model_locked_o);
        if(!page_verified) assert(!private_model_locked_o);
      end
    endmodule
'''
def owner_design():
    return '''module owner_factor(input wire [3:0] state_q,input wire fault_q,root_fault,lms_fault,SHARE_VERIFIER);
      localparam [3:0] RUN=8,AUTH_WAIT=7;
      wire fail_closed_o=fault_q || root_fault || (state_q==AUTH_WAIT && lms_fault);
      wire sealed_o=state_q==RUN && !fail_closed_o;
      wire original_owner=SHARE_VERIFIER && sealed_o;
      wire factored_owner=SHARE_VERIFIER && state_q==RUN && !fault_q && !root_fault;
      always_comb assert(original_owner==factored_owner);
    endmodule
'''
def handoff_design(observe=False,mutant=None):
    parent=(PROJECT/'swic/swic_boot_admission.sv').read_text()
    # Equivalent binary factorization removes an async2sync-created structural
    # SCC through the phase-exclusive AUTH_WAIT fault term. owner_factor proves
    # this rewrite for every state/flag value; production RTL is unchanged.
    old='wire lease_owner=SHARE_VERIFIER && sealed_o;';assert parent.count(old)==1
    parent=parent.replace(old,'wire lease_owner=SHARE_VERIFIER && state_q==RUN && !fault_q && !root_fault;')
    remove=['    input wire lease_crypto_reset_n_i,lease_crypto_start_i,\n','    input wire [127:0] lease_key_id_i,\n','    input wire [255:0] lease_key_root_i,\n','    input wire [7:0] lease_signature_byte_i,lease_message_byte_i,\n','    input wire lease_signature_ready_i,\n']
    for s in remove:assert parent.count(s)==1;parent=parent.replace(s,'')
    _,_,end=extract_instance(parent,'u_root');start=parent.rfind('    su_sha256 #',0,end);assert start>=0
    root_instance=parent[start:end]
    parent=parent[:start]+parent[end:]
    header_end=parent.index('\n);')
    parent=parent[:header_end]+',\n    input wire proof_sha_ready,proof_sha_busy,proof_sha_done,proof_sha_fault,\n    input wire [31:0] proof_sha_offset,\n    input wire [255:0] proof_sha_digest'+parent[header_end:]
    cut='''
    assign root_ready=proof_sha_ready;assign root_busy=proof_sha_busy;
    assign root_done=proof_sha_done;assign root_fault=proof_sha_fault;
    assign root_offset=proof_sha_offset;assign root_digest=proof_sha_digest;
'''
    _,close,_=extract_instance(parent,'u_lms')
    parent=parent[:close]+''',
        .proof_lease_owner_i(lease_owner),.proof_started_o(proof_verifier_started),
        .proof_lease_epoch_o(proof_verifier_lease_epoch),.proof_identifier_o(proof_verifier_identifier),
        .proof_root_o(proof_verifier_root),.proof_length_o(proof_verifier_length)'''+parent[close:]
    parent=inject(parent,cut+'\n'+(HERE/'boot_handoff_properties.sv').read_text())
    home=(PROJECT/'home/home_boot_gate.sv').read_text()
    old='input wire shared_busy_i,shared_done_i,shared_valid_i,shared_fault_i';assert home.count(old)==1
    home=home.replace(old,old+',\n    output wire proof_have_root_o,\n    output wire [3:0] proof_state_o')
    home=inject(home,'''
    assign proof_have_root_o=have_root_q;assign proof_state_o=state_q;
    always_comb if(reset_n) begin
        assert(state_q==COLLECT || state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
               state_q==START || state_q==VERIFY || state_q==RUN || state_q==FAIL);
        if(fault_q) assert(state_q==FAIL);
        if(state_q==SEND || state_q==RECEIVE || state_q==ARM || state_q==ARM_WAIT ||
           state_q==START || state_q==VERIFY || state_q==RUN) assert(have_root_q);
        if(!have_root_q) assert(state_q==COLLECT || state_q==FAIL);
    end
''')
    lms=(PROJECT/'swic/su_lms_verify.sv').read_text();old='input wire [255:0] shared_hash_digest_i';assert lms.count(old)==1
    lms=lms.replace(old,old+',\n    input wire proof_lease_owner_i,\n    output wire proof_started_o,proof_lease_epoch_o,\n    output wire [127:0] proof_identifier_o,\n    output wire [255:0] proof_root_o,\n    output wire [8:0] proof_length_o')
    lms=inject(lms,(HERE/'verifier_properties.sv').read_text()+'''
    logic spec_lease_epoch;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n)spec_lease_epoch<=0;
        else if(start_i && state_q==IDLE && !hash_fault)spec_lease_epoch<=proof_lease_owner_i;
    end
    assign proof_started_o=spec_started;assign proof_lease_epoch_o=spec_lease_epoch;
    assign proof_identifier_o=spec_identifier;assign proof_root_o=spec_root;assign proof_length_o=spec_length;
''')
    if observe:
        ports=[]
        pattern=r'\(\* anyseq \*\) wire (?:\[[^]]+\] )?[^;]+;'
        for match in list(re.finditer(pattern,parent)):
            declaration=match[0].replace('(* anyseq *) wire','input wire').rstrip(';')
            ports.append(declaration);parent=parent.replace(match[0],'')
        ports+=['output wire observe_lms_hash_selected,observe_lease_owner,observe_lms_reset,observe_lms_done,observe_lms_valid,observe_lease_epoch,observe_home_enabled,observe_home_failed,observe_home_grant,observe_request_valid,observe_request_last,observe_grant_ready',
                'output wire [7:0] observe_request_byte','output wire [255:0] observe_selected_key_root']
        end=parent.index('\n);');parent=parent[:end]+',\n    '+',\n    '.join(ports)+parent[end:]
        parent=parent.replace('.request_ready_i(proof_request_ready),','.request_ready_i(proof_request_ready),.request_valid_o(observe_request_valid),.request_byte_o(observe_request_byte),.request_last_o(observe_request_last),.grant_ready_o(observe_grant_ready),')
        parent=inject(parent,'''
    assign observe_lms_hash_selected=lms_hash_selected;assign observe_lease_owner=lease_owner;
    assign observe_lms_reset=selected_lms_reset_n;assign observe_lms_done=lms_done;assign observe_lms_valid=lms_valid;
    assign observe_lease_epoch=proof_verifier_lease_epoch;assign observe_home_enabled=proof_home_enabled;
    assign observe_home_failed=proof_home_failed;assign observe_home_grant=proof_home_grant;
    assign observe_selected_key_root=lease_owner ? lease_key_root_i : su_authority_root(key_q);
''')
    if mutant=='reset-bypass':
        old='assign selected_lms_reset_n=lease_owner ? lease_crypto_reset_n_i : lms_reset_n;';assert parent.count(old)==1
        parent=parent.replace(old,"assign selected_lms_reset_n=lease_owner ? 1'b1 : lms_reset_n;")
    return parent+'\n'+home+'\n'+lms,{'cut_instance':'u_root','cut_sha256_instance_sha256':__import__('hashlib').sha256(root_instance.encode()).hexdigest(),'retained_real_admission_controller':True,'retained_real_signature_and_manifest_memories':True,'retained_real_shared_lms_controller':True,'abstracted_shared_sha_outputs':True}
def main():
    p=argparse.ArgumentParser();p.add_argument('job',choices=['pin','model-lock','owner-factor','boot-handoff']);p.add_argument('--name');p.add_argument('--depth',type=int,default=4);p.add_argument('--mutant',choices=['reset-bypass','admission-guard']);a=p.parse_args()
    pin=HERE/'BOOT-SOURCE-PINS.json'
    if a.job=='pin':
        assert not pin.exists();pin.write_text(json.dumps({'public_commit':'c7ea55dba49bb64bd99a601421bb42cb9e6e8347','files':{f:sha(PROJECT/f) for f in ADDED}},indent=2)+'\n');print(pin);return
    for manifest in ['SOURCE-PINS.json','BOOT-SOURCE-PINS.json']:
        for f,h in json.loads((HERE/manifest).read_text())['files'].items():assert sha(PROJECT/f)==h,f
    out=HERE/'runs'/(a.name or a.job+'-v1');out.mkdir(exist_ok=False)
    if a.job in ['model-lock','owner-factor']:
        design=lock_design() if a.job=='model-lock' else owner_design();top='model_lock_origin' if a.job=='model-lock' else 'owner_factor'
        if a.mutant=='admission-guard':
            old='boot_state_locked_i && source_ready &&';assert design.count(old)==1;design=design.replace(old,'boot_state_locked_i &&')
        recipe=f'''read_verilog -formal -sv design.sv
prep -top {top} -flatten
chformal -lower
sat -verify -prove-asserts -set-def-inputs -show-ports -dump_vcd failure.vcd
'''
    else:
        design,extraction=handoff_design(mutant=a.mutant);(out/'EXTRACTION.json').write_text(json.dumps(extraction,indent=2)+'\n')
        recipe='''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set USE_SHARED_HASH 1 -set MAX_MESSAGE_BYTES 128 su_lms_verify
chparam -set SHARE_VERIFIER 1 -set SHARE_NONCE_HASH 1 -set SHARE_LMS_HASH 1 swic_boot_admission
prep -top swic_boot_admission -flatten
delete swic_boot_admission/digest_data_o swic_boot_admission/metadata_data_o
async2sync
dffunmap
opt -full
dffunmap
write_smt2 -wires model.smt2
'''
    (out/'design.sv').write_text(design);(out/'prove.ys').write_text(recipe)
    (out/'STARTED.json').write_text(json.dumps({'job':a.job,'depth':a.depth,'runner_sha256':sha(Path(__file__)),'source_pins_sha256':sha(HERE/'BOOT-SOURCE-PINS.json')},indent=2)+'\n')
    records={};records['prepare']=monitored(['yosys','-Q','-T','prove.ys'],out,'prepare');ok=records['prepare']['exit_code']==0
    if a.job in ['model-lock','owner-factor']:ok=ok and 'SAT proof finished - no model found: SUCCESS!' in (out/'prepare.log').read_text()
    elif ok:
        for label,flag in [('induction',['-i']),('base',[])]:
            records[label]=monitored(['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t',str(a.depth),'--dump-vcd',label+'.vcd']+flag+['model.smt2'],out,label)
            ok=records[label]['exit_code']==0 and 'Status: PASSED' in (out/(label+'.log')).read_text()
            if not ok:break
    r={'result':'PASS' if ok else 'NOT_PROVEN','job':a.job,'records':records,'design_sha256':sha(out/'design.sv'),'scope':'Source-derived actual admission-to-model-lock guard cone (all hidden state arbitrary), or full actual admission-controller/shared-verifier/home-controller handoff with real signature/manifest RAM and abstract shared-SHA results. Proves ownership/reset/epoch isolation, not SHA/LMS algorithm or boot payload numerical correctness.'}
    (out/'RESULT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__':main()
