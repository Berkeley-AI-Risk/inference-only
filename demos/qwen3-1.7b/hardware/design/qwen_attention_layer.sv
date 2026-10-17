// PRIVATE complete Qwen attention layer: 16 Q heads, 8 K/V heads, width 128.
// CORES is a synthesis-time choice (1/2/4 GQA pairs), never a host operation.
// The private sequencer supplies layer/length, then exactly 2048 rotary Q values
// in head-major order. Fixed counters own all K/V head/position/group routing.
// Output rows may enter a PRIVATE uncommitted tensor buffer; done without
// done_error is the commit point. An error invalidates the entire operation.
// Actual authenticated HBM and its abort/drain implementation are not here.
module qwen_attention_layer #(
    parameter integer CORES=1,
    parameter EXP_ROM_FILE="softmax-exp2.hex"
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire start_valid,output wire start_ready,
    input wire [4:0] op_layer,input wire [15:0] context_length,
    input wire query_valid,output wire query_ready,input wire [15:0] query,
    input wire [CORES-1:0] key_valid,output wire [CORES-1:0] key_ready,
    output wire [CORES*15-1:0] key_position,input wire [CORES*2048-1:0] keys,
    input wire [CORES-1:0] value_valid,output wire [CORES-1:0] value_ready,
    output wire [CORES*15-1:0] value_position,output wire [CORES-1:0] value_group,
    input wire [CORES*1024-1:0] values,
    output wire [4:0] memory_layer,output wire [CORES*3-1:0] memory_head,
    input wire [CORES-1:0] memory_error,output wire [CORES-1:0] memory_abort,
    input wire [CORES-1:0] memory_quiescent,
    output wire result_valid,input wire result_ready,
    output wire [10:0] result_index,output wire [15:0] result,
    output wire done_valid,input wire done_ready,output wire done_error
);
    localparam integer CORE_BITS=CORES<=2 ? 1 : 2;
    localparam [3:0] IDLE=0,LOAD=1,Q_READ=2,Q_DRAIN=3,KICK=4,RUN=5,OUTPUT=6,DONE=7,FLUSH=8;
    reg [3:0] state;
    reg [4:0] layer;
    reg [15:0] length;
    reg [10:0] query_count;
    reg [2:0] base_pair;
    reg [8:0] query_read_count;
    reg query_sample_valid;
    reg [7:0] query_sample_index;
    reg [CORE_BITS-1:0] capture_core;
    reg [4:0] capture_beat;
    reg [11:0] output_issue_count;
    reg output_valid;
    reg [10:0] output_index;
    reg failed,report_error;
    wire alive=rst_n && !clear;
    wire fault;
    wire abort_all=!rst_n || clear || state==FLUSH;
    wire child_clear=clear || state==IDLE || state==DONE || state==FLUSH;
    wire [CORES-1:0] child_start_ready,child_valid,child_error,child_abort;
    wire [2047:0] child_result0 [0:CORES-1],child_result1 [0:CORES-1];
    reg [2047:0] child_query0 [0:CORES-1],child_query1 [0:CORES-1];
    wire [CORES-1:0] child_key_ready,child_value_ready;
    wire [CORES-1:0] child_out_ready;
    wire child_start=state==KICK && alive && !fault && (&child_start_ready);
    assign start_ready=state==IDLE && alive && (&memory_quiescent);
    assign query_ready=state==LOAD && alive && !fault;
    wire query_take=query_valid && query_ready;
    wire query_fault=state==LOAD && query_valid && (&query[14:7]);
    assign fault=((state!=IDLE && state!=DONE && state!=FLUSH) &&
        ((|memory_error) || query_fault || (state==RUN && ((|child_abort) || (|(child_valid & child_error)))))) ||
        (state==DONE && !failed && (|memory_error));
    assign memory_layer=layer;
    assign done_valid=state==DONE && alive && (failed || !(|memory_error));
    assign done_error=failed;
    wire run_enabled=state==RUN && alive && !fault;
    assign key_ready=child_key_ready & {CORES{run_enabled}};
    assign value_ready=child_value_ready & {CORES{run_enabled}};
    wire capture_valid=run_enabled && child_valid[capture_core];
    wire [2047:0] capture_head=capture_beat[4] ? child_result1[capture_core] : child_result0[capture_core];
    wire [127:0] capture_word=capture_head[{capture_beat[3:0],7'b0} +:128];
    wire [7:0] capture_address={base_pair,5'b0}+{3'(capture_core),5'b0}+{3'b0,capture_beat};
    wire query_issue=state==Q_READ && alive && !fault;
    wire [7:0] query_read_address={base_pair,5'b0}+query_read_count[7:0];
    wire [127:0] query_word;
    wire output_advance=state==OUTPUT && alive && !fault && (!output_valid || result_ready);
    wire output_issue=output_advance && output_issue_count<12'd2048;
    wire [127:0] output_word;
    assign result_valid=state==OUTPUT && output_valid && alive && !fault;
    assign result_index=output_index;
    assign result=output_word[{output_index[2:0],4'b0} +:16];

    initial if(CORES!=1 && CORES!=2 && CORES!=4)$fatal(1,"Invalid fixed attention core count");
    genvar bank,core;
    generate for(bank=0;bank<8;bank=bank+1)begin:banks
        // Eight small banks allow one scalar query write and eight-coordinate
        // internal transfers. No large RAM reset or multiported query RAM.
        (* ram_style="distributed" *) reg [15:0] queries [0:255];
        (* ram_style="distributed" *) reg [15:0] results [0:255];
        reg [15:0] query_sample,result_sample;
        always @(posedge clk)if(alive)begin
            if(query_take && query_count[2:0]==3'(bank))queries[query_count[10:3]]<=query;
            if(query_issue)query_sample<=queries[query_read_address];
            if(capture_valid)results[capture_address]<=capture_word[16*bank +:16];
            if(output_issue)result_sample<=results[output_issue_count[10:3]];
        end
        assign query_word[16*bank +:16]=query_sample;
        assign output_word[16*bank +:16]=result_sample;
    end
    for(core=0;core<CORES;core=core+1)begin:engines
        assign memory_head[3*core +:3]=base_pair+3'(core);
        assign memory_abort[core]=abort_all;
        assign child_out_ready[core]=capture_valid && capture_core==CORE_BITS'(core) && capture_beat==5'd31;
        always @(posedge clk)if(alive && query_sample_valid && query_sample_index[7:5]==3'(core))begin
            if(query_sample_index[4])child_query1[core][{query_sample_index[3:0],7'b0} +:128]<=query_word;
            else child_query0[core][{query_sample_index[3:0],7'b0} +:128]<=query_word;
        end
        qwen_attention_pair #(.EXP_ROM_FILE(EXP_ROM_FILE)) pair(
            .clk(clk),.rst_n(rst_n),.clear(child_clear),.start_valid(child_start),.start_ready(child_start_ready[core]),
            .context_length(length),.query0(child_query0[core]),.query1(child_query1[core]),
            .key_valid(key_valid[core] && run_enabled),.key_ready(child_key_ready[core]),
            .key_position(key_position[15*core +:15]),.key(keys[2048*core +:2048]),
            .value_valid(value_valid[core] && run_enabled),.value_ready(child_value_ready[core]),
            .value_position(value_position[15*core +:15]),.value_group(value_group[core]),.values(values[1024*core +:1024]),
            .memory_error(memory_error[core]),.memory_abort(child_abort[core]),.memory_quiescent(memory_quiescent[core]),
            .out_valid(child_valid[core]),.out_ready(child_out_ready[core]),
            .result0(child_result0[core]),.result1(child_result1[core]),.out_error(child_error[core]));
    end endgenerate

    always @(posedge clk)begin
        if(!rst_n || clear)begin
            state<=FLUSH;layer<=0;length<=0;query_count<=0;base_pair<=0;
            query_read_count<=0;query_sample_valid<=0;query_sample_index<=0;
            capture_core<=0;capture_beat<=0;output_issue_count<=0;output_index<=0;output_valid<=0;
            failed<=0;report_error<=0;
        end else if(fault)begin
            state<=FLUSH;failed<=1;report_error<=1;query_sample_valid<=0;output_valid<=0;
        end else begin
            query_sample_valid<=query_issue;
            if(query_issue)query_sample_index<=query_read_count[7:0];
            if(output_advance)begin
                output_valid<=output_issue;
                if(output_issue)begin output_index<=output_issue_count[10:0];output_issue_count<=output_issue_count+1'b1;end
            end
            case(state)
                IDLE:if(start_valid && start_ready)begin
                    layer<=op_layer;length<=context_length;query_count<=0;base_pair<=0;
                    query_read_count<=0;capture_core<=0;capture_beat<=0;output_valid<=0;output_issue_count<=0;
                    failed<=op_layer>=5'd28 || context_length==0 || context_length>16'd32768;
                    report_error<=op_layer>=5'd28 || context_length==0 || context_length>16'd32768;
                    state<=op_layer>=5'd28 || context_length==0 || context_length>16'd32768 ? FLUSH : LOAD;
                end
                LOAD:if(query_take)begin query_count<=query_count+1'b1;if(query_count==11'd2047)state<=Q_READ;end
                Q_READ:begin
                    query_read_count<=query_read_count+1'b1;
                    if(query_read_count==9'(CORES*32-1))state<=Q_DRAIN;
                end
                Q_DRAIN:if(query_sample_valid)state<=KICK;
                KICK:if(child_start)begin state<=RUN;capture_core<=0;capture_beat<=0;end
                RUN:if(capture_valid)begin
                    capture_beat<=capture_beat+1'b1;
                    if(capture_beat==5'd31)begin
                        capture_core<=capture_core==CORE_BITS'(CORES-1) ? {CORE_BITS{1'b0}} : capture_core+1'b1;
                        if(capture_core==CORE_BITS'(CORES-1))begin
                            if(base_pair==3'(8-CORES))begin state<=OUTPUT;output_issue_count<=0;output_valid<=0;end
                            else begin base_pair<=base_pair+3'(CORES);query_read_count<=0;state<=Q_READ;end
                        end
                    end
                end
                OUTPUT:if(result_valid && result_ready && result_index==11'd2047)begin state<=DONE;output_valid<=0;end
                DONE:if(done_ready)state<=IDLE;
                FLUSH:if(&memory_quiescent)state<=report_error ? DONE : IDLE;
                default:begin state<=FLUSH;failed<=1;report_error<=1;end
            endcase
        end
    end
endmodule
