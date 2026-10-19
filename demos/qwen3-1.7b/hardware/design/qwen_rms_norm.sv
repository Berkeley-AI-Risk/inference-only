// PRIVATE RMSNorm speed candidate. The ordered FP32 sum, mean, sqrt,
// reciprocal and two BF16 rounding boundaries match qwen_rms_norm exactly.
// Only independent elements in the output pass overlap. This module has no
// host arithmetic/configuration port. Not yet qualified for FPGA deployment.
module qwen_rms_norm (
    input wire clk, rst_n, clear, start, head_mode,
    input wire in_valid,
    output wire in_ready,
    input wire [15:0] activation, norm_weight,
    output wire out_valid,
    input wire out_ready,
    output wire [10:0] out_index,
    output wire [15:0] result,
    output wire out_error,
    output wire busy
);
    localparam [3:0] IDLE=0, LOAD=1, DRAIN=2, MEAN_LAUNCH=3, MEAN_WAIT=4,
        SQRT_LAUNCH=5, SQRT_WAIT=6, RECIP_LAUNCH=7, RECIP_WAIT=8,
        STREAM=9, ERROR=15;
    reg [3:0] state;
    reg short_vector;
    reg [10:0] input_index, sum_index, issue_index;
    wire [10:0] last_index=short_vector ? 11'd127 : 11'd2047;
    wire alive=rst_n && !clear;
    assign in_ready=state==LOAD && alive;
    wire input_accept=in_valid && in_ready;
    assign busy=state!=IDLE;
    (* ram_style="block" *) reg [31:0] values [0:2047];
    reg [31:0] sample;

    // One common enable freezes every payload, tag, valid bit and arithmetic
    // stage when the final result is stalled. Read latency is stage zero.
    reg [4:0] stream_valid;
    reg [10:0] stream_index [0:4];
    reg issued_all;
    wire stream_advance=alive && state==STREAM && (!stream_valid[4] || out_ready);
    wire stream_issue=stream_advance && !issued_all;
    always @(posedge clk) if(rst_n) begin
        if(input_accept) values[input_index]<={norm_weight,activation};
        if(stream_issue) sample<=values[issue_index];
    end

    reg [32:0] sum, mean_epsilon, root, inverse;
    wire [32:0] input_rec, mean_factor_rec, epsilon_rec, one_rec;
    fNToRecFN #(8,24) decode_input(.in({activation,16'b0}),.out(input_rec));
    fNToRecFN #(8,24) decode_mean_factor(.in(short_vector ? 32'h3c000000 : 32'h3a000000),.out(mean_factor_rec));
    fNToRecFN #(8,24) decode_epsilon(.in(32'h358637bd),.out(epsilon_rec));
    fNToRecFN #(8,24) decode_one(.in(32'h3f800000),.out(one_rec));
    wire input_nonfinite=(&activation[14:7]) || (&norm_weight[14:7]);
    wire mul_launch=alive && (input_accept || state==MEAN_LAUNCH);
    reg [1:0] mul_valid;
    wire [32:0] product;
    wire mul_error;
    qwen_fp32_mul_stage multiply(
        .clk(clk),.advance(alive),
        .a(state==MEAN_LAUNCH ? sum : input_rec),
        .b(state==MEAN_LAUNCH ? mean_factor_rec : input_rec),
        .in_error(1'b0),.result(product),.out_error(mul_error)
    );
    wire [32:0] addition, mean_addition;
    wire [4:0] add_flags, mean_add_flags;
    addRecFN #(8,24) add(
        .control(1'b1),.subOp(1'b0),.a(sum),
        .b(product),.roundingMode(3'b000),
        .out(addition),.exceptionFlags(add_flags)
    );
    // Fixed private mean path: no FSM operand mux ahead of either adder.
    addRecFN #(8,24) add_mean(
        .control(1'b1),.subOp(1'b0),.a(product),.b(epsilon_rec),
        .roundingMode(3'b000),.out(mean_addition),.exceptionFlags(mean_add_flags)
    );
    wire divide_ready, divide_valid, unused_sqrt;
    wire [32:0] quotient;
    wire [4:0] divide_flags;
    wire divide_launch=alive && (state==SQRT_LAUNCH || state==RECIP_LAUNCH);
    divSqrtRecFN_small #(8,24,0) divide_sqrt(
        .nReset(alive),.clock(clk),.control(1'b1),.inReady(divide_ready),
        .inValid(divide_launch),.sqrtOp(state==SQRT_LAUNCH),
        .a(state==SQRT_LAUNCH ? mean_epsilon : one_rec),.b(root),
        .roundingMode(3'b000),.outValid(divide_valid),.sqrtOpOut(unused_sqrt),
        .out(quotient),.exceptionFlags(divide_flags)
    );

    wire [32:0] sample_rec, norm_product, normalized_rec, weight_rec, weighted_product;
    wire norm_error, weight_error;
    reg [15:0] weight_delay1, weight_delay2;
    fNToRecFN #(8,24) decode_sample(.in({sample[15:0],16'b0}),.out(sample_rec));
    qwen_fp32_mul_stage normalize(
        .clk(clk),.advance(stream_advance),.a(sample_rec),.b(inverse),
        .in_error(1'b0),.result(norm_product),.out_error(norm_error)
    );
    wire [16:0] normalized_bf16_rec, weighted_bf16_rec;
    wire [15:0] normalized_bf16, weighted_bf16;
    wire [4:0] norm_flags, weight_flags;
    recFNToRecFN #(8,24,8,8) round_normalized(
        .control(1'b1),.in(norm_product),.roundingMode(3'b000),
        .out(normalized_bf16_rec),.exceptionFlags(norm_flags)
    );
    recFNToFN #(8,8) encode_normalized(.in(normalized_bf16_rec),.out(normalized_bf16));
    fNToRecFN #(8,24) decode_normalized(.in({normalized_bf16,16'b0}),.out(normalized_rec));
    fNToRecFN #(8,24) decode_weight(.in({weight_delay2,16'b0}),.out(weight_rec));
    qwen_fp32_mul_stage weight_multiply(
        .clk(clk),.advance(stream_advance),.a(normalized_rec),.b(weight_rec),
        .in_error(norm_error || (|norm_flags[4:2]) || (&normalized_bf16[14:7])),
        .result(weighted_product),.out_error(weight_error)
    );
    recFNToRecFN #(8,24,8,8) round_weighted(
        .control(1'b1),.in(weighted_product),.roundingMode(3'b000),
        .out(weighted_bf16_rec),.exceptionFlags(weight_flags)
    );
    recFNToFN #(8,8) encode_weighted(.in(weighted_bf16_rec),.out(weighted_bf16));
    wire stream_error=weight_error || (|weight_flags[4:2]) || (&weighted_bf16[14:7]);
    assign out_valid=alive && (state==ERROR || (state==STREAM && stream_valid[4]));
    assign out_error=state==ERROR || (state==STREAM && stream_valid[4] && stream_error);
    assign out_index=state==STREAM ? stream_index[4] : 11'd0;
    assign result=weighted_bf16;

    integer lane;
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            state<=IDLE; short_vector<=0; input_index<=0; sum_index<=0;
            issue_index<=0; mul_valid<=0; sum<=0; mean_epsilon<=0;
            root<=0; inverse<=0; stream_valid<=0; issued_all<=0;
            weight_delay1<=0; weight_delay2<=0;
            for(lane=0;lane<5;lane=lane+1) stream_index[lane]<=0;
        end else begin
            mul_valid<={mul_valid[0],mul_launch};
            if(stream_advance) begin
                stream_valid<={stream_valid[3:0],!issued_all};
                stream_index[0]<=issue_index;
                for(lane=1;lane<5;lane=lane+1) stream_index[lane]<=stream_index[lane-1];
                weight_delay1<=sample[31:16]; weight_delay2<=weight_delay1;
                if(!issued_all) begin
                    if(issue_index==last_index) issued_all<=1;
                    else issue_index<=issue_index+1'b1;
                end
            end
            if((input_accept && input_nonfinite)
                    || (state!=IDLE && state!=ERROR && mul_valid[1] && mul_error))
                state<=ERROR;
            else case(state)
                IDLE: if(start) begin
                    short_vector<=head_mode; input_index<=0; sum_index<=0;
                    issue_index<=0; sum<=0; mul_valid<=0; state<=LOAD;
                    stream_valid<=0; issued_all<=0;
                end
                LOAD,DRAIN: begin
                    if(input_accept) begin
                        if(input_index==last_index) state<=DRAIN;
                        else input_index<=input_index+1'b1;
                    end
                    if(mul_valid[1]) begin
                        if(|add_flags[4:2]) state<=ERROR;
                        else begin
                            sum<=addition;
                            if(sum_index==last_index) state<=MEAN_LAUNCH;
                            else sum_index<=sum_index+1'b1;
                        end
                    end
                end
                MEAN_LAUNCH: state<=MEAN_WAIT;
                MEAN_WAIT: if(mul_valid[1]) begin
                    if(|mean_add_flags[4:2]) state<=ERROR;
                    else begin mean_epsilon<=mean_addition; state<=SQRT_LAUNCH; end
                end
                SQRT_LAUNCH: if(divide_ready) state<=SQRT_WAIT;
                SQRT_WAIT: if(divide_valid) begin
                    if(|divide_flags[4:2]) state<=ERROR;
                    else begin root<=quotient; state<=RECIP_LAUNCH; end
                end
                RECIP_LAUNCH: if(divide_ready) state<=RECIP_WAIT;
                RECIP_WAIT: if(divide_valid) begin
                    if(|divide_flags[4:2]) state<=ERROR;
                    else begin inverse<=quotient; state<=STREAM; end
                end
                STREAM: if(out_valid && out_ready && (out_error || out_index==last_index)) begin
                    state<=IDLE; stream_valid<=0;
                end
                ERROR: if(out_ready) begin state<=IDLE; stream_valid<=0; end
                default: state<=ERROR;
            endcase
        end
    end
    wire unused_flags=^{add_flags[1:0],mean_add_flags[1:0],divide_flags[1:0],norm_flags[1:0],weight_flags[1:0]};
endmodule
