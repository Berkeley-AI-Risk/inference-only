`timescale 1ns/1ps
`default_nettype none

// Fixed-model projection-vector commit and BFP-v5 normalizer.
//
// This module is below the sealed six-layer controller.  layer/job, raw
// values, exponents, and result vectors are private integration seams.  The
// user-visible machine has no access to them and gains no length, address,
// shift, normalization, or arithmetic operation from this block.
module board1_fixed_vector_normalizer #(
    parameter integer MAX_COMPUTE_CYCLES = 2_000_000
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [2:0]              fixed_layer_i,
    input  wire [3:0]              fixed_job_i,

    input  wire                    input_valid_i,
    output logic                   input_ready_o,
    input  wire [9:0]              input_row_index_i,
    input  wire signed [49:0]      input_raw_i,
    input  wire signed [7:0]       input_source_exponent_i,
    input  wire                    input_last_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [9:0]             result_row_index_o,
    output logic signed [15:0]     result_mantissa_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,
    output logic                   busy_o,
    output logic                   range_fault_o
);
    localparam signed [63:0] I16_MAXIMUM = 64'sd32767;
    localparam signed [63:0] I16_MINIMUM = -64'sd32767;

    typedef enum logic [3:0] {
        ST_IDLE        = 4'd0,
        ST_CAPTURE     = 4'd1,
        ST_SELECT_READ = 4'd2,
        ST_SELECT_EVAL = 4'd3,
        ST_FIND_READ   = 4'd4,
        ST_FIND_ISSUE  = 4'd5,
        ST_SHIFT_WAIT  = 4'd6,
        ST_WRITE_READ  = 4'd7,
        ST_WRITE_ISSUE = 4'd8,
        ST_RESULT      = 4'd9,
        ST_DONE        = 4'd10,
        ST_SELECT_BITS = 4'd11,
        ST_SELECT_EXP  = 4'd12,
        ST_FAULT       = 4'd15
    } state_t;

    localparam logic SHIFT_CLIENT_FIND  = 1'b0;
    localparam logic SHIFT_CLIENT_WRITE = 1'b1;

    function automatic [9:0] rows_for_job(input logic [3:0] job);
        case (job)
            4'd0, 4'd3, 4'd6: rows_for_job = 10'd256;
            4'd1, 4'd2:       rows_for_job = 10'd128;
            4'd4, 4'd5:       rows_for_job = 10'd682;
            default:          rows_for_job = 10'd0;
        endcase
    endfunction

    // Lower bound used by the accepted BFP-v5 oracle.  A subsequent exact
    // RNE fit pass catches the one-bit rounding carry case and retries at the
    // next coarser exponent.  This is equivalent to the older exhaustive
    // candidate scan for every legal vector but avoids rescanning obviously
    // impossible exponents.
    function automatic signed [7:0] first_fit_exponent50(
        input signed [49:0] value,
        input signed [7:0] source_exponent
    );
        logic [49:0] fit_present;
        logic [5:0] bit_length;
        logic signed [9:0] required;
        logic [5:0] fit_bits_0_49;
        logic [5:0] fit_bits_0_24;
        logic [5:0] fit_bits_0_12;
        logic [5:0] fit_bits_0_6;
        logic [5:0] fit_bits_0_3;
        logic [5:0] fit_bits_4_6;
        logic [5:0] fit_bits_7_12;
        logic [5:0] fit_bits_7_9;
        logic [5:0] fit_bits_10_12;
        logic [5:0] fit_bits_13_24;
        logic [5:0] fit_bits_13_18;
        logic [5:0] fit_bits_13_15;
        logic [5:0] fit_bits_16_18;
        logic [5:0] fit_bits_19_24;
        logic [5:0] fit_bits_19_21;
        logic [5:0] fit_bits_22_24;
        logic [5:0] fit_bits_25_49;
        logic [5:0] fit_bits_25_37;
        logic [5:0] fit_bits_25_31;
        logic [5:0] fit_bits_25_28;
        logic [5:0] fit_bits_29_31;
        logic [5:0] fit_bits_32_37;
        logic [5:0] fit_bits_32_34;
        logic [5:0] fit_bits_35_37;
        logic [5:0] fit_bits_38_49;
        logic [5:0] fit_bits_38_43;
        logic [5:0] fit_bits_38_40;
        logic [5:0] fit_bits_41_43;
        logic [5:0] fit_bits_44_49;
        logic [5:0] fit_bits_44_46;
        logic [5:0] fit_bits_47_49;
        begin
            if (value == 0) begin
                first_fit_exponent50 = -8'sd32;
            end else begin
                fit_present = 50'd0;
                // A positive input uses its known-one bits. A negative
                // input reaches bit k iff value <= -2**k. Constant
                // thresholds need no absolute-value carry chain.
                // Unknown sign enters the comparison branch; like the
                // original unary negate, unknown data sets no fit bits.
                if (!value[49]) begin
                    if (value[0]) fit_present[0] = 1'b1;
                    if (value[1]) fit_present[1] = 1'b1;
                    if (value[2]) fit_present[2] = 1'b1;
                    if (value[3]) fit_present[3] = 1'b1;
                    if (value[4]) fit_present[4] = 1'b1;
                    if (value[5]) fit_present[5] = 1'b1;
                    if (value[6]) fit_present[6] = 1'b1;
                    if (value[7]) fit_present[7] = 1'b1;
                    if (value[8]) fit_present[8] = 1'b1;
                    if (value[9]) fit_present[9] = 1'b1;
                    if (value[10]) fit_present[10] = 1'b1;
                    if (value[11]) fit_present[11] = 1'b1;
                    if (value[12]) fit_present[12] = 1'b1;
                    if (value[13]) fit_present[13] = 1'b1;
                    if (value[14]) fit_present[14] = 1'b1;
                    if (value[15]) fit_present[15] = 1'b1;
                    if (value[16]) fit_present[16] = 1'b1;
                    if (value[17]) fit_present[17] = 1'b1;
                    if (value[18]) fit_present[18] = 1'b1;
                    if (value[19]) fit_present[19] = 1'b1;
                    if (value[20]) fit_present[20] = 1'b1;
                    if (value[21]) fit_present[21] = 1'b1;
                    if (value[22]) fit_present[22] = 1'b1;
                    if (value[23]) fit_present[23] = 1'b1;
                    if (value[24]) fit_present[24] = 1'b1;
                    if (value[25]) fit_present[25] = 1'b1;
                    if (value[26]) fit_present[26] = 1'b1;
                    if (value[27]) fit_present[27] = 1'b1;
                    if (value[28]) fit_present[28] = 1'b1;
                    if (value[29]) fit_present[29] = 1'b1;
                    if (value[30]) fit_present[30] = 1'b1;
                    if (value[31]) fit_present[31] = 1'b1;
                    if (value[32]) fit_present[32] = 1'b1;
                    if (value[33]) fit_present[33] = 1'b1;
                    if (value[34]) fit_present[34] = 1'b1;
                    if (value[35]) fit_present[35] = 1'b1;
                    if (value[36]) fit_present[36] = 1'b1;
                    if (value[37]) fit_present[37] = 1'b1;
                    if (value[38]) fit_present[38] = 1'b1;
                    if (value[39]) fit_present[39] = 1'b1;
                    if (value[40]) fit_present[40] = 1'b1;
                    if (value[41]) fit_present[41] = 1'b1;
                    if (value[42]) fit_present[42] = 1'b1;
                    if (value[43]) fit_present[43] = 1'b1;
                    if (value[44]) fit_present[44] = 1'b1;
                    if (value[45]) fit_present[45] = 1'b1;
                    if (value[46]) fit_present[46] = 1'b1;
                    if (value[47]) fit_present[47] = 1'b1;
                    if (value[48]) fit_present[48] = 1'b1;
                    if (value[49]) fit_present[49] = 1'b1;
                end else begin
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1)
                        fit_present[0] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2)
                        fit_present[1] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4)
                        fit_present[2] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8)
                        fit_present[3] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16)
                        fit_present[4] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd32)
                        fit_present[5] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd64)
                        fit_present[6] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd128)
                        fit_present[7] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd256)
                        fit_present[8] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd512)
                        fit_present[9] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1024)
                        fit_present[10] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2048)
                        fit_present[11] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4096)
                        fit_present[12] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8192)
                        fit_present[13] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16384)
                        fit_present[14] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd32768)
                        fit_present[15] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd65536)
                        fit_present[16] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd131072)
                        fit_present[17] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd262144)
                        fit_present[18] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd524288)
                        fit_present[19] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1048576)
                        fit_present[20] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2097152)
                        fit_present[21] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4194304)
                        fit_present[22] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8388608)
                        fit_present[23] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16777216)
                        fit_present[24] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd33554432)
                        fit_present[25] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd67108864)
                        fit_present[26] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd134217728)
                        fit_present[27] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd268435456)
                        fit_present[28] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd536870912)
                        fit_present[29] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1073741824)
                        fit_present[30] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2147483648)
                        fit_present[31] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4294967296)
                        fit_present[32] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8589934592)
                        fit_present[33] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd17179869184)
                        fit_present[34] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd34359738368)
                        fit_present[35] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd68719476736)
                        fit_present[36] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd137438953472)
                        fit_present[37] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd274877906944)
                        fit_present[38] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd549755813888)
                        fit_present[39] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1099511627776)
                        fit_present[40] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2199023255552)
                        fit_present[41] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4398046511104)
                        fit_present[42] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8796093022208)
                        fit_present[43] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd17592186044416)
                        fit_present[44] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd35184372088832)
                        fit_present[45] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd70368744177664)
                        fit_present[46] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd140737488355328)
                        fit_present[47] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd281474976710656)
                        fit_present[48] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd562949953421312)
                        fit_present[49] = 1'b1;
                end
                // Parallel <=4-bit encoders followed by small-result
                // selection. No shifted 64-bit search-word dependency.
                fit_bits_0_3 = 6'd0;
                if (fit_present[0])
                    fit_bits_0_3 = 6'd1;
                if (fit_present[1])
                    fit_bits_0_3 = 6'd2;
                if (fit_present[2])
                    fit_bits_0_3 = 6'd3;
                if (fit_present[3])
                    fit_bits_0_3 = 6'd4;
                fit_bits_4_6 = 6'd0;
                if (fit_present[4])
                    fit_bits_4_6 = 6'd5;
                if (fit_present[5])
                    fit_bits_4_6 = 6'd6;
                if (fit_present[6])
                    fit_bits_4_6 = 6'd7;
                if (|fit_present[6:4])
                    fit_bits_0_6 = fit_bits_4_6;
                else
                    fit_bits_0_6 = fit_bits_0_3;
                fit_bits_7_9 = 6'd0;
                if (fit_present[7])
                    fit_bits_7_9 = 6'd8;
                if (fit_present[8])
                    fit_bits_7_9 = 6'd9;
                if (fit_present[9])
                    fit_bits_7_9 = 6'd10;
                fit_bits_10_12 = 6'd0;
                if (fit_present[10])
                    fit_bits_10_12 = 6'd11;
                if (fit_present[11])
                    fit_bits_10_12 = 6'd12;
                if (fit_present[12])
                    fit_bits_10_12 = 6'd13;
                if (|fit_present[12:10])
                    fit_bits_7_12 = fit_bits_10_12;
                else
                    fit_bits_7_12 = fit_bits_7_9;
                if (|fit_present[12:7])
                    fit_bits_0_12 = fit_bits_7_12;
                else
                    fit_bits_0_12 = fit_bits_0_6;
                fit_bits_13_15 = 6'd0;
                if (fit_present[13])
                    fit_bits_13_15 = 6'd14;
                if (fit_present[14])
                    fit_bits_13_15 = 6'd15;
                if (fit_present[15])
                    fit_bits_13_15 = 6'd16;
                fit_bits_16_18 = 6'd0;
                if (fit_present[16])
                    fit_bits_16_18 = 6'd17;
                if (fit_present[17])
                    fit_bits_16_18 = 6'd18;
                if (fit_present[18])
                    fit_bits_16_18 = 6'd19;
                if (|fit_present[18:16])
                    fit_bits_13_18 = fit_bits_16_18;
                else
                    fit_bits_13_18 = fit_bits_13_15;
                fit_bits_19_21 = 6'd0;
                if (fit_present[19])
                    fit_bits_19_21 = 6'd20;
                if (fit_present[20])
                    fit_bits_19_21 = 6'd21;
                if (fit_present[21])
                    fit_bits_19_21 = 6'd22;
                fit_bits_22_24 = 6'd0;
                if (fit_present[22])
                    fit_bits_22_24 = 6'd23;
                if (fit_present[23])
                    fit_bits_22_24 = 6'd24;
                if (fit_present[24])
                    fit_bits_22_24 = 6'd25;
                if (|fit_present[24:22])
                    fit_bits_19_24 = fit_bits_22_24;
                else
                    fit_bits_19_24 = fit_bits_19_21;
                if (|fit_present[24:19])
                    fit_bits_13_24 = fit_bits_19_24;
                else
                    fit_bits_13_24 = fit_bits_13_18;
                if (|fit_present[24:13])
                    fit_bits_0_24 = fit_bits_13_24;
                else
                    fit_bits_0_24 = fit_bits_0_12;
                fit_bits_25_28 = 6'd0;
                if (fit_present[25])
                    fit_bits_25_28 = 6'd26;
                if (fit_present[26])
                    fit_bits_25_28 = 6'd27;
                if (fit_present[27])
                    fit_bits_25_28 = 6'd28;
                if (fit_present[28])
                    fit_bits_25_28 = 6'd29;
                fit_bits_29_31 = 6'd0;
                if (fit_present[29])
                    fit_bits_29_31 = 6'd30;
                if (fit_present[30])
                    fit_bits_29_31 = 6'd31;
                if (fit_present[31])
                    fit_bits_29_31 = 6'd32;
                if (|fit_present[31:29])
                    fit_bits_25_31 = fit_bits_29_31;
                else
                    fit_bits_25_31 = fit_bits_25_28;
                fit_bits_32_34 = 6'd0;
                if (fit_present[32])
                    fit_bits_32_34 = 6'd33;
                if (fit_present[33])
                    fit_bits_32_34 = 6'd34;
                if (fit_present[34])
                    fit_bits_32_34 = 6'd35;
                fit_bits_35_37 = 6'd0;
                if (fit_present[35])
                    fit_bits_35_37 = 6'd36;
                if (fit_present[36])
                    fit_bits_35_37 = 6'd37;
                if (fit_present[37])
                    fit_bits_35_37 = 6'd38;
                if (|fit_present[37:35])
                    fit_bits_32_37 = fit_bits_35_37;
                else
                    fit_bits_32_37 = fit_bits_32_34;
                if (|fit_present[37:32])
                    fit_bits_25_37 = fit_bits_32_37;
                else
                    fit_bits_25_37 = fit_bits_25_31;
                fit_bits_38_40 = 6'd0;
                if (fit_present[38])
                    fit_bits_38_40 = 6'd39;
                if (fit_present[39])
                    fit_bits_38_40 = 6'd40;
                if (fit_present[40])
                    fit_bits_38_40 = 6'd41;
                fit_bits_41_43 = 6'd0;
                if (fit_present[41])
                    fit_bits_41_43 = 6'd42;
                if (fit_present[42])
                    fit_bits_41_43 = 6'd43;
                if (fit_present[43])
                    fit_bits_41_43 = 6'd44;
                if (|fit_present[43:41])
                    fit_bits_38_43 = fit_bits_41_43;
                else
                    fit_bits_38_43 = fit_bits_38_40;
                fit_bits_44_46 = 6'd0;
                if (fit_present[44])
                    fit_bits_44_46 = 6'd45;
                if (fit_present[45])
                    fit_bits_44_46 = 6'd46;
                if (fit_present[46])
                    fit_bits_44_46 = 6'd47;
                fit_bits_47_49 = 6'd0;
                if (fit_present[47])
                    fit_bits_47_49 = 6'd48;
                if (fit_present[48])
                    fit_bits_47_49 = 6'd49;
                if (fit_present[49])
                    fit_bits_47_49 = 6'd50;
                if (|fit_present[49:47])
                    fit_bits_44_49 = fit_bits_47_49;
                else
                    fit_bits_44_49 = fit_bits_44_46;
                if (|fit_present[49:44])
                    fit_bits_38_49 = fit_bits_44_49;
                else
                    fit_bits_38_49 = fit_bits_38_43;
                if (|fit_present[49:38])
                    fit_bits_25_49 = fit_bits_38_49;
                else
                    fit_bits_25_49 = fit_bits_25_37;
                if (|fit_present[49:25])
                    fit_bits_0_49 = fit_bits_25_49;
                else
                    fit_bits_0_49 = fit_bits_0_24;
                bit_length = fit_bits_0_49;
                required = $signed({{2{source_exponent[7]}},
                                    source_exponent}) +
                           $signed({4'd0, bit_length}) - 10'sd15;
                if (required < -10'sd32)
                    first_fit_exponent50 = -8'sd32;
                else if (required > 10'sd31)
                    first_fit_exponent50 = 8'sd31;
                else
                    first_fit_exponent50 = required[7:0];
            end
        end
    endfunction

    function automatic [5:0] first_fit_length50(
        input signed [49:0] value
    );
        logic [49:0] fit_present;
        logic [5:0] fit_bits_0_49;
        logic [5:0] fit_bits_0_24;
        logic [5:0] fit_bits_0_12;
        logic [5:0] fit_bits_0_6;
        logic [5:0] fit_bits_0_3;
        logic [5:0] fit_bits_4_6;
        logic [5:0] fit_bits_7_12;
        logic [5:0] fit_bits_7_9;
        logic [5:0] fit_bits_10_12;
        logic [5:0] fit_bits_13_24;
        logic [5:0] fit_bits_13_18;
        logic [5:0] fit_bits_13_15;
        logic [5:0] fit_bits_16_18;
        logic [5:0] fit_bits_19_24;
        logic [5:0] fit_bits_19_21;
        logic [5:0] fit_bits_22_24;
        logic [5:0] fit_bits_25_49;
        logic [5:0] fit_bits_25_37;
        logic [5:0] fit_bits_25_31;
        logic [5:0] fit_bits_25_28;
        logic [5:0] fit_bits_29_31;
        logic [5:0] fit_bits_32_37;
        logic [5:0] fit_bits_32_34;
        logic [5:0] fit_bits_35_37;
        logic [5:0] fit_bits_38_49;
        logic [5:0] fit_bits_38_43;
        logic [5:0] fit_bits_38_40;
        logic [5:0] fit_bits_41_43;
        logic [5:0] fit_bits_44_49;
        logic [5:0] fit_bits_44_46;
        logic [5:0] fit_bits_47_49;
        begin
            if (value == 0) begin
                first_fit_length50 = 6'd0;
            end else begin
                fit_present = 50'd0;
                // A positive input uses its known-one bits. A negative
                // input reaches bit k iff value <= -2**k. Constant
                // thresholds need no absolute-value carry chain.
                // Unknown sign enters the comparison branch; like the
                // original unary negate, unknown data sets no fit bits.
                if (!value[49]) begin
                    if (value[0]) fit_present[0] = 1'b1;
                    if (value[1]) fit_present[1] = 1'b1;
                    if (value[2]) fit_present[2] = 1'b1;
                    if (value[3]) fit_present[3] = 1'b1;
                    if (value[4]) fit_present[4] = 1'b1;
                    if (value[5]) fit_present[5] = 1'b1;
                    if (value[6]) fit_present[6] = 1'b1;
                    if (value[7]) fit_present[7] = 1'b1;
                    if (value[8]) fit_present[8] = 1'b1;
                    if (value[9]) fit_present[9] = 1'b1;
                    if (value[10]) fit_present[10] = 1'b1;
                    if (value[11]) fit_present[11] = 1'b1;
                    if (value[12]) fit_present[12] = 1'b1;
                    if (value[13]) fit_present[13] = 1'b1;
                    if (value[14]) fit_present[14] = 1'b1;
                    if (value[15]) fit_present[15] = 1'b1;
                    if (value[16]) fit_present[16] = 1'b1;
                    if (value[17]) fit_present[17] = 1'b1;
                    if (value[18]) fit_present[18] = 1'b1;
                    if (value[19]) fit_present[19] = 1'b1;
                    if (value[20]) fit_present[20] = 1'b1;
                    if (value[21]) fit_present[21] = 1'b1;
                    if (value[22]) fit_present[22] = 1'b1;
                    if (value[23]) fit_present[23] = 1'b1;
                    if (value[24]) fit_present[24] = 1'b1;
                    if (value[25]) fit_present[25] = 1'b1;
                    if (value[26]) fit_present[26] = 1'b1;
                    if (value[27]) fit_present[27] = 1'b1;
                    if (value[28]) fit_present[28] = 1'b1;
                    if (value[29]) fit_present[29] = 1'b1;
                    if (value[30]) fit_present[30] = 1'b1;
                    if (value[31]) fit_present[31] = 1'b1;
                    if (value[32]) fit_present[32] = 1'b1;
                    if (value[33]) fit_present[33] = 1'b1;
                    if (value[34]) fit_present[34] = 1'b1;
                    if (value[35]) fit_present[35] = 1'b1;
                    if (value[36]) fit_present[36] = 1'b1;
                    if (value[37]) fit_present[37] = 1'b1;
                    if (value[38]) fit_present[38] = 1'b1;
                    if (value[39]) fit_present[39] = 1'b1;
                    if (value[40]) fit_present[40] = 1'b1;
                    if (value[41]) fit_present[41] = 1'b1;
                    if (value[42]) fit_present[42] = 1'b1;
                    if (value[43]) fit_present[43] = 1'b1;
                    if (value[44]) fit_present[44] = 1'b1;
                    if (value[45]) fit_present[45] = 1'b1;
                    if (value[46]) fit_present[46] = 1'b1;
                    if (value[47]) fit_present[47] = 1'b1;
                    if (value[48]) fit_present[48] = 1'b1;
                    if (value[49]) fit_present[49] = 1'b1;
                end else begin
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1)
                        fit_present[0] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2)
                        fit_present[1] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4)
                        fit_present[2] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8)
                        fit_present[3] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16)
                        fit_present[4] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd32)
                        fit_present[5] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd64)
                        fit_present[6] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd128)
                        fit_present[7] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd256)
                        fit_present[8] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd512)
                        fit_present[9] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1024)
                        fit_present[10] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2048)
                        fit_present[11] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4096)
                        fit_present[12] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8192)
                        fit_present[13] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16384)
                        fit_present[14] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd32768)
                        fit_present[15] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd65536)
                        fit_present[16] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd131072)
                        fit_present[17] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd262144)
                        fit_present[18] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd524288)
                        fit_present[19] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1048576)
                        fit_present[20] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2097152)
                        fit_present[21] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4194304)
                        fit_present[22] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8388608)
                        fit_present[23] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd16777216)
                        fit_present[24] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd33554432)
                        fit_present[25] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd67108864)
                        fit_present[26] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd134217728)
                        fit_present[27] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd268435456)
                        fit_present[28] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd536870912)
                        fit_present[29] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1073741824)
                        fit_present[30] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2147483648)
                        fit_present[31] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4294967296)
                        fit_present[32] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8589934592)
                        fit_present[33] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd17179869184)
                        fit_present[34] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd34359738368)
                        fit_present[35] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd68719476736)
                        fit_present[36] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd137438953472)
                        fit_present[37] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd274877906944)
                        fit_present[38] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd549755813888)
                        fit_present[39] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd1099511627776)
                        fit_present[40] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd2199023255552)
                        fit_present[41] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd4398046511104)
                        fit_present[42] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd8796093022208)
                        fit_present[43] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd17592186044416)
                        fit_present[44] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd35184372088832)
                        fit_present[45] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd70368744177664)
                        fit_present[46] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd140737488355328)
                        fit_present[47] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd281474976710656)
                        fit_present[48] = 1'b1;
                    if ($signed({{14{value[49]}}, value}) <= -64'sd562949953421312)
                        fit_present[49] = 1'b1;
                end
                // Parallel <=4-bit encoders followed by small-result
                // selection. No shifted 64-bit search-word dependency.
                fit_bits_0_3 = 6'd0;
                if (fit_present[0])
                    fit_bits_0_3 = 6'd1;
                if (fit_present[1])
                    fit_bits_0_3 = 6'd2;
                if (fit_present[2])
                    fit_bits_0_3 = 6'd3;
                if (fit_present[3])
                    fit_bits_0_3 = 6'd4;
                fit_bits_4_6 = 6'd0;
                if (fit_present[4])
                    fit_bits_4_6 = 6'd5;
                if (fit_present[5])
                    fit_bits_4_6 = 6'd6;
                if (fit_present[6])
                    fit_bits_4_6 = 6'd7;
                if (|fit_present[6:4])
                    fit_bits_0_6 = fit_bits_4_6;
                else
                    fit_bits_0_6 = fit_bits_0_3;
                fit_bits_7_9 = 6'd0;
                if (fit_present[7])
                    fit_bits_7_9 = 6'd8;
                if (fit_present[8])
                    fit_bits_7_9 = 6'd9;
                if (fit_present[9])
                    fit_bits_7_9 = 6'd10;
                fit_bits_10_12 = 6'd0;
                if (fit_present[10])
                    fit_bits_10_12 = 6'd11;
                if (fit_present[11])
                    fit_bits_10_12 = 6'd12;
                if (fit_present[12])
                    fit_bits_10_12 = 6'd13;
                if (|fit_present[12:10])
                    fit_bits_7_12 = fit_bits_10_12;
                else
                    fit_bits_7_12 = fit_bits_7_9;
                if (|fit_present[12:7])
                    fit_bits_0_12 = fit_bits_7_12;
                else
                    fit_bits_0_12 = fit_bits_0_6;
                fit_bits_13_15 = 6'd0;
                if (fit_present[13])
                    fit_bits_13_15 = 6'd14;
                if (fit_present[14])
                    fit_bits_13_15 = 6'd15;
                if (fit_present[15])
                    fit_bits_13_15 = 6'd16;
                fit_bits_16_18 = 6'd0;
                if (fit_present[16])
                    fit_bits_16_18 = 6'd17;
                if (fit_present[17])
                    fit_bits_16_18 = 6'd18;
                if (fit_present[18])
                    fit_bits_16_18 = 6'd19;
                if (|fit_present[18:16])
                    fit_bits_13_18 = fit_bits_16_18;
                else
                    fit_bits_13_18 = fit_bits_13_15;
                fit_bits_19_21 = 6'd0;
                if (fit_present[19])
                    fit_bits_19_21 = 6'd20;
                if (fit_present[20])
                    fit_bits_19_21 = 6'd21;
                if (fit_present[21])
                    fit_bits_19_21 = 6'd22;
                fit_bits_22_24 = 6'd0;
                if (fit_present[22])
                    fit_bits_22_24 = 6'd23;
                if (fit_present[23])
                    fit_bits_22_24 = 6'd24;
                if (fit_present[24])
                    fit_bits_22_24 = 6'd25;
                if (|fit_present[24:22])
                    fit_bits_19_24 = fit_bits_22_24;
                else
                    fit_bits_19_24 = fit_bits_19_21;
                if (|fit_present[24:19])
                    fit_bits_13_24 = fit_bits_19_24;
                else
                    fit_bits_13_24 = fit_bits_13_18;
                if (|fit_present[24:13])
                    fit_bits_0_24 = fit_bits_13_24;
                else
                    fit_bits_0_24 = fit_bits_0_12;
                fit_bits_25_28 = 6'd0;
                if (fit_present[25])
                    fit_bits_25_28 = 6'd26;
                if (fit_present[26])
                    fit_bits_25_28 = 6'd27;
                if (fit_present[27])
                    fit_bits_25_28 = 6'd28;
                if (fit_present[28])
                    fit_bits_25_28 = 6'd29;
                fit_bits_29_31 = 6'd0;
                if (fit_present[29])
                    fit_bits_29_31 = 6'd30;
                if (fit_present[30])
                    fit_bits_29_31 = 6'd31;
                if (fit_present[31])
                    fit_bits_29_31 = 6'd32;
                if (|fit_present[31:29])
                    fit_bits_25_31 = fit_bits_29_31;
                else
                    fit_bits_25_31 = fit_bits_25_28;
                fit_bits_32_34 = 6'd0;
                if (fit_present[32])
                    fit_bits_32_34 = 6'd33;
                if (fit_present[33])
                    fit_bits_32_34 = 6'd34;
                if (fit_present[34])
                    fit_bits_32_34 = 6'd35;
                fit_bits_35_37 = 6'd0;
                if (fit_present[35])
                    fit_bits_35_37 = 6'd36;
                if (fit_present[36])
                    fit_bits_35_37 = 6'd37;
                if (fit_present[37])
                    fit_bits_35_37 = 6'd38;
                if (|fit_present[37:35])
                    fit_bits_32_37 = fit_bits_35_37;
                else
                    fit_bits_32_37 = fit_bits_32_34;
                if (|fit_present[37:32])
                    fit_bits_25_37 = fit_bits_32_37;
                else
                    fit_bits_25_37 = fit_bits_25_31;
                fit_bits_38_40 = 6'd0;
                if (fit_present[38])
                    fit_bits_38_40 = 6'd39;
                if (fit_present[39])
                    fit_bits_38_40 = 6'd40;
                if (fit_present[40])
                    fit_bits_38_40 = 6'd41;
                fit_bits_41_43 = 6'd0;
                if (fit_present[41])
                    fit_bits_41_43 = 6'd42;
                if (fit_present[42])
                    fit_bits_41_43 = 6'd43;
                if (fit_present[43])
                    fit_bits_41_43 = 6'd44;
                if (|fit_present[43:41])
                    fit_bits_38_43 = fit_bits_41_43;
                else
                    fit_bits_38_43 = fit_bits_38_40;
                fit_bits_44_46 = 6'd0;
                if (fit_present[44])
                    fit_bits_44_46 = 6'd45;
                if (fit_present[45])
                    fit_bits_44_46 = 6'd46;
                if (fit_present[46])
                    fit_bits_44_46 = 6'd47;
                fit_bits_47_49 = 6'd0;
                if (fit_present[47])
                    fit_bits_47_49 = 6'd48;
                if (fit_present[48])
                    fit_bits_47_49 = 6'd49;
                if (fit_present[49])
                    fit_bits_47_49 = 6'd50;
                if (|fit_present[49:47])
                    fit_bits_44_49 = fit_bits_47_49;
                else
                    fit_bits_44_49 = fit_bits_44_46;
                if (|fit_present[49:44])
                    fit_bits_38_49 = fit_bits_44_49;
                else
                    fit_bits_38_49 = fit_bits_38_43;
                if (|fit_present[49:38])
                    fit_bits_25_49 = fit_bits_38_49;
                else
                    fit_bits_25_49 = fit_bits_25_37;
                if (|fit_present[49:25])
                    fit_bits_0_49 = fit_bits_25_49;
                else
                    fit_bits_0_49 = fit_bits_0_24;
                first_fit_length50 = fit_bits_0_49;
            end
        end
    endfunction

    function automatic signed [7:0] first_fit_from_length(
        input [5:0] bit_length,
        input signed [7:0] source_exponent,
        input value_zero
    );
        logic signed [9:0] required;
        begin
            if (value_zero) begin
                first_fit_from_length = -8'sd32;
            end else begin
                required = $signed({{2{source_exponent[7]}},
                                    source_exponent}) +
                           $signed({4'd0, bit_length}) - 10'sd15;
                if (required < -10'sd32)
                    first_fit_from_length = -8'sd32;
                else if (required > 10'sd31)
                    first_fit_from_length = 8'sd31;
                else
                    first_fit_from_length = required[7:0];
            end
        end
    endfunction

    state_t state_q;
    logic [5:0] fit_length_pipe_q;
    logic signed [7:0] fit_source_pipe_q;
    logic fit_zero_pipe_q;
    logic signed [7:0] fit_first_pipe_q;
    logic [2:0] layer_q;
    logic [3:0] job_q;
    logic [9:0] rows_q;
    logic [9:0] capture_index_q;
    logic [9:0] scan_index_q;
    logic signed [7:0] candidate_q;
    logic any_nonzero_q;
    logic all_fit_q;
    logic shift_client_q;
    logic [31:0] compute_cycles_q;

    // 682 * 58 bits.  It is private, transaction-scoped, and has no address
    // above this fixed controller.  The synchronous read and absence of a
    // reset loop permit exact-device block-RAM inference.
    (* nomem2reg, ram_style = "block" *)
    logic [57:0] record_mem_q [0:681];
    logic [57:0] record_read_q;
    // A malformed beat must not even perturb the private transaction RAM.
    // The controller still enters its sticky fault state below.
    wire record_write_enable = input_valid_i && input_ready_o &&
        (input_row_index_i == capture_index_q) &&
        (input_last_i == (capture_index_q == (rows_q - 1'b1)));
    wire record_read_enable = (state_q == ST_SELECT_READ) ||
                              (state_q == ST_FIND_READ) ||
                              (state_q == ST_WRITE_READ);

    always_ff @(posedge clk) begin
        if (record_write_enable)
            record_mem_q[input_row_index_i] <=
                {input_source_exponent_i, input_raw_i};
        if (record_read_enable)
            record_read_q <= record_mem_q[scan_index_q];
    end

    wire signed [49:0] selected_raw = $signed(record_read_q[49:0]);
    wire signed [7:0] selected_source_exponent =
        $signed(record_read_q[57:50]);
    wire signed [7:0] selected_first_fit = fit_first_pipe_q;
    wire signed [7:0] selected_candidate =
        (selected_first_fit > candidate_q) ? selected_first_fit : candidate_q;
    wire selected_nonzero = !fit_zero_pipe_q;
    wire selected_last = (scan_index_q == (rows_q - 1'b1));

    wire descriptor_valid = (fixed_layer_i < 3'd6) &&
                            (rows_for_job(fixed_job_i) != 10'd0);
    wire interface_live = rst_n && !clear_i && model_lock_i &&
                          !upstream_fault_i && !range_fault_o &&
                          (compute_cycles_q < MAX_COMPUTE_CYCLES);

    logic shift_request_valid;
    wire shift_request_ready;
    wire shift_response_valid;
    logic shift_response_ready;
    wire signed [63:0] shift_response_result;
    wire shift_response_fault;
    wire signed [8:0] requested_shift =
        $signed({candidate_q[7], candidate_q}) -
        $signed({selected_source_exponent[7], selected_source_exponent});
    wire shift_response_fits = !shift_response_fault &&
        (shift_response_result >= I16_MINIMUM) &&
        (shift_response_result <= I16_MAXIMUM) &&
        (shift_response_result != -64'sd32768);

    always_comb begin
        start_ready_o = interface_live && (state_q == ST_IDLE);
        input_ready_o = interface_live && (state_q == ST_CAPTURE);
        result_valid_o = interface_live && (state_q == ST_RESULT);
        done_valid_o = interface_live && (state_q == ST_DONE);
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAULT);
        shift_request_valid = interface_live &&
            ((state_q == ST_FIND_ISSUE) || (state_q == ST_WRITE_ISSUE));
        shift_response_ready = (state_q == ST_SHIFT_WAIT);
    end

    board1_fixed_vector_rne_shift_pipeline1 u_shift (
        .clk(clk), .rst_n(rst_n),
        .clear_i(clear_i || range_fault_o),
        .request_valid_i(shift_request_valid),
        .request_ready_o(shift_request_ready),
        .request_value_i({{14{selected_raw[49]}}, selected_raw}),
        .request_shift_i(requested_shift),
        .response_valid_o(shift_response_valid),
        .response_ready_i(shift_response_ready),
        .response_result_o(shift_response_result),
        .response_fault_o(shift_response_fault)
    );

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            rows_q <= 10'd0;
            capture_index_q <= 10'd0;
            scan_index_q <= 10'd0;
            candidate_q <= -8'sd32;
            fit_length_pipe_q <= 6'd0;
            fit_source_pipe_q <= 8'sd0;
            fit_zero_pipe_q <= 1'b1;
            fit_first_pipe_q <= -8'sd32;
            any_nonzero_q <= 1'b0;
            all_fit_q <= 1'b1;
            shift_client_q <= SHIFT_CLIENT_FIND;
            compute_cycles_q <= 32'd0;
            result_row_index_o <= 10'd0;
            result_mantissa_o <= 16'sd0;
            result_exponent_o <= 8'sd0;
            result_last_o <= 1'b0;
            range_fault_o <= 1'b0;
        end else if (clear_i) begin
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            job_q <= 4'd0;
            rows_q <= 10'd0;
            capture_index_q <= 10'd0;
            scan_index_q <= 10'd0;
            candidate_q <= -8'sd32;
            fit_length_pipe_q <= 6'd0;
            fit_source_pipe_q <= 8'sd0;
            fit_zero_pipe_q <= 1'b1;
            fit_first_pipe_q <= -8'sd32;
            any_nonzero_q <= 1'b0;
            all_fit_q <= 1'b1;
            shift_client_q <= SHIFT_CLIENT_FIND;
            compute_cycles_q <= 32'd0;
            result_row_index_o <= 10'd0;
            result_mantissa_o <= 16'sd0;
            result_exponent_o <= 8'sd0;
            result_last_o <= 1'b0;
            range_fault_o <= 1'b0;
        end else if (range_fault_o) begin
            state_q <= ST_FAULT;
            range_fault_o <= 1'b1;
        end else if ((state_q != ST_IDLE) && (state_q != ST_FAULT) &&
                     (compute_cycles_q >= MAX_COMPUTE_CYCLES - 1)) begin
            // Give the watchdog priority over every ordinary state update.
            state_q <= ST_FAULT;
            range_fault_o <= 1'b1;
        end else begin
            if ((state_q != ST_IDLE) && (state_q != ST_FAULT))
                compute_cycles_q <= compute_cycles_q + 1'b1;

`ifndef SYNTHESIS
            if ($isunknown(clear_i) ||
                $isunknown(model_lock_i) ||
                $isunknown(upstream_fault_i) ||
                $isunknown(start_valid_i) ||
                $isunknown(input_valid_i) ||
                $isunknown(result_ready_i) ||
                $isunknown(done_ready_i) ||
                ((start_valid_i === 1'b1) &&
                 ($isunknown(fixed_layer_i) || $isunknown(fixed_job_i))) ||
                ((input_valid_i === 1'b1) &&
                 ($isunknown(input_row_index_i) || $isunknown(input_raw_i) ||
                  $isunknown(input_source_exponent_i) ||
                  $isunknown(input_last_i)))) begin
                state_q <= ST_FAULT;
                range_fault_o <= 1'b1;
            end else
`endif
            if ((upstream_fault_i === 1'b1) ||
                (((state_q != ST_IDLE) && (state_q != ST_FAULT)) &&
                 (model_lock_i !== 1'b1)) ||
                ((start_valid_i === 1'b1) &&
                 (model_lock_i !== 1'b1))) begin
                state_q <= ST_FAULT;
                range_fault_o <= 1'b1;
            end else if ((start_valid_i === 1'b1) &&
                         (state_q != ST_IDLE)) begin
                state_q <= ST_FAULT;
                range_fault_o <= 1'b1;
            end else if ((input_valid_i === 1'b1) &&
                         (state_q != ST_CAPTURE)) begin
                state_q <= ST_FAULT;
                range_fault_o <= 1'b1;
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        compute_cycles_q <= 32'd0;
                        if (start_valid_i && start_ready_o) begin
                            if (!descriptor_valid) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else begin
                                layer_q <= fixed_layer_i;
                                job_q <= fixed_job_i;
                                rows_q <= rows_for_job(fixed_job_i);
                                capture_index_q <= 10'd0;
                                state_q <= ST_CAPTURE;
                            end
                        end
                    end

                    ST_CAPTURE: begin
                        if (input_valid_i && input_ready_o) begin
                            if ((input_row_index_i != capture_index_q) ||
                                (input_last_i !=
                                 (capture_index_q == (rows_q - 1'b1)))) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else if (input_last_i) begin
                                scan_index_q <= 10'd0;
                                candidate_q <= -8'sd32;
                                any_nonzero_q <= 1'b0;
                                all_fit_q <= 1'b1;
                                state_q <= ST_SELECT_READ;
                            end else begin
                                capture_index_q <= capture_index_q + 1'b1;
                            end
                        end
                    end

                    ST_SELECT_READ:
                        state_q <= ST_SELECT_BITS;

                    ST_SELECT_BITS: begin
                        fit_length_pipe_q <= first_fit_length50(selected_raw);
                        fit_source_pipe_q <= selected_source_exponent;
                        fit_zero_pipe_q <= (selected_raw == 0);
                        state_q <= ST_SELECT_EXP;
                    end

                    ST_SELECT_EXP: begin
                        fit_first_pipe_q <= first_fit_from_length(
                            fit_length_pipe_q, fit_source_pipe_q, fit_zero_pipe_q);
                        state_q <= ST_SELECT_EVAL;
                    end

                    ST_SELECT_EVAL: begin
                        if (selected_nonzero) begin
                            any_nonzero_q <= 1'b1;
                            if (selected_first_fit > candidate_q)
                                candidate_q <= selected_first_fit;
                        end
                        if (selected_last) begin
                            scan_index_q <= 10'd0;
                            all_fit_q <= 1'b1;
                            if (!any_nonzero_q && !selected_nonzero) begin
                                candidate_q <= 8'sd0;
                                state_q <= ST_WRITE_READ;
                            end else begin
                                candidate_q <= selected_candidate;
                                state_q <= ST_FIND_READ;
                            end
                        end else begin
                            scan_index_q <= scan_index_q + 1'b1;
                            state_q <= ST_SELECT_READ;
                        end
                    end

                    ST_FIND_READ:
                        state_q <= ST_FIND_ISSUE;

                    ST_FIND_ISSUE: begin
                        if (shift_request_valid && shift_request_ready) begin
                            shift_client_q <= SHIFT_CLIENT_FIND;
                            state_q <= ST_SHIFT_WAIT;
                        end
                    end

                    ST_WRITE_READ:
                        state_q <= ST_WRITE_ISSUE;

                    ST_WRITE_ISSUE: begin
                        if (shift_request_valid && shift_request_ready) begin
                            shift_client_q <= SHIFT_CLIENT_WRITE;
                            state_q <= ST_SHIFT_WAIT;
                        end
                    end

                    ST_SHIFT_WAIT: begin
                        if (shift_response_valid && shift_response_ready) begin
                            if (shift_client_q == SHIFT_CLIENT_FIND) begin
                                if (!shift_response_fits)
                                    all_fit_q <= 1'b0;
                                if (selected_last) begin
                                    scan_index_q <= 10'd0;
                                    if (all_fit_q && shift_response_fits) begin
                                        state_q <= ST_WRITE_READ;
                                    end else if (shift_response_fault ||
                                                 (candidate_q == 8'sd31)) begin
                                        state_q <= ST_FAULT;
                                        range_fault_o <= 1'b1;
                                    end else begin
                                        candidate_q <= candidate_q + 1'b1;
                                        all_fit_q <= 1'b1;
                                        state_q <= ST_FIND_READ;
                                    end
                                end else if (shift_response_fault) begin
                                    state_q <= ST_FAULT;
                                    range_fault_o <= 1'b1;
                                end else begin
                                    scan_index_q <= scan_index_q + 1'b1;
                                    state_q <= ST_FIND_READ;
                                end
                            end else if (!shift_response_fits) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else begin
                                result_row_index_o <= scan_index_q;
                                result_mantissa_o <=
                                    shift_response_result[15:0];
                                result_exponent_o <= candidate_q;
                                result_last_o <= selected_last;
                                state_q <= ST_RESULT;
                            end
                        end
                    end

                    ST_RESULT: begin
                        if (result_valid_o && result_ready_i) begin
                            if (result_last_o) begin
                                state_q <= ST_DONE;
                            end else begin
                                scan_index_q <= scan_index_q + 1'b1;
                                state_q <= ST_WRITE_READ;
                            end
                        end
                    end

                    ST_DONE: begin
                        if (done_valid_o && done_ready_i)
                            state_q <= ST_IDLE;
                    end

                    ST_FAULT: begin
                        state_q <= ST_FAULT;
                        range_fault_o <= 1'b1;
                    end

                    default: begin
                        state_q <= ST_FAULT;
                        range_fault_o <= 1'b1;
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk) begin
        if (rst_n && !$past(clear_i)) begin
            if ($past(range_fault_o)) assert(range_fault_o);
            if ($past(result_valid_o) && !$past(result_ready_i)) begin
                assert(result_valid_o);
                assert(result_row_index_o == $past(result_row_index_o));
                assert(result_mantissa_o == $past(result_mantissa_o));
                assert(result_exponent_o == $past(result_exponent_o));
                assert(result_last_o == $past(result_last_o));
            end
            if (result_valid_o) begin
                assert(result_exponent_o >= -8'sd32);
                assert(result_exponent_o <= 8'sd31);
                assert(result_mantissa_o != -16'sd32768);
                assert(result_row_index_o < rows_q);
                assert(result_last_o ==
                       (result_row_index_o == (rows_q - 1'b1)));
            end
            if (start_ready_o) begin
                assert(state_q == ST_IDLE);
                assert(model_lock_i);
                assert(!upstream_fault_i);
            end
        end
        if (rst_n && clear_i) begin
            assert(!result_valid_o);
            assert(!done_valid_o);
        end
    end
`endif

    wire _unused_private_identity = ^{layer_q, job_q};
endmodule

`default_nettype wire
