`undef FORMAL
`default_nettype none
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

module board1_fixed_rmsnorm_isqrt_u45_iterative (
    input  wire clk, input wire rst_n, input wire cancel_i,
    input  wire request_valid_i, output wire request_ready_o,
    input  wire [44:0] request_value_i,
    output wire response_valid_o, input wire response_ready_i,
    output wire [22:0] response_result_o, output wire response_fault_o
);
    board0_exact_isqrt_u45_iterative u_exact_board0_isqrt (
        .clk(clk), .rst_n(rst_n), .cancel_i(cancel_i),
        .request_valid_i(request_valid_i),
        .request_ready_o(request_ready_o),
        .request_value_i(request_value_i),
        .response_valid_o(response_valid_o),
        .response_ready_i(response_ready_i),
        .response_result_o(response_result_o),
        .response_fault_o(response_fault_o)
    );
endmodule

module board1_fixed_rmsnorm_rne_div_signed64_iterative (
    input  wire clk, input wire rst_n, input wire cancel_i,
    input  wire request_valid_i, output wire request_ready_o,
    input  wire signed [63:0] request_numerator_i,
    input  wire [63:0] request_denominator_i,
    output wire response_valid_o, input wire response_ready_i,
    output wire signed [63:0] response_result_o,
    output wire response_fault_o
);
    board1_rmsnorm_bounded28_divider u_exact_bounded_divider (
        .clk(clk), .rst_n(rst_n), .cancel_i(cancel_i),
        .request_valid_i(request_valid_i),
        .request_ready_o(request_ready_o),
        .request_numerator_i(request_numerator_i),
        .request_denominator_i(request_denominator_i),
        .response_valid_o(response_valid_o),
        .response_ready_i(response_ready_i),
        .response_result_o(response_result_o),
        .response_fault_o(response_fault_o)
    );
endmodule

module board1_rmsnorm_bounded28_divider (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cancel_i,

    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire signed [63:0]      request_numerator_i,
    input  wire [63:0]             request_denominator_i,

    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [63:0]     response_result_o,
    output logic                   response_fault_o
);
    logic                          busy_q;
    logic [5:0]                    iteration_q;
    logic                          negative_q;
    logic                          divide_by_zero_q;
    logic [63:0]                   divisor_q;
    logic [63:0]                   dividend_shift_q;
    logic [63:0]                   quotient_q;
    logic [64:0]                   remainder_q;

    logic [64:0]                   shifted_remainder;
    logic [64:0]                   reduced_remainder;
    logic [63:0]                   shifted_quotient;
    logic [63:0]                   rounded_magnitude;
    logic                          quotient_bit;
    logic                          round_up;

    // A response is deliberately retired before another request is admitted.
    // This makes the one-outstanding-request ownership unambiguous and costs
    // only one idle clock between independent operations.
    always_comb begin
        request_ready_o = rst_n && !cancel_i && !busy_q && !response_valid_o;

        shifted_remainder = {remainder_q[63:0], dividend_shift_q[63]};
        if (shifted_remainder >= {1'b0, divisor_q}) begin
            reduced_remainder = shifted_remainder - {1'b0, divisor_q};
            quotient_bit = 1'b1;
        end else begin
            reduced_remainder = shifted_remainder;
            quotient_bit = 1'b0;
        end
        shifted_quotient = {quotient_q[62:0], quotient_bit};

        // reduced_remainder is the final mathematical remainder during the
        // last iteration.  The 65-bit comparison cannot overflow at 2*r.
        round_up = ({reduced_remainder[63:0], 1'b0} >
                    {1'b0, divisor_q}) ||
                   (({reduced_remainder[63:0], 1'b0} ==
                     {1'b0, divisor_q}) && shifted_quotient[0]);
        rounded_magnitude = shifted_quotient +
                            {{63{1'b0}}, round_up};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            iteration_q <= 6'd0;
            negative_q <= 1'b0;
            divide_by_zero_q <= 1'b0;
            divisor_q <= 64'd0;
            dividend_shift_q <= 64'd0;
            quotient_q <= 64'd0;
            remainder_q <= 65'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 64'sd0;
            response_fault_o <= 1'b0;
        end else if (cancel_i) begin
            busy_q <= 1'b0;
            iteration_q <= 6'd0;
            negative_q <= 1'b0;
            divide_by_zero_q <= 1'b0;
            divisor_q <= 64'd0;
            dividend_shift_q <= 64'd0;
            quotient_q <= 64'd0;
            remainder_q <= 65'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 64'sd0;
            response_fault_o <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) begin
                response_valid_o <= 1'b0;
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
            end

            if (request_valid_i && request_ready_o) begin
                busy_q <= 1'b1;
                iteration_q <= 6'd36;
                negative_q <= request_numerator_i[63];
                divide_by_zero_q <= (request_denominator_i == 64'd0);
                divisor_q <= request_denominator_i;
                // Unary negation intentionally occurs at 64-bit width.  Its
                // bit pattern is also the correct magnitude for INT64_MIN.
                dividend_shift_q <= (request_numerator_i[63]
                    ? $unsigned(-request_numerator_i)
                    : $unsigned(request_numerator_i)) << 36;
                quotient_q <= 64'd0;
                remainder_q <= 65'd0;
                response_result_o <= 64'sd0;
                response_fault_o <= 1'b0;
            end else if (busy_q) begin
                dividend_shift_q <= {dividend_shift_q[62:0], 1'b0};
                quotient_q <= shifted_quotient;
                remainder_q <= reduced_remainder;

                if (iteration_q == 6'd63) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    if (divide_by_zero_q) begin
                        // Preserve the legacy result while making the invalid
                        // divisor explicit to its fixed-model caller.
                        response_result_o <= 64'sd0;
                        response_fault_o <= 1'b1;
                    end else begin
                        response_result_o <= negative_q
                            ? $signed(~rounded_magnitude + 64'd1)
                            : $signed(rounded_magnitude);
                        response_fault_o <= 1'b0;
                    end
                end else begin
                    iteration_q <= iteration_q + 6'd1;
                end
            end
        end
    end
endmodule

module board1_fixed_rmsnorm_rom #(
    parameter NORM_ROM_FILE =
        "fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/recorded/norm_rom34.memh"
) (
    input  wire                    clk,
    input  wire                    read_i,
    input  wire [11:0]             fixed_address_i,
    output logic signed [9:0]      coefficient_o,
    output logic [15:0]            multiplier_o,
    output logic signed [7:0]      tensor_exponent_o
);
    // 13 immutable vectors x 256 rows.  A synchronous read allows exact
    // device BSRAM inference; the file is independently reconstructed twice.
    (* nomem2reg, ram_style = "block" *)
    logic [33:0] norm_rom [0:3327];
    initial $readmemh(NORM_ROM_FILE, norm_rom);

    always_ff @(posedge clk) begin
        if (read_i && (fixed_address_i < 12'd3328)) begin
            coefficient_o <= $signed(norm_rom[fixed_address_i][9:0]);
            multiplier_o <= norm_rom[fixed_address_i][25:10];
            tensor_exponent_o <= $signed(norm_rom[fixed_address_i][33:26]);
        end
    end
endmodule

module board0_exact_isqrt_u45_iterative (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    cancel_i,

    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire [44:0]             request_value_i,

    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic [22:0]            response_result_o,
    output logic                   response_fault_o
);
    logic                          busy_q;
    logic [4:0]                    iteration_q;
    logic [45:0]                   radicand_shift_q;
    logic [46:0]                   remainder_q;
    logic [22:0]                   root_q;

    logic [46:0]                   shifted_remainder;
    logic [46:0]                   trial;
    logic [46:0]                   reduced_remainder;
    logic [22:0]                   shifted_root;
    logic                          root_bit;

    always_comb begin
        request_ready_o = rst_n && !cancel_i && !busy_q && !response_valid_o;

        shifted_remainder = (remainder_q << 2) |
                            {{45{1'b0}}, radicand_shift_q[45:44]};
        trial = ({24'd0, root_q} << 2) | 47'd1;
        if (shifted_remainder >= trial) begin
            reduced_remainder = shifted_remainder - trial;
            root_bit = 1'b1;
        end else begin
            reduced_remainder = shifted_remainder;
            root_bit = 1'b0;
        end
        shifted_root = {root_q[21:0], root_bit};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy_q <= 1'b0;
            iteration_q <= 5'd0;
            radicand_shift_q <= 46'd0;
            remainder_q <= 47'd0;
            root_q <= 23'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 23'd0;
            response_fault_o <= 1'b0;
        end else if (cancel_i) begin
            busy_q <= 1'b0;
            iteration_q <= 5'd0;
            radicand_shift_q <= 46'd0;
            remainder_q <= 47'd0;
            root_q <= 23'd0;
            response_valid_o <= 1'b0;
            response_result_o <= 23'd0;
            response_fault_o <= 1'b0;
        end else begin
            if (response_valid_o && response_ready_i) begin
                response_valid_o <= 1'b0;
                response_result_o <= 23'd0;
                response_fault_o <= 1'b0;
            end

            if (request_valid_i && request_ready_o) begin
                busy_q <= 1'b1;
                iteration_q <= 5'd0;
                // The leading zero makes the 45-bit radicand into exactly 23
                // two-bit groups, matching {2'b00,value} in the old function.
                radicand_shift_q <= {1'b0, request_value_i};
                remainder_q <= 47'd0;
                root_q <= 23'd0;
                response_result_o <= 23'd0;
                response_fault_o <= 1'b0;
            end else if (busy_q) begin
                radicand_shift_q <= {radicand_shift_q[43:0], 2'b00};
                remainder_q <= reduced_remainder;
                root_q <= shifted_root;

                if (iteration_q == 5'd22) begin
                    busy_q <= 1'b0;
                    response_valid_o <= 1'b1;
                    response_result_o <= shifted_root;
                    response_fault_o <= 1'b0;
                end else begin
                    iteration_q <= iteration_q + 5'd1;
                end
            end
        end
    end
endmodule

module board1_fixed_elementwise_dsp_lane (
    input  wire        [2:0]        mode_i,
    input  wire signed [15:0]       activation_i,
    input  wire signed [15:0]       dynamic_operand_i,
    input  wire signed [9:0]        direct_weight_i,
    input  wire signed [3:0]        coarse_weight0_i,
    input  wire signed [3:0]        coarse_weight1_i,
    input  wire        [5:0]        residual_weight0_i,
    input  wire        [5:0]        residual_weight1_i,
    input  wire signed [25:0]       wide_operand_i,
    input  wire        [15:0]       scale_operand_i,
    output wire signed [31:0]       product0_o,
    output wire signed [31:0]       product1_o,
    output wire signed [47:0]       wide_product_o
);
    localparam [2:0] MODE_DIRECT   = 3'd0;
    localparam [2:0] MODE_COARSE   = 3'd1;
    localparam [2:0] MODE_RESIDUAL = 3'd2;
    localparam [2:0] MODE_DYNAMIC  = 3'd3;
    localparam [2:0] MODE_WIDE     = 3'd4;

    wire signed [16:0] activation_extended =
        {activation_i[15], activation_i};
    wire [16:0] activation_magnitude = activation_i[15] ?
        $unsigned(-activation_extended) : $unsigned(activation_extended);

    wire signed [26:0] direct_operand =
        {{17{direct_weight_i[9]}}, direct_weight_i};
    wire signed [17:0] direct_activation_operand =
        {{2{activation_i[15]}}, activation_i};
    wire [3:0] coarse_unsigned0 = coarse_weight0_i + 4'd8;
    wire [3:0] coarse_unsigned1 = coarse_weight1_i + 4'd8;
    wire signed [26:0] coarse_operand = $signed({
        3'b000, coarse_unsigned1, 16'b0, coarse_unsigned0
    });
    wire signed [26:0] residual_operand = $signed({
        residual_weight1_i, 15'b0, residual_weight0_i
    });
    wire signed [17:0] magnitude_operand =
        $signed({1'b0, activation_magnitude});
    wire signed [26:0] dynamic_activation_operand =
        {{11{activation_i[15]}}, activation_i};
    wire signed [17:0] dynamic_second_operand =
        {{2{dynamic_operand_i[15]}}, dynamic_operand_i};
    wire signed [26:0] wide_first_operand =
        {wide_operand_i[25], wide_operand_i};
    wire signed [17:0] wide_scale_operand =
        $signed({2'b00, scale_operand_i});

    reg signed [26:0] selected_a;
    reg signed [17:0] selected_b;
    always @* begin
        case (mode_i)
            MODE_DIRECT: begin
                selected_a = direct_operand;
                selected_b = direct_activation_operand;
            end
            MODE_COARSE: begin
                selected_a = coarse_operand;
                selected_b = magnitude_operand;
            end
            MODE_RESIDUAL: begin
                selected_a = residual_operand;
                selected_b = magnitude_operand;
            end
            MODE_DYNAMIC: begin
                selected_a = dynamic_activation_operand;
                selected_b = dynamic_second_operand;
            end
            MODE_WIDE: begin
                selected_a = wide_first_operand;
                selected_b = wide_scale_operand;
            end
            default: begin
                selected_a = 27'bx;
                selected_b = 18'bx;
            end
        endcase
    end

    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [47:0] dsp_product;
    /* verilator lint_on UNUSEDSIGNAL */

`ifdef BOARD1_FIXED_ELEMENTWISE_GW5_DSP
    MULTALU27X18 #(
        .AREG_CLK("BYPASS"), .BREG_CLK("BYPASS"),
        .DREG_CLK("BYPASS"), .C_IREG_CLK("BYPASS"),
        .PSEL_IREG_CLK("BYPASS"), .PADDSUB_IREG_CLK("BYPASS"),
        .ADDSUB0_IREG_CLK("BYPASS"), .ADDSUB1_IREG_CLK("BYPASS"),
        .CSEL_IREG_CLK("BYPASS"), .CASISEL_IREG_CLK("BYPASS"),
        .ACCSEL_IREG_CLK("BYPASS"), .PREG_CLK("BYPASS"),
        .ADDSUB0_PREG_CLK("BYPASS"), .ADDSUB1_PREG_CLK("BYPASS"),
        .CSEL_PREG_CLK("BYPASS"), .CASISEL_PREG_CLK("BYPASS"),
        .ACCSEL_PREG_CLK("BYPASS"), .C_PREG_CLK("BYPASS"),
        .OREG_CLK("BYPASS"), .FB_PREG_EN("FALSE"),
        .SOA_PREG_EN("FALSE"), .PRE_LOAD(48'd0),
        .DYN_P_SEL("FALSE"), .P_SEL(1'b0),
        .DYN_P_ADDSUB("FALSE"), .P_ADDSUB(1'b0),
        .DYN_A_SEL("FALSE"), .A_SEL(1'b0),
        .DYN_ADD_SUB_0("FALSE"), .ADD_SUB_0(1'b0),
        .DYN_ADD_SUB_1("FALSE"), .ADD_SUB_1(1'b0),
        .DYN_C_SEL("FALSE"), .C_SEL(1'b0),
        .DYN_CASI_SEL("FALSE"), .CASI_SEL(1'b0),
        .DYN_ACC_SEL("FALSE"), .ACC_SEL(1'b0),
        .MULT12X12_EN("FALSE")
    ) u_shared_product (
        .DOUT(dsp_product), .CASO(), .SOA(),
        .A(selected_a), .SIA(27'd0), .B(selected_b),
        .C(48'd0), .D(26'd0), .CASI(48'd0),
        .ACCSEL(1'b0), .PSEL(1'b0), .ASEL(1'b0),
        .PADDSUB(1'b0), .CSEL(1'b0), .CASISEL(1'b0),
        .ADDSUB(2'b00), .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
    );
`else
    wire signed [44:0] behavioral_product = selected_a * selected_b;
    assign dsp_product = {{3{behavioral_product[44]}}, behavioral_product};
`endif

    wire [19:0] coarse_raw0 = dsp_product[19:0];
    wire [19:0] coarse_raw1 = dsp_product[39:20];
    wire [19:0] coarse_bias_product = {activation_magnitude, 3'b000};
    wire signed [20:0] coarse_centered0 =
        $signed({1'b0, coarse_raw0}) -
        $signed({1'b0, coarse_bias_product});
    wire signed [20:0] coarse_centered1 =
        $signed({1'b0, coarse_raw1}) -
        $signed({1'b0, coarse_bias_product});
    wire signed [20:0] coarse_signed0 = activation_i[15] ?
        -coarse_centered0 : coarse_centered0;
    wire signed [20:0] coarse_signed1 = activation_i[15] ?
        -coarse_centered1 : coarse_centered1;

    wire [20:0] residual_raw0 = dsp_product[20:0];
    /* verilator lint_off UNUSEDSIGNAL */
    wire signed [47:0] residual_high_shifted = $signed(dsp_product) >>> 21;
    /* verilator lint_on UNUSEDSIGNAL */
    wire signed [23:0] residual_sign_correction =
        $signed({1'b0, activation_magnitude, 6'b000000});
    wire signed [23:0] residual_magnitude0 =
        $signed({3'b000, residual_raw0});
    wire signed [23:0] residual_magnitude1 =
        $signed(residual_high_shifted[23:0]) +
        (residual_weight1_i[5] ? residual_sign_correction : 24'sd0);
    wire signed [23:0] residual_signed0 = activation_i[15] ?
        -residual_magnitude0 : residual_magnitude0;
    wire signed [23:0] residual_signed1 = activation_i[15] ?
        -residual_magnitude1 : residual_magnitude1;

    reg signed [31:0] selected_product0;
    reg signed [31:0] selected_product1;
    reg signed [47:0] selected_wide_product;
    always @* begin
        selected_product0 = 32'sd0;
        selected_product1 = 32'sd0;
        selected_wide_product = 48'sd0;
        case (mode_i)
            MODE_DIRECT: begin
                selected_product0 = {{6{dsp_product[25]}}, dsp_product[25:0]};
            end
            MODE_COARSE: begin
                selected_product0 = {{11{coarse_signed0[20]}}, coarse_signed0};
                selected_product1 = {{11{coarse_signed1[20]}}, coarse_signed1};
            end
            MODE_RESIDUAL: begin
                selected_product0 = {{8{residual_signed0[23]}}, residual_signed0};
                selected_product1 = {{8{residual_signed1[23]}}, residual_signed1};
            end
            MODE_DYNAMIC: begin
                selected_product0 = dsp_product[31:0];
            end
            MODE_WIDE: begin
                selected_wide_product = dsp_product;
            end
            default: begin
                selected_product0 = 32'bx;
                selected_product1 = 32'bx;
                selected_wide_product = 48'bx;
            end
        endcase
    end

    assign product0_o = selected_product0;
    assign product1_o = selected_product1;
    assign wide_product_o = selected_wide_product;
endmodule

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

module board1_fixed_vector_rne_shift_pipeline1 (
    input wire clk,rst_n,clear_i,request_valid_i,
    output wire request_ready_o,
    input wire signed [63:0] request_value_i,
    input wire signed [8:0] request_shift_i,
    output logic response_valid_o,
    input wire response_ready_i,
    output logic signed [63:0] response_result_o,
    output logic response_fault_o
);
    localparam [2:0] IDLE=0,LOW=1,HIGH=2,ROUND=3,HOLD=5;
    logic [2:0] state_q;
    wire busy_q=state_q!=IDLE && state_q!=HOLD;
    assign request_ready_o=rst_n && !clear_i && !busy_q && !response_valid_o;
    wire request_fire=request_valid_i && request_ready_o;

    // Reset/cancellation revokes state and output validity; private payload
    // registers are unread until a fresh accepted request initializes them.
    logic [127:0] source_q,low_q,shifted_q;
    logic [5:0] amount_q;
    logic left_q,negative_q,force_zero_q,bad_count_q;
    function automatic [127:0] reverse_bits(input [127:0] value);
        for(integer bit_index=0;bit_index<128;bit_index=bit_index+1)
            reverse_bits[bit_index]=value[127-bit_index];
    endfunction
    wire [63:0] magnitude=request_value_i[63] ? $unsigned(-request_value_i) : $unsigned(request_value_i);
    wire [127:0] left_result=reverse_bits(shifted_q);
    wire left_overflow=left_result[127:64]!={64{left_result[63]}};
    wire right_round_up=shifted_q[63] && ((|shifted_q[62:0]) || shifted_q[64]);
    // Merge sign and RNE increment into one modular two's-complement adder.
    wire [63:0] signed_right = (shifted_q[127:64] ^ {64{negative_q}}) +
        {63'd0, (right_round_up ^ negative_q)};
    wire result_fault = bad_count_q || (left_q && left_overflow);
    always_ff @(posedge clk) begin
        if(request_fire) begin
            source_q<=request_shift_i[8] ? reverse_bits({{64{request_value_i[63]}},request_value_i}) :
                {magnitude,64'd0};
            amount_q<=request_shift_i[8] ? -request_shift_i[5:0] : request_shift_i[5:0];
            left_q<=request_shift_i[8];negative_q<=request_value_i[63];
            // Preserve the predecessor's specified tails, even for zero:
            // count < -62 faults; count > +62 returns zero without fault.
            bad_count_q<=request_shift_i < -9'sd62;
            force_zero_q<=request_shift_i > 9'sd62;
        end
        if(state_q==LOW) low_q<=source_q>>amount_q[2:0];
        if(state_q==HIGH) shifted_q<=low_q>>{amount_q[5:3],3'b000};
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else if(clear_i) begin
            state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else case(state_q)
            IDLE: if(request_fire) state_q<=LOW;
            LOW: state_q<=HIGH;
            HIGH: state_q<=ROUND;
            ROUND: begin
                state_q<=HOLD;response_valid_o<=1;response_fault_o<=result_fault;
                response_result_o<=(result_fault || force_zero_q) ? 64'sd0 :
                    (left_q ? $signed(left_result[63:0]) : $signed(signed_right));
            end
            HOLD: if(response_ready_i) begin
                state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
            end
            default: begin
                state_q<=HOLD;response_valid_o<=1;response_result_o<=0;response_fault_o<=1;
            end
        endcase
    end
endmodule
