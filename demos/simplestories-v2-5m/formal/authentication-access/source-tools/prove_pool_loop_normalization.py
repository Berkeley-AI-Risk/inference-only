"""Universal combinational equivalence of native/scoped pool loop temporaries.

The original arbiter body is retained verbatim with always @* event spelling
so Yosys can remove its unused module-scope loop-index latch. This block calls
no functions and has the same complete read sensitivity in both spellings.
No latch/data value is cut: the optimized miter must be wholly stateless.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def load(name,path):
    spec=importlib.util.spec_from_file_location('_pool_loop_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def leaf(name,body):
    return('''module '''+name+'''(
    input wire enabled,
    input wire [1:0] engine_busy,engine_done,rr_i,
    input wire [3:0] request_valid_i,pending_q,
    output logic [3:0] request_ready_o,
    output logic [1:0] grant_valid,
    output wire [1:0] slot_o,
    output wire [3:0] bank_o
);
    localparam integer GROUP_BANKS=2,SLOT_W=1,BANK_W=2;
    wire [SLOT_W-1:0] rr_q[0:1];
    assign rr_q[0]=rr_i[0];assign rr_q[1]=rr_i[1];
    logic [SLOT_W-1:0] grant_slot[0:1];
    logic [BANK_W-1:0] grant_bank[0:1];
    assign slot_o={grant_slot[1],grant_slot[0]};
    assign bank_o={grant_bank[1],grant_bank[0]};
'''+body+'\nendmodule\n')


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--run',type=Path,required=True)
    args=p.parse_args();parent=HERE/'runs/encrypted-hash-owner-r2-scoped-loop'
    original=(parent/'pool-loop-native.sv').read_text();scoped=(parent/'pool-loop-scoped.sv').read_text()
    def block(text):
        a=text.index('    integer engine,');b=text.index('    integer e;',a);return text[a:b]
    native_body=block(original);scoped_body=block(scoped)
    expected=native_body.replace('integer engine,offset,slot,bank;','integer engine,slot,bank;',1).replace(
        'for(offset=0;offset<GROUP_BANKS;offset=offset+1)','for(integer offset=0;offset<GROUP_BANKS;offset=offset+1)',1)
    if expected!=scoped_body:raise ValueError('Scope normalization changed more than the private temporary declaration')
    if native_body.count('always_comb')!=1 or re.search(r'\bfunction\b',native_body):raise ValueError('Event-sensitivity translation requires review')
    sources=leaf('native_arb',native_body.replace('always_comb','always @*',1))+leaf('scoped_arb',scoped_body)
    sources+='''module pool_loop_equivalence(
    input wire enabled,input wire [1:0] engine_busy,engine_done,rr_i,
    input wire [3:0] request_valid_i,pending_q
);
    wire [3:0] ready0,ready1,bank0,bank1;
    wire [1:0] valid0,valid1,slot0,slot1;
    native_arb u_native(.enabled(enabled),.engine_busy(engine_busy),.engine_done(engine_done),.rr_i(rr_i),
        .request_valid_i(request_valid_i),.pending_q(pending_q),.request_ready_o(ready0),
        .grant_valid(valid0),.slot_o(slot0),.bank_o(bank0));
    scoped_arb u_scoped(.enabled(enabled),.engine_busy(engine_busy),.engine_done(engine_done),.rr_i(rr_i),
        .request_valid_i(request_valid_i),.pending_q(pending_q),.request_ready_o(ready1),
        .grant_valid(valid1),.slot_o(slot1),.bank_o(bank1));
    always_comb begin
        assert({ready0,valid0,slot0,bank0}=={ready1,valid1,slot1,bank1});
        cover(ready0==4'b0011);
    end
endmodule
'''
    engine=load('engine',HERE/'engine.py')
    return engine.check(args.run,{'equivalence.sv':sources.encode(),'native-pool.sv':original.encode(),
        'scoped-pool.sv':scoped.encode(),'runner.py':Path(__file__).read_bytes()},top='pool_loop_equivalence',
        reset_constraints='',assertions=1,covers=1,cuts=[],depth=1,induction_depth=1,cover_depth=1,timeout=45,
        binding=dict(parent_run=parent.name,native_banks=4,native_pool_sha256=sha(original.encode()),
            scoped_pool_sha256=sha(scoped.encode()),all_current_control_inputs_unrestricted=True,
            identical_native_arbiter_body_except_unused_temporary_scope=True,
            original_event_spelling='always @* in the miter only; complete read sensitivity; no function calls',
            stateless_model_audit_required=True),source_list=['equivalence.sv'],optimize_full=True,
        scope='Universal current-input/output equivalence of the exact native four-bank arbiter and its narrower loop-index scope. No native expression, loop bound or observable net is changed. The original body uses always @* in this miter to let the frontend remove its unused index latch; stateless optimized-graph audit is required. This is a frontend loop normalization lemma, not pool ownership or SHA correctness.')


if __name__=='__main__':raise SystemExit(main())
