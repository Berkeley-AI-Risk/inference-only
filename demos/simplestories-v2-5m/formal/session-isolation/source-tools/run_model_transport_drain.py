"""Actual four core FIFOs + 16-owner arbiter: history and drain conservation.

Extract functional connections verbatim from the native core. No FIFO is
aborted on public CLEAR. Track requests at the actual client-side acceptance
and retire them only at actual client-side response consumption. Client FSM
busy-to-pending and the enclosing public-ready barrier remain separate joins.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25);ap.add_argument('--mutant',action='store_true')
    ap.add_argument('--client-counts',action='store_true')
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release','baseline')
    definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):definitions[m[1]]=(m[0],name,raw)
    fifo_name='board1_ddr_request_fifo2';arb_name='board1_fixed_private_ddr_arbiter';core_name='board1_context2048_token_machine_core'
    fifo,fp,fo=definitions[fifo_name];arb,apath,ao=definitions[arb_name];core,cp,co=definitions[core_name]
    start=core.index('    wire shell_queued_req_valid, shell_queued_req_ready;')
    end=core.index('    always_comb begin',start)
    block=core[start:end]
    if block.count('.abort_i(1\'b0)')!=4:raise ValueError('Public CLEAR now affects a native local FIFO abort')
    scopes=[('shell_request','shell_model_request_queue'),('shell_response','shell_model_response_queue'),
        ('layer_request','layer_model_request_queue'),('layer_response','layer_model_response_queue')]
    fifo_monitor='''
    reg [1:0] f_owned=0;
    reg f_ref_write[0:1];
    reg [ADDR_W-1:0] f_ref_addr[0:1];
    reg [255:0] f_ref_data[0:1];
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)f_owned<=0;
        else if(!f_scope_i)f_owned<=0;
        else begin
            if(push)begin
                f_owned[wr_ptr_q]<=1;
                f_ref_write[wr_ptr_q]<=in_write_i;f_ref_addr[wr_ptr_q]<=in_addr_i;f_ref_data[wr_ptr_q]<=in_data_i;
            end
            if(pop)f_owned[rd_ptr_q]<=0;
        end
    end
    always @*if(reset_n && f_scope_i)begin
        assert(count_q<=2);
        assert(wr_ptr_q==(rd_ptr_q ^ count_q[0]));
        assert(f_owned==(count_q==0 ? 2'b00 : count_q==2 ? 2'b11 : (2'b01<<rd_ptr_q)));
'''
    for i in range(2):
        fifo_monitor+='        if(f_owned['+str(i)+'])begin assert(write_q['+str(i)+']==f_ref_write['+str(i)+']);assert(addr_q['+str(i)+']==f_ref_addr['+str(i)+']);assert(data_q['+str(i)+']==f_ref_data['+str(i)+']);end\n'
    fifo_monitor+='''
        if(out_valid_o)begin
            assert(f_owned[rd_ptr_q]);assert(out_write_o==f_ref_write[rd_ptr_q]);
            assert(out_addr_o==f_ref_addr[rd_ptr_q]);assert(out_data_o==f_ref_data[rd_ptr_q]);
        end
    end
'''
    fifo=fifo.replace('\n);',',\n    input wire f_scope_i\n);',1)
    fifo=fifo.replace('\nendmodule','\n'+fifo_monitor+'\nendmodule',1)
    fifo=tap(fifo,{'f_count_o':('[1:0] ','count_q'),'f_write_pointer_o':('','wr_ptr_q'),
        'f_read_pointer_o':('','rd_ptr_q'),'f_raw_addr0_o':('[ADDR_W-1:0] ','addr_q[0]')})
    if args.mutant:
        before='addr_q[wr_ptr_q] <= in_addr_i;'
        if fifo.count(before)!=1:raise ValueError('Native FIFO address write mutation site changed')
        fifo=fifo.replace(before,"addr_q[wr_ptr_q] <= wr_ptr_q ? in_addr_i : {ADDR_W{1'b0}};",1)
    arb=tap(arb,{'f_count_o':('[4:0] ','owner_count_q'),'f_write_pointer_o':('[3:0] ','owner_write_pointer_q'),
        'f_read_pointer_o':('[3:0] ','owner_read_pointer_q'),'f_owner_words_o':('[15:0] ','owner_fifo_q'),
        'f_sticky_fail_o':('','fail_q')})
    arb_history='''
    reg[15:0]f_saved_valid=0;
    reg[15:0]f_saved_owner;
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)f_saved_valid<=0;
        else if(!f_scope_i)f_saved_valid<=0;
        else begin
            if(request_transfer)begin f_saved_valid[owner_write_pointer_q]<=1;f_saved_owner[owner_write_pointer_q]<=layer_req_valid_i;end
            if(response_has_owner)f_saved_valid[owner_read_pointer_q]<=0;
        end
    end
'''
    for i in range(16):
        arb_history+='    wire[3:0]f_distance_'+str(i)+'=4\'d'+str(i)+'-owner_read_pointer_q;\n'
    arb_history+='    wire[15:0]f_expected_valid={'+','.join("({1'b0,f_distance_"+str(i)+'}<owner_count_q)'for i in reversed(range(16)))+'};\n'
    arb_history+='''
    always @*if(reset_n && f_scope_i)begin
        assert(owner_count_q<=16);
        assert(owner_write_pointer_q==owner_read_pointer_q+owner_count_q[3:0]);
        assert(f_saved_valid==f_expected_valid);
'''
    for i in range(16):arb_history+='        if(f_saved_valid['+str(i)+'])assert(owner_fifo_q['+str(i)+']==f_saved_owner['+str(i)+']);\n'
    arb_history+='''
        if(have_owner)assert(f_saved_valid[owner_read_pointer_q]);
        if(request_transfer)begin
            assert(shell_req_valid_i ^ layer_req_valid_i);
            assert(private_req_index_o==(layer_req_valid_i ? layer_req_index_i : shell_req_index_i));
        end
        if(have_owner && !terminal_now && private_rsp_valid_i)begin
            assert(layer_rsp_valid_o==f_saved_owner[owner_read_pointer_q]);
            assert(shell_rsp_valid_o==!f_saved_owner[owner_read_pointer_q]);
        end
    end
'''
    if args.client_counts:
        arb_history+='''
    reg[4:0]f_shell_count=0,f_layer_count=0;
    wire f_shell_retire=response_has_owner && !owner_fifo_q[owner_read_pointer_q];
    wire f_layer_retire=response_has_owner && owner_fifo_q[owner_read_pointer_q];
    always @(posedge clk or negedge reset_n)begin
        if(!reset_n)begin f_shell_count<=0;f_layer_count<=0;end
        else if(!f_scope_i)begin f_shell_count<=0;f_layer_count<=0;end
        else begin
            f_shell_count<=f_shell_count+{4'd0,(request_transfer && !layer_req_valid_i)}-{4'd0,f_shell_retire};
            f_layer_count<=f_layer_count+{4'd0,(request_transfer && layer_req_valid_i)}-{4'd0,f_layer_retire};
        end
    end
'''
        for role,negate in [('shell','!'),('layer','')]:
            terms=["{5'd0,(f_saved_valid["+str(i)+'] && '+negate+'owner_fifo_q['+str(i)+'])}'for i in range(16)]
            arb_history+="    wire[5:0]f_"+role+"_actual_count="+'+'.join(terms)+';\n'
        arb_history+='''
    always @*if(reset_n && f_scope_i)begin
        assert({1'b0,f_shell_count}==f_shell_actual_count);
        assert({1'b0,f_layer_count}==f_layer_actual_count);
        assert(f_shell_count<=16 && f_layer_count<=16);
        assert({1'b0,owner_count_q}=={1'b0,f_shell_count}+{1'b0,f_layer_count});
    end
'''
        arb=tap(arb,{'f_shell_count_o':('[4:0] ','f_shell_count'),'f_layer_count_o':('[4:0] ','f_layer_count')})
    arb=arb.replace('\n);',',\n    input wire f_scope_i\n);',1)
    arb=arb.replace('\nendmodule','\n'+arb_history+'\nendmodule',1)
    declarations=['    wire arbiter_busy,arbiter_fail;wire f_scope;',
        '    wire [4:0] f_owner_count;wire[3:0]f_owner_write,f_owner_read;wire[15:0]f_owners;wire f_owner_fail;']
    for short,instance in scopes:
        bits=1 if short.endswith('response')else 19
        declarations+=['    wire [1:0] f_'+short+'_count;wire f_'+short+'_write,f_'+short+'_read;',
            '    wire ['+str(bits-1)+':0] f_'+short+'_raw_addr;']
        block=extend_instance(block,'u_'+instance,{'f_scope_i':'f_scope','f_count_o':'f_'+short+'_count',
            'f_write_pointer_o':'f_'+short+'_write','f_read_pointer_o':'f_'+short+'_read','f_raw_addr0_o':'f_'+short+'_raw_addr'})
    block=extend_instance(block,'u_private_ddr_arbiter',{'f_count_o':'f_owner_count','f_write_pointer_o':'f_owner_write',
        'f_read_pointer_o':'f_owner_read','f_owner_words_o':'f_owners','f_sticky_fail_o':'f_owner_fail','f_scope_i':'f_scope'})
    if args.client_counts:
        declarations+=['    wire[4:0]f_shell_owner_count,f_layer_owner_count;']
        block=extend_instance(block,'u_private_ddr_arbiter',{'f_shell_count_o':'f_shell_owner_count','f_layer_count_o':'f_layer_owner_count'})
    header='''module model_transport_drain(
    input wire clk,reset_n,child_reset_n,clear_i,model_locked_i,upstream_fail_closed_i,shell_fail,layer_fail,
    input wire shell_ddr_req_valid,output wire shell_ddr_req_ready,input wire[18:0]shell_ddr_req_index,
    output wire shell_ddr_rsp_valid,input wire shell_ddr_rsp_ready,output wire[255:0]shell_ddr_rsp_data,output wire shell_ddr_rsp_fault,
    input wire layer_ddr_req_valid,output wire layer_ddr_req_ready,input wire[18:0]layer_ddr_req_index,
    output wire layer_ddr_rsp_valid,input wire layer_ddr_rsp_ready,output wire[255:0]layer_ddr_rsp_data,output wire layer_ddr_rsp_fault,
    output wire private_runtime_req_valid_o,input wire private_runtime_req_ready_i,output wire[18:0]private_runtime_req_word_index_o,
    input wire private_runtime_rsp_valid_i,output wire private_runtime_rsp_ready_o,input wire[255:0]private_runtime_rsp_data_i,
    input wire private_runtime_rsp_fault_i
);
    localparam integer ADDR_W=19,MODEL_WORDS=227062;
'''
    empty=' && '.join('f_'+short+'_count==0 && f_'+short+'_write==f_'+short+'_read'for short,_ in scopes)
    monitor='''
    reg f_active=0,f_clear_pending=0,f_any_reset=0;
    reg[5:0]f_shell_pending=0,f_layer_pending=0,f_total_pending=0;
    wire f_arm=reset_n && child_reset_n && model_locked_i && !f_owner_fail && !upstream_fail_closed_i && !shell_fail && !layer_fail &&
        EMPTY_QUEUES && f_owner_count==0 && f_owner_write==f_owner_read;
    assign f_scope=f_active || f_arm;
    wire f_shell_push=shell_ddr_req_valid && shell_ddr_req_ready;
    wire f_layer_push=layer_ddr_req_valid && layer_ddr_req_ready;
    wire f_shell_pop=shell_ddr_rsp_valid && shell_ddr_rsp_ready;
    wire f_layer_pop=layer_ddr_rsp_valid && layer_ddr_rsp_ready;
    always @(posedge clk)begin
        if(!reset_n || !child_reset_n)begin
            f_active<=0;f_clear_pending<=0;f_shell_pending<=0;f_layer_pending<=0;f_total_pending<=0;
            f_any_reset<=1;
        end else begin
            if(f_active || f_arm)begin
                f_active<=1;
                f_shell_pending<=(f_active ? f_shell_pending : 6'd0)+{5'd0,f_shell_push}-{5'd0,f_shell_pop};
                f_layer_pending<=(f_active ? f_layer_pending : 6'd0)+{5'd0,f_layer_push}-{5'd0,f_layer_pop};
                f_total_pending<=(f_active ? f_total_pending : 6'd0)+{5'd0,f_shell_push}+{5'd0,f_layer_push}-{5'd0,f_shell_pop}-{5'd0,f_layer_pop};
            end
            if(clear_i && f_active && (f_shell_pending!=0 || f_layer_pending!=0))f_clear_pending<=1;
        end
    end
'''.replace('EMPTY_QUEUES',empty)
    monitor+='''
    wire f_healthy=reset_n && child_reset_n && f_active && !f_owner_fail;
    always @*if(f_healthy)begin
        assert(f_owner_count<=16);
        assert(f_owner_write==f_owner_read+f_owner_count[3:0]);
        assert(f_total_pending=={4'd0,f_shell_request_count}+{4'd0,f_layer_request_count}+{1'b0,f_owner_count}+{4'd0,f_shell_response_count}+{4'd0,f_layer_response_count});
        assert(f_total_pending==(f_shell_pending+f_layer_pending));
        assert(f_total_pending<=24);
        if(f_shell_pending==0 && f_layer_pending==0)begin
            assert(f_owner_count==0 && !arbiter_busy);
            assert(f_shell_request_count==0 && f_layer_request_count==0);
            assert(f_shell_response_count==0 && f_layer_response_count==0);
        end
        if(clear_i)assert(!private_runtime_req_valid_o);
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_clear_pending && !clear_i && private_runtime_req_valid_o && private_runtime_req_ready_i);
        cover(f_healthy && !f_any_reset && f_clear_pending && !clear_i && f_shell_pending==0 && f_layer_pending==0);
        cover(f_healthy && !f_any_reset && f_clear_pending && !clear_i && f_shell_pending==0 && f_layer_pending==0 && f_shell_request_raw_addr!=0);
    end
'''
    if args.client_counts:
        monitor+='''
    always @*if(f_healthy)begin
        assert(f_shell_pending=={4'd0,f_shell_request_count}+{1'b0,f_shell_owner_count}+{4'd0,f_shell_response_count});
        assert(f_layer_pending=={4'd0,f_layer_request_count}+{1'b0,f_layer_owner_count}+{4'd0,f_layer_response_count});
        assert(f_shell_pending<=20 && f_layer_pending<=20);
        assert({1'b0,f_total_pending}=={1'b0,f_shell_pending}+{1'b0,f_layer_pending});
    end
'''
    wrapper=header+'\n'.join(declarations)+'\n'+block+'\n'+monitor+'\nendmodule\n'
    files={'production-fifo.sv':fo,'production-arbiter.sv':ao,'production-core.sv':co,
        'fifo.sv':('`undef FORMAL\n'+fifo+'\n').encode(),'arbiter.sv':('`undef FORMAL\n'+arb+'\n').encode(),
        'wrapper.sv':wrapper.encode(),'fifo-history-monitor.inc.sv':fifo_monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    files['arbiter-history-monitor.inc.sv']=arb_history.encode()
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='model_transport_drain',
        reset_constraints='initial\nassume (= [reset_n] true)\nassume (= [child_reset_n] true)\nstate 1\nassume (= [reset_n] true)\nassume (= [child_reset_n] true)\n',
        assertions=monitor.count('assert(')+4*fifo_monitor.count('assert(')+arb_history.count('assert('),covers=3,
        binding=dict(native_join=binding,variant='baseline',initial_hard_reset=False,
            concrete_hierarchy_modules=[fifo_name,arb_name],native_core_path=cp,
            exact_native_functional_instance_block=True,actual_queue_roles=scopes,owner_depth=16,
            native_queue_entry_depth=2,public_clear_aborts_any_queue=False,exact_per_client_conservation=args.client_counts,
            entry_policy='Tracking begins at a healthy empty native transport with aligned pointers; all old payloads arbitrary. No initial core/child reset; resetless covers required.'),
        cuts=[],depth=6 if args.mutant else 3,induction_depth=3,cover_depth=12,timeout=args.timeout,
        mutant='corrupt-first-queued-word'if args.mutant else None,
        source_list=['fifo.sv','arbiter.sv','wrapper.sv'],primary_only=True,optimize_full=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual four core model FIFOs and 16-owner private arbiter with native wiring. Accepted FIFO word/saved-role history and healthy total request/response conservation through ordinary CLEAR. Both client pending counters zero imply all four local queues and owner FIFO empty; CLEAR cannot abort accepted work. Initial native transport control is logically empty with arbitrary old payloads and no hard-reset prerequisite. Actual client busy-to-pending and public-ready barrier remain separate.')


if __name__=='__main__':raise SystemExit(main())
