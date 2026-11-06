#!/usr/bin/env python3
"""Join actual grant controller/RAM and LMS control after boot admission."""
import argparse,json
from pathlib import Path
from run_proofs import HERE,PROJECT,sha
from run_memory_proof import monitored
from run_next_proofs import inject
def design():
    gate=(PROJECT/'home/home_boot_gate.sv').read_text()
    old='''    output wire shared_signature_ready_o,
    input wire [10:0] shared_signature_address_i,
    input wire [7:0] shared_message_address_i,
    input wire shared_busy_i,shared_done_i,shared_valid_i,shared_fault_i'''
    assert gate.count(old)==1;gate=gate.replace(old,'    output wire shared_signature_ready_o')
    gate=inject(gate,(HERE/'controller_properties.sv').read_text()+'\n'+(HERE/'renewal_properties.sv').read_text()+'\n'+(HERE/'verifier_join_properties.sv').read_text())
    lms=(PROJECT/'swic/su_lms_verify.sv').read_text()
    old='input wire [255:0] shared_hash_digest_i';assert lms.count(old)==1
    lms=lms.replace(old,old+',\n    output wire proof_started_o,\n    output wire [127:0] proof_identifier_o,\n    output wire [255:0] proof_root_o,\n    output wire [8:0] proof_length_o')
    lms=inject(lms,(HERE/'verifier_properties.sv').read_text()+'''\n
    assign proof_started_o=spec_started;
    assign proof_identifier_o=spec_identifier;
    assign proof_root_o=spec_root;
    assign proof_length_o=spec_length;
    // These inputs are fixed by the enclosing lease-owner connection. Unlike
    // the reusable standalone verifier lemma, this joined lemma may therefore
    // retain their equality throughout the verifier epoch.
    always_comb if(reset_n && spec_started) begin
        assert(spec_identifier==public_i_i && spec_root==public_root_i && spec_length==message_length_i);
    end
''')
    return gate+'\n'+lms
def main():
    p=argparse.ArgumentParser();p.add_argument('--name',default='verifier-join-v1');p.add_argument('--depth',type=int,default=12);a=p.parse_args()
    out=HERE/'runs'/a.name;out.mkdir(exist_ok=False)
    for f,h in json.loads((HERE/'SOURCE-PINS.json').read_text())['files'].items():assert sha(PROJECT/f)==h,f
    (out/'design.sv').write_text(design())
    (out/'prove.ys').write_text('''read_verilog -formal -D SYNTHESIS -sv design.sv
chparam -set USE_SHARED_HASH 1 -set MAX_MESSAGE_BYTES 128 su_lms_verify
chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 -set DEVICE_ID 128'h395c83e440d5252bfa59f6138e5ed3b8 -set GEOMETRY 256'h2128664c0025b4ed2ddbd53b2178ea926fe1b3c5e817a2b043a2abc9ee41f078 -set HOME_KEY_ID 128'hc044bbc6bdd6530b85e435fd6184137a -set HOME_KEY_ROOT 256'h90c220be722a4b158990b9cff559c0eae3dfd5b45746f8363a1adfe0231556d2 home_boot_gate
prep -top home_boot_gate -flatten
async2sync
dffunmap
opt_clean
write_smt2 -wires model.smt2
''')
    (out/'STARTED.json').write_text(json.dumps({'runner_sha256':sha(Path(__file__)),'depth':a.depth,'post_admission_lease_owner':True,'actual_grant_and_lms_controllers':True,'grant_ram_retained':True,'hash_results_abstract':True},indent=2)+'\n')
    records={};records['prepare']=monitored(['yosys','-Q','-T','prove.ys'],out,'prepare');ok=records['prepare']['exit_code']==0
    if ok:
        for label,flag in [('induction',['-i']),('base',[])]:
            records[label]=monitored(['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t',str(a.depth),'--dump-vcd',label+'.vcd']+flag+['model.smt2'],out,label)
            ok=ok and records[label]['exit_code']==0 and 'Status: PASSED' in (out/(label+'.log')).read_text()
            if not ok:break
    r={'result':'PASS' if ok else 'NOT_PROVEN','records':records,'design_sha256':sha(out/'design.sv'),'scope':'Post-admission selected lease-owner connection of real home grant controller/RAM and real LMS controller. Lease grants require a start since the current verifier reset and the fixed home key/128-byte message length. Shared SHA results remain arbitrary; boot-owner prefix is discharged only through the explicit admission/ownership contract and source correspondence audit. Not LMS/SHA functional correctness.'}
    (out/'RESULT.json').write_text(json.dumps(r,indent=2)+'\n');print(json.dumps(r,indent=2));raise SystemExit(0 if ok else 1)
if __name__=='__main__':main()
