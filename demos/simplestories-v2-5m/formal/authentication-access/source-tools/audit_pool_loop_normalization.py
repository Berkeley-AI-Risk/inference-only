"""Audit the stateless loop-scope lemma and exhaust its actual SV input table."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--out',type=Path,required=True)
    args=p.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    root=HERE/'runs/pool-loop-equivalence-r1';inputs=json.loads((root/'INPUTS.json').read_bytes())
    result=json.loads((root/'FINISHED.json').read_bytes())
    if not result['passed']or result['inputs_sha256']!=sha((root/'INPUTS.json').read_bytes()):raise ValueError('Equivalence lemma incomplete')
    if inputs['internal_cuts']or inputs['assumption_cells']or (root/'reset.smtc').read_bytes():raise ValueError('Lemma inputs are restricted')
    for n,row in inputs['files'].items():
        raw=(root/n).read_bytes()
        if row!={'bytes':len(raw),'sha256':sha(raw)}:raise ValueError('Lemma source changed')
    for phase,row in result['results'].items():
        if not row['passed']or row['status']!=['PASSED']or row['exit']!=0:raise ValueError('A lemma solver phase is incomplete')
        for ext,key in(('.log','log_sha256'),('.smt2','query_sha256'),('.responses','solver_responses_sha256')):
            if sha((root/(phase+ext)).read_bytes())!=row[key]:raise ValueError('Lemma solver evidence changed')
    graph=json.loads((root/'elaborated.json').read_bytes())['modules'][inputs['top']]
    for cell in graph['cells'].values():
        kind=cell['type'].lower()
        if any(x in kind for x in('ff','latch'))or kind in('$mem_v2','$anyseq','$anyconst','$assume'):
            raise ValueError('Loop equivalence is not a stateless total function')
    native=(root/'native-pool.sv').read_bytes();scoped=(root/'scoped-pool.sv').read_bytes()
    expected=native.replace(b'integer engine,offset,slot,bank;',b'integer engine,slot,bank;',1).replace(
        b'for(offset=0;offset<GROUP_BANKS;offset=offset+1)',b'for(integer offset=0;offset<GROUP_BANKS;offset=offset+1)',1)
    if expected!=scoped:raise ValueError('A native expression or bound changed')
    production=(HERE/'runs/encrypted-hash-owner-r2-scoped-loop/production-sha.sv').read_bytes()
    a=production.index(b'module tang_private_sha256_pool2 #(');b=production.index(b'\nendmodule',a)+len(b'\nendmodule')
    if native!=production[a:b]:raise ValueError('Native pool differs from the actual released source')
    # Both actual always_comb bodies are simulated, including the original
    # module-scope temporary. This independent SV frontend exhausts all 15
    # current input bits. The SMT proof above establishes statelessness.
    leaves=(root/'equivalence.sv').read_text().split('module pool_loop_equivalence',1)[0]
    if leaves.count('always @*')!=1:raise ValueError('Native event-spelling boundary changed')
    leaves=leaves.replace('always @*','always_comb',1)
    tb='''module exhaustive;
    reg enabled;reg [1:0] engine_busy,engine_done,rr_i;
    reg [3:0] request_valid_i,pending_q;
    wire [3:0] ready0,ready1,bank0,bank1;wire [1:0] valid0,valid1,slot0,slot1;
    native_arb a(.enabled(enabled),.engine_busy(engine_busy),.engine_done(engine_done),.rr_i(rr_i),
        .request_valid_i(request_valid_i),.pending_q(pending_q),.request_ready_o(ready0),
        .grant_valid(valid0),.slot_o(slot0),.bank_o(bank0));
    scoped_arb b(.enabled(enabled),.engine_busy(engine_busy),.engine_done(engine_done),.rr_i(rr_i),
        .request_valid_i(request_valid_i),.pending_q(pending_q),.request_ready_o(ready1),
        .grant_valid(valid1),.slot_o(slot1),.bank_o(bank1));
    integer row;
    initial begin
        for(row=0;row<32768;row=row+1) begin
            {enabled,engine_busy,engine_done,rr_i,request_valid_i,pending_q}=15'(row);
            #1;
            if({ready0,valid0,slot0,bank0}!=={ready1,valid1,slot1,bank1})
                $fatal(1,"native/scoped arbiter mismatch at row %0d",row);
        end
        $display("PASS all 32768 input combinations");$finish;
    end
endmodule
'''
    (out/'exhaustive.sv').write_text(leaves+tb)
    command=['iverilog','-g2012','-s','exhaustive','-o','exhaustive.vvp','exhaustive.sv']
    cp=subprocess.run(command,cwd=out,capture_output=True,timeout=30)
    (out/'compile.log').write_bytes(cp.stdout+cp.stderr)
    if cp.returncode:raise ValueError('Independent SV frontend failed')
    cp=subprocess.run(['vvp','exhaustive.vvp'],cwd=out,capture_output=True,timeout=45)
    log=cp.stdout+cp.stderr;(out/'exhaustive.log').write_bytes(log)
    if cp.returncode or b'PASS all 32768 input combinations'not in log:raise ValueError('Exhaustive SV equivalence failed')
    receipt=dict(schema='native-private-loop-scope-equivalence-audit-v1',passed=True,
        source_reversal=True,native_module_sha256=sha(native),scoped_module_sha256=sha(scoped),
        lemma_finished_sha256=sha((root/'FINISHED.json').read_bytes()),both_solver_all_phases_passed=True,
        model_is_total_stateless_function=True,no_data_cuts_or_input_assumptions=True,
        actual_always_comb_bodies_exhaustively_checked_with_independent_SV_frontend=True,
        free_input_bits=15,combinations=32768,source_sha256=sha((leaves+tb).encode()),log_sha256=sha(log),
        compiler_sha256=sha(Path(shutil.which('iverilog')).read_bytes()),
        scope='Narrower scope of the unused procedural offset loop variable preserves every native arbiter output, with exact native bounds/expressions and all 15 current input bits free. No RTL output/state is cut. This discharges the documented frontend normalization in four-bank pool proofs; it does not establish ownership, hash arithmetic, bitstream equivalence or physical behavior.')
    (out/'FINISHED.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    (HERE/'POOL-LOOP-NORMALIZATION-AUDIT.json').write_text(json.dumps(receipt,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(passed=True,combinations=32768,stateless=True)))


if __name__=='__main__':main()
