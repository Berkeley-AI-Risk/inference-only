// PRIVATE projection rescaling with a globally stalled six-stage pipeline:
// BF16_RNE(FP32_RNE(FP32_RNE(sum40) * row_scale) * vector_scale).
// Scales must be finite and positive. The fixed model's internal controller
// supplies them; they are NOT application operands or programmable settings.
module qwen_projection_scale (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    output wire in_ready,
    input wire signed [39:0] integer_sum,
    input wire [31:0] row_scale,
    input wire [31:0] vector_scale,
    output wire out_valid,
    input wire out_ready,
    output reg [15:0] result,
    output reg out_error
);
    reg [5:0] valid;
    wire advance = (!valid[5] || out_ready) && rst_n && !clear;
    assign in_ready = advance;
    assign out_valid = valid[5] && rst_n && !clear;
    wire [32:0] converted, row_recoded, vector_recoded;
    wire [4:0] conversion_flags;
    iNToRecFN #(40,8,24) integer_to_float(
        .control(1'b1), .signedIn(1'b1), .in(integer_sum),
        .roundingMode(3'b000), .out(converted), .exceptionFlags(conversion_flags)
    );
    fNToRecFN #(8,24) decode_row(.in(row_scale), .out(row_recoded));
    fNToRecFN #(8,24) decode_vector(.in(vector_scale), .out(vector_recoded));
    reg [32:0] sum0, row0, vector0, vector1, vector2;
    reg error0;
    wire [32:0] product2, product4;
    wire error2, error4;
    qwen_fp32_mul_stage first_multiply(
        .clk(clk), .advance(advance), .a(sum0), .b(row0),
        .in_error(error0), .result(product2), .out_error(error2)
    );
    qwen_fp32_mul_stage second_multiply(
        .clk(clk), .advance(advance), .a(product2), .b(vector2),
        .in_error(error2), .result(product4), .out_error(error4)
    );
    wire [16:0] bf16_recoded;
    wire [15:0] bf16_standard;
    wire [4:0] bf16_flags;
    recFNToRecFN #(8,24,8,8) round_bf16(
        .control(1'b1), .in(product4), .roundingMode(3'b000),
        .out(bf16_recoded), .exceptionFlags(bf16_flags)
    );
    recFNToFN #(8,8) encode_result(.in(bf16_recoded), .out(bf16_standard));
    wire scales_invalid = row_scale[31] || vector_scale[31]
        || &row_scale[30:23] || &vector_scale[30:23]
        || !(|row_scale[30:0]) || !(|vector_scale[30:0]);
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            valid <= 0;
            result <= 0;
            out_error <= 0;
        end else if (advance) begin
            valid <= {valid[4:0], in_valid};
            sum0 <= converted;
            row0 <= row_recoded;
            vector0 <= vector_recoded;
            vector1 <= vector0;
            vector2 <= vector1;
            error0 <= scales_invalid || |conversion_flags[4:2];
            result <= bf16_standard;
            out_error <= error4 || |bf16_flags[4:2] || &bf16_standard[14:7];
        end
    end
    wire unused_flags = ^{conversion_flags[1:0], bf16_flags[1:0]};
endmodule
