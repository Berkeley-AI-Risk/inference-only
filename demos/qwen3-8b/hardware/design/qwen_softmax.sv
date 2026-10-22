// PRIVATE single-head softmax for a sequencer-owned length 1..32768.
// Three streaming passes: finite BF16 scores/max, exp/max-distance plus exact
// carry-save sum, then FP32 reciprocal scaling and BF16 probabilities.
// No host addresses, logits or configurable arithmetic operation is exposed.
module qwen_softmax #(
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter PRIVATE_READY_STATE_ONLY=0,
    parameter PRIVATE_STREAM_STATE_ONLY=0
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire start_valid,
    output wire start_ready,
    input wire [15:0] context_length,
    input wire in_valid,
    output wire in_ready,
    input wire [15:0] score,
    output wire out_valid,
    input wire out_ready,
    output wire [14:0] out_index,
    output wire out_last,
    output wire [15:0] probability,
    output wire out_error
);
    localparam [3:0] IDLE=0,LOAD=1,EXP_READ=2,EXP_DRAIN=3,SUM_LOW=4,SUM_HIGH=5,
        SUM_ROUND=6,RECIP_START=7,RECIP_WAIT=8,PROB_READ=9,PROB_DRAIN=10,ERROR=11;
    reg [3:0] state;
    reg [15:0] length,load_count,exp_read_count,prob_read_count;
    reg [15:0] maximum;
    wire alive=rst_n && !clear;
    // PRIVATE readiness cofactor: the attention parent already gates
    // START by reset/CLEAR. Only its fixed instantiation selects this.
    assign start_ready=state==IDLE && (PRIVATE_READY_STATE_ONLY || alive);
    // PRIVATE stream cofactor: the fixed parent gates RUN transfers
    // by reset/CLEAR; synchronous child reset still dominates updates.
    assign in_ready=state==LOAD && (PRIVATE_STREAM_STATE_ONLY || alive);
    wire input_accept=in_valid && in_ready;
    wire score_nonfinite=&score[14:7];
    wire score_greater=(score[15]!=maximum[15]) ? !score[15] :
        (score[15] ? score[14:0]<maximum[14:0] : score[14:0]>maximum[14:0]);

    (* ram_style="block" *) reg [15:0] scores [0:32767];
    (* ram_style="block" *) reg [31:0] exponentials [0:32767];
    reg [15:0] score_sample;
    reg score_sample_valid;
    reg [14:0] score_sample_index;
    wire exp_issue=state==EXP_READ && alive;
    wire [32:0] maximum_rec,negative_score_rec,distance_rec;
    wire distance_error;
    wire [31:0] distance_bits;
    fNToRecFN #(8,24) decode_maximum(.in({maximum,16'b0}),.out(maximum_rec));
    fNToRecFN #(8,24) decode_score(.in({!score_sample[15],score_sample[14:0],16'b0}),.out(negative_score_rec));
    qwen_fp32_add_stage distance(.clk(clk),.advance(alive),.a(maximum_rec),.b(negative_score_rec),
        .in_error(1'b0),.result(distance_rec),.out_error(distance_error));
    recFNToFN #(8,24) encode_distance(.in(distance_rec),.out(distance_bits));
    reg [1:0] distance_valid;
    reg [14:0] distance_index [0:1];
    wire exp_in_ready,exp_valid,exp_error;
    wire [31:0] exp_bits;
    qwen_exp_negative #(.ROM_FILE(EXP_ROM_FILE)) exponential(
        .clk(clk),.rst_n(rst_n),.clear(clear || state==IDLE || state==ERROR),
        .in_valid(distance_valid[1]),.in_ready(exp_in_ready),.distance(distance_bits),
        .out_valid(exp_valid),.out_ready(1'b1),.result(exp_bits),.out_error(exp_error));
    reg [14:0] exp_index [0:8];
    wire exp_take=exp_valid && (state==EXP_READ || state==EXP_DRAIN) && alive;

    // Every nonnegative FP32 exponential is an integer multiple of 2^-149.
    // Max 32768 entries in [0,1] require 165 bits. Carry-save accumulation
    // has no per-score long carry chain and loses no low-order contributions.
    reg [164:0] sum_bits,carry_bits;
    wire [164:0] exp_integer=exp_bits[30:23]==0 ? {142'b0,exp_bits[22:0]} :
        ({141'b0,1'b1,exp_bits[22:0]} << (exp_bits[30:23]-1'b1));
    reg [96:0] low_sum;
    wire [69:0] high_sum={1'b0,sum_bits[164:96]}+{1'b0,carry_bits[164:96]}+{{69{1'b0}},low_sum[96]};
    reg [164:0] exact_total;
    reg [31:0] denominator;
    function automatic [31:0] round_total(input [164:0] total);
        integer i;
        reg [3:0] exponent;
        reg [164:0] shifted;
        reg [24:0] window,rounded;
        reg sticky;
        reg [7:0] biased;
        begin
            exponent=0;
            for(i=0;i<16;i=i+1)if(total[149+i])exponent=4'(i);
            shifted=total >> (8'd125+{4'b0,exponent});window=shifted[24:0];
            shifted=total << (8'd40-{4'b0,exponent});sticky=|shifted;
            rounded={1'b0,window[24:1]}+{{24{1'b0}},(window[0] && (sticky || window[1]))};
            biased=8'd127+{4'b0,exponent}+{7'b0,rounded[24]};
            round_total={1'b0,biased,(rounded[24] ? rounded[23:1] : rounded[22:0])};
        end
    endfunction
    wire [32:0] denominator_rec,one_rec,quotient;
    reg [32:0] inverse;
    wire divide_ready,divide_valid,unused_sqrt;
    wire [4:0] divide_flags;
    // HardFloat uses an asynchronous reset. Never drive it directly from a
    // multi-bit state decode: RECIP_START (7) -> RECIP_WAIT (8) can momentarily
    // decode IDLE/ERROR after routing and cancel an accepted division. The
    // registered level is released well before RECIP_START; CLEAR withdraws
    // public validity immediately and resets the divider at the next edge.
    (* DONT_TOUCH="yes" *) reg divide_reset_n_q;
    always @(posedge clk)
        divide_reset_n_q<=alive && state!=IDLE && state!=ERROR;
    fNToRecFN #(8,24) decode_denominator(.in(denominator),.out(denominator_rec));
    fNToRecFN #(8,24) decode_one(.in(32'h3f800000),.out(one_rec));
    divSqrtRecFN_small #(8,24,0) divide(
        .nReset(divide_reset_n_q),.clock(clk),.control(1'b1),.inReady(divide_ready),
        .inValid(state==RECIP_START && alive),.sqrtOp(1'b0),.a(one_rec),.b(denominator_rec),
        .roundingMode(3'b000),.outValid(divide_valid),.sqrtOpOut(unused_sqrt),
        .out(quotient),.exceptionFlags(divide_flags));

    reg [3:0] probability_valid;
    reg [14:0] probability_index [0:3];
    reg [31:0] exp_sample;
    reg [15:0] output_probability;
    reg probability_error;
    wire probability_state=state==PROB_READ || state==PROB_DRAIN;
    wire probability_advance=probability_state && (!probability_valid[3] || out_ready) && alive;
    wire probability_issue=state==PROB_READ && probability_advance;
    wire [32:0] exp_sample_rec,product;
    wire product_error;
    wire [16:0] product_bf16_rec;
    wire [15:0] product_bf16;
    wire [4:0] product_flags;
    fNToRecFN #(8,24) decode_exp_sample(.in(exp_sample),.out(exp_sample_rec));
    qwen_fp32_mul_stage scale_probability(.clk(clk),.advance(probability_advance),.a(exp_sample_rec),
        .b(inverse),.in_error(1'b0),.result(product),.out_error(product_error));
    recFNToRecFN #(8,24,8,8) narrow_probability(.control(1'b1),.in(product),.roundingMode(3'b000),
        .out(product_bf16_rec),.exceptionFlags(product_flags));
    recFNToFN #(8,8) encode_probability(.in(product_bf16_rec),.out(product_bf16));
    assign out_valid=(PRIVATE_STREAM_STATE_ONLY || alive) && ((probability_state && probability_valid[3]) || state==ERROR);
    assign out_index=state==ERROR ? 15'b0 : probability_index[3];
    assign out_last=state==ERROR || {1'b0,probability_index[3]}==length-1'b1;
    assign probability=state==ERROR ? 16'b0 : output_probability;
    assign out_error=state==ERROR || probability_error;

    always @(posedge clk) if(alive) begin
        if(input_accept)scores[load_count[14:0]]<=score;
        if(exp_issue)score_sample<=scores[exp_read_count[14:0]];
        if(exp_take)exponentials[exp_index[8]]<=exp_bits;
        if(probability_issue)exp_sample<=exponentials[prob_read_count[14:0]];
    end
    integer i;
    always @(posedge clk) begin
        if(!rst_n || clear)begin
            state<=IDLE;length<=0;load_count<=0;exp_read_count<=0;prob_read_count<=0;maximum<=0;
            score_sample_valid<=0;distance_valid<=0;probability_valid<=0;
            sum_bits<=0;carry_bits<=0;low_sum<=0;exact_total<=0;denominator<=0;inverse<=0;
            output_probability<=0;probability_error<=0;
        end else begin
            score_sample_valid<=exp_issue;score_sample_index<=exp_read_count[14:0];
            distance_valid<={distance_valid[0],score_sample_valid};
            distance_index[0]<=score_sample_index;distance_index[1]<=distance_index[0];
            if(exp_in_ready)begin
                exp_index[0]<=distance_index[1];
                for(i=1;i<9;i=i+1)exp_index[i]<=exp_index[i-1];
            end
            if(probability_advance)begin
                probability_valid<={probability_valid[2:0],probability_issue};
                probability_index[0]<=prob_read_count[14:0];
                for(i=1;i<4;i=i+1)probability_index[i]<=probability_index[i-1];
                output_probability<=product_bf16;
                probability_error<=product_error || |product_flags[4:2] || product_bf16>16'h3f80;
            end
            if((input_accept && score_nonfinite) || (exp_take && (exp_error || exp_bits>32'h3f800000)) ||
                ((state==EXP_READ || state==EXP_DRAIN) && distance_valid[1] && distance_error && distance_bits!=32'h7f800000))
                state<=ERROR;
            else case(state)
                IDLE: begin
                    score_sample_valid<=0;distance_valid<=0;probability_valid<=0;probability_error<=0;
                    if(start_valid)begin
                        length<=context_length;load_count<=0;exp_read_count<=0;prob_read_count<=0;
                        sum_bits<=0;carry_bits<=0;maximum<=0;
                        state<=context_length==0 || context_length>16'd32768 ? ERROR : LOAD;
                    end
                end
                LOAD:if(input_accept)begin
                    if(load_count==0 || score_greater)maximum<=score;
                    load_count<=load_count+1'b1;
                    if(load_count==length-1'b1)state<=EXP_READ;
                end
                EXP_READ,EXP_DRAIN:begin
                    if(exp_issue)begin
                        exp_read_count<=exp_read_count+1'b1;
                        if(exp_read_count==length-1'b1)state<=EXP_DRAIN;
                    end
                    if(exp_take)begin
                        sum_bits<=sum_bits ^ carry_bits ^ exp_integer;
                        carry_bits<=((sum_bits & carry_bits) | (sum_bits & exp_integer) | (carry_bits & exp_integer)) << 1;
                        if({1'b0,exp_index[8]}==length-1'b1)state<=SUM_LOW;
                    end
                end
                SUM_LOW:begin low_sum<={1'b0,sum_bits[95:0]}+{1'b0,carry_bits[95:0]};state<=SUM_HIGH;end
                SUM_HIGH:begin
                    exact_total<={high_sum[68:0],low_sum[95:0]};state<=high_sum[69] ? ERROR : SUM_ROUND;
                end
                SUM_ROUND:begin
                    denominator<=round_total(exact_total);
                    state<=exact_total[164:149]==0 || (exact_total[164] && |exact_total[163:0]) ? ERROR : RECIP_START;
                end
                RECIP_START:if(divide_ready)state<=RECIP_WAIT;
                RECIP_WAIT:if(divide_valid)begin
                    inverse<=quotient;state<=|divide_flags[4:2] ? ERROR : PROB_READ;
                end
                PROB_READ,PROB_DRAIN:begin
                    if(probability_issue)begin
                        prob_read_count<=prob_read_count+1'b1;
                        if(prob_read_count==length-1'b1)state<=PROB_DRAIN;
                    end
                    if(out_valid && out_ready && out_last)state<=IDLE;
                end
                ERROR:if(out_ready)state<=IDLE;
                default:state<=ERROR;
            endcase
        end
    end
    wire unused_flags=^{divide_flags[1:0],product_flags[1:0]};
endmodule
