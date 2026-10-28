"""Actual semantic parent DDR accounting and busy barrier across public CLEAR."""
import argparse
import json
from pathlib import Path

from run_attention_ownership import HERE, load
from run_semantic_relational import erase_checks


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    prior=HERE/'runs/semantic-result-clear-r8';pi=json.loads((prior/'INPUTS.json').read_text())
    original=(prior/'production-datapath.sv').read_bytes()
    source=erase_checks((prior/'datapath.sv').read_text())
    monitor='''
    reg f_active=0,f_any_reset=0,f_cleared_pending=0;
    reg[4:0]f_pending=0;
    wire f_arm=rst_n && !ddr_arbiter_fault_q && ddr_owner_q==DDR_NONE && ddr_pending_q==0;
    wire f_scope=f_active || f_arm;
    always @(posedge clk)begin
        if(!rst_n)begin
            f_active<=0;f_pending<=0;f_any_reset<=1;f_cleared_pending<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_pending<=(f_active ? f_pending : 5'd0)+{4'd0,ddr_request_fire}-{4'd0,ddr_response_fire};
            end
            if(clear_i && f_active && f_pending!=0)f_cleared_pending<=1;
        end
    end
    wire f_healthy=rst_n && f_scope && !ddr_arbiter_fault_q;
    always @*if(rst_n && !f_active)assert(f_pending==0);
    always @*if(f_healthy)begin
        assert(ddr_owner_q<=DDR_LOOK);
        assert(ddr_pending_q<=8);
        assert((ddr_pending_q==0)==(ddr_owner_q==DDR_NONE));
        if(ddr_owner_q==DDR_LOOK)assert(ddr_pending_q==1);
        assert(f_pending=={1'b0,ddr_pending_q});
        if(!busy_o)assert(f_pending==0);
        if(clear_i)assert(!private_word_req_valid_o);
        if(ddr_response_fire)assert(f_pending!=0);
        if(ddr_owner_q==DDR_PROJ)assert(!lookup_word_rsp_valid);
        if(ddr_owner_q==DDR_LOOK)assert(!projection_word_rsp_valid);
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_pending!=0 && !fault_q);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && busy_o && f_pending!=0 && !fault_q);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && !busy_o && f_pending==0 && !fault_q);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);top='board1_context2048_semantic_datapath'
    wrapper='module semantic_drain(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files={'production-datapath.sv':original,'datapath.sv':source.encode(),'wrapper.sv':wrapper.encode(),
        'drain-monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='semantic_drain',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=monitor.count('assert('),covers=3,binding=dict(native_join=pi['binding']['native_join'],
            variant='baseline',initial_hard_reset=False,concrete_module=top,
            entry_policy='Tracking begins at empty native DDR owner/count without arbiter fault; no physical reset or empty-at-CLEAR prerequisite.',
            observer_pending_bits=5,clear_resets_pending_observer=False),cuts=pi['internal_cuts'],
        depth=4,induction_depth=4,cover_depth=8,timeout=args.timeout,
        source_list=['datapath.sv','wrapper.sv'],primary_only=True,optimize_full=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual native semantic DDR owner/count, admission cap and response routing. Accepted model reads remain owed across CLEAR until actual reply consumption. Healthy busy-low implies zero pending reads. No initial physical reset; numerical/RAM child replies unrestricted. Source wiring to core transport and enclosing public-ready barrier remain separate composition obligations.')


if __name__=='__main__':raise SystemExit(main())
