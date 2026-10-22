// PRIVATE BF16 addition/multiplication for residuals, gates and rotary math.
// The fixed model controller owns both operands and operation selection;
// none of these ports is an application interface. Four-register pipeline,
// FP32 calculation then BF16 round-to-nearest-even, global backpressure and
// cancellation by CLEAR. FP32 also avoids the upstream raw adder's alignment
// saturation issue at precision exactly 8 (BF16 0x0100 + 0x0001 is a tie).
module qwen_bf16_elementwise (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    output wire in_ready,
    input wire multiply,
    input wire [15:0] a,
    input wire [15:0] b,
    output wire out_valid,
    input wire out_ready,
    output reg [15:0] result,
    output reg out_error
);
    reg [3:0] valid;
    wire advance=(!valid[3] || out_ready) && rst_n && !clear;
    assign in_ready=advance;
    assign out_valid=valid[3] && rst_n && !clear;
    wire [32:0] a_rec,b_rec;
    fNToRecFN #(8,24) decode_a(.in({a,16'b0}),.out(a_rec));
    fNToRecFN #(8,24) decode_b(.in({b,16'b0}),.out(b_rec));
    reg [32:0] a0,b0;
    reg multiply0,error0;
    wire add_invalid,add_nan,add_inf,add_zero,add_sign;
    wire mul_invalid,mul_nan,mul_inf,mul_zero,mul_sign;
    wire signed [9:0] add_exp,mul_exp;
    wire [26:0] add_sig,mul_sig;
    addRecFNToRaw #(8,24) add_raw(
        .control(1'b1),.subOp(1'b0),.a(a0),.b(b0),.roundingMode(3'b000),
        .invalidExc(add_invalid),.out_isNaN(add_nan),.out_isInf(add_inf),
        .out_isZero(add_zero),.out_sign(add_sign),.out_sExp(add_exp),.out_sig(add_sig)
    );
    mulRecFNToRaw #(8,24) mul_raw(
        .control(1'b1),.a(a0),.b(b0),.invalidExc(mul_invalid),.out_isNaN(mul_nan),
        .out_isInf(mul_inf),.out_isZero(mul_zero),.out_sign(mul_sign),
        .out_sExp(mul_exp),.out_sig(mul_sig)
    );
    reg invalid1,nan1,inf1,zero1,sign1,error1;
    reg signed [9:0] exp1;
    reg [26:0] sig1;
    wire [32:0] rounded;
    reg [32:0] rounded2;
    reg error2;
    wire [16:0] bf16_rec;
    wire [15:0] standard;
    wire [4:0] flags,bf16_flags;
    roundRawFNToRecFN #(8,24,0) round_result(
        .control(1'b1),.invalidExc(invalid1),.infiniteExc(1'b0),
        .in_isNaN(nan1),.in_isInf(inf1),.in_isZero(zero1),.in_sign(sign1),
        .in_sExp(exp1),.in_sig(sig1),.roundingMode(3'b000),
        .out(rounded),.exceptionFlags(flags)
    );
    recFNToRecFN #(8,24,8,8) narrow_result(
        .control(1'b1),.in(rounded2),.roundingMode(3'b000),
        .out(bf16_rec),.exceptionFlags(bf16_flags)
    );
    recFNToFN #(8,8) encode(.in(bf16_rec),.out(standard));
    always @(posedge clk) begin
        if(!rst_n || clear) begin valid<=0;result<=0;out_error<=0;end
        else if(advance) begin
            valid<={valid[2:0],in_valid};
            a0<=a_rec;b0<=b_rec;multiply0<=multiply;
            error0<=(&a[14:7]) || (&b[14:7]);
            invalid1<=multiply0 ? mul_invalid : add_invalid;
            nan1<=multiply0 ? mul_nan : add_nan;
            inf1<=multiply0 ? mul_inf : add_inf;
            zero1<=multiply0 ? mul_zero : add_zero;
            sign1<=multiply0 ? mul_sign : add_sign;
            exp1<=multiply0 ? mul_exp : add_exp;
            sig1<=multiply0 ? mul_sig : add_sig;
            error1<=error0;
            rounded2<=rounded;
            error2<=error1 || nan1 || inf1 || (|flags[4:2]);
            result<=standard;
            out_error<=error2 || (|bf16_flags[4:2]) || (&standard[14:7]);
        end
    end
    wire unused_flags=^{flags[1:0],bf16_flags[1:0]};
endmodule
