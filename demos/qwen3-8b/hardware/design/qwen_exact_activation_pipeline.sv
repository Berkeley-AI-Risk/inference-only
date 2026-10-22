// PRIVATE fixed-latency implementation of the existing BF16 -> A16 rule.
// Contract: finite BF16 x belongs to a loaded vector whose nonzero maximum M
// gave scale = FP32_RNE(M / 32767). This is not a general floating divider.
// Exact integer division is followed by a correction for BOTH rounding steps:
// RNE_integer(FP32_RNE(x/scale)), clamped to [-32767,32767].
// The caller reserves output space before asserting in_valid. No host interface.
module qwen_exact_activation_pipeline (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    input wire [15:0] activation,
    input wire [31:0] vector_scale,
    output wire out_valid,
    output reg signed [15:0] code
);
    wire [7:0] xe=activation[14:7];
    wire [7:0] se=vector_scale[30:23];
    wire [7:0] xm={|xe,activation[6:0]};
    wire [23:0] divisor={|se,vector_scale[22:0]};
    wire signed [9:0] shift=$signed({2'b0,(xe==0 ? 8'd1 : xe)})
        -$signed({2'b0,(se==0 ? 8'd1 : se)})+10'sd16;
    wire [38:0] numerator=(shift<0 || shift>31) ? 39'b0
        : {31'b0,xm} << shift[4:0];
    wire saturate=(|xm) && (shift>31 || {1'b0,numerator[38:16]}>=divisor);

    reg [17:0] valid;
    reg [16:0] negative, clipped;
    reg [23:0] remainder [0:16];
    reg [23:0] denominator [0:16];
    reg [15:0] quotient [0:16];
    assign out_valid=valid[17] && rst_n && !clear;

    // Only validity is reset. Invalid arithmetic payload never controls state.
    always @(posedge clk) begin
        if(!rst_n || clear) valid<=0;
        else valid<={valid[16:0],in_valid};
        negative[0]<=activation[15];
        clipped[0]<=saturate;
        denominator[0]<=divisor;
        remainder[0]<=saturate ? 24'b0 : {1'b0,numerator[38:16]};
        quotient[0]<=saturate ? 16'b0 : numerator[15:0];
    end
    genvar stage;
    generate for(stage=0;stage<16;stage=stage+1) begin: divide_bits
        wire [24:0] trial={remainder[stage],quotient[stage][15]};
        wire take=trial>={1'b0,denominator[stage]};
        wire [24:0] reduced=trial-{1'b0,denominator[stage]};
        always @(posedge clk) begin
            remainder[stage+1]<=take ? reduced[23:0] : trial[23:0];
            quotient[stage+1]<={quotient[stage][14:0],take};
            denominator[stage+1]<=denominator[stage];
            negative[stage+1]<=negative[stage];
            clipped[stage+1]<=clipped[stage];
        end
    end endgenerate

    // N+1/2 has an even binary32 significand. Its FP32 rounding interval must
    // be included before integer ties-to-even. The N=0 case uses its upper
    // interval, which is the only boundary relevant when rounding to even zero.
    reg [4:0] epsilon_shift;
    integer bit_index;
    always @* begin
        epsilon_shift=5'd24;
        for(bit_index=0;bit_index<15;bit_index=bit_index+1)
            if(quotient[16][bit_index]) epsilon_shift=5'(23-bit_index);
    end
    wire [23:0] epsilon=denominator[16] >> epsilon_shift;
    wire signed [25:0] delta=$signed({1'b0,remainder[16],1'b0})
        -$signed({2'b0,denominator[16]});
    wire round_up=quotient[16][0] ? delta>=-$signed({2'b0,epsilon})
        : delta>$signed({2'b0,epsilon});
    wire [15:0] magnitude=(clipped[16] || quotient[16]>=16'd32767)
        ? 16'd32767 : quotient[16]+{15'b0,round_up};
    always @(posedge clk) code<=negative[16] ? -$signed(magnitude) : $signed(magnitude);
endmodule
