// PRIVATE Qwen attention-value accumulator. Compile-time 16/32/64 coordinates
// per beat; 8/4/2 beats per context position, in fixed order. The same private
// BF16 probability accompanies every beat of a position. No host addresses.
// Each coordinate uses separate FP32 product and left-to-right FP32 additions,
// then BF16 RNE on output. The fixed sequencer owns the 1..32768 length.
// Output errors invalidate the entire head, including earlier output beats.
module qwen_av_stream16 #(
    parameter integer LANES=16
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] context_length,
    input wire in_valid,
    output wire in_ready,
    input wire [15:0] probability,
    input wire [LANES*16-1:0] values,
    output wire out_valid,
    input wire out_ready,
    output wire [2:0] out_group,
    output wire [LANES*16-1:0] result,
    output wire out_error
);
    localparam [2:0] IDLE=0,FEED=1,DRAIN=2,CAPTURE=3,OUTPUT=4,READ_OUTPUT=5;
    localparam integer GROUPS=128/LANES;
    localparam integer ADDRESS_BITS=$clog2(GROUPS);
    localparam [2:0] LAST_GROUP=LANES==16 ? 3'd7 : LANES==32 ? 3'd3 : 3'd1;
    reg [2:0] state;
    reg [15:0] length,position;
    reg [2:0] input_group,output_group;
    reg [15:0] held_probability;
    reg [4:0] valid_pipe,first_pipe,last_pipe;
    reg [2:0] group_pipe [0:4];
    reg arithmetic_error,bad_length;
    wire advance=rst_n && !clear;
    assign start_ready=state==IDLE && advance;
    assign in_ready=state==FEED && advance;
    assign out_valid=state==OUTPUT && advance;
    assign out_group=output_group;
    wire accept=in_valid && in_ready;
    wire last_input=position==length-1'b1 && input_group==LAST_GROUP;
    wire probability_error=(probability[15] && |probability[14:0]) || probability[14:0]>15'h3f80 ||
        (input_group!=0 && probability!=held_probability);
    // Private input payload is sampled each clock. Only the matching
    // delayed valid metadata may commit it; CLEAR discards that metadata.
    reg [15:0] probability_q;
    reg [LANES*16-1:0] values_q;
    reg probability_error_q;
    always @(posedge clk) begin
        probability_q<=probability;values_q<=values;
        probability_error_q<=probability_error;
    end
    wire [32:0] p_rec;
    fNToRecFN #(8,24) decode_probability(.in({probability_q,16'b0}),.out(p_rec));
    wire [LANES-1:0] lane_error,output_error;
    wire [LANES*16-1:0] next_result;
    reg [LANES*16-1:0] output_payload;
    reg output_fault;
    assign result=output_payload;
    genvar lane;
    generate for(lane=0;lane<LANES;lane=lane+1) begin:lanes
        (* ram_style="distributed" *) reg [32:0] accumulator [0:GROUPS-1];
        wire [15:0] v=values_q[16*lane +:16];
        wire [32:0] v_rec,product,sum;
        wire product_error;
        fNToRecFN #(8,24) decode_value(.in({v,16'b0}),.out(v_rec));
        qwen_fp32_mul_stage multiply(.clk(clk),.advance(1'b1),.a(p_rec),.b(v_rec),
            .in_error(probability_error_q || (&v[14:7])),.result(product),.out_error(product_error));
        // With 64 lanes the next position reaches the adder on the same
        // edge as its predecessor commits. Forward that registered sum.
        // This preserves left-to-right ordering without an input bubble.
        // Pipeline metadata advances every non-clear clock, including
        // bubbles. Predecode the next cycle's exact bypass condition. Keep
        // a local copy for this lane; no DONT_TOUCH restricts physical repair.
        (* keep="true" *) reg forward_sum_q;
        always @(posedge clk) begin
            if(!rst_n || clear) forward_sum_q<=0;
            else forward_sum_q<=valid_pipe[3] && group_pipe[3]==group_pipe[1];
        end
        wire forward_sum=forward_sum_q;
        wire [32:0] previous=first_pipe[2] ? 33'b0 :
            (forward_sum ? sum : accumulator[group_pipe[2][ADDRESS_BITS-1:0]]);
        qwen_fp32_add_stage add(.clk(clk),.advance(1'b1),.a(previous),.b(product),
            .in_error(product_error),.result(sum),.out_error(lane_error[lane]));
        // AV_COMMIT097: this is a local copy of valid_pipe[4], not a
        // new arithmetic operation or an extra pipeline stage. Keep each
        // lane's write enable separate through native optimization.
        (* DONT_TOUCH="TRUE" *) reg accumulator_write_valid_q;
        always @(posedge clk)begin
            if(!rst_n || clear)accumulator_write_valid_q<=0;
            else accumulator_write_valid_q<=valid_pipe[3];
        end
        // On reset/CLEAR an old write can touch private stale payload only.
        // Output/valid metadata still clear, and a new first position starts
        // from zero. Cancellation/restart correctness is tested separately.
        always @(posedge clk) if(accumulator_write_valid_q)
            accumulator[group_pipe[4][ADDRESS_BITS-1:0]]<=sum;
        // Separate the accumulator RAM read from the final BF16 conversion.
        // The output group remains fixed throughout READ_OUTPUT and CAPTURE.
        reg [32:0] output_accumulator_q;
        always @(posedge clk) if(state==READ_OUTPUT)
            output_accumulator_q<=accumulator[output_group[ADDRESS_BITS-1:0]];
        wire [16:0] narrowed;
        wire [15:0] encoded;
        wire [4:0] flags;
        recFNToRecFN #(8,24,8,8) narrow(.control(1'b1),.in(output_accumulator_q),
            .roundingMode(3'b000),.out(narrowed),.exceptionFlags(flags));
        recFNToFN #(8,8) encode(.in(narrowed),.out(encoded));
        assign next_result[16*lane +:16]=bad_length ? 16'b0 : encoded;
        assign output_error[lane]=|flags[4:2] || (&encoded[14:7]);
        wire unused_flags=^flags[1:0];
    end endgenerate
    assign out_error=output_fault;
    integer i;
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            state<=IDLE;position<=0;length<=0;input_group<=0;output_group<=0;
            valid_pipe<=0;first_pipe<=0;last_pipe<=0;arithmetic_error<=0;bad_length<=0;output_fault<=0;
        end else begin
            valid_pipe<={valid_pipe[3:0],accept};
            first_pipe<={first_pipe[3:0],position==0};
            last_pipe<={last_pipe[3:0],last_input};
            group_pipe[0]<=input_group;
            for(i=1;i<5;i=i+1)group_pipe[i]<=group_pipe[i-1];
            if(start_valid && start_ready) begin
                length<=context_length;position<=0;input_group<=0;output_group<=0;
                arithmetic_error<=0;
                bad_length<=context_length==0 || context_length>16'd32768;
                state<=(context_length==0 || context_length>16'd32768) ? READ_OUTPUT : FEED;
            end
            if(accept) begin
                if(input_group==0)held_probability<=probability;
                input_group<=input_group==LAST_GROUP ? 3'b0 : input_group+1'b1;
                if(input_group==LAST_GROUP)position<=position+1'b1;
                if(last_input)state<=DRAIN;
            end
            if(valid_pipe[4]) begin
                arithmetic_error<=arithmetic_error || |lane_error;
                if(last_pipe[4])begin state<=READ_OUTPUT;output_group<=0;end
            end
            // Capture only after the final sum and sticky error commit.
            // OUTPUT holds this private packet until it is accepted.
            if(state==READ_OUTPUT)state<=CAPTURE;
            if(state==CAPTURE) begin
                output_payload<=next_result;
                output_fault<=arithmetic_error || bad_length || |output_error;
                state<=OUTPUT;
            end
            if(out_valid && out_ready) begin
                output_group<=output_group+1'b1;
                if(output_group==LAST_GROUP)state<=IDLE;
                else state<=READ_OUTPUT;
            end
        end
    end
endmodule
