// PRIVATE two-register FP32 RNE adder. The pipeline owner supplies valid,
// cancellation and global advance. No application arithmetic interface.
module qwen_fp32_add_stage (
    input wire clk,
    input wire advance,
    input wire [32:0] a,
    input wire [32:0] b,
    input wire in_error,
    output reg [32:0] result,
    output reg out_error
);
    wire invalid_next,nan_next,inf_next,zero_next,sign_next;
    wire signed [9:0] exponent_next;
    wire [26:0] significand_next;
    reg invalid_reg,nan_reg,inf_reg,zero_reg,sign_reg,error_reg;
    reg signed [9:0] exponent_reg;
    reg [26:0] significand_reg;
    wire [32:0] rounded;
    wire [4:0] flags;
    addRecFNToRaw #(8,24) add_raw(
        .control(1'b1),.subOp(1'b0),.a(a),.b(b),.roundingMode(3'b000),
        .invalidExc(invalid_next),.out_isNaN(nan_next),.out_isInf(inf_next),
        .out_isZero(zero_next),.out_sign(sign_next),.out_sExp(exponent_next),
        .out_sig(significand_next)
    );
    roundRawFNToRecFN #(8,24,0) round_sum(
        .control(1'b1),.invalidExc(invalid_reg),.infiniteExc(1'b0),
        .in_isNaN(nan_reg),.in_isInf(inf_reg),.in_isZero(zero_reg),
        .in_sign(sign_reg),.in_sExp(exponent_reg),.in_sig(significand_reg),
        .roundingMode(3'b000),.out(rounded),.exceptionFlags(flags)
    );
    always @(posedge clk) if(advance) begin
        invalid_reg<=invalid_next;nan_reg<=nan_next;inf_reg<=inf_next;
        zero_reg<=zero_next;sign_reg<=sign_next;exponent_reg<=exponent_next;
        significand_reg<=significand_next;error_reg<=in_error;
        result<=rounded;
        out_error<=error_reg || nan_reg || inf_reg || |flags[4:2];
    end
    wire unused_flags=^flags[1:0];
endmodule
