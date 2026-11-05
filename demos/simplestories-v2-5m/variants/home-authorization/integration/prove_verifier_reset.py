#!/usr/bin/env python3
"""Prove reset/start spacing and retained fail-closed gates in actual controller."""
import argparse,hashlib,json,subprocess
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--build',type=Path,required=True);p.add_argument('--output',type=Path,required=True);a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
buildroot=Path(json.loads((a.build/'STARTED.json').read_text())['directory'])
source=buildroot/'home_boot_gate.sv'
if not source.exists():source=buildroot/'project/home/home_boot_gate.sv'
s=source.read_text()
assert 'logic crypto_reset_release_q;' in s and 'ARM_WAIT=7' in s
end=s.index('\nendmodule')
s=s[:end]+'''
    always_comb if(reset_n)begin
        if(shared_start_o)assert(shared_reset_n_o);
        if(new_lease_o)assert(state_q==VERIFY && crypto_done && crypto_valid && !failed_o);
        if(failed_o)assert(!inference_enabled_o);
        if(state_q==ARM || state_q==ARM_WAIT)assert(!new_lease_o);
    end
    logic proof_past_valid=0;
    always_ff @(posedge clk)begin
        proof_past_valid<=1;
        if(proof_past_valid && reset_n && $past(reset_n))begin
            if(shared_start_o)assert($past(shared_reset_n_o));
            if($past(state_q)==START && state_q==VERIFY)begin
                assert(shared_reset_n_o);
                assert($past(shared_reset_n_o));
            end
        end
    end
'''+s[end:]
(out/'design.sv').write_text(s)
(out/'prove.ys').write_text('''read_verilog -formal -sv design.sv
chparam -set USE_SHARED_VERIFIER 1 -set RESPONSE_LIMIT_CYCLES 100000000 -set LEASE_CYCLES 250000000 -set RENEW_LEAD_CYCLES 125000000 home_boot_gate
prep -top home_boot_gate -flatten
delete home_boot_gate/shared_signature_byte_o
async2sync
memory_map
opt_clean
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps 12 -set clk 1 -set-at 1 reset_n 0 -set-def-inputs -dump_vcd failure.vcd
''')
r=subprocess.run(['yosys','-Q','-T','-l','proof.log','prove.ys'],cwd=out,capture_output=True,text=True);(out/'console.log').write_text(r.stdout+r.stderr)
ok=r.returncode==0 and 'Induction step proven: SUCCESS!'in r.stdout;sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
rec={'result':'PASS'if ok else'NOT_PROVEN','exit_code':r.returncode,'actual_controller_sha256':sha(source),'design_sha256':sha(out/'design.sv'),'log_sha256':sha(out/'proof.log'),
    'scope':'Actual controller at native25MHz timer parameters, arbitrary binary inputs and crypto verdicts. Start has reset released in previous sampled cycle, reset stays released across START-to-VERIFY, preparatory states cannot grant a lease, failure suppresses inference, lease grant requires the verified verdict. Clocked async2sync model, not an analog reset-glitch, physical timing, cryptography or complete security proof.'}
(out/'RESULT.json').write_text(json.dumps(rec,indent=2)+'\n');print(json.dumps(rec,indent=2));raise SystemExit(0 if ok else 1)
