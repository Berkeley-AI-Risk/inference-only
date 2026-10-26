`timescale 1ns/1ps
`default_nettype none

// Exact private 256-element RMSNorm service for the fixed six-layer model.
// fixed_layer/kind are issued only by the sealed semantic schedule.  There is
// no public length, vector address, norm address, multiplier, divider, square
// root, or arithmetic operation in the proposed product boundary.
module board1_fixed_vector_rmsnorm_service #(
    parameter integer MAX_COMPUTE_CYCLES = 2_000_000,
    parameter NORM_ROM_FILE =
        "fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh"
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [2:0]              fixed_layer_i,
    // 0=input RMSNorm, 1=post-attention RMSNorm, 2=final RMSNorm.
    input  wire [1:0]              fixed_norm_kind_i,
    input  wire signed [7:0]       input_exponent_i,

    input  wire                    input_valid_i,
    output logic                   input_ready_o,
    input  wire [7:0]              input_row_index_i,
    input  wire signed [15:0]      input_mantissa_i,
    input  wire                    input_last_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [7:0]             result_row_index_o,
    output logic signed [15:0]     result_mantissa_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,
    output logic                   busy_o,
    output logic                   range_fault_o
);
    localparam signed [63:0] RMS_RAW_MAXIMUM = (64'sd1 <<< 39) - 1'b1;
    localparam signed [63:0] RMS_RAW_MINIMUM = -((64'sd1 <<< 39) - 1'b1);

    typedef enum logic [4:0] {
        ST_IDLE          = 5'd0,
        ST_CAPTURE       = 5'd1,
        ST_SQUARE_READ   = 5'd2,
        ST_SQUARE_ACCUM  = 5'd3,
        ST_SQRT_PREP     = 5'd4,
        ST_SQRT_ISSUE    = 5'd5,
        ST_SQRT_WAIT     = 5'd6,
        ST_NORM_START    = 5'd7,
        ST_LANE_READ     = 5'd8,
        ST_DIV_ISSUE     = 5'd9,
        ST_DIV_WAIT      = 5'd10,
        ST_MUL_WEIGHT    = 5'd11,
        ST_MUL_SCALE     = 5'd12,
        ST_RAW_ISSUE     = 5'd13,
        ST_NORM_WAIT     = 5'd14,
        ST_FAULT         = 5'd31
    } state_t;

    function automatic signed [63:0] rne_shift_signed64(
        input signed [63:0] value,
        input integer shift
    );
        logic [63:0] magnitude;
        logic [63:0] quotient_floor;
        logic [63:0] remainder;
        logic [63:0] half;
        logic [63:0] rounded;
        logic round_up;
        begin
            if (shift < 0) begin
                if ((-shift) > 62)
                    rne_shift_signed64 = 64'sd0;
                else
                    rne_shift_signed64 = value <<< (-shift);
            end else if (shift == 0) begin
                rne_shift_signed64 = value;
            end else if (shift > 62) begin
                rne_shift_signed64 = 64'sd0;
            end else begin
                magnitude = value[63] ? $unsigned(-value) : $unsigned(value);
                quotient_floor = magnitude >> shift;
                remainder = magnitude & ((64'd1 << shift) - 1'b1);
                half = 64'd1 << (shift - 1);
                round_up = (remainder > half) ||
                           ((remainder == half) && quotient_floor[0]);
                rounded = quotient_floor + {{63{1'b0}}, round_up};
                rne_shift_signed64 = value[63] ? -$signed(rounded) :
                                                 $signed(rounded);
            end
        end
    endfunction

    function automatic [15:0] expected_multiplier(input logic [3:0] selector);
        case (selector)
            4'd0:  expected_multiplier = 16'd18950;
            4'd1:  expected_multiplier = 16'd17930;
            4'd2:  expected_multiplier = 16'd18104;
            4'd3:  expected_multiplier = 16'd18211;
            4'd4:  expected_multiplier = 16'd18373;
            4'd5:  expected_multiplier = 16'd18536;
            4'd6:  expected_multiplier = 16'd18639;
            4'd7:  expected_multiplier = 16'd19036;
            4'd8:  expected_multiplier = 16'd19944;
            4'd9:  expected_multiplier = 16'd19662;
            4'd10: expected_multiplier = 16'd20229;
            4'd11: expected_multiplier = 16'd20732;
            4'd12: expected_multiplier = 16'd23930;
            default: expected_multiplier = 16'd0;
        endcase
    endfunction

    state_t state_q;
    logic [2:0] layer_q;
    logic [3:0] selector_q;
    logic signed [7:0] input_exponent_q;
    logic [7:0] capture_index_q;
    logic [7:0] lane_index_q;
    logic [37:0] square_sum_q;
    logic [44:0] radicand_q;
    logic [22:0] rms_q;
    logic signed [15:0] rms_normalized_q;
    logic signed [25:0] weight_product_q;
    logic signed [49:0] raw_q;
    logic signed [7:0] raw_source_exponent_q;
    logic [31:0] compute_cycles_q;

    (* nomem2reg, ram_style = "block" *)
    logic signed [15:0] vector_mem_q [0:255];
    logic signed [15:0] vector_read_q;
    wire vector_write_enable = input_valid_i && input_ready_o &&
        (input_row_index_i == capture_index_q) &&
        (input_mantissa_i != -16'sd32768) &&
        (input_last_i == (capture_index_q == 8'd255));
    wire vector_read_enable = (state_q == ST_SQUARE_READ) ||
                              (state_q == ST_LANE_READ);
    always_ff @(posedge clk) begin
        if (vector_write_enable)
            vector_mem_q[input_row_index_i] <= input_mantissa_i;
        if (vector_read_enable)
            vector_read_q <= vector_mem_q[lane_index_q];
    end

    wire descriptor_valid = (fixed_layer_i < 3'd6) &&
        ((fixed_norm_kind_i < 2'd2) ||
         ((fixed_norm_kind_i == 2'd2) && (fixed_layer_i == 3'd5)));
    wire [3:0] derived_selector = (fixed_norm_kind_i == 2'd2)
        ? 4'd12 : ({fixed_layer_i, 1'b0} + {2'd0, fixed_norm_kind_i});
    wire input_exponent_valid = (input_exponent_i >= -8'sd32) &&
                                (input_exponent_i <= 8'sd31);
    wire interface_live = rst_n && !clear_i && model_lock_i &&
        !upstream_fault_i && !range_fault_o &&
        (compute_cycles_q < MAX_COMPUTE_CYCLES);

    wire [11:0] rom_address = ({8'd0, selector_q} << 8) |
                              {4'd0, lane_index_q};
    logic signed [9:0] rom_coefficient;
    logic [15:0] rom_multiplier;
    logic signed [7:0] rom_tensor_exponent;
    board1_fixed_rmsnorm_rom #(.NORM_ROM_FILE(NORM_ROM_FILE)) u_norm_rom (
        .clk(clk), .read_i(state_q == ST_LANE_READ),
        .fixed_address_i(rom_address),
        .coefficient_o(rom_coefficient),
        .multiplier_o(rom_multiplier),
        .tensor_exponent_o(rom_tensor_exponent)
    );

    logic [2:0] dsp_mode;
    logic signed [15:0] dsp_activation;
    logic signed [15:0] dsp_dynamic_operand;
    logic signed [25:0] dsp_wide_operand;
    logic [15:0] dsp_scale_operand;
    logic signed [31:0] dsp_product0;
    /* verilator lint_off UNUSEDSIGNAL */
    logic signed [31:0] dsp_product1;
    /* verilator lint_on UNUSEDSIGNAL */
    logic signed [47:0] dsp_wide_product;
    board1_fixed_elementwise_dsp_lane u_sealed_shared_multiply (
        .mode_i(dsp_mode), .activation_i(dsp_activation),
        .dynamic_operand_i(dsp_dynamic_operand),
        .direct_weight_i(rom_coefficient),
        .coarse_weight0_i(4'sd0), .coarse_weight1_i(4'sd0),
        .residual_weight0_i(6'd0), .residual_weight1_i(6'd0),
        .wide_operand_i(dsp_wide_operand),
        .scale_operand_i(dsp_scale_operand),
        .product0_o(dsp_product0), .product1_o(dsp_product1),
        .wide_product_o(dsp_wide_product)
    );
    always_comb begin
        dsp_mode = 3'd0;
        dsp_activation = 16'sd0;
        dsp_dynamic_operand = 16'sd0;
        dsp_wide_operand = 26'sd0;
        dsp_scale_operand = 16'd0;
        case (state_q)
            ST_SQUARE_ACCUM: begin
                dsp_mode = 3'd3;
                dsp_activation = vector_read_q;
                dsp_dynamic_operand = vector_read_q;
            end
            ST_MUL_WEIGHT: begin
                dsp_mode = 3'd0;
                dsp_activation = rms_normalized_q;
            end
            ST_MUL_SCALE: begin
                dsp_mode = 3'd4;
                dsp_wide_operand = weight_product_q;
                dsp_scale_operand = rom_multiplier;
            end
            default: begin end
        endcase
    end

    logic signed [63:0] mean_square_wide;
    integer epsilon_shift;
    logic [44:0] epsilon_integer;
    logic [45:0] radicand_wide;
    always_comb begin
        mean_square_wide = rne_shift_signed64(
            $signed({1'b0, 25'd0, square_sum_q}), 8);
        epsilon_shift = -20 - (2 * $signed(input_exponent_q));
        if (epsilon_shift < 0)
            epsilon_integer = 45'(rne_shift_signed64(64'sd1,
                                                      -epsilon_shift));
        else if (epsilon_shift > 44)
            epsilon_integer = {45{1'b1}};
        else
            epsilon_integer = 45'd1 << epsilon_shift;
        radicand_wide = {1'b0, mean_square_wide[44:0]} +
                        {1'b0, epsilon_integer};
        if (radicand_wide == 0)
            radicand_wide = 46'd1;
    end

    logic sqrt_request_valid;
    wire sqrt_request_ready;
    wire sqrt_response_valid;
    logic sqrt_response_ready;
    wire [22:0] sqrt_response_result;
    wire sqrt_response_fault;
    board1_fixed_rmsnorm_isqrt_u45_iterative u_exact_isqrt (
        .clk(clk), .rst_n(rst_n),
        .cancel_i(clear_i || range_fault_o),
        .request_valid_i(sqrt_request_valid),
        .request_ready_o(sqrt_request_ready),
        .request_value_i(radicand_q),
        .response_valid_o(sqrt_response_valid),
        .response_ready_i(sqrt_response_ready),
        .response_result_o(sqrt_response_result),
        .response_fault_o(sqrt_response_fault)
    );

    logic div_request_valid;
    wire div_request_ready;
    wire div_response_valid;
    logic div_response_ready;
    wire signed [63:0] div_response_result;
    wire div_response_fault;
    wire signed [63:0] div_numerator =
        $signed({{48{vector_read_q[15]}}, vector_read_q}) <<< 12;
    wire signed [15:0] div_clamped16 =
        (div_response_result < -64'sd32767) ? -16'sd32767 :
        (div_response_result > 64'sd32767) ? 16'sd32767 :
        div_response_result[15:0];
    board1_fixed_rmsnorm_rne_div_signed64_iterative u_exact_divider (
        .clk(clk), .rst_n(rst_n),
        .cancel_i(clear_i || range_fault_o),
        .request_valid_i(div_request_valid),
        .request_ready_o(div_request_ready),
        .request_numerator_i(div_numerator),
        .request_denominator_i({41'd0, rms_q}),
        .response_valid_o(div_response_valid),
        .response_ready_i(div_response_ready),
        .response_result_o(div_response_result),
        .response_fault_o(div_response_fault)
    );

    logic norm_start_valid;
    wire norm_start_ready;
    logic norm_input_valid;
    wire norm_input_ready;
    wire norm_result_valid;
    logic norm_result_ready;
    wire [9:0] norm_result_row;
    wire signed [15:0] norm_result_mantissa;
    wire signed [7:0] norm_result_exponent;
    wire norm_result_last;
    wire norm_done_valid;
    logic norm_done_ready;
    wire norm_busy;
    wire norm_fault;
    board1_fixed_vector_normalizer u_frozen_vector_normalizer (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i || range_fault_o),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || range_fault_o),
        .start_valid_i(norm_start_valid), .start_ready_o(norm_start_ready),
        .fixed_layer_i(layer_q), .fixed_job_i(4'd0),
        .input_valid_i(norm_input_valid), .input_ready_o(norm_input_ready),
        .input_row_index_i({2'd0, lane_index_q}), .input_raw_i(raw_q),
        .input_source_exponent_i(raw_source_exponent_q),
        .input_last_i(lane_index_q == 8'd255),
        .result_valid_o(norm_result_valid),
        .result_ready_i(norm_result_ready),
        .result_row_index_o(norm_result_row),
        .result_mantissa_o(norm_result_mantissa),
        .result_exponent_o(norm_result_exponent),
        .result_last_o(norm_result_last),
        .done_valid_o(norm_done_valid), .done_ready_i(norm_done_ready),
        .busy_o(norm_busy), .range_fault_o(norm_fault)
    );

    logic signed [63:0] raw_wide;
    logic signed [8:0] source_exponent_wide;
    always_comb begin
        raw_wide = {{16{dsp_wide_product[47]}}, dsp_wide_product};
        source_exponent_wide =
            $signed({rom_tensor_exponent[7], rom_tensor_exponent}) - 9'sd27;

        start_ready_o = interface_live && (state_q == ST_IDLE);
        input_ready_o = interface_live && (state_q == ST_CAPTURE);
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAULT);

        sqrt_request_valid = interface_live && (state_q == ST_SQRT_ISSUE);
        sqrt_response_ready = (state_q == ST_SQRT_WAIT);
        div_request_valid = interface_live && (state_q == ST_DIV_ISSUE);
        div_response_ready = (state_q == ST_DIV_WAIT);
        norm_start_valid = interface_live && (state_q == ST_NORM_START);
        norm_input_valid = interface_live && (state_q == ST_RAW_ISSUE);

        result_valid_o = interface_live && (state_q == ST_NORM_WAIT) &&
                         norm_result_valid;
        result_row_index_o = norm_result_row[7:0];
        result_mantissa_o = norm_result_mantissa;
        result_exponent_o = norm_result_exponent;
        result_last_o = norm_result_last;
        norm_result_ready = (state_q == ST_NORM_WAIT) && result_ready_i;
        done_valid_o = interface_live && (state_q == ST_NORM_WAIT) &&
                       norm_done_valid;
        norm_done_ready = (state_q == ST_NORM_WAIT) && done_ready_i;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            selector_q <= 4'd0;
            input_exponent_q <= 8'sd0;
            capture_index_q <= 8'd0;
            lane_index_q <= 8'd0;
            square_sum_q <= 38'd0;
            radicand_q <= 45'd0;
            rms_q <= 23'd0;
            rms_normalized_q <= 16'sd0;
            weight_product_q <= 26'sd0;
            raw_q <= 50'sd0;
            raw_source_exponent_q <= 8'sd0;
            compute_cycles_q <= 32'd0;
            range_fault_o <= 1'b0;
        end else if (clear_i) begin
            // Precise component abort contract: CLEAR cancels an accepted
            // RMS request with no terminal response; the fixed caller replays
            // the whole sealed vector.  The internal ROM owns no outstanding
            // external transaction, so no response can be orphaned.
            state_q <= ST_IDLE;
            layer_q <= 3'd0;
            selector_q <= 4'd0;
            input_exponent_q <= 8'sd0;
            capture_index_q <= 8'd0;
            lane_index_q <= 8'd0;
            square_sum_q <= 38'd0;
            radicand_q <= 45'd0;
            rms_q <= 23'd0;
            rms_normalized_q <= 16'sd0;
            weight_product_q <= 26'sd0;
            raw_q <= 50'sd0;
            raw_source_exponent_q <= 8'sd0;
            compute_cycles_q <= 32'd0;
            range_fault_o <= 1'b0;
        end else if (range_fault_o) begin
            state_q <= ST_FAULT;
            range_fault_o <= 1'b1;
        end else if ((state_q != ST_IDLE) && (state_q != ST_FAULT) &&
                     (compute_cycles_q >= MAX_COMPUTE_CYCLES - 1)) begin
            state_q <= ST_FAULT;
            range_fault_o <= 1'b1;
        end else begin
            if ((state_q != ST_IDLE) && (state_q != ST_FAULT))
                compute_cycles_q <= compute_cycles_q + 1'b1;

`ifndef SYNTHESIS
            if ($isunknown(clear_i) || $isunknown(model_lock_i) ||
                $isunknown(upstream_fault_i) || $isunknown(start_valid_i) ||
                $isunknown(input_valid_i) || $isunknown(result_ready_i) ||
                $isunknown(done_ready_i) ||
                ((start_valid_i === 1'b1) &&
                 ($isunknown(fixed_layer_i) ||
                  $isunknown(fixed_norm_kind_i) ||
                  $isunknown(input_exponent_i))) ||
                ((input_valid_i === 1'b1) &&
                 ($isunknown(input_row_index_i) ||
                  $isunknown(input_mantissa_i) ||
                  $isunknown(input_last_i)))) begin
                state_q <= ST_FAULT;
                range_fault_o <= 1'b1;
            end else
`endif
            if (upstream_fault_i === 1'b1 ||
                (((state_q != ST_IDLE) && (state_q != ST_FAULT)) &&
                 (model_lock_i !== 1'b1)) ||
                ((start_valid_i === 1'b1) &&
                 (model_lock_i !== 1'b1)) || norm_fault ||
                (sqrt_response_valid && (state_q != ST_SQRT_WAIT)) ||
                (div_response_valid && (state_q != ST_DIV_WAIT)) ||
                (norm_result_valid && (norm_result_row[9:8] != 2'd0)) ||
                ((norm_result_valid || norm_done_valid) &&
                 (state_q != ST_NORM_WAIT))) begin
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
                            if (!descriptor_valid || !input_exponent_valid) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else begin
                                layer_q <= fixed_layer_i;
                                selector_q <= derived_selector;
                                input_exponent_q <= input_exponent_i;
                                capture_index_q <= 8'd0;
                                lane_index_q <= 8'd0;
                                square_sum_q <= 38'd0;
                                state_q <= ST_CAPTURE;
                            end
                        end
                    end
                    ST_CAPTURE: begin
                        if (input_valid_i && input_ready_o) begin
                            if ((input_row_index_i != capture_index_q) ||
                                (input_last_i !=
                                 (capture_index_q == 8'd255)) ||
                                (input_mantissa_i == -16'sd32768)) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else if (capture_index_q == 8'd255) begin
                                lane_index_q <= 8'd0;
                                square_sum_q <= 38'd0;
                                state_q <= ST_SQUARE_READ;
                            end else begin
                                capture_index_q <= capture_index_q + 1'b1;
                            end
                        end
                    end
                    ST_SQUARE_READ: state_q <= ST_SQUARE_ACCUM;
                    ST_SQUARE_ACCUM: begin
                        if (dsp_product0[31] ||
                            ({1'b0, square_sum_q} +
                             {7'd0, dsp_product0[31:0]} >= (39'd1 << 38))) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            square_sum_q <= square_sum_q +
                                            {7'd0, dsp_product0[30:0]};
                            if (lane_index_q == 8'd255)
                                state_q <= ST_SQRT_PREP;
                            else begin
                                lane_index_q <= lane_index_q + 1'b1;
                                state_q <= ST_SQUARE_READ;
                            end
                        end
                    end
                    ST_SQRT_PREP: begin
                        if (mean_square_wide < 0 || radicand_wide[45]) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            radicand_q <= radicand_wide[44:0];
                            state_q <= ST_SQRT_ISSUE;
                        end
                    end
                    ST_SQRT_ISSUE: begin
                        if (sqrt_request_valid && sqrt_request_ready)
                            state_q <= ST_SQRT_WAIT;
                    end
                    ST_SQRT_WAIT: begin
                        if (sqrt_response_valid && sqrt_response_ready) begin
                            if (sqrt_response_fault ||
                                (sqrt_response_result == 0)) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else begin
                                rms_q <= sqrt_response_result;
                                lane_index_q <= 8'd0;
                                state_q <= ST_NORM_START;
                            end
                        end
                    end
                    ST_NORM_START: begin
                        if (norm_start_valid && norm_start_ready)
                            state_q <= ST_LANE_READ;
                    end
                    ST_LANE_READ: state_q <= ST_DIV_ISSUE;
                    ST_DIV_ISSUE: begin
                        if ((rom_coefficient == -10'sd512) ||
                            (rom_multiplier != expected_multiplier(selector_q)) ||
                            ((selector_q < 4'd12) &&
                             (rom_tensor_exponent != -8'sd8)) ||
                            ((selector_q == 4'd12) &&
                             (rom_tensor_exponent != -8'sd7)) ||
                            (vector_read_q == -16'sd32768)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else if (div_request_valid && div_request_ready) begin
                            state_q <= ST_DIV_WAIT;
                        end
                    end
                    ST_DIV_WAIT: begin
                        if (div_response_valid && div_response_ready) begin
                            if (div_response_fault) begin
                                state_q <= ST_FAULT;
                                range_fault_o <= 1'b1;
                            end else begin
                                rms_normalized_q <= div_clamped16;
                                state_q <= ST_MUL_WEIGHT;
                            end
                        end
                    end
                    ST_MUL_WEIGHT: begin
                        weight_product_q <= dsp_product0[25:0];
                        state_q <= ST_MUL_SCALE;
                    end
                    ST_MUL_SCALE: begin
                        if ((raw_wide < RMS_RAW_MINIMUM) ||
                            (raw_wide > RMS_RAW_MAXIMUM) ||
                            (source_exponent_wide < -9'sd128) ||
                            (source_exponent_wide > 9'sd127)) begin
                            state_q <= ST_FAULT;
                            range_fault_o <= 1'b1;
                        end else begin
                            raw_q <= 50'(raw_wide);
                            raw_source_exponent_q <= 8'(source_exponent_wide);
                            state_q <= ST_RAW_ISSUE;
                        end
                    end
                    ST_RAW_ISSUE: begin
                        if (norm_input_valid && norm_input_ready) begin
                            if (lane_index_q == 8'd255)
                                state_q <= ST_NORM_WAIT;
                            else begin
                                lane_index_q <= lane_index_q + 1'b1;
                                state_q <= ST_LANE_READ;
                            end
                        end
                    end
                    ST_NORM_WAIT: begin
                        if (norm_done_valid && norm_done_ready) begin
                            state_q <= ST_IDLE;
                            compute_cycles_q <= 32'd0;
                        end
                    end
                    default: begin
                        state_q <= ST_FAULT;
                        range_fault_o <= 1'b1;
                    end
                endcase
            end
        end
    end

    // Keep the child busy indication structurally observed without creating a
    // product-visible status operation.
    wire _unused_norm_busy = norm_busy;
endmodule

`default_nettype wire
