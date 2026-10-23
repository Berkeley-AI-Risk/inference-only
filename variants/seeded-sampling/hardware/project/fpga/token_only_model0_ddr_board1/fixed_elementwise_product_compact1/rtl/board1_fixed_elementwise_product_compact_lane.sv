`timescale 1ns/1ps
`default_nettype none

// Product-specialized successor to board1_fixed_elementwise_lane_core.
//
// The connected six-layer controller can issue only RoPE, SiLU*up, and
// residual-add transactions.  RMSNorm is served by its dedicated exact
// service.  For every connected transaction the caller also fixes the common
// and safety exponents.  This lane enforces that smaller reachable contract
// and implements it with width-bounded arithmetic.  It retains the same
// private handshake so it can be checked as a drop-in integration successor.
module board1_fixed_elementwise_product_compact_lane (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire [2:0]              operation_i,
    input  wire signed [15:0]      first_i,
    input  wire signed [15:0]      second_i,
    input  wire signed [9:0]       coefficient_i,
    input  wire [15:0]             multiplier_i,
    input  wire signed [15:0]      cosine_i,
    input  wire signed [15:0]      sine_i,
    input  wire signed [7:0]       first_exponent_i,
    input  wire signed [7:0]       second_exponent_i,
    input  wire signed [7:0]       common_exponent_i,
    input  wire signed [7:0]       target_exponent_i,

    output logic                   lut_request_o,
    output logic [15:0]            lut_index_o,
    input  wire                    lut_response_valid_i,
    input  wire signed [15:0]      lut_value_i,
    input  wire                    lut_fault_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic signed [15:0]     result0_o,
    output logic signed [15:0]     result1_o,
    output logic signed [15:0]     auxiliary_o,
    output logic signed [49:0]     raw0_o,
    output logic signed [49:0]     raw1_o,
    output logic signed [7:0]      source_exponent_o,
    output logic                   range_fault_o
);
    localparam logic [2:0] OP_ROPE_PAIR    = 3'd0;
    localparam logic [2:0] OP_SILU_GATE_UP = 3'd2;
    localparam logic [2:0] OP_RESIDUAL_ADD = 3'd3;

    localparam signed [33:0] ROPE_MAXIMUM = (34'sd1 <<< 31) - 1'b1;
    localparam signed [33:0] ROPE_MINIMUM = -((34'sd1 <<< 31) - 1'b1);
    localparam signed [31:0] ELEMENT_MAXIMUM = (32'sd1 <<< 30) - 1'b1;
    localparam signed [31:0] ELEMENT_MINIMUM = -((32'sd1 <<< 30) - 1'b1);

    function automatic signed [33:0] rne_right15_signed34(
        input signed [33:0] value
    );
        logic [33:0] magnitude;
        logic [33:0] quotient;
        logic [33:0] rounded;
        logic round_up;
        begin
            magnitude = value[33] ? (~$unsigned(value) + 1'b1) :
                                    $unsigned(value);
            quotient = magnitude >> 15;
            round_up = (magnitude[14:0] > 15'h4000) ||
                       ((magnitude[14:0] == 15'h4000) && quotient[0]);
            rounded = quotient + {{33{1'b0}}, round_up};
            rne_right15_signed34 = value[33] ? -$signed(rounded) :
                                                       $signed(rounded);
        end
    endfunction

    function automatic signed [33:0] rne_right1_signed34(
        input signed [33:0] value
    );
        logic [33:0] magnitude;
        logic [33:0] quotient;
        logic [33:0] rounded;
        logic round_up;
        begin
            magnitude = value[33] ? (~$unsigned(value) + 1'b1) :
                                    $unsigned(value);
            quotient = magnitude >> 1;
            round_up = magnitude[0] && quotient[0];
            rounded = quotient + {{33{1'b0}}, round_up};
            rne_right1_signed34 = value[33] ? -$signed(rounded) :
                                                      $signed(rounded);
        end
    endfunction

    function automatic signed [16:0] rne_right_signed16(
        input signed [15:0] value,
        input logic [5:0] shift
    );
        logic [15:0] magnitude;
        logic [15:0] quotient;
        logic [15:0] remainder;
        logic [15:0] half;
        logic [16:0] rounded;
        logic round_up;
        begin
            magnitude = value[15] ? (~$unsigned(value) + 1'b1) :
                                    $unsigned(value);
            if (shift == 0) begin
                rne_right_signed16 = {{1{value[15]}}, value};
            end else if (shift > 6'd15) begin
                rne_right_signed16 = 17'sd0;
            end else begin
                quotient = magnitude >> shift;
                remainder = magnitude & ((16'd1 << shift) - 1'b1);
                half = 16'd1 << (shift - 1'b1);
                round_up = (remainder > half) ||
                           ((remainder == half) && quotient[0]);
                rounded = {1'b0, quotient} + {{16{1'b0}}, round_up};
                rne_right_signed16 = value[15] ? -$signed(rounded) :
                                                         $signed(rounded);
            end
        end
    endfunction

    function automatic signed [17:0] rne_right1_signed18(
        input signed [17:0] value
    );
        logic [17:0] magnitude;
        logic [17:0] quotient;
        logic [17:0] rounded;
        logic round_up;
        begin
            magnitude = value[17] ? (~$unsigned(value) + 1'b1) :
                                    $unsigned(value);
            quotient = magnitude >> 1;
            round_up = magnitude[0] && quotient[0];
            rounded = quotient + {{17{1'b0}}, round_up};
            rne_right1_signed18 = value[17] ? -$signed(rounded) :
                                                      $signed(rounded);
        end
    endfunction

    function automatic signed [31:0] rne_right_signed32(
        input signed [31:0] value,
        input logic [6:0] shift
    );
        logic [31:0] magnitude;
        logic [31:0] quotient;
        logic [31:0] remainder;
        logic [31:0] half;
        logic [31:0] rounded;
        logic round_up;
        begin
            magnitude = value[31] ? (~$unsigned(value) + 1'b1) :
                                    $unsigned(value);
            if (shift == 0) begin
                rne_right_signed32 = value;
            end else if (shift > 7'd31) begin
                rne_right_signed32 = 32'sd0;
            end else begin
                quotient = magnitude >> shift;
                remainder = magnitude & ((32'd1 << shift) - 1'b1);
                half = 32'd1 << (shift - 1'b1);
                round_up = (remainder > half) ||
                           ((remainder == half) && quotient[0]);
                rounded = quotient + {{31{1'b0}}, round_up};
                rne_right_signed32 = value[31] ? -$signed(rounded) :
                                                         $signed(rounded);
            end
        end
    endfunction

    function automatic [15:0] silu_index_narrow(
        input signed [15:0] mantissa,
        input signed [7:0] exponent
    );
        integer amount;
        logic signed [16:0] q10;
        logic signed [31:0] left_value;
        logic signed [16:0] clipped;
        begin
            q10 = 17'sd0;
            left_value = 32'sd0;
            if (exponent < -8'sd10) begin
                amount = -($signed(exponent) + 10);
                q10 = rne_right_signed16(mantissa, amount[5:0]);
                clipped = q10;
            end else if (exponent == -8'sd10) begin
                clipped = {{1{mantissa[15]}}, mantissa};
            end else begin
                amount = $signed(exponent) + 10;
                if (mantissa == 0) begin
                    clipped = 17'sd0;
                end else if (amount >= 15) begin
                    clipped = mantissa[15] ? -17'sd32768 : 17'sd32767;
                end else begin
                    left_value =
                        $signed({{16{mantissa[15]}}, mantissa}) <<< amount;
                    if (left_value < -32'sd32768)
                        clipped = -17'sd32768;
                    else if (left_value > 32'sd32767)
                        clipped = 17'sd32767;
                    else
                        clipped = left_value[16:0];
                end
            end
            silu_index_narrow = 16'($signed(clipped) + 18'sd32768);
        end
    endfunction

    typedef enum logic [3:0] {
        ST_IDLE      = 4'd0,
        ST_ROPE_P0   = 4'd1,
        ST_ROPE_P1   = 4'd2,
        ST_ROPE_P2   = 4'd3,
        ST_ROPE_P3   = 4'd4,
        ST_SILU_REQ  = 4'd5,
        ST_SILU_WAIT = 4'd6,
        ST_SILU_MUL  = 4'd7,
        ST_RESIDUAL  = 4'd8,
        ST_RESULT    = 4'd9,
        ST_FAULT     = 4'd10,
        ST_ROPE_ROUND = 4'd11,
        ST_ROPE_CHECK = 4'd12,
        ST_SILU_ROUND = 4'd13,
        ST_SILU_CHECK = 4'd14,
        ST_RESIDUAL_CHECK = 4'd15
    } state_t;

    state_t state_q;
    logic signed [15:0] first_q;
    logic signed [15:0] second_q;
    logic signed [15:0] cosine_q;
    logic signed [15:0] sine_q;
    logic signed [7:0] first_exponent_q;
    logic signed [7:0] second_exponent_q;
    logic signed [7:0] common_exponent_q;
    logic signed [7:0] target_exponent_q;
    logic signed [31:0] product0_q;
    logic signed [31:0] product1_q;
    logic signed [31:0] product2_q;
    logic signed [15:0] silu_value_q;
    logic [4:0] lut_wait_q;
    logic range_fault_q;

    // Private arithmetic pipeline payload; never exposed as new commands.
    logic signed [33:0] rope_accum0_pipe_q;
    logic signed [33:0] rope_accum1_pipe_q;
    logic signed [33:0] rope_raw0_pipe_q;
    logic signed [33:0] rope_raw1_pipe_q;
    logic rope_bound_bad_q;
    logic signed [31:0] silu_product_pipe_q;
    logic signed [31:0] silu_result_pipe_q;
    logic silu_bound_bad_q;
    logic signed [17:0] residual_raw_pipe_q;

    logic signed [15:0] dsp_first;
    logic signed [15:0] dsp_second;
    logic signed [31:0] dsp_product;

    logic signed [33:0] rope_accumulator0;
    logic signed [33:0] rope_accumulator1;
    logic signed [33:0] rope_raw0_calc;
    logic signed [33:0] rope_raw1_calc;
    logic signed [33:0] rope_result0_calc;
    logic signed [33:0] rope_result1_calc;

    logic [5:0] residual_first_shift;
    logic [5:0] residual_second_shift;
    logic signed [16:0] residual_first_aligned;
    logic signed [16:0] residual_second_aligned;
    logic signed [17:0] residual_raw_calc;
    logic signed [17:0] residual_result_calc;

    logic signed [31:0] silu_raw_calc;
    logic signed [8:0] silu_source_exponent_calc;
    logic [6:0] silu_normalize_shift;
    logic signed [31:0] silu_result_calc;

`ifndef SYNTHESIS
    logic simulation_x_fault;
`endif

    board1_fixed_elementwise_product_dsp u_product_dsp (
        .first_i(dsp_first), .second_i(dsp_second), .product_o(dsp_product)
    );

    always_comb begin
        request_ready_o = rst_n && !clear_i && !range_fault_q &&
                          (state_q == ST_IDLE);
        result_valid_o = rst_n && !clear_i && !range_fault_q &&
                         (state_q == ST_RESULT);
        range_fault_o = range_fault_q;
        lut_request_o = !clear_i && !range_fault_q &&
                        (state_q == ST_SILU_REQ);
        lut_index_o = silu_index_narrow(first_q, first_exponent_q);

        dsp_first = 16'sd0;
        dsp_second = 16'sd0;
        case (state_q)
            ST_ROPE_P0: begin dsp_first = first_q;  dsp_second = cosine_q; end
            ST_ROPE_P1: begin dsp_first = second_q; dsp_second = sine_q;   end
            ST_ROPE_P2: begin dsp_first = second_q; dsp_second = cosine_q; end
            ST_ROPE_P3: begin dsp_first = first_q;  dsp_second = sine_q;   end
            ST_SILU_MUL: begin
                dsp_first = silu_value_q;
                dsp_second = second_q;
            end
            default: begin end
        endcase

        rope_accumulator0 =
            $signed({{2{product0_q[31]}}, product0_q}) -
            $signed({{2{product1_q[31]}}, product1_q});
        rope_accumulator1 =
            $signed({{2{product2_q[31]}}, product2_q}) +
            $signed({{2{dsp_product[31]}}, dsp_product});
        rope_raw0_calc = rne_right15_signed34(rope_accum0_pipe_q);
        rope_raw1_calc = rne_right15_signed34(rope_accum1_pipe_q);
        rope_result0_calc = (first_exponent_q < 8'sd31) ?
            rne_right1_signed34(rope_raw0_pipe_q) : rope_raw0_pipe_q;
        rope_result1_calc = (first_exponent_q < 8'sd31) ?
            rne_right1_signed34(rope_raw1_pipe_q) : rope_raw1_pipe_q;

        residual_first_shift =
            $unsigned($signed({common_exponent_q[7], common_exponent_q}) -
                      $signed({first_exponent_q[7], first_exponent_q}));
        residual_second_shift =
            $unsigned($signed({common_exponent_q[7], common_exponent_q}) -
                      $signed({second_exponent_q[7], second_exponent_q}));
        residual_first_aligned = rne_right_signed16(
            first_q, residual_first_shift);
        residual_second_aligned = rne_right_signed16(
            second_q, residual_second_shift);
        residual_raw_calc =
            $signed({residual_first_aligned[16], residual_first_aligned}) +
            $signed({residual_second_aligned[16], residual_second_aligned});
        residual_result_calc = (common_exponent_q < 8'sd31) ?
            rne_right1_signed18(residual_raw_pipe_q) : residual_raw_pipe_q;

        silu_raw_calc = silu_product_pipe_q;
        silu_source_exponent_calc =
            $signed({second_exponent_q[7], second_exponent_q}) - 9'sd10;
        silu_normalize_shift =
            7'(9'sd31 - silu_source_exponent_calc);
        silu_result_calc = rne_right_signed32(
            silu_raw_calc, silu_normalize_shift);
    end

`ifndef SYNTHESIS
    always_comb begin
        simulation_x_fault = $isunknown(rst_n) || $isunknown(clear_i) ||
            $isunknown(request_valid_i) || $isunknown(result_ready_i) ||
            $isunknown(lut_response_valid_i) || $isunknown(lut_fault_i);
        if (request_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(operation_i) || $isunknown(first_i) ||
                $isunknown(second_i) || $isunknown(coefficient_i) ||
                $isunknown(multiplier_i) || $isunknown(cosine_i) ||
                $isunknown(sine_i) || $isunknown(first_exponent_i) ||
                $isunknown(second_exponent_i) ||
                $isunknown(common_exponent_i) ||
                $isunknown(target_exponent_i);
        if (lut_response_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault || $isunknown(lut_value_i);
    end
`endif

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            first_q <= '0;
            second_q <= '0;
            cosine_q <= '0;
            sine_q <= '0;
            first_exponent_q <= '0;
            second_exponent_q <= '0;
            common_exponent_q <= '0;
            target_exponent_q <= '0;
            product0_q <= '0;
            product1_q <= '0;
            product2_q <= '0;
            rope_accum0_pipe_q <= '0;
            rope_accum1_pipe_q <= '0;
            rope_raw0_pipe_q <= '0;
            rope_raw1_pipe_q <= '0;
            rope_bound_bad_q <= '0;
            silu_product_pipe_q <= '0;
            silu_result_pipe_q <= '0;
            silu_bound_bad_q <= '0;
            residual_raw_pipe_q <= '0;
            silu_value_q <= '0;
            lut_wait_q <= '0;
            result0_o <= '0;
            result1_o <= '0;
            auxiliary_o <= '0;
            raw0_o <= '0;
            raw1_o <= '0;
            source_exponent_o <= '0;
            range_fault_q <= 1'b0;
        end else if (clear_i) begin
            state_q <= ST_IDLE;
            first_q <= '0;
            second_q <= '0;
            cosine_q <= '0;
            sine_q <= '0;
            first_exponent_q <= '0;
            second_exponent_q <= '0;
            common_exponent_q <= '0;
            target_exponent_q <= '0;
            product0_q <= '0;
            product1_q <= '0;
            product2_q <= '0;
            rope_accum0_pipe_q <= '0;
            rope_accum1_pipe_q <= '0;
            rope_raw0_pipe_q <= '0;
            rope_raw1_pipe_q <= '0;
            rope_bound_bad_q <= '0;
            silu_product_pipe_q <= '0;
            silu_result_pipe_q <= '0;
            silu_bound_bad_q <= '0;
            residual_raw_pipe_q <= '0;
            silu_value_q <= '0;
            lut_wait_q <= '0;
            result0_o <= '0;
            result1_o <= '0;
            auxiliary_o <= '0;
            raw0_o <= '0;
            raw1_o <= '0;
            source_exponent_o <= '0;
            range_fault_q <= 1'b0;
`ifndef SYNTHESIS
        end else if (simulation_x_fault) begin
            state_q <= ST_FAULT;
            range_fault_q <= 1'b1;
`endif
        end else if (lut_fault_i ||
                     (lut_response_valid_i && (state_q != ST_SILU_WAIT))) begin
            state_q <= ST_FAULT;
            range_fault_q <= 1'b1;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    if (request_valid_i) begin
                        first_q <= first_i;
                        second_q <= second_i;
                        cosine_q <= cosine_i;
                        sine_q <= sine_i;
                        first_exponent_q <= first_exponent_i;
                        second_exponent_q <= second_exponent_i;
                        common_exponent_q <= common_exponent_i;
                        target_exponent_q <= target_exponent_i;
                        result0_o <= '0;
                        result1_o <= '0;
                        auxiliary_o <= '0;
                        raw0_o <= '0;
                        raw1_o <= '0;
                        source_exponent_o <= '0;
                        if (((operation_i != OP_ROPE_PAIR) &&
                             (operation_i != OP_SILU_GATE_UP) &&
                             (operation_i != OP_RESIDUAL_ADD)) ||
                            (coefficient_i != 10'sd0) ||
                            (multiplier_i != 16'd0) ||
                            (first_i == 16'sh8000) ||
                            (second_i == 16'sh8000) ||
                            (first_exponent_i < -8'sd32) ||
                            (first_exponent_i > 8'sd31) ||
                            (second_exponent_i < -8'sd32) ||
                            (second_exponent_i > 8'sd31) ||
                            (common_exponent_i < -8'sd32) ||
                            (common_exponent_i > 8'sd31) ||
                            (target_exponent_i < -8'sd32) ||
                            (target_exponent_i > 8'sd31) ||
                            ((operation_i == OP_ROPE_PAIR) &&
                             ((second_exponent_i != first_exponent_i) ||
                              (common_exponent_i != first_exponent_i) ||
                              (target_exponent_i !=
                               ((first_exponent_i < 8'sd31) ?
                                first_exponent_i + 1'b1 : 8'sd31)))) ||
                            ((operation_i == OP_SILU_GATE_UP) &&
                             ((common_exponent_i != 8'sd0) ||
                              (target_exponent_i != 8'sd31))) ||
                            ((operation_i == OP_RESIDUAL_ADD) &&
                             ((common_exponent_i !=
                               ((first_exponent_i > second_exponent_i) ?
                                first_exponent_i : second_exponent_i)) ||
                              (target_exponent_i !=
                               ((common_exponent_i < 8'sd31) ?
                                common_exponent_i + 1'b1 : 8'sd31))))) begin
                            state_q <= ST_FAULT;
                            range_fault_q <= 1'b1;
                        end else begin
                            case (operation_i)
                                OP_ROPE_PAIR: state_q <= ST_ROPE_P0;
                                OP_SILU_GATE_UP: state_q <= ST_SILU_REQ;
                                OP_RESIDUAL_ADD: state_q <= ST_RESIDUAL;
                                default: begin
                                    state_q <= ST_FAULT;
                                    range_fault_q <= 1'b1;
                                end
                            endcase
                        end
                    end
                end

                ST_ROPE_P0: begin
                    product0_q <= dsp_product;
                    state_q <= ST_ROPE_P1;
                end
                ST_ROPE_P1: begin
                    product1_q <= dsp_product;
                    state_q <= ST_ROPE_P2;
                end
                ST_ROPE_P2: begin
                    product2_q <= dsp_product;
                    state_q <= ST_ROPE_P3;
                end
                ST_ROPE_P3: begin
                    rope_accum0_pipe_q <= rope_accumulator0;
                    rope_accum1_pipe_q <= rope_accumulator1;
                    state_q <= ST_ROPE_ROUND;
                end
                ST_ROPE_ROUND: begin
                    rope_raw0_pipe_q <= rope_raw0_calc;
                    rope_raw1_pipe_q <= rope_raw1_calc;
                    rope_bound_bad_q <=
                        (rope_accum0_pipe_q < ROPE_MINIMUM) ||
                        (rope_accum0_pipe_q > ROPE_MAXIMUM) ||
                        (rope_accum1_pipe_q < ROPE_MINIMUM) ||
                        (rope_accum1_pipe_q > ROPE_MAXIMUM);
                    state_q <= ST_ROPE_CHECK;
                end
                ST_ROPE_CHECK: begin
                    if (rope_bound_bad_q ||
                        (rope_result0_calc < -34'sd32767) ||
                        (rope_result0_calc > 34'sd32767) ||
                        (rope_result1_calc < -34'sd32767) ||
                        (rope_result1_calc > 34'sd32767)) begin
                        state_q <= ST_FAULT;
                        range_fault_q <= 1'b1;
                    end else begin
                        result0_o <= rope_result0_calc[15:0];
                        result1_o <= rope_result1_calc[15:0];
                        raw0_o <= {{16{rope_raw0_pipe_q[33]}}, rope_raw0_pipe_q};
                        raw1_o <= {{16{rope_raw1_pipe_q[33]}}, rope_raw1_pipe_q};
                        source_exponent_o <= first_exponent_q;
                        state_q <= ST_RESULT;
                    end
                end

                ST_SILU_REQ: begin
                    lut_wait_q <= '0;
                    state_q <= ST_SILU_WAIT;
                end
                ST_SILU_WAIT: begin
                    if (lut_response_valid_i) begin
                        if (lut_value_i == 16'sh8000) begin
                            state_q <= ST_FAULT;
                            range_fault_q <= 1'b1;
                        end else begin
                            silu_value_q <= lut_value_i;
                            state_q <= ST_SILU_MUL;
                        end
                    end else if (lut_wait_q == 5'd16) begin
                        state_q <= ST_FAULT;
                        range_fault_q <= 1'b1;
                    end else begin
                        lut_wait_q <= lut_wait_q + 1'b1;
                    end
                end
                ST_SILU_MUL: begin
                    silu_product_pipe_q <= dsp_product;
                    state_q <= ST_SILU_ROUND;
                end
                ST_SILU_ROUND: begin
                    silu_result_pipe_q <= silu_result_calc;
                    silu_bound_bad_q <= (silu_raw_calc < ELEMENT_MINIMUM) ||
                                        (silu_raw_calc > ELEMENT_MAXIMUM);
                    state_q <= ST_SILU_CHECK;
                end
                ST_SILU_CHECK: begin
                    if (silu_bound_bad_q ||
                        (silu_result_pipe_q < -32'sd32767) ||
                        (silu_result_pipe_q > 32'sd32767)) begin
                        state_q <= ST_FAULT;
                        range_fault_q <= 1'b1;
                    end else begin
                        result0_o <= silu_result_pipe_q[15:0];
                        auxiliary_o <= silu_value_q;
                        raw0_o <= {{18{silu_raw_calc[31]}}, silu_raw_calc};
                        source_exponent_o <= silu_source_exponent_calc[7:0];
                        state_q <= ST_RESULT;
                    end
                end

                ST_RESIDUAL: begin
                    residual_raw_pipe_q <= residual_raw_calc;
                    state_q <= ST_RESIDUAL_CHECK;
                end
                ST_RESIDUAL_CHECK: begin
                    if ((residual_result_calc < -18'sd32767) ||
                        (residual_result_calc > 18'sd32767)) begin
                        state_q <= ST_FAULT;
                        range_fault_q <= 1'b1;
                    end else begin
                        result0_o <= residual_result_calc[15:0];
                        raw0_o <= {{32{residual_raw_pipe_q[17]}},
                                   residual_raw_pipe_q};
                        source_exponent_o <= common_exponent_q;
                        state_q <= ST_RESULT;
                    end
                end

                ST_RESULT: begin
                    if (result_valid_o && result_ready_i)
                        state_q <= ST_IDLE;
                end
                ST_FAULT: begin end
                default: begin
                    state_q <= ST_FAULT;
                    range_fault_q <= 1'b1;
                end
            endcase
        end
    end
endmodule

`default_nettype wire
