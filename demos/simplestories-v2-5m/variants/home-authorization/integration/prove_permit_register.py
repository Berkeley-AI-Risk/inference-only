#!/usr/bin/env python3
"""Prove the registered permit's clocked safety against the real home gate.

Crypto verdicts and external inputs are arbitrary binary values. This is not
a cryptographic, CDC, physical-reset, or whole-chip noninterference proof.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))
import permit_register
import shared_selector

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--output', type=Path, required=True)
p.add_argument('--response', type=int, default=50_000_000)
p.add_argument('--lease', type=int, default=125_000_000)
p.add_argument('--renew-lead', type=int, default=62_500_000)
p.add_argument('--shared-message-selector', action='store_true')
a = p.parse_args()
assert 1 < a.response < a.renew_lead < a.lease
out = a.output.resolve()
out.mkdir(parents=True, exist_ok=False)
source = ROOT / 'rtl/home_boot_gate.sv'
gate = source.read_text()
assert gate == (ROOT / 'integration/project/home/home_boot_gate.sv').read_text()
if a.shared_message_selector:
    gate = shared_selector.transform('home/home_boot_gate.sv', gate)
gate = gate.replace('input wire clk, reset_n,', 'input wire clk, reset_n,\n    input wire proof_stop_i,', 1)
reset = permit_register.transform('top.sv',
    '    wire token_reset_n=core_reset_n && home_enabled && !home_stop_q;')
for old, new in [('core_clk', 'clk'), ('core_reset_n', 'reset_n'),
                 ('home_failed', 'failed_o'), ('home_transport_fault', "1'b0"),
                 ('home_stop_q', 'proof_stop_i'), ('home_accepted', 'new_lease_o')]:
    reset = reset.replace(old, new)
assertions = '''
    always_comb if (reset_n) begin
        assert (!(state_q==SEND || state_q==RECEIVE || state_q==START || state_q==VERIFY || state_q==RUN) || have_root_q);
        assert (!lease_active_q || have_root_q);
        assert (!token_reset_n || lease_active_q);
        assert (!token_reset_n || (inference_enabled_o && !proof_stop_i));
    end
'''
gate = gate.replace('\nendmodule', '\n' + reset + '\n' + assertions + '\nendmodule', 1)
wrapper = f'''
module formal_top(input wire clk,reset_n,stop_i,nonce_valid,nonce_fault,root_valid,model_fault,
 input wire [255:0] nonce,root,input wire request_ready,grant_valid,grant_last,
 input wire [7:0] grant_byte,input wire crypto_busy,crypto_done,crypto_valid,crypto_fault);
 home_boot_gate #(.USE_SHARED_VERIFIER(1),.RESPONSE_LIMIT_CYCLES({a.response}),
 .LEASE_CYCLES({a.lease}),.RENEW_LEAD_CYCLES({a.renew_lead})) dut(
 .clk(clk),.reset_n(reset_n),.proof_stop_i(stop_i),.nonce_valid_i(nonce_valid),.nonce_fault_i(nonce_fault),
 .nonce_i(nonce),.admitted_root_valid_i(root_valid),.model_fault_i(model_fault),.admitted_root_i(root),
 .request_ready_i(request_ready),.grant_valid_i(grant_valid),.grant_last_i(grant_last),.grant_byte_i(grant_byte),
 .shared_signature_address_i(11'd0),.shared_message_address_i(8'd0),.shared_busy_i(crypto_busy),
 .shared_done_i(crypto_done),.shared_valid_i(crypto_valid),.shared_fault_i(crypto_fault));
endmodule
'''
(out / 'design.sv').write_text(gate + wrapper)
(out / 'prove.ys').write_text('''read_verilog -formal -sv design.sv
chparam -set USE_SHARED_VERIFIER 1 home_boot_gate
prep -top formal_top -flatten
async2sync
memory_map
opt_clean
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps 12 -set clk 1 -set-at 1 reset_n 0 -set-def-inputs -show-public -dump_vcd induction.vcd -dump_json induction.json
''')
digest = lambda f: hashlib.sha256(f.read_bytes()).hexdigest()
bound = [source, ROOT / 'integration/permit_register.py', ROOT / 'integration/shared_selector.py',
         Path(__file__).resolve(), out / 'design.sv', out / 'prove.ys']
inputs = {str(f): digest(f) for f in bound}
(out / 'INPUTS.json').write_text(json.dumps(inputs, indent=2) + '\n')
yosys = Path(shutil.which('yosys')).resolve()
command = [str(yosys), '-Q', '-T', '-l', 'proof.log', 'prove.ys']
started = time.monotonic()
with (out / 'console.log').open('w') as log:
    proc = subprocess.Popen(command, cwd=out, stdout=log, stderr=subprocess.STDOUT)
    (out / 'STARTED.json').write_text(json.dumps({'pid': proc.pid, 'command': command, 'directory': str(out)}, indent=2) + '\n')
    code = proc.wait()
assert all(digest(Path(f)) == sha for f, sha in inputs.items()), 'Proof inputs changed during run'
passed = code == 0 and 'Induction step proven: SUCCESS!' in (out / 'proof.log').read_text()
record = {'result': 'PASS' if passed else 'NOT_PROVEN', 'exit_code': code,
          'elapsed_seconds': time.monotonic() - started, 'yosys_sha256': digest(yosys),
          'response_cycles': a.response, 'lease_cycles': a.lease, 'renew_lead_cycles': a.renew_lead,
          'shared_message_selector': a.shared_message_selector,
          'method': 'Temporal induction from reset, with binary induction states and arbitrary binary inputs; async2sync clocked abstraction.',
          'property': 'Whenever the registered permit releases reset, the existing home gate permits inference and stop is clear.',
          'excluded': ['cryptographic correctness', 'entropy', 'analog or sub-cycle reset behavior', 'CDC', 'whole-chip noninterference'],
          'inputs_sha256': digest(out / 'INPUTS.json'), 'proof_log_sha256': digest(out / 'proof.log')}
(out / 'RESULT.json').write_text(json.dumps(record, indent=2) + '\n')
print(json.dumps(record, indent=2))
raise SystemExit(0 if passed else 1)
