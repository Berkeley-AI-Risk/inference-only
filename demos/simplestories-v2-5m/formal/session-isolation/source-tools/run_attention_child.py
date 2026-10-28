"""Concrete resetless arithmetic-child isolation; no numerical output cuts."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, REL, load


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--kind',choices=('align8','norm-candidate'),required=True)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/REL).read_bytes()
    name='board1_fixed_attention_align8'if args.kind=='align8'else'board1_attention_norm_candidate_stage'
    found=re.findall(r'^module '+name+r'\b[\s\S]*?^endmodule',raw.decode(),re.M)
    if len(found)!=1:raise ValueError('Child source not unique')
    source=found[0]
    lines=['`default_nettype none']
    if args.kind=='align8':
        expression='{'+','.join('magnitude_q['+str(i)+']'for i in range(8))+',negative_q,amount_q,left_q,far_left_q,zero_right_q,bad_shift_q}'
        source=source.replace('\n);',',\n    output wire [1:0] f_state_o,\n    output wire [143:0] f_payload_o\n);',1)
        source=source.replace('\nendmodule','\n    assign f_state_o=state_q;\n    assign f_payload_o='+expression+';\nendmodule',1)
        lines += ['module concrete_child_isolation(input wire clk,rst_n,clear_i,request_valid_i,response_ready_i,',
                  '    input wire [127:0] request_vector_i,discarded_vector_i,input wire signed [8:0] request_shift_i,discarded_shift_i);',
                  '    reg f_past_valid=0,f_joined=0;',
                  '    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;']
        for copy in ('a','b'):
            lines += [f'    wire [1:0] {copy}_state;wire [143:0] {copy}_payload;',
                      f'    wire {copy}_ready,{copy}_valid,{copy}_fault;wire [127:0] {copy}_vector;wire [15:0] {copy}_magnitude;',
                      f'    {name} u_{copy}(.clk(clk),.rst_n(rst_n),.clear_i(clear_i),',
                      f'        .request_valid_i(request_valid_i),.request_ready_o({copy}_ready),',
                      '        .request_vector_i('+('request_vector_i'if copy=='a'else'(request_valid_i ? request_vector_i : discarded_vector_i)')+'),',
                      '        .request_shift_i('+('request_shift_i'if copy=='a'else'(request_valid_i ? request_shift_i : discarded_shift_i)')+'),',
                      f'        .response_ready_i(response_ready_i),.response_valid_o({copy}_valid),',
                      f'        .response_vector_o({copy}_vector),.response_magnitude_or_o({copy}_magnitude),',
                      f'        .response_fault_o({copy}_fault),.f_state_o({copy}_state),.f_payload_o({copy}_payload));']
        lines += ['    always @(posedge clk)begin f_past_valid<=1;',
                  '        cover(f_past_valid && rst_n && a_state==0 && a_payload!=b_payload);',
                  '        cover(f_joined && rst_n && a_valid && !a_fault);end',
                  '    always @*if(rst_n && f_joined)begin',
                  '        assert(a_state==b_state);assert(a_state<=2);',
                  '        assert(a_ready==b_ready);assert(a_valid==b_valid);',
                  '        if(a_state==1)assert(a_payload==b_payload);',
                  '        if(a_state==2)begin assert(a_vector==b_vector);assert(a_fault==b_fault);assert(a_magnitude==b_magnitude);end',
                  '    end']
    else:
        lines += ['module concrete_child_isolation(input wire clk,rst_n,clear_i,capture_i,',
                  '    input wire signed [63:0] value_i,discarded_value_i,input wire signed [7:0] source_exponent_i,discarded_exponent_i);',
                  '    reg f_seen=0,f_past_valid=0;',
                  '    wire signed [7:0] a_fit,b_fit;wire a_nonzero,b_nonzero;']
        for copy in ('a','b'):
            lines += [f'    {name} u_{copy}(.clk(clk),.reset_n(rst_n),.capture_i(capture_i),',
                      '        .value_i('+('value_i'if copy=='a'else'(capture_i && !clear_i ? value_i : discarded_value_i)')+'),',
                      '        .source_exponent_i('+('source_exponent_i'if copy=='a'else'(capture_i && !clear_i ? source_exponent_i : discarded_exponent_i)')+f'),.first_fit_o({copy}_fit),.nonzero_o({copy}_nonzero));']
        lines += ['    always @(posedge clk)begin f_past_valid<=1;',
                  '        if(!rst_n || clear_i)f_seen<=0;else if(capture_i)f_seen<=1;',
                  '        cover(f_past_valid && rst_n && !f_seen && a_fit!=b_fit);',
                  '        cover(f_past_valid && rst_n && f_seen);end',
                  '    always @*if(rst_n && f_seen)begin assert(a_fit==b_fit);assert(a_nonzero==b_nonzero);end']
    lines+=['endmodule','`default_nettype wire'];wrapper='\n'.join(lines)+'\n'
    files={'production-attention.sv':raw,'child.sv':('`undef FORMAL\n'+source+'\n').encode(),
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='concrete_child_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='No initial hard reset. Native mutable state is arbitrary and independent; a common CLEAR enables align8 correspondence. Norm-candidate outputs require a fresh matched capture. Invalid request/capture operands may differ.',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=REL,concrete_module=name,original_module_sha256=engine.sha(found[0].encode()),
            initial_hard_reset=False,invalid_operands_independent=True),
        cuts=[],depth=3,induction_depth=3,cover_depth=10,timeout=args.timeout,
        source_list=['child.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Concrete native resetless arithmetic child in two copies, actual arithmetic retained. Matched accepted current inputs determine valid/owned replies despite independent old payloads. CLEAR revokes ownership; norm-candidate use requires a fresh capture after cancellation, which is a separate parent obligation. No full numerical-transformer or whole-session theorem.')


if __name__=='__main__':raise SystemExit(main())
