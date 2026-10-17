// PRIVATE Qwen GQA pair: two fixed query heads share one key/value head.
// Two wide QK trees -> two softmax heads -> two 64-lane ordered AV engines.
// The reader supplies keys in position order and two 64-coordinate V beats
// per position. All positions and lane ordering come from this fixed circuit.
// These are internal ports, NOT host memory/arithmetic interfaces.
//
// CLEAR/error asserts memory_abort until the reader confirms that every old
// response has been drained/cancelled. No new operation can start before that
// acknowledgement. The memory reader and authentication are not implemented
// here; asserting memory_quiescent prematurely violates this private contract.
// The reader must authenticate each payload before making it valid. A reported
// memory fault also withdraws a queued, unconsumed successful pair result.
// A pair is buffered and committed atomically only after both heads succeed.
module qwen_attention_pair #(
    parameter EXP_ROM_FILE="softmax-exp2.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] context_length,
    input wire [2047:0] query0,
    input wire [2047:0] query1,
    input wire key_valid,
    output wire key_ready,
    output wire [14:0] key_position,
    input wire [2047:0] key,
    input wire value_valid,
    output wire value_ready,
    output wire [14:0] value_position,
    output wire value_group,
    input wire [1023:0] values,
    input wire memory_error,
    output wire memory_abort,
    input wire memory_quiescent,
    output wire out_valid,
    input wire out_ready,
    output wire [2047:0] result0,
    output wire [2047:0] result1,
    output wire out_error
);
    localparam [2:0] IDLE=0,START=1,RUN=2,FLUSH=3,RESULT=4;
    reg [2:0] state;
    reg [15:0] length,key_count,value_count;
    reg input_group,result_group,report_error,failed;
    reg [2047:0] queries [0:1];
    reg [2047:0] results [0:1];
    wire alive=rst_n && !clear;
    wire active=state==RUN && alive;
    wire child_clear=clear || state==IDLE || state==FLUSH || state==RESULT;
    assign start_ready=alive && state==IDLE && memory_quiescent;
    // Fault gates below suppress invalid transfers immediately. Latch it
    // before withdrawing memory responses: FLUSH asserts abort next clock.
    // This breaks the arithmetic-error -> abort -> drain-ack feedback path.
    assign memory_abort=!rst_n || clear || state==FLUSH;
    assign out_valid=alive && state==RESULT && (failed || !memory_error);
    assign out_error=failed;
    assign result0=failed ? 2048'b0 : results[0];
    assign result1=failed ? 2048'b0 : results[1];
    assign key_position=key_count[14:0];
    assign value_position=value_count[14:0];
    assign value_group=input_group;

    wire [1:0] qk_in_ready,qk_valid,qk_error;
    wire [15:0] score [0:1];
    wire [1:0] sm_start_ready,sm_in_ready,sm_valid,sm_error,sm_last;
    wire [14:0] sm_index [0:1];
    wire [15:0] probability [0:1];
    // PRIVATE_PROBABILITY_BUFFER: decouple the softmax RAM/pipeline
    // enable from K/V transport backpressure. Both heads enter/leave together.
    // Index/LAST validation uses the PRODUCER position; value_count still
    // owns the reader and both V groups for each consumed probability pair.
    reg [31:0] probability_buffer [0:1];
    reg probability_read,probability_write;
    reg [1:0] probability_count;
    reg [15:0] probability_produced;
    wire [31:0] queued_probability=probability_buffer[probability_read];
    wire probability_enqueue=active && probability_count<2 && (&sm_valid);
    wire [1:0] av_start_ready,av_in_ready,av_valid,av_error;
    wire [2:0] av_group [0:1];
    wire [1023:0] av_result [0:1];
    wire children_start=state==START && alive && (&sm_start_ready) && (&av_start_ready) && !memory_error;
    wire qk_fault=|(qk_valid & qk_error);
    wire sm_fault=|(sm_valid & sm_error) || ((&sm_valid) &&
        (probability_produced>=length || sm_index[0]!=probability_produced[14:0] ||
         sm_index[1]!=probability_produced[14:0] ||
         sm_last[0]!=(probability_produced==length-1'b1) ||
         sm_last[1]!=(probability_produced==length-1'b1)));
    wire av_fault=|(av_valid & av_error) || ((&av_valid) &&
        (av_group[0]!={2'b0,result_group} || av_group[1]!={2'b0,result_group} || value_count!=length));
    wire fault=((state==START || state==RUN) &&
        (memory_error || (state==RUN && (qk_fault || sm_fault || av_fault)))) ||
        (state==RESULT && !failed && memory_error);
    assign key_ready=active && !fault && key_count<length && (&qk_in_ready);
    wire key_take=key_valid && key_ready;
    wire score_take=active && !fault && (&qk_valid) && (&sm_in_ready);
    assign value_ready=active && !fault && value_count<length && probability_count!=0 && (&av_in_ready);
    wire value_take=value_valid && value_ready;
    wire probability_take=value_take && input_group;
    wire result_take=active && !fault && (&av_valid);

    genvar head;
    generate for(head=0;head<2;head=head+1)begin:heads
        qwen_qk_dot128 qk(.clk(clk),.rst_n(rst_n),.clear(child_clear),
            .in_valid(key_take),.in_ready(qk_in_ready[head]),.query(queries[head]),.key(key),
            .out_valid(qk_valid[head]),.out_ready(score_take),.score(score[head]),.out_error(qk_error[head]));
        qwen_softmax #(.EXP_ROM_FILE(EXP_ROM_FILE)) softmax(.clk(clk),.rst_n(rst_n),.clear(child_clear),
            .start_valid(children_start),.start_ready(sm_start_ready[head]),.context_length(length),
            .in_valid(score_take),.in_ready(sm_in_ready[head]),.score(score[head]),
            .out_valid(sm_valid[head]),.out_ready(probability_enqueue),.out_index(sm_index[head]),
            .out_last(sm_last[head]),.probability(probability[head]),.out_error(sm_error[head]));
        qwen_av_stream16 #(.LANES(64)) av(.clk(clk),.rst_n(rst_n),.clear(child_clear),
            .start_valid(children_start),.start_ready(av_start_ready[head]),.context_length(length),
            .in_valid(value_take),.in_ready(av_in_ready[head]),.probability(queued_probability[16*head +:16]),.values(values),
            .out_valid(av_valid[head]),.out_ready(result_take),.out_group(av_group[head]),
            .result(av_result[head]),.out_error(av_error[head]));
    end endgenerate

    // Advancing a private softmax output on a fault edge is harmless:
    // the fault branch below discards queue validity, and the unchanged fault
    // gates suppress value_take, result_take and successful pair publication.
    // Keeping fault out of probability_enqueue breaks the measured long path.
    always @(posedge clk) if(probability_enqueue)
        probability_buffer[probability_write]<={probability[1],probability[0]};
    always @(posedge clk) begin
        if(!rst_n || child_clear || fault) begin
            probability_read<=0;probability_write<=0;
            probability_count<=0;probability_produced<=0;
        end else begin
            if(probability_enqueue) begin
                probability_write<=!probability_write;
                probability_produced<=probability_produced+1'b1;
            end
            if(probability_take)probability_read<=!probability_read;
            case({probability_enqueue,probability_take})
                2'b10:probability_count<=probability_count+1'b1;
                2'b01:probability_count<=probability_count-1'b1;
                default:;
            endcase
        end
    end

    // Private speculative capture only while idle. The accepted-start
    // edge captures the exact queries used by the unchanged START/RUN schedule.
    // Invalid idle contents are neither consumed nor exposed to the host.
    always @(posedge clk) if(state==IDLE)begin
        queries[0]<=query0;queries[1]<=query1;
    end

    integer i;
    always @(posedge clk)begin
        if(!rst_n || clear)begin
            state<=FLUSH;length<=0;key_count<=0;value_count<=0;input_group<=0;result_group<=0;
            failed<=0;report_error<=0;
        end else if(fault)begin
            state<=FLUSH;report_error<=1;failed<=1;
        end else case(state)
            IDLE:if(start_valid && start_ready)begin
                length<=context_length;
                key_count<=0;value_count<=0;input_group<=0;result_group<=0;
                failed<=context_length==0 || context_length>16'd32768;
                report_error<=context_length==0 || context_length>16'd32768;
                state<=context_length==0 || context_length>16'd32768 ? FLUSH : START;
            end
            START:if(children_start)state<=RUN;
            RUN:begin
                if(key_take)key_count<=key_count+1'b1;
                if(value_take)begin
                    input_group<=!input_group;
                    if(input_group)value_count<=value_count+1'b1;
                end
                if(result_take)begin
                    for(i=0;i<2;i=i+1)begin
                        if(result_group)results[i][2047:1024]<=av_result[i];
                        else results[i][1023:0]<=av_result[i];
                    end
                    result_group<=!result_group;
                    if(result_group)state<=RESULT;
                end
            end
            FLUSH:if(memory_quiescent)state<=report_error ? RESULT : IDLE;
            RESULT:if(out_ready)state<=IDLE;
            default:begin state<=FLUSH;report_error<=1;failed<=1;end
        endcase
    end
endmodule
