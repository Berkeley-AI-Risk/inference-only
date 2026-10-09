`default_nettype none
module fcp_stage_reference #(parameter integer ADDR_W=19)(
    input wire attention_done_ready,
    input wire attention_done_valid,
    input wire attention_query_fire,
    input wire attention_ram_read_enable,
    input wire attention_result_descriptor_ok,
    input wire signed [7:0] attention_result_exponent,
    input wire attention_result_fire,
    input wire attention_result_last,
    input wire attention_result_valid,
    input wire attention_start_ready,
    input wire attention_start_valid,
    input wire child_fault,
    input wire clear_i,
    input wire clk,
    input wire signed [15:0] gate_read_data,
    input wire head_activation_fire,
    input wire head_done_fire,
    input wire head_result_fire,
    input wire head_start_accept,
    input wire hidden_ram_read_enable,
    input wire signed [15:0] key_ram_read_data,
    input wire key_ram_read_enable,
    input wire kv_commit_ready,
    input wire kv_commit_valid,
    input wire kv_pending_complete,
    input wire kv_stage_begin_ready,
    input wire kv_stage_begin_valid,
    input wire kv_stage_payload_ready,
    input wire kv_stage_payload_valid,
    input wire [15:0] lane_lut_index,
    input wire lane_lut_request,
    input wire lane_request_ready,
    input wire lane_request_valid,
    input wire lane_result_fire,
    input wire lookup_request_ready,
    input wire lookup_request_valid,
    input wire lookup_response_fault,
    input wire lookup_response_ready,
    input wire lookup_response_valid,
    input wire signed [15:0] lookup_response_value,
    input wire model_lock_i,
    input wire norm_done_ready,
    input wire norm_done_valid,
    input wire norm_input_fire,
    input wire signed [7:0] norm_result_exponent,
    input wire norm_result_fire,
    input wire [9:0] norm_result_index,
    input wire norm_result_last,
    input wire norm_start_ready,
    input wire norm_start_valid,
    input wire signed [7:0] private_head_activation_exponent_i,
    input wire signed [7:0] private_initial_exponent_i,
    input wire [2:0] private_layer_i,
    input wire [10:0] private_position_i,
    input wire [4:0] private_stage_i,
    input wire [9:0] projection_activation_count,
    input wire projection_activation_fire,
    input wire projection_done_ready,
    input wire projection_done_valid,
    input wire [9:0] projection_result_count,
    input wire projection_result_last,
    input wire projection_start_ready,
    input wire projection_start_valid,
    input wire projection_uses_rms,
    input wire signed [15:0] query_ram_read_data,
    input wire query_ram_read_enable,
    input wire rms_done_ready,
    input wire rms_done_valid,
    input wire rms_input_fire,
    input wire rms_ram_read_enable,
    input wire signed [7:0] rms_result_exponent,
    input wire rms_result_fire,
    input wire [7:0] rms_result_index,
    input wire rms_result_last,
    input wire rms_start_ready,
    input wire rms_start_valid,
    input wire rst_n,
    input wire scratch_read_enable,
    input wire simulation_x_fault,
    input wire stage_accept,
    input wire upstream_fault_i,
    input wire value_ram_read_enable,
    output wire fault_o,
    output wire [3:0] engine_o,
    output wire [296:0] private_state_o
);
    localparam logic [4:0] STAGE_INPUT_RMS = 5'd0;
    localparam logic [4:0] STAGE_Q          = 5'd1;
    localparam logic [4:0] STAGE_K          = 5'd2;
    localparam logic [4:0] STAGE_V          = 5'd3;
    localparam logic [4:0] STAGE_Q_ROPE     = 5'd4;
    localparam logic [4:0] STAGE_K_ROPE     = 5'd5;
    localparam logic [4:0] STAGE_KV_STAGE   = 5'd6;
    localparam logic [4:0] STAGE_ATTENTION  = 5'd7;
    localparam logic [4:0] STAGE_O          = 5'd8;
    localparam logic [4:0] STAGE_RESIDUAL_1 = 5'd9;
    localparam logic [4:0] STAGE_POST_RMS   = 5'd10;
    localparam logic [4:0] STAGE_GATE       = 5'd11;
    localparam logic [4:0] STAGE_UP         = 5'd12;
    localparam logic [4:0] STAGE_SILU_MUL   = 5'd13;
    localparam logic [4:0] STAGE_DOWN       = 5'd14;
    localparam logic [4:0] STAGE_RESIDUAL_2 = 5'd15;
    localparam logic [4:0] STAGE_KV_COMMIT  = 5'd16;

    typedef enum logic [3:0] {
        E_IDLE   = 4'd0,
        E_RMS    = 4'd1,
        E_PROJ   = 4'd2,
        E_ROPE   = 4'd3,
        E_KV     = 4'd4,
        E_ATTN   = 4'd5,
        E_ELEM   = 4'd6,
        E_COMMIT = 4'd7,
        E_HEAD   = 4'd8,
        E_FAULT  = 4'd15
    } engine_state_t;

    localparam logic [3:0] RP_NORM_START = 4'd0;
    localparam logic [3:0] RP_COS_REQ    = 4'd1;
    localparam logic [3:0] RP_COS_WAIT   = 4'd2;
    localparam logic [3:0] RP_SIN_REQ    = 4'd3;
    localparam logic [3:0] RP_SIN_WAIT   = 4'd4;
    localparam logic [3:0] RP_LANE_REQ   = 4'd5;
    localparam logic [3:0] RP_LANE_WAIT  = 4'd6;
    localparam logic [3:0] RP_SECOND     = 4'd7;
    localparam logic [3:0] RP_NORM_WAIT  = 4'd8;
    localparam logic [3:0] RP_OPERAND0_REQ  = 4'd9;
    localparam logic [3:0] RP_OPERAND0_WAIT = 4'd10;
    localparam logic [3:0] RP_OPERAND1_REQ  = 4'd11;
    localparam logic [3:0] RP_OPERAND1_WAIT = 4'd12;
    localparam logic [3:0] RP_SECOND_REQ    = 4'd13;

    localparam logic [2:0] EL_NORM_START = 3'd0;
    localparam logic [2:0] EL_RAM_REQ    = 3'd1;
    localparam logic [2:0] EL_LOOK_REQ   = 3'd2;
    localparam logic [2:0] EL_LOOK_WAIT  = 3'd3;
    localparam logic [2:0] EL_LANE_REQ   = 3'd4;
    localparam logic [2:0] EL_LANE_WAIT  = 3'd5;
    localparam logic [2:0] EL_NORM_WAIT  = 3'd6;

    function automatic signed [63:0] rne_shift_signed64(
        input signed [63:0] value,
        input integer shift
    );
        logic [63:0] magnitude;
        logic [63:0] quotient_floor;
        logic [63:0] remainder;
        logic [63:0] half;
        logic round_up;
        begin
            if (shift < 0)
                rne_shift_signed64 = value <<< (-shift);
            else if (shift == 0)
                rne_shift_signed64 = value;
            else if (shift > 62)
                rne_shift_signed64 = 64'sd0;
            else begin
                magnitude = value[63] ? $unsigned(-value) : $unsigned(value);
                quotient_floor = magnitude >> shift;
                remainder = magnitude & ((64'd1 << shift) - 1'b1);
                half = 64'd1 << (shift - 1);
                round_up = (remainder > half) ||
                    ((remainder == half) && quotient_floor[0]);
                rne_shift_signed64 = value[63]
                    ? -$signed(quotient_floor + round_up)
                    : $signed(quotient_floor + round_up);
            end
        end
    endfunction

    function automatic [15:0] silu_index_for_reference(
        input signed [15:0] mantissa,
        input signed [7:0] exponent
    );
        logic signed [63:0] q10;
        logic signed [16:0] clipped;
        integer shift;
        begin
            shift = -($signed({{24{exponent[7]}}, exponent}) + 32'sd10);
            q10 = rne_shift_signed64({{48{mantissa[15]}}, mantissa}, shift);
            if (q10 < -64'sd32768)
                clipped = -17'sd32768;
            else if (q10 > 64'sd32767)
                clipped = 17'sd32767;
            else
                clipped = 17'(q10);
            silu_index_for_reference = 16'($signed(clipped) + 18'sd32768);
        end
    endfunction

    function automatic [15:0] silu_index_for(
        input signed [15:0] mantissa,
        input signed [7:0] exponent
    );
        logic signed [8:0] left_amount;
        logic [8:0] right_amount;
        logic [15:0] magnitude, quotient_floor, remainder, half, rounded;
        logic signed [15:0] small_q10;
        logic signed [30:0] shifted;
        logic [15:0] tail_mask;
        logic [3:0] wrapped_sign_index;
        begin
            // The input has only 16 significant bits. Right shifts >=16
            // round to zero, including the -32768 / 65536 tie-to-even.
            left_amount=$signed({exponent[7],exponent})+9'sd10;
            right_amount=$unsigned(-left_amount);
            magnitude=mantissa[15] ? -$unsigned(mantissa) : $unsigned(mantissa);
            quotient_floor=0; remainder=0; half=0; rounded=0;
            small_q10=0; shifted=0; tail_mask=0; wrapped_sign_index=0;
            silu_index_for=16'h8000;
            if(left_amount<0) begin
                if(right_amount<9'd16) begin
                    quotient_floor=magnitude>>right_amount[3:0];
                    remainder=magnitude&((16'd1<<right_amount[3:0])-16'd1);
                    half=16'd1<<(right_amount[3:0]-4'd1);
                    rounded=quotient_floor+16'((remainder>half)||
                        ((remainder==half)&&quotient_floor[0]));
                    small_q10=mantissa[15] ? -$signed(rounded) : $signed(rounded);
                    silu_index_for={~small_q10[15],small_q10[14:0]};
                end
            end else if(left_amount==0) begin
                silu_index_for={~mantissa[15],mantissa[14:0]};
            end else if(left_amount<9'sd15) begin
                shifted=$signed({{15{mantissa[15]}},mantissa})<<<left_amount[3:0];
                if(shifted < -31'sd32768) silu_index_for=16'h0000;
                else if(shifted > 31'sd32767) silu_index_for=16'hffff;
                else silu_index_for={~shifted[15],shifted[14:0]};
            end else if(left_amount<=9'sd48) begin
                if(mantissa!=0) silu_index_for=mantissa[15] ? 16'h0000 : 16'hffff;
            end else if(left_amount<9'sd64) begin
                // Preserve the ORIGINAL signed-64-bit overflow semantics
                // even for extreme exponents not expected during inference.
                // For shifts 49..63 only the low 15..1 input bits survive.
                tail_mask=16'hffff>>left_amount[3:0];
                wrapped_sign_index=4'd15-left_amount[3:0];
                if(($unsigned(mantissa)&tail_mask)!=0)
                    silu_index_for=mantissa[wrapped_sign_index] ? 16'h0000 : 16'hffff;
            end
            // A signed-64-bit shift >=64 yields zero, hence the default.
`ifndef SYNTHESIS
            // Preserve the predecessor's exact four-state behavior too.
            // This is simulation-only, not a physical unknown detector.
            if($isunknown({mantissa,exponent}))
                silu_index_for=silu_index_for_reference(mantissa,exponent);
`endif
        end
    endfunction
    logic signed [7:0] attention_exponent_q;
    logic [2:0] attention_head_q;
    logic [5:0] attention_query_load_lane_q;
    logic attention_query_loaded_q;
    logic attention_query_read_valid_q;
    logic attention_read_valid_q;
    logic [2:0] attention_result_head_q;
    logic [5:0] attention_store_lane_q;
    logic [2:0] current_layer_q;
    logic [10:0] current_position_q;
    logic [4:0] current_stage_q;
    logic down_gate_valid_q;
    logic [9:0] elem_index_q;
    logic [2:0] elem_phase_q;
    engine_state_t engine_state_q;
    logic [2:0] expected_layer_q;
    logic [4:0] expected_stage_q;
    logic fault_q;
    logic signed [7:0] gate_exponent_q;
    logic signed [7:0] head_activation_exponent_q;
    logic head_last_seen_q;
    logic [12:0] head_result_index_q;
    logic signed [7:0] hidden_exponent_q;
    logic hidden_read_valid_q;
    logic input_done_q;
    logic [9:0] input_index_q;
    logic signed [7:0] key_exponent_q;
    logic kv_read_valid_q;
    logic lane_lut_response_q;
    logic lock_seen_q;
    logic norm_done_seen_q;
    logic norm_start_seen_q;
    logic output_done_q;
    logic signed [7:0] output_exponent_q;
    logic [9:0] output_index_q;
    logic signed [7:0] query_exponent_q;
    logic signed [7:0] rms_exponent_q;
    logic rms_read_valid_q;
    logic signed [15:0] rope_cosine_q;
    logic [4:0] rope_half_q;
    logic [1:0] rope_head_q;
    logic signed [15:0] rope_operand0_q;
    logic signed [15:0] rope_operand1_q;
    logic [3:0] rope_phase_q;
    logic [4:0] rope_second_index_q;
    logic signed [15:0] rope_sine_q;
    logic service_done_seen_q;
    logic service_start_seen_q;
    logic signed [15:0] silu_value_q;
    logic silu_value_valid_q;
    logic stage_done_q;
    logic [10:0] transaction_position_q;
    logic transaction_seen_q;
    logic signed [7:0] up_exponent_q;
    logic signed [7:0] value_exponent_q;
    // Stage controller and private vector writes.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            engine_state_q <= E_IDLE;
            current_stage_q <= STAGE_INPUT_RMS;
            current_layer_q <= 3'd0;
            current_position_q <= 11'd0;
            expected_stage_q <= STAGE_INPUT_RMS;
            expected_layer_q <= 3'd0;
            transaction_position_q <= 11'd0;
            transaction_seen_q <= 1'b0;
            fault_q <= 1'b0;
            lock_seen_q <= 1'b0;
            stage_done_q <= 1'b0;
            hidden_exponent_q <= 8'sd0;
            rms_exponent_q <= 8'sd0;
            query_exponent_q <= 8'sd0;
            key_exponent_q <= 8'sd0;
            value_exponent_q <= 8'sd0;
            attention_exponent_q <= 8'sd0;
            output_exponent_q <= 8'sd0;
            gate_exponent_q <= 8'sd0;
            up_exponent_q <= 8'sd0;
            service_start_seen_q <= 1'b0;
            norm_start_seen_q <= 1'b0;
            input_done_q <= 1'b0;
            output_done_q <= 1'b0;
            service_done_seen_q <= 1'b0;
            norm_done_seen_q <= 1'b0;
            input_index_q <= 10'd0;
            output_index_q <= 10'd0;
            head_activation_exponent_q <= 8'sd0;
            head_result_index_q <= 13'd0;
            head_last_seen_q <= 1'b0;
            down_gate_valid_q <= 1'b0;
            attention_read_valid_q <= 1'b0;
            attention_store_lane_q <= 6'd0;
            rms_read_valid_q <= 1'b0;
            hidden_read_valid_q <= 1'b0;
            rope_phase_q <= RP_NORM_START;
            rope_head_q <= 2'd0;
            rope_half_q <= 5'd0;
            rope_second_index_q <= 5'd0;
            rope_cosine_q <= 16'sd0;
            rope_sine_q <= 16'sd0;
            rope_operand0_q <= 16'sd0;
            rope_operand1_q <= 16'sd0;
            elem_phase_q <= EL_NORM_START;
            elem_index_q <= 10'd0;
            silu_value_q <= 16'sd0;
            silu_value_valid_q <= 1'b0;
            lane_lut_response_q <= 1'b0;
            attention_head_q <= 3'd0;
            attention_result_head_q <= 3'd0;
            attention_query_load_lane_q <= 6'd0;
            attention_query_read_valid_q <= 1'b0;
            attention_query_loaded_q <= 1'b0;
            kv_read_valid_q <= 1'b0;
        end else begin
            stage_done_q <= 1'b0;
            lane_lut_response_q <= 1'b0;
            if (model_lock_i)
                lock_seen_q <= 1'b1;

            if (upstream_fault_i || child_fault ||
                (lock_seen_q && !model_lock_i)
`ifndef SYNTHESIS
                || simulation_x_fault
`endif
            ) begin
                fault_q <= 1'b1;
                engine_state_q <= E_FAULT;
            end else if (clear_i) begin
                if (fault_q)
                    engine_state_q <= E_FAULT;
                else
                    engine_state_q <= E_IDLE;
                current_stage_q <= STAGE_INPUT_RMS;
                current_layer_q <= 3'd0;
                current_position_q <= 11'd0;
                expected_stage_q <= STAGE_INPUT_RMS;
                expected_layer_q <= 3'd0;
                transaction_position_q <= 11'd0;
                transaction_seen_q <= 1'b0;
                stage_done_q <= 1'b0;
                service_start_seen_q <= 1'b0;
                norm_start_seen_q <= 1'b0;
                input_done_q <= 1'b0;
                output_done_q <= 1'b0;
                service_done_seen_q <= 1'b0;
                norm_done_seen_q <= 1'b0;
                input_index_q <= 10'd0;
                output_index_q <= 10'd0;
                head_activation_exponent_q <= 8'sd0;
                head_result_index_q <= 13'd0;
                head_last_seen_q <= 1'b0;
                down_gate_valid_q <= 1'b0;
                attention_read_valid_q <= 1'b0;
                attention_store_lane_q <= 6'd0;
                rms_read_valid_q <= 1'b0;
                hidden_read_valid_q <= 1'b0;
                silu_value_valid_q <= 1'b0;
                attention_query_load_lane_q <= 6'd0;
                attention_query_read_valid_q <= 1'b0;
                attention_query_loaded_q <= 1'b0;
                kv_read_valid_q <= 1'b0;
            end else if (fault_q) begin
                engine_state_q <= E_FAULT;
            end else begin
                case (engine_state_q)
                    E_IDLE: begin
                        if (head_start_accept) begin
                            head_activation_exponent_q <=
                                private_head_activation_exponent_i;
                            service_start_seen_q <= 1'b0;
                            input_done_q <= 1'b0;
                            input_index_q <= 10'd0;
                            head_result_index_q <= 13'd0;
                            head_last_seen_q <= 1'b0;
                            engine_state_q <= E_HEAD;
                        end else if (stage_accept) begin
                            if ((private_stage_i != expected_stage_q) ||
                                (private_layer_i != expected_layer_q) ||
                                ((transaction_seen_q) &&
                                 (private_position_i !=
                                  transaction_position_q))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                current_stage_q <= private_stage_i;
                                current_layer_q <= private_layer_i;
                                current_position_q <= private_position_i;
                                if (!transaction_seen_q) begin
                                    transaction_seen_q <= 1'b1;
                                    transaction_position_q <=
                                        private_position_i;
                                    hidden_exponent_q <=
                                        private_initial_exponent_i;
                                end
                                service_start_seen_q <= 1'b0;
                                norm_start_seen_q <= 1'b0;
                                input_done_q <= 1'b0;
                                output_done_q <= 1'b0;
                                service_done_seen_q <= 1'b0;
                                norm_done_seen_q <= 1'b0;
                                input_index_q <= 10'd0;
                                output_index_q <= 10'd0;
                                down_gate_valid_q <= 1'b0;
                                attention_read_valid_q <= 1'b0;
                                attention_store_lane_q <= 6'd0;
                                rms_read_valid_q <= 1'b0;
                                hidden_read_valid_q <= 1'b0;
                                attention_query_load_lane_q <= 6'd0;
                                attention_query_read_valid_q <= 1'b0;
                                attention_query_loaded_q <= 1'b0;
                                kv_read_valid_q <= 1'b0;
                                if ((private_stage_i == STAGE_INPUT_RMS) ||
                                    (private_stage_i == STAGE_POST_RMS)) begin
                                    engine_state_q <= E_RMS;
                                end else if ((private_stage_i >= STAGE_Q) &&
                                             (private_stage_i <= STAGE_V)) begin
                                    engine_state_q <= E_PROJ;
                                end else if ((private_stage_i == STAGE_O) ||
                                             (private_stage_i == STAGE_GATE) ||
                                             (private_stage_i == STAGE_UP) ||
                                             (private_stage_i == STAGE_DOWN)) begin
                                    engine_state_q <= E_PROJ;
                                end else if ((private_stage_i ==
                                              STAGE_Q_ROPE) ||
                                             (private_stage_i ==
                                              STAGE_K_ROPE)) begin
                                    rope_phase_q <= RP_NORM_START;
                                    rope_head_q <= 2'd0;
                                    rope_half_q <= 5'd0;
                                    rope_second_index_q <= 5'd0;
                                    engine_state_q <= E_ROPE;
                                end else if (private_stage_i ==
                                             STAGE_KV_STAGE) begin
                                    engine_state_q <= E_KV;
                                end else if (private_stage_i ==
                                             STAGE_ATTENTION) begin
                                    attention_head_q <= 3'd0;
                                    attention_result_head_q <= 3'd0;
                                    attention_query_load_lane_q <= 6'd0;
                                    attention_query_read_valid_q <= 1'b0;
                                    attention_query_loaded_q <= 1'b0;
                                    engine_state_q <= E_ATTN;
                                end else if ((private_stage_i ==
                                              STAGE_RESIDUAL_1) ||
                                             (private_stage_i ==
                                              STAGE_SILU_MUL) ||
                                             (private_stage_i ==
                                              STAGE_RESIDUAL_2)) begin
                                    elem_phase_q <= EL_NORM_START;
                                    elem_index_q <= 10'd0;
                                    silu_value_valid_q <= 1'b0;
                                    engine_state_q <= E_ELEM;
                                end else if (private_stage_i ==
                                             STAGE_KV_COMMIT) begin
                                    engine_state_q <= E_COMMIT;
                                end else begin
                                    fault_q <= 1'b1;
                                    engine_state_q <= E_FAULT;
                                end
                            end
                        end
                    end

                    E_RMS: begin
                        if (rms_start_valid && rms_start_ready)
                            service_start_seen_q <= 1'b1;
                        if (hidden_ram_read_enable)
                            hidden_read_valid_q <= 1'b1;
                        if (rms_input_fire) begin
                            hidden_read_valid_q <= 1'b0;
                            if (input_index_q == 10'd255)
                                input_done_q <= 1'b1;
                            else
                                input_index_q <= input_index_q + 1'b1;
                        end
                        if (rms_result_fire) begin
                            if ((rms_result_index != output_index_q[7:0]) ||
                                (rms_result_last !=
                                 (output_index_q == 10'd255))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                rms_exponent_q <= rms_result_exponent;
                                if (output_index_q == 10'd255)
                                    output_done_q <= 1'b1;
                                else
                                    output_index_q <= output_index_q + 1'b1;
                            end
                        end
                        if (rms_done_valid && rms_done_ready)
                            service_done_seen_q <= 1'b1;
                        if ((output_done_q ||
                             (rms_result_fire && rms_result_last)) &&
                            (service_done_seen_q ||
                             (rms_done_valid && rms_done_ready))) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_PROJ: begin
                        if (projection_start_valid && projection_start_ready)
                            service_start_seen_q <= 1'b1;
                        if (norm_start_valid && norm_start_ready)
                            norm_start_seen_q <= 1'b1;
                        if (projection_activation_fire) begin
                            if (current_stage_q == STAGE_DOWN)
                                down_gate_valid_q <= 1'b0;
                            if (current_stage_q == STAGE_O)
                                attention_read_valid_q <= 1'b0;
                            if (projection_uses_rms)
                                rms_read_valid_q <= 1'b0;
                            if (input_index_q ==
                                projection_activation_count - 1'b1)
                                input_done_q <= 1'b1;
                            else
                                input_index_q <= input_index_q + 1'b1;
                        end
                        if (projection_done_valid && projection_done_ready)
                            service_done_seen_q <= 1'b1;
                        if (norm_done_valid && norm_done_ready)
                            norm_done_seen_q <= 1'b1;
                        if (norm_result_fire) begin
                            if ((norm_result_index != output_index_q) ||
                                (norm_result_last !=
                                 (output_index_q ==
                                  projection_result_count - 1'b1))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                case (current_stage_q)
                                    STAGE_Q: begin
                                        query_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    STAGE_K: begin
                                        key_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    STAGE_V: begin
                                        value_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    STAGE_O, STAGE_DOWN: begin
                                        output_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    STAGE_GATE: begin
                                        gate_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    STAGE_UP: begin
                                        up_exponent_q <=
                                            norm_result_exponent;
                                    end
                                    default: begin
                                        fault_q <= 1'b1;
                                        engine_state_q <= E_FAULT;
                                    end
                                endcase
                                if (norm_result_last)
                                    output_done_q <= 1'b1;
                                else
                                    output_index_q <= output_index_q + 1'b1;
                            end
                        end
                        if ((output_done_q ||
                             (norm_result_fire && norm_result_last)) &&
                            (service_done_seen_q ||
                             (projection_done_valid &&
                              projection_done_ready)) &&
                            (norm_done_seen_q ||
                             (norm_done_valid && norm_done_ready))) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                        if ((current_stage_q == STAGE_DOWN) &&
                            scratch_read_enable)
                            down_gate_valid_q <= 1'b1;
                        if ((current_stage_q == STAGE_O) &&
                            attention_ram_read_enable)
                            attention_read_valid_q <= 1'b1;
                        if (projection_uses_rms && rms_ram_read_enable)
                            rms_read_valid_q <= 1'b1;
                    end

                    E_HEAD: begin
                        if (projection_start_valid && projection_start_ready)
                            service_start_seen_q <= 1'b1;
                        if (head_activation_fire) begin
                            if (input_index_q == 10'd255)
                                input_done_q <= 1'b1;
                            else
                                input_index_q <= input_index_q + 1'b1;
                        end
                        if (head_result_fire) begin
                            if (projection_result_last)
                                head_last_seen_q <= 1'b1;
                            else
                                head_result_index_q <=
                                    head_result_index_q + 1'b1;
                        end
                        if (head_done_fire) begin
                            service_start_seen_q <= 1'b0;
                            input_done_q <= 1'b0;
                            input_index_q <= 10'd0;
                            head_result_index_q <= 13'd0;
                            head_last_seen_q <= 1'b0;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_ROPE: begin
                        if (norm_start_valid && norm_start_ready) begin
                            norm_start_seen_q <= 1'b1;
                            rope_phase_q <= RP_COS_REQ;
                        end
                        if (lookup_request_valid && lookup_request_ready)
                            rope_phase_q <= (rope_phase_q == RP_COS_REQ) ?
                                RP_COS_WAIT : RP_SIN_WAIT;
                        if (lookup_response_valid && lookup_response_ready) begin
                            if (lookup_response_fault) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else if (rope_phase_q == RP_COS_WAIT) begin
                                rope_cosine_q <= lookup_response_value;
                                rope_phase_q <= RP_SIN_REQ;
                            end else if (rope_phase_q == RP_SIN_WAIT) begin
                                rope_sine_q <= lookup_response_value;
                                rope_phase_q <= RP_OPERAND0_REQ;
                            end else begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end
                        end
                        if (rope_phase_q == RP_OPERAND0_REQ)
                            rope_phase_q <= RP_OPERAND0_WAIT;
                        if (rope_phase_q == RP_OPERAND0_WAIT) begin
                            rope_operand0_q <=
                                (current_stage_q == STAGE_Q_ROPE) ?
                                query_ram_read_data : key_ram_read_data;
                            rope_phase_q <= RP_OPERAND1_REQ;
                        end
                        if (rope_phase_q == RP_OPERAND1_REQ)
                            rope_phase_q <= RP_OPERAND1_WAIT;
                        if (rope_phase_q == RP_OPERAND1_WAIT) begin
                            rope_operand1_q <=
                                (current_stage_q == STAGE_Q_ROPE) ?
                                query_ram_read_data : key_ram_read_data;
                            rope_phase_q <= RP_LANE_REQ;
                        end
                        if (lane_request_valid && lane_request_ready)
                            rope_phase_q <= RP_LANE_WAIT;
                        if ((rope_phase_q == RP_LANE_WAIT) &&
                            lane_result_fire) begin
                            if (rope_half_q == 5'd31) begin
                                rope_second_index_q <= 5'd0;
                                rope_phase_q <= RP_SECOND_REQ;
                            end else begin
                                rope_half_q <= rope_half_q + 1'b1;
                                rope_phase_q <= RP_COS_REQ;
                            end
                        end
                        if (rope_phase_q == RP_SECOND_REQ)
                            rope_phase_q <= RP_SECOND;
                        if ((rope_phase_q == RP_SECOND) && norm_input_fire) begin
                            if (rope_second_index_q == 5'd31) begin
                                rope_half_q <= 5'd0;
                                if (((current_stage_q == STAGE_Q_ROPE) &&
                                     (rope_head_q == 2'd3)) ||
                                    ((current_stage_q == STAGE_K_ROPE) &&
                                     (rope_head_q == 2'd1))) begin
                                    input_done_q <= 1'b1;
                                    rope_phase_q <= RP_NORM_WAIT;
                                end else begin
                                    rope_head_q <= rope_head_q + 1'b1;
                                    rope_phase_q <= RP_COS_REQ;
                                end
                            end else begin
                                rope_second_index_q <=
                                    rope_second_index_q + 1'b1;
                                rope_phase_q <= RP_SECOND_REQ;
                            end
                        end
                        if (norm_result_fire) begin
                            if ((norm_result_index != output_index_q) ||
                                (norm_result_last !=
                                 ((current_stage_q == STAGE_Q_ROPE) ?
                                  (output_index_q == 10'd255) :
                                  (output_index_q == 10'd127)))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                if (current_stage_q == STAGE_Q_ROPE) begin
                                    query_exponent_q <=
                                        norm_result_exponent;
                                end else begin
                                    key_exponent_q <= norm_result_exponent;
                                end
                                if (norm_result_last)
                                    output_done_q <= 1'b1;
                                else
                                    output_index_q <= output_index_q + 1'b1;
                            end
                        end
                        if (norm_done_valid && norm_done_ready)
                            norm_done_seen_q <= 1'b1;
                        if ((output_done_q ||
                             (norm_result_fire && norm_result_last)) &&
                            (norm_done_seen_q ||
                             (norm_done_valid && norm_done_ready))) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_KV: begin
                        if (kv_stage_begin_valid && kv_stage_begin_ready)
                            service_start_seen_q <= 1'b1;
                        if (key_ram_read_enable && value_ram_read_enable)
                            kv_read_valid_q <= 1'b1;
                        if (kv_stage_payload_valid &&
                            kv_stage_payload_ready) begin
                            kv_read_valid_q <= 1'b0;
                            if (input_index_q == 10'd127)
                                input_done_q <= 1'b1;
                            else
                                input_index_q <= input_index_q + 1'b1;
                        end
                        if ((input_done_q ||
                             (kv_stage_payload_valid &&
                              kv_stage_payload_ready &&
                              (input_index_q == 10'd127))) &&
                            kv_pending_complete) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_ATTN: begin
                        if (attention_start_valid && attention_start_ready)
                            service_start_seen_q <= 1'b1;
                        if (query_ram_read_enable)
                            attention_query_read_valid_q <= 1'b1;
                        if (attention_query_read_valid_q) begin
                            attention_query_read_valid_q <= 1'b0;
                            if (attention_query_load_lane_q == 6'd63)
                                attention_query_loaded_q <= 1'b1;
                            else
                                attention_query_load_lane_q <=
                                    attention_query_load_lane_q + 1'b1;
                        end
                        if (attention_query_fire) begin
                            attention_query_load_lane_q <= 6'd0;
                            attention_query_loaded_q <= 1'b0;
                            if (attention_head_q == 3'd3)
                                input_done_q <= 1'b1;
                            else
                                attention_head_q <= attention_head_q + 1'b1;
                        end
                        if (attention_result_valid) begin
                            if (!attention_result_descriptor_ok) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else if (attention_store_lane_q != 6'd63) begin
                                attention_store_lane_q <=
                                    attention_store_lane_q + 1'b1;
                            end else begin
                                attention_store_lane_q <= 6'd0;
                                attention_exponent_q <=
                                    attention_result_exponent;
                                if (attention_result_head_q == 3'd3)
                                    output_done_q <= 1'b1;
                                else
                                    attention_result_head_q <=
                                        attention_result_head_q + 1'b1;
                            end
                        end
                        if (attention_done_valid && attention_done_ready)
                            service_done_seen_q <= 1'b1;
                        if ((output_done_q ||
                             (attention_result_fire &&
                              attention_result_last)) &&
                            (service_done_seen_q ||
                             (attention_done_valid &&
                              attention_done_ready))) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_ELEM: begin
                        if (norm_start_valid && norm_start_ready) begin
                            norm_start_seen_q <= 1'b1;
                            elem_phase_q <=
                                EL_RAM_REQ;
                        end
                        if (elem_phase_q == EL_RAM_REQ)
                            elem_phase_q <=
                                (current_stage_q == STAGE_SILU_MUL) ?
                                EL_LOOK_REQ : EL_LANE_REQ;
                        if (lookup_request_valid && lookup_request_ready)
                            elem_phase_q <= EL_LOOK_WAIT;
                        if (lookup_response_valid && lookup_response_ready) begin
                            if (lookup_response_fault) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                silu_value_q <= lookup_response_value;
                                silu_value_valid_q <= 1'b1;
                                elem_phase_q <= EL_LANE_REQ;
                            end
                        end
                        if (lane_request_valid && lane_request_ready) begin
                            elem_phase_q <= EL_LANE_WAIT;
                        end
                        if (lane_lut_request) begin
                            if (!silu_value_valid_q &&
                                (current_stage_q == STAGE_SILU_MUL)) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else if ((current_stage_q == STAGE_SILU_MUL) &&
                                         (lane_lut_index != silu_index_for(
                                             gate_read_data,
                                             gate_exponent_q))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                lane_lut_response_q <= 1'b1;
                                silu_value_valid_q <= 1'b0;
                            end
                        end
                        if ((elem_phase_q == EL_LANE_WAIT) &&
                            lane_result_fire) begin
                            if (((current_stage_q == STAGE_SILU_MUL) &&
                                 (elem_index_q == 10'd681)) ||
                                ((current_stage_q != STAGE_SILU_MUL) &&
                                 (elem_index_q == 10'd255))) begin
                                input_done_q <= 1'b1;
                                elem_phase_q <= EL_NORM_WAIT;
                            end else begin
                                elem_index_q <= elem_index_q + 1'b1;
                                elem_phase_q <= EL_RAM_REQ;
                            end
                        end
                        if (norm_result_fire) begin
                            if ((norm_result_index != output_index_q) ||
                                (norm_result_last !=
                                 ((current_stage_q == STAGE_SILU_MUL) ?
                                  (output_index_q == 10'd681) :
                                  (output_index_q == 10'd255)))) begin
                                fault_q <= 1'b1;
                                engine_state_q <= E_FAULT;
                            end else begin
                                if (current_stage_q == STAGE_SILU_MUL) begin
                                    gate_exponent_q <=
                                        norm_result_exponent;
                                end else begin
                                    hidden_exponent_q <=
                                        norm_result_exponent;
                                end
                                if (norm_result_last)
                                    output_done_q <= 1'b1;
                                else
                                    output_index_q <= output_index_q + 1'b1;
                            end
                        end
                        if (norm_done_valid && norm_done_ready)
                            norm_done_seen_q <= 1'b1;
                        if ((output_done_q ||
                             (norm_result_fire && norm_result_last)) &&
                            (norm_done_seen_q ||
                             (norm_done_valid && norm_done_ready))) begin
                            expected_stage_q <= expected_stage_q + 1'b1;
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                        end
                    end

                    E_COMMIT: begin
                        if (kv_commit_valid && kv_commit_ready) begin
                            stage_done_q <= 1'b1;
                            engine_state_q <= E_IDLE;
                            if (current_layer_q == 3'd5) begin
                                expected_layer_q <= 3'd0;
                                expected_stage_q <= STAGE_INPUT_RMS;
                                transaction_seen_q <= 1'b0;
                            end else begin
                                expected_layer_q <= current_layer_q + 1'b1;
                                expected_stage_q <= STAGE_INPUT_RMS;
                            end
                        end
                    end

                    default: begin
                        fault_q <= 1'b1;
                        engine_state_q <= E_FAULT;
                    end
                endcase
            end
        end
    end

    assign fault_o = fault_q;
    assign engine_o = engine_state_q;
    assign private_state_o = {attention_exponent_q,attention_head_q,attention_query_load_lane_q,attention_query_loaded_q,attention_query_read_valid_q,attention_read_valid_q,attention_result_head_q,attention_store_lane_q,current_layer_q,current_position_q,current_stage_q,down_gate_valid_q,elem_index_q,elem_phase_q,expected_layer_q,expected_stage_q,gate_exponent_q,head_activation_exponent_q,head_last_seen_q,head_result_index_q,hidden_exponent_q,hidden_read_valid_q,input_done_q,input_index_q,key_exponent_q,kv_read_valid_q,lane_lut_response_q,lock_seen_q,norm_done_seen_q,norm_start_seen_q,output_done_q,output_exponent_q,output_index_q,query_exponent_q,rms_exponent_q,rms_read_valid_q,rope_cosine_q,rope_half_q,rope_head_q,rope_operand0_q,rope_operand1_q,rope_phase_q,rope_second_index_q,rope_sine_q,service_done_seen_q,service_start_seen_q,silu_value_q,silu_value_valid_q,stage_done_q,transaction_position_q,transaction_seen_q,up_exponent_q,value_exponent_q};
endmodule
