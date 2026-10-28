"""Native typed K/V cache: pending ownership and CLEAR/drain normal form.

Both actual cache source classes retain all payload RAMs and mapper children.
This scope checks cancellation/control, separately from payload correspondence
and the protected guard's published checked-copy/hash theorems.
"""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load


TOP='board1_context2048_atomic_kv_typed'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variant',choices=('baseline','kv-protected'),default='baseline')
    ap.add_argument('--mutant',action='store_true',help='Negative control: drop the actual pending-write owner on CLEAR.')
    ap.add_argument('--base-depth',type=int,default=2)
    ap.add_argument('--induction-depth',type=int,default=1)
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=30)
    args=ap.parse_args();baseline=args.variant=='baseline'
    builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py')
    builder.ROOTS['kv-cache']=TOP
    files,binding,count,covers=builder.derive(HERE.parents[1]/'fpga-demo/public-release',args.variant,'kv-cache')
    if count or covers:raise ValueError('Unexpected imported property inventory')
    source=files[TOP+'.sv'].decode()
    if args.mutant:
        old="if (clear_i)\n                        write_aborted_q <= 1'b1;"
        new="if (clear_i) begin\n                        write_aborted_q <= 1'b1;\n                        state_q <= ST_IDLE;\n                    end"
        if source.count(old)!=1:raise ValueError('Native pending-write cancellation branch changed')
        source=source.replace(old,new,1)
    monitor='''
    reg f_active=0,f_any_reset=0,f_clear_seen=0,f_quiet=0,f_cleared_pending=0;
    reg[1:0]f_write_pending=0;
    reg[4:0]f_read_pending=0;
    wire f_request_write=kv_write_req_valid_o && kv_write_req_ready_i;
    wire f_retire_write=kv_write_cpl_valid_i && kv_write_cpl_ready_o;
    wire f_request_read=kv_read_req_valid_o && kv_read_req_ready_i;
    wire f_retire_read=kv_read_rsp_valid_i && kv_read_rsp_ready_o;
    wire f_arm=reset_n && model_locked_i && !fault_q && !terminal_fault_now &&
        !write_aborted_q && !read_aborted_q && READ_EMPTY &&
        (state_q==ST_IDLE || state_q==ST_WRITE_REQ || state_q==ST_READ_REQ);
    wire f_scope=f_active || f_arm;
    wire f_new_upper=(stage_begin_valid_i && stage_begin_ready_o) ||
        (commit_valid_i && commit_ready_o) || (attention_req_valid_i && attention_req_ready_o);
    always @(posedge clk)begin
        if(!reset_n)begin
            f_active<=0;f_any_reset<=1;f_clear_seen<=0;f_quiet<=0;
            f_write_pending<=0;f_read_pending<=0;f_cleared_pending<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_write_pending<=(f_active ? f_write_pending : 2'd0)+{1'b0,f_request_write}-{1'b0,f_retire_write};
                f_read_pending<=(f_active ? f_read_pending : 5'd0)+{4'd0,f_request_read}-{4'd0,f_retire_read};
            end
            if(clear_i && f_scope)begin
                f_clear_seen<=1;f_quiet<=1;
                if(f_active && (f_write_pending!=0 || f_read_pending!=0))f_cleared_pending<=1;
            end else if(f_new_upper)f_quiet<=0;
        end
    end
    wire f_healthy=reset_n && f_scope && !fault_q;
    always @*if(reset_n && !f_active)begin
        assert(f_write_pending==0 && f_read_pending==0);assert(!f_clear_seen);
    end
    always @*if(f_healthy)begin
        assert(state_q<=LAST_STATE);
        assert(f_write_pending=={1'b0,(state_q==ST_WRITE_WAIT)});
        assert(f_read_pending==READ_PENDING);
        assert(f_read_pending<=READ_LIMIT);
        if(f_read_pending!=0)assert(READ_STATE);
        if(f_write_pending!=0)assert(f_read_pending==0);
        if(!busy_o)assert(f_write_pending==0 && f_read_pending==0);
        if(clear_i)assert(!kv_write_req_valid_o && !kv_read_req_valid_o);
        if(f_clear_seen && f_quiet)begin
            assert(state_q==ST_IDLE || state_q==ST_WRITE_WAIT || READ_STATE || state_q==ST_RESPONSE);
            if(state_q==ST_WRITE_WAIT)assert(write_aborted_q);
            if(READ_STATE)assert(read_aborted_q);
            assert(!kv_write_req_valid_o && !kv_read_req_valid_o);
            assert(!pending_complete_o);
            if(attention_rsp_valid_o)begin
                assert(attention_rsp_fault_o && !attention_rsp_from_pending_o);
                assert(attention_rsp_key_vector_o==0 && attention_rsp_value_vector_o==0);
                assert(attention_rsp_key_exponent_o==0 && attention_rsp_value_exponent_o==0);
            end
            assert(!pending_persisted_q && pending_layer_q==0 && pending_position_q==0 && expected_coordinate_q==0);
CACHE_INVALID
'''
    monitor=monitor.replace('READ_EMPTY','read_outstanding_q==0'if baseline else"1'b1")
    monitor=monitor.replace('READ_PENDING',"{1'b0,read_outstanding_q}"if baseline else"{4'd0,(state_q==ST_READ_WAIT)}")
    monitor=monitor.replace('READ_STATE','read_collect_state'if baseline else'(state_q==ST_READ_WAIT)')
    monitor=monitor.replace('READ_LIMIT','8'if baseline else'1').replace('LAST_STATE','ST_PENDING_READ'if baseline else'ST_PENDING_LOAD')
    monitor=monitor.replace('CACHE_INVALID','            assert(!cache_valid_q);'if baseline else'')
    for i in range(6):monitor+='            assert(committed_prefix_q['+str(i)+']==0);\n'
    monitor+='''
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_write_pending!=0);
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_read_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && busy_o && (f_write_pending!=0 || f_read_pending!=0));
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && !busy_o && f_write_pending==0 && f_read_pending==0);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files[TOP+'.sv']=source.encode();files['session-drain-monitor.inc.sv']=monitor.encode()
    files['session-drain-runner.py']=Path(__file__).read_bytes()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);wrapper='module native_kv_session(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+TOP+' u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n';files['wrapper.sv']=wrapper.encode()
    binding.update(initial_hard_reset=False,concrete_hierarchy_modules=sorted(binding['isolated_native_modules']),
        actual_all_native_RAMs_retained=True,read_credit_limit=8 if baseline else 1,
        entry_policy='Tracking begins at native IDLE or an empty pre-request WRITE_REQ/READ_REQ boundary with healthy control and no typed outstanding work. Existing current tensor/row payload may be arbitrary; no physical reset or empty-at-CLEAR prerequisite.')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_kv_session',
        reset_constraints='initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=monitor.count('assert('),covers=4,binding=binding,cuts=[],depth=args.base_depth,induction_depth=args.induction_depth,
        mutant='Drop native pending typed-write owner on CLEAR before its completion' if args.mutant else None,
        cover_depth=10,timeout=args.timeout,source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual '+args.variant+' typed K/V cache with native RAMs and every mapper child retained. Accepted writes/reads remain owed across busy CLEAR until actual completions/responses. Healthy busy-low implies no owed typed work. Quiet CLEAR revokes prefixes/pending authority and suppresses requests/data publication until new upper work. Pre-request covers may start with already captured current data. Guard/outer transport and full data/session correspondence remain separate.')


if __name__=='__main__':raise SystemExit(main())
