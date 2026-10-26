`timescale 1ns/1ps
`default_nettype none

// Production-shaped private datapath for one immutable six-layer schedule.
// The surrounding sequence controller is the only permitted caller.  All
// child descriptors below are derived from its authenticated fixed stage.
module board1_context2048_semantic_datapath #(
    parameter integer ADDR_W = 25
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    // Integration-private tied-head service.  There is deliberately no
    // layer, job, row-count, address, or arithmetic-mode input: this service
    // can invoke only the immutable layer-7/job-7 projection after the fixed
    // six-layer sequencer has relinquished the shared datapath.
    input  wire                    private_head_start_valid_i,
    output logic                   private_head_start_ready_o,
    input  wire signed [7:0]       private_head_activation_exponent_i,
    input  wire                    private_head_activation_valid_i,
    output logic                   private_head_activation_ready_o,
    input  wire [7:0]              private_head_activation_index_i,
    input  wire signed [15:0]      private_head_activation_mantissa_i,
    input  wire                    private_head_activation_last_i,
    output logic                   private_head_result_valid_o,
    input  wire                    private_head_result_ready_i,
    output logic [12:0]            private_head_result_row_index_o,
    output logic signed [49:0]     private_head_result_scaled_raw_o,
    output logic signed [7:0]      private_head_result_source_exponent_o,
    output logic                   private_head_result_last_o,
    output logic                   private_head_done_valid_o,
    input  wire                    private_head_done_ready_i,

    input  wire                    private_ingress_write_i,
    input  wire [7:0]              private_ingress_index_i,
    input  wire signed [15:0]      private_ingress_mantissa_i,

    input  wire                    private_stage_valid_i,
    output logic                   private_stage_ready_o,
    input  wire [4:0]              private_stage_i,
    input  wire [2:0]              private_layer_i,
    input  wire [10:0]             private_position_i,
    input  wire signed [7:0]       private_initial_exponent_i,
    output logic                   private_stage_done_o,
    output logic                   private_stage_fault_o,

    input  wire [7:0]              private_result_index_i,
    output logic signed [15:0]     private_result_mantissa_o,
    output logic signed [7:0]      private_result_exponent_o,

    output logic                   private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output logic [ADDR_W-1:0]      private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output logic                   private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    // Typed mutable-K/V capabilities.  These terminate at the private
    // context-2,048 DDR boundary; no raw address or direction enters here.
    output logic                   kv_write_req_valid_o,
    input  wire                    kv_write_req_ready_i,
    output logic [2:0]             kv_write_req_layer_o,
    output logic [11:0]            kv_write_req_position_o,
    output logic [1:0]             kv_write_req_head_o,
    output logic [3:0]             kv_write_req_row_word_o,
    output logic [18:0]            kv_write_req_shadow_address_o,
    output logic [255:0]           kv_write_req_data_o,
    input  wire                    kv_write_cpl_valid_i,
    output logic                   kv_write_cpl_ready_o,
    input  wire                    kv_write_cpl_fault_i,
    output logic                   kv_read_req_valid_o,
    input  wire                    kv_read_req_ready_i,
    output logic [2:0]             kv_read_req_layer_o,
    output logic [11:0]            kv_read_req_position_o,
    output logic [1:0]             kv_read_req_head_o,
    output logic [3:0]             kv_read_req_row_word_o,
    output logic [18:0]            kv_read_req_shadow_address_o,
    input  wire                    kv_read_rsp_valid_i,
    output logic                   kv_read_rsp_ready_o,
    input  wire [255:0]            kv_read_rsp_data_i,
    input  wire                    kv_read_rsp_fault_i,
    input  wire                    kv_endpoint_fault_i,

    output logic [71:0]            committed_prefixes_o,
    output logic                   busy_o,
    output logic                   range_fault_o
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

    // These private arrays are never bulk-erased.  CLEAR invalidates only the
    // transaction/cache metadata.  They are intentionally not observable.
    logic scratch_read_enable;
    logic [9:0] scratch_read_address;
    logic signed [15:0] gate_read_data;
    logic signed [15:0] up_read_data;
    logic gate_write_enable;
    logic up_write_enable;
    logic down_gate_valid_q;

    logic attention_ram_read_enable;
    logic [7:0] attention_ram_read_address;
    logic signed [15:0] attention_ram_read_data;
    logic attention_ram_write_enable;
    logic [7:0] attention_ram_write_address;
    logic signed [15:0] attention_ram_write_data;
    logic attention_read_valid_q;
    logic [5:0] attention_store_lane_q;

    logic rms_ram_read_enable;
    logic [7:0] rms_ram_read_address;
    logic signed [15:0] rms_ram_read_data;
    logic rms_ram_write_enable;
    logic rms_read_valid_q;

    logic output_ram_read_enable;
    logic [7:0] output_ram_read_address;
    logic signed [15:0] output_ram_read_data;
    logic output_ram_write_enable;

    logic hidden_ram_read_enable;
    logic [7:0] hidden_ram_read_address;
    logic signed [15:0] hidden_ram_read_data;
    logic hidden_ram_write_enable;
    logic [7:0] hidden_ram_write_address;
    logic signed [15:0] hidden_ram_write_data;
    logic hidden_read_valid_q;

    logic query_ram_read_enable;
    logic [7:0] query_ram_read_address;
    logic signed [15:0] query_ram_read_data;
    logic query_ram_write_enable;
    logic key_ram_read_enable;
    logic [6:0] key_ram_read_address;
    logic signed [15:0] key_ram_read_data;
    logic key_ram_write_enable;
    logic value_ram_read_enable;
    logic [6:0] value_ram_read_address;
    logic signed [15:0] value_ram_read_data;
    logic value_ram_write_enable;
    logic rope_raw_ram_read_enable;
    logic signed [49:0] rope_raw_ram_read_data;
    logic rope_raw_ram_write_enable;

    engine_state_t engine_state_q;
    logic [4:0] current_stage_q;
    logic [2:0] current_layer_q;
    logic [10:0] current_position_q;
    logic [4:0] expected_stage_q;
    logic [2:0] expected_layer_q;
    logic [10:0] transaction_position_q;
    logic transaction_seen_q;
    logic fault_q;
    logic lock_seen_q;
    logic stage_done_q;

    logic signed [7:0] hidden_exponent_q;
    logic signed [7:0] rms_exponent_q;
    logic signed [7:0] query_exponent_q;
    logic signed [7:0] key_exponent_q;
    logic signed [7:0] value_exponent_q;
    logic signed [7:0] attention_exponent_q;
    logic signed [7:0] output_exponent_q;
    logic signed [7:0] gate_exponent_q;
    logic signed [7:0] up_exponent_q;

    logic service_start_seen_q;
    logic norm_start_seen_q;
    logic input_done_q;
    logic output_done_q;
    logic service_done_seen_q;
    logic norm_done_seen_q;
    logic [9:0] input_index_q;
    logic [9:0] output_index_q;
    logic signed [7:0] head_activation_exponent_q;
    logic [12:0] head_result_index_q;
    logic head_last_seen_q;

    logic [3:0] rope_phase_q;
    logic [1:0] rope_head_q;
    logic [4:0] rope_half_q;
    logic [4:0] rope_second_index_q;
    logic signed [15:0] rope_cosine_q;
    logic signed [15:0] rope_sine_q;
    logic signed [15:0] rope_operand0_q;
    logic signed [15:0] rope_operand1_q;

    logic [2:0] elem_phase_q;
    logic [9:0] elem_index_q;
    logic signed [15:0] silu_value_q;
    logic silu_value_valid_q;
    logic lane_lut_response_q;

    logic [2:0] attention_head_q;
    logic [2:0] attention_result_head_q;
    logic [5:0] attention_query_load_lane_q;
    logic attention_query_read_valid_q;
    logic attention_query_loaded_q;
    logic [1023:0] attention_query_vector_q;
    logic kv_read_valid_q;

    logic lookup_request_valid;
    logic lookup_request_ready;
    logic [1:0] lookup_kind;
    logic [15:0] lookup_index;
    logic lookup_response_valid;
    logic lookup_response_ready;
    logic signed [15:0] lookup_response_value;
    logic lookup_response_fault;
    logic lookup_word_req_valid;
    logic lookup_word_req_ready;
    logic [ADDR_W-1:0] lookup_word_req_index;
    logic lookup_word_rsp_valid;
    logic lookup_word_rsp_ready;
    logic lookup_busy;
    logic lookup_fault;

    logic rms_start_valid;
    logic rms_start_ready;
    logic rms_input_valid;
    logic rms_input_ready;
    logic rms_result_valid;
    logic rms_result_ready;
    logic [7:0] rms_result_index;
    logic signed [15:0] rms_result_mantissa;
    logic signed [7:0] rms_result_exponent;
    logic rms_result_last;
    logic rms_done_valid;
    logic rms_done_ready;
    logic rms_busy;
    logic rms_fault;

    logic projection_start_valid;
    logic projection_start_ready;
    logic projection_activation_valid;
    logic projection_activation_ready;
    logic signed [15:0] projection_activation;
    logic projection_activation_last;
    logic projection_word_req_valid;
    logic projection_word_req_ready;
    logic [ADDR_W-1:0] projection_word_req_index;
    logic projection_word_rsp_valid;
    logic projection_word_rsp_ready;
    logic projection_result_valid;
    logic projection_result_ready;
    logic [12:0] projection_result_index;
    logic signed [49:0] projection_result_raw;
    logic signed [7:0] projection_result_exponent;
    logic projection_result_last;
    logic projection_done_valid;
    logic projection_done_ready;
    logic projection_busy;
    logic projection_fault;

    logic norm_start_valid;
    logic norm_start_ready;
    logic [3:0] norm_job;
    logic norm_input_valid;
    logic norm_input_ready;
    logic [9:0] norm_input_index;
    logic signed [49:0] norm_input_raw;
    logic signed [7:0] norm_input_exponent;
    logic norm_input_last;
    logic norm_result_valid;
    logic norm_result_ready;
    logic [9:0] norm_result_index;
    logic signed [15:0] norm_result_mantissa;
    logic signed [7:0] norm_result_exponent;
    logic norm_result_last;
    logic norm_done_valid;
    logic norm_done_ready;
    logic norm_busy;
    logic norm_fault;

    logic lane_request_valid;
    logic lane_request_ready;
    logic [2:0] lane_operation;
    logic signed [15:0] lane_first;
    logic signed [15:0] lane_second;
    logic signed [7:0] lane_first_exponent;
    logic signed [7:0] lane_second_exponent;
    logic signed [7:0] lane_common_exponent;
    logic signed [7:0] lane_safety_exponent;
    logic lane_lut_request;
    logic [15:0] lane_lut_index;
    logic lane_result_valid;
    logic lane_result_ready;
    logic signed [15:0] lane_result0;
    logic signed [15:0] lane_result1;
    logic signed [15:0] lane_auxiliary;
    logic signed [49:0] lane_raw0;
    logic signed [49:0] lane_raw1;
    logic signed [7:0] lane_source_exponent;
    logic lane_fault;

    logic kv_stage_begin_valid;
    logic kv_stage_begin_ready;
    logic kv_stage_payload_valid;
    logic kv_stage_payload_ready;
    logic kv_pending_complete;
    wire [1:0] attention_cache_req_kind;
    logic kv_commit_valid;
    logic kv_commit_ready;
    logic attention_cache_req_valid;
    logic attention_cache_req_ready;
    logic [10:0] attention_cache_req_position;
    logic attention_cache_req_head;
    logic attention_cache_rsp_valid;
    logic attention_cache_rsp_ready;
    logic [1023:0] attention_cache_key;
    logic signed [7:0] attention_cache_key_exp;
    logic [1023:0] attention_cache_value;
    logic signed [7:0] attention_cache_value_exp;
    logic attention_cache_rsp_fault;
    logic attention_cache_rsp_from_pending;
    logic [71:0] kv_committed_prefixes;
    logic kv_busy;
    logic kv_fault;

    logic attention_start_valid;
    logic attention_start_ready;
    logic attention_query_valid;
    logic attention_query_ready;
    logic [1023:0] attention_query_vector;
    logic attention_query_last;
    logic attention_result_valid;
    logic attention_result_ready;
    logic [1023:0] attention_result_vector;
    logic signed [7:0] attention_result_exponent;
    logic attention_result_last;
    logic attention_done_valid;
    logic attention_done_ready;
    logic attention_busy;
    logic attention_fault;

    logic [1:0] ddr_owner_q;
    logic [3:0] ddr_pending_q;
    localparam logic [1:0] DDR_NONE = 2'd0;
    localparam logic [1:0] DDR_PROJ = 2'd1;
    localparam logic [1:0] DDR_LOOK = 2'd2;
    logic ddr_arbiter_fault_q;
`ifndef SYNTHESIS
    logic simulation_x_fault;
`endif

    function automatic [3:0] projection_job_for_stage(
        input logic [4:0] stage
    );
        case (stage)
            STAGE_Q:    projection_job_for_stage = 4'd0;
            STAGE_K:    projection_job_for_stage = 4'd1;
            STAGE_V:    projection_job_for_stage = 4'd2;
            STAGE_O:    projection_job_for_stage = 4'd3;
            STAGE_GATE: projection_job_for_stage = 4'd4;
            STAGE_UP:   projection_job_for_stage = 4'd5;
            STAGE_DOWN: projection_job_for_stage = 4'd6;
            default:    projection_job_for_stage = 4'd15;
        endcase
    endfunction

    function automatic [9:0] activation_count_for_job(input logic [3:0] job);
        activation_count_for_job = (job == 4'd6) ? 10'd682 : 10'd256;
    endfunction

    function automatic [9:0] result_count_for_job(input logic [3:0] job);
        case (job)
            4'd0, 4'd3, 4'd6: result_count_for_job = 10'd256;
            4'd1, 4'd2:       result_count_for_job = 10'd128;
            4'd4, 4'd5:       result_count_for_job = 10'd682;
            default:          result_count_for_job = 10'd0;
        endcase
    endfunction

    function automatic signed [7:0] maximum_exponent(
        input signed [7:0] first,
        input signed [7:0] second
    );
        maximum_exponent = (first > second) ? first : second;
    endfunction

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

`ifndef SYNTHESIS
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
`endif
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

    wire projection_is_head = engine_state_q == E_HEAD;
    wire [3:0] semantic_projection_job =
        projection_job_for_stage(current_stage_q);
    wire [3:0] projection_job = projection_is_head ? 4'd7 :
                                                      semantic_projection_job;
    wire [2:0] projection_layer = projection_is_head ? 3'd7 :
                                                        current_layer_q;
    wire [9:0] projection_activation_count =
        activation_count_for_job(semantic_projection_job);
    wire [9:0] projection_result_count =
        result_count_for_job(semantic_projection_job);
    wire stage_accept = private_stage_valid_i && private_stage_ready_o;
    wire head_start_accept = private_head_start_valid_i &&
                             private_head_start_ready_o;
    wire rms_input_fire = rms_input_valid && rms_input_ready;
    wire rms_result_fire = rms_result_valid && rms_result_ready;
    wire projection_activation_fire = projection_activation_valid &&
        projection_activation_ready;
    wire head_activation_fire = private_head_activation_valid_i &&
                                private_head_activation_ready_o;
    wire head_result_fire = private_head_result_valid_o &&
                            private_head_result_ready_i;
    wire head_done_fire = private_head_done_valid_o &&
                          private_head_done_ready_i;
    wire norm_result_fire = norm_result_valid && norm_result_ready;
    wire norm_input_fire = norm_input_valid && norm_input_ready;
    wire lane_result_fire = lane_result_valid && lane_result_ready;
    wire attention_query_fire = attention_query_valid &&
        attention_query_ready;
    wire attention_result_fire = attention_result_valid &&
                                 attention_result_ready;
    wire attention_result_descriptor_ok = attention_result_last ==
        (attention_result_head_q == 3'd3);
    wire projection_uses_rms = (current_stage_q == STAGE_Q) ||
        (current_stage_q == STAGE_K) || (current_stage_q == STAGE_V) ||
        (current_stage_q == STAGE_GATE) || (current_stage_q == STAGE_UP);
    wire rms_result_order_ok =
        (rms_result_index == output_index_q[7:0]) &&
        (rms_result_last == (output_index_q == 10'd255));

    wire projection_norm_result_order_ok =
        (norm_result_index == output_index_q) &&
        (norm_result_last ==
         (output_index_q == projection_result_count - 1'b1));
    wire element_norm_result_order_ok =
        (norm_result_index == output_index_q) &&
        (norm_result_last ==
         ((current_stage_q == STAGE_SILU_MUL) ?
          (output_index_q == 10'd681) : (output_index_q == 10'd255)));

    wire head_activation_descriptor_ok =
        (private_head_activation_index_i == input_index_q[7:0]) &&
        (private_head_activation_last_i == (input_index_q == 10'd255)) &&
        (private_head_activation_mantissa_i != -16'sd32768);
    wire head_result_descriptor_ok =
        (projection_result_index == head_result_index_q) &&
        (projection_result_last == (head_result_index_q == 13'd4018));
    wire head_start_collision = private_head_start_valid_i &&
                                private_stage_valid_i &&
                                (engine_state_q == E_IDLE) && !stage_done_q &&
                                !clear_i;
    wire head_activation_protocol_fault = !clear_i &&
        ((private_head_activation_valid_i &&
         (engine_state_q != E_HEAD)) ||
        (head_activation_fire && !head_activation_descriptor_ok) ||
        (private_head_activation_valid_i && (engine_state_q == E_HEAD) &&
         input_done_q));
    wire head_result_protocol_fault = !clear_i && projection_result_valid &&
        (engine_state_q == E_HEAD) && !head_result_descriptor_ok;
    wire head_done_protocol_fault = !clear_i && projection_done_valid &&
        (engine_state_q == E_HEAD) && !head_last_seen_q &&
        !(head_result_fire && projection_result_last);
    wire head_overlap_protocol_fault = !clear_i &&
        (((engine_state_q != E_IDLE) && private_head_start_valid_i) ||
         ((engine_state_q == E_HEAD) &&
          (private_stage_valid_i || private_ingress_write_i)));

    // Declare the aggregate before any fail-closed write gate consumes it;
    // this ordering is required by strict Icarus elaboration as well as being
    // clearer than relying on SystemVerilog's later-declaration allowance.
    wire child_fault = rms_fault || projection_fault || norm_fault ||
        lane_fault || attention_fault || kv_fault || lookup_fault ||
        ddr_arbiter_fault_q || head_start_collision ||
        head_activation_protocol_fault || head_result_protocol_fault ||
        head_done_protocol_fault || head_overlap_protocol_fault ||
        (projection_result_valid && (engine_state_q == E_PROJ) &&
         (projection_result_index[12:10] != 3'd0));

    assign gate_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (((engine_state_q == E_PROJ) &&
          (current_stage_q == STAGE_GATE) &&
          projection_norm_result_order_ok) ||
         ((engine_state_q == E_ELEM) &&
          (current_stage_q == STAGE_SILU_MUL) &&
          element_norm_result_order_ok));
    assign up_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (engine_state_q == E_PROJ) && (current_stage_q == STAGE_UP) &&
        projection_norm_result_order_ok;
    assign attention_ram_write_enable = !fault_q && !clear_i &&
        model_lock_i && !upstream_fault_i && !child_fault &&
        (engine_state_q == E_ATTN) && attention_result_valid &&
        attention_result_descriptor_ok;
    assign attention_ram_write_address =
        {attention_result_head_q[1:0], attention_store_lane_q};
    assign attention_ram_write_data = attention_result_vector[
        attention_store_lane_q*16 +: 16];
    assign rms_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && (engine_state_q == E_RMS) &&
        rms_result_fire && rms_result_order_ok;
    assign output_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (engine_state_q == E_PROJ) &&
        ((current_stage_q == STAGE_O) ||
         (current_stage_q == STAGE_DOWN)) &&
        projection_norm_result_order_ok;
    assign hidden_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault &&
        (private_ingress_write_i ||
         (norm_result_fire && (engine_state_q == E_ELEM) &&
          (current_stage_q != STAGE_SILU_MUL) &&
          element_norm_result_order_ok));
    assign hidden_ram_write_address = private_ingress_write_i ?
        private_ingress_index_i : output_index_q[7:0];
    assign hidden_ram_write_data = private_ingress_write_i ?
        private_ingress_mantissa_i : norm_result_mantissa;
    assign query_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (((engine_state_q == E_PROJ) && (current_stage_q == STAGE_Q) &&
          projection_norm_result_order_ok) ||
         ((engine_state_q == E_ROPE) &&
          (current_stage_q == STAGE_Q_ROPE) &&
          (norm_result_index == output_index_q) &&
          (norm_result_last == (output_index_q == 10'd255))));
    assign key_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (((engine_state_q == E_PROJ) && (current_stage_q == STAGE_K) &&
          projection_norm_result_order_ok) ||
         ((engine_state_q == E_ROPE) &&
          (current_stage_q == STAGE_K_ROPE) &&
          (norm_result_index == output_index_q) &&
          (norm_result_last == (output_index_q == 10'd127))));
    assign value_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault && norm_result_fire &&
        (engine_state_q == E_PROJ) && (current_stage_q == STAGE_V) &&
        projection_norm_result_order_ok;
    assign rope_raw_ram_write_enable = !fault_q && !clear_i && model_lock_i &&
        !upstream_fault_i && !child_fault &&
        (engine_state_q == E_ROPE) && (rope_phase_q == RP_LANE_WAIT) &&
        lane_result_fire;

`ifndef SYNTHESIS
    // The production boundary is two-state hardware, but four-state RTL
    // verification must never let an unknown private descriptor or DDR beat
    // select arbitrary arithmetic or memory.  Any such condition fails shut.
    always @* begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_lock_i) || $isunknown(upstream_fault_i) ||
            $isunknown(private_head_start_valid_i) ||
            $isunknown(private_head_activation_valid_i) ||
            $isunknown(private_head_result_ready_i) ||
            $isunknown(private_head_done_ready_i) ||
            $isunknown(private_ingress_write_i) ||
            $isunknown(private_stage_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i) ||
            $isunknown(kv_write_req_ready_i) ||
            $isunknown(kv_write_cpl_valid_i) ||
            $isunknown(kv_write_cpl_fault_i) ||
            $isunknown(kv_read_req_ready_i) ||
            $isunknown(kv_read_rsp_valid_i) ||
            $isunknown(kv_read_rsp_fault_i) ||
            $isunknown(kv_endpoint_fault_i) ||
            $isunknown(private_result_index_i);
        if (private_head_start_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_head_activation_exponent_i);
        if (private_head_activation_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_head_activation_index_i) ||
                $isunknown(private_head_activation_mantissa_i) ||
                $isunknown(private_head_activation_last_i);
        if (private_ingress_write_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_ingress_index_i) ||
                $isunknown(private_ingress_mantissa_i);
        if (private_stage_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_stage_i) ||
                $isunknown(private_layer_i) ||
                $isunknown(private_position_i) ||
                $isunknown(private_initial_exponent_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_word_rsp_data_i);
        if (kv_read_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(kv_read_rsp_data_i);
    end
`endif

    always @* begin
        private_stage_ready_o = rst_n && !clear_i && model_lock_i &&
            !fault_q && !child_fault && (engine_state_q == E_IDLE) &&
            !stage_done_q && !private_head_start_valid_i;
        private_stage_done_o = stage_done_q && !fault_q;
        private_stage_fault_o = fault_q;
        private_head_start_ready_o = rst_n && !clear_i && model_lock_i &&
            !fault_q && !child_fault && (engine_state_q == E_IDLE) &&
            !stage_done_q && !private_stage_valid_i &&
            (ddr_owner_q == DDR_NONE) && !projection_busy && !lookup_busy;
        private_head_activation_ready_o = 1'b0;
        private_head_result_valid_o = 1'b0;
        private_head_result_row_index_o = 13'd0;
        private_head_result_scaled_raw_o = 50'sd0;
        private_head_result_source_exponent_o = 8'sd0;
        private_head_result_last_o = 1'b0;
        private_head_done_valid_o = 1'b0;
        private_result_mantissa_o = hidden_ram_read_data;
        private_result_exponent_o = hidden_exponent_q;
        committed_prefixes_o = kv_committed_prefixes;
        busy_o = (engine_state_q != E_IDLE) || stage_done_q ||
            rms_busy || projection_busy || norm_busy || attention_busy ||
            lookup_busy || kv_busy || (ddr_owner_q != DDR_NONE);
        range_fault_o = fault_q;

        rms_start_valid = 1'b0;
        rms_input_valid = 1'b0;
        rms_result_ready = 1'b0;
        rms_done_ready = 1'b0;

        projection_start_valid = 1'b0;
        projection_activation_valid = 1'b0;
        projection_activation = 16'sd0;
        projection_activation_last = 1'b0;
        projection_result_ready = 1'b0;
        projection_done_ready = 1'b0;

        norm_start_valid = 1'b0;
        norm_job = 4'd0;
        norm_input_valid = 1'b0;
        norm_input_index = 10'd0;
        norm_input_raw = 50'sd0;
        norm_input_exponent = 8'sd0;
        norm_input_last = 1'b0;
        norm_result_ready = 1'b0;
        norm_done_ready = 1'b0;

        lane_request_valid = 1'b0;
        lane_operation = 3'd0;
        lane_first = 16'sd0;
        lane_second = 16'sd0;
        lane_first_exponent = 8'sd0;
        lane_second_exponent = 8'sd0;
        lane_common_exponent = 8'sd0;
        lane_safety_exponent = 8'sd31;
        lane_result_ready = 1'b0;

        lookup_request_valid = 1'b0;
        lookup_kind = 2'd0;
        lookup_index = 16'd0;
        lookup_response_ready = 1'b0;

        kv_stage_begin_valid = 1'b0;
        kv_stage_payload_valid = 1'b0;
        kv_commit_valid = 1'b0;

        attention_start_valid = 1'b0;
        attention_query_valid = 1'b0;
        attention_query_vector = 1024'd0;
        attention_query_last = 1'b0;
        attention_result_ready = 1'b0;
        attention_done_ready = 1'b0;

        scratch_read_enable = 1'b0;
        scratch_read_address = 10'd0;
        attention_ram_read_enable = 1'b0;
        attention_ram_read_address = 8'd0;
        rms_ram_read_enable = 1'b0;
        rms_ram_read_address = 8'd0;
        output_ram_read_enable = 1'b0;
        output_ram_read_address = 8'd0;
        hidden_ram_read_enable = 1'b0;
        hidden_ram_read_address = private_result_index_i;
        query_ram_read_enable = 1'b0;
        query_ram_read_address = 8'd0;
        key_ram_read_enable = 1'b0;
        key_ram_read_address = 7'd0;
        value_ram_read_enable = 1'b0;
        value_ram_read_address = 7'd0;
        rope_raw_ram_read_enable = 1'b0;

        if (!fault_q && !clear_i) begin
            case (engine_state_q)
                E_RMS: begin
                    rms_start_valid = !service_start_seen_q;
                    rms_input_valid = service_start_seen_q && !input_done_q &&
                        hidden_read_valid_q;
                    rms_result_ready = 1'b1;
                    rms_done_ready = 1'b1;
                    if (service_start_seen_q && !input_done_q &&
                        !hidden_read_valid_q) begin
                        hidden_ram_read_enable = 1'b1;
                        hidden_ram_read_address = input_index_q[7:0];
                    end
                end

                E_PROJ: begin
                    projection_start_valid = !service_start_seen_q;
                    norm_start_valid = !norm_start_seen_q;
                    norm_job = projection_job;
                    projection_activation_valid = service_start_seen_q &&
                        norm_start_seen_q && !input_done_q &&
                        ((current_stage_q != STAGE_DOWN) ||
                         down_gate_valid_q) &&
                        ((current_stage_q != STAGE_O) ||
                         attention_read_valid_q) &&
                        (!projection_uses_rms || rms_read_valid_q);
                    case (current_stage_q)
                        STAGE_Q, STAGE_K, STAGE_V:
                            projection_activation = rms_ram_read_data;
                        STAGE_O:
                            projection_activation = attention_ram_read_data;
                        STAGE_GATE, STAGE_UP:
                            projection_activation = rms_ram_read_data;
                        STAGE_DOWN:
                            projection_activation = gate_read_data;
                        default: projection_activation = 16'sd0;
                    endcase
                    projection_activation_last =
                        (input_index_q == projection_activation_count - 1'b1);
                    if ((current_stage_q == STAGE_DOWN) &&
                        service_start_seen_q && norm_start_seen_q &&
                        !input_done_q && !down_gate_valid_q) begin
                        scratch_read_enable = 1'b1;
                        scratch_read_address = input_index_q;
                    end
                    if ((current_stage_q == STAGE_O) &&
                        service_start_seen_q && norm_start_seen_q &&
                        !input_done_q && !attention_read_valid_q) begin
                        attention_ram_read_enable = 1'b1;
                        attention_ram_read_address = input_index_q[7:0];
                    end
                    if (projection_uses_rms && service_start_seen_q &&
                        norm_start_seen_q && !input_done_q &&
                        !rms_read_valid_q) begin
                        rms_ram_read_enable = 1'b1;
                        rms_ram_read_address = input_index_q[7:0];
                    end
                    projection_result_ready = norm_input_ready;
                    projection_done_ready = 1'b1;
                    norm_input_valid = projection_result_valid;
                    norm_input_index = projection_result_index[9:0];
                    norm_input_raw = projection_result_raw;
                    norm_input_exponent = projection_result_exponent;
                    norm_input_last = projection_result_last;
                    norm_result_ready = 1'b1;
                    norm_done_ready = 1'b1;
                end

                E_HEAD: begin
                    // The shared child sees only the fixed tied-head
                    // descriptor.  Unlike jobs 0..6, all 4,019 raw rows stream
                    // directly to the fixed exponent-aware argmax; job 7 must
                    // never enter the 10-bit vector normalizer path.
                    projection_start_valid = !service_start_seen_q;
                    private_head_activation_ready_o = service_start_seen_q &&
                        !input_done_q && projection_activation_ready;
                    projection_activation_valid = service_start_seen_q &&
                        !input_done_q && private_head_activation_valid_i &&
                        head_activation_descriptor_ok;
                    projection_activation = private_head_activation_mantissa_i;
                    projection_activation_last =
                        private_head_activation_last_i;

                    private_head_result_valid_o = projection_result_valid &&
                        head_result_descriptor_ok;
                    private_head_result_row_index_o =
                        private_head_result_valid_o ? projection_result_index :
                                                      13'd0;
                    private_head_result_scaled_raw_o =
                        private_head_result_valid_o ? projection_result_raw :
                                                      50'sd0;
                    private_head_result_source_exponent_o =
                        private_head_result_valid_o ?
                        projection_result_exponent : 8'sd0;
                    private_head_result_last_o = private_head_result_valid_o &&
                                                 projection_result_last;
                    projection_result_ready = private_head_result_ready_i &&
                                              head_result_descriptor_ok;

                    private_head_done_valid_o = projection_done_valid &&
                                                head_last_seen_q;
                    projection_done_ready = private_head_done_ready_i &&
                                            head_last_seen_q;
                end

                E_ROPE: begin
                    norm_job = (current_stage_q == STAGE_Q_ROPE) ? 4'd0 :
                                                                         4'd1;
                    norm_start_valid = !norm_start_seen_q;
                    norm_result_ready = 1'b1;
                    norm_done_ready = 1'b1;
                    lookup_index = {11'd0, rope_half_q};
                    if (rope_phase_q == RP_COS_REQ) begin
                        lookup_request_valid = 1'b1;
                        lookup_kind = 2'd0;
                    end else if (rope_phase_q == RP_COS_WAIT) begin
                        lookup_response_ready = 1'b1;
                    end else if (rope_phase_q == RP_SIN_REQ) begin
                        lookup_request_valid = 1'b1;
                        lookup_kind = 2'd1;
                    end else if (rope_phase_q == RP_SIN_WAIT) begin
                        lookup_response_ready = 1'b1;
                    end else if (rope_phase_q == RP_LANE_REQ) begin
                        lane_request_valid = 1'b1;
                    end else if (rope_phase_q == RP_LANE_WAIT) begin
                        norm_input_valid = lane_result_valid;
                        norm_input_index = {2'd0, rope_head_q, 6'd0} +
                            {5'd0, rope_half_q};
                        norm_input_raw = lane_raw0;
                        norm_input_exponent = lane_source_exponent;
                        norm_input_last = 1'b0;
                        lane_result_ready = norm_input_ready;
                    end else if (rope_phase_q == RP_SECOND) begin
                        norm_input_valid = 1'b1;
                        norm_input_index = {2'd0, rope_head_q, 6'd0} + 10'd32 +
                            {5'd0, rope_second_index_q};
                        norm_input_raw = rope_raw_ram_read_data;
                        norm_input_exponent =
                            (current_stage_q == STAGE_Q_ROPE) ?
                            query_exponent_q : key_exponent_q;
                        norm_input_last =
                            (rope_second_index_q == 5'd31) &&
                            (((current_stage_q == STAGE_Q_ROPE) &&
                              (rope_head_q == 2'd3)) ||
                             ((current_stage_q == STAGE_K_ROPE) &&
                              (rope_head_q == 2'd1)));
                    end
                    if ((rope_phase_q == RP_OPERAND0_REQ) ||
                        (rope_phase_q == RP_OPERAND1_REQ)) begin
                        if (current_stage_q == STAGE_Q_ROPE) begin
                            query_ram_read_enable = 1'b1;
                            query_ram_read_address = {rope_head_q, 6'd0} +
                                {3'd0, rope_half_q} +
                                ((rope_phase_q == RP_OPERAND1_REQ) ?
                                 8'd32 : 8'd0);
                        end else begin
                            key_ram_read_enable = 1'b1;
                            key_ram_read_address = {rope_head_q[0], 6'd0} +
                                {2'd0, rope_half_q} +
                                ((rope_phase_q == RP_OPERAND1_REQ) ?
                                 7'd32 : 7'd0);
                        end
                    end
                    if (rope_phase_q == RP_SECOND_REQ)
                        rope_raw_ram_read_enable = 1'b1;
                    lane_operation = 3'd0;
                    lane_first = rope_operand0_q;
                    lane_second = rope_operand1_q;
                    lane_first_exponent =
                        (current_stage_q == STAGE_Q_ROPE) ?
                        query_exponent_q : key_exponent_q;
                    lane_second_exponent = lane_first_exponent;
                    lane_common_exponent = lane_first_exponent;
                    lane_safety_exponent =
                        (lane_first_exponent < 8'sd31) ?
                        (lane_first_exponent + 1'b1) : 8'sd31;
                end

                E_KV: begin
                    if (!service_start_seen_q)
                        kv_stage_begin_valid = 1'b1;
                    else if (!input_done_q) begin
                        kv_stage_payload_valid = kv_read_valid_q;
                        if (!kv_read_valid_q) begin
                            key_ram_read_enable = 1'b1;
                            key_ram_read_address = input_index_q[6:0];
                            value_ram_read_enable = 1'b1;
                            value_ram_read_address = input_index_q[6:0];
                        end
                    end
                end

                E_ATTN: begin
                    attention_start_valid = !service_start_seen_q;
                    attention_query_valid = service_start_seen_q &&
                        !input_done_q && attention_query_loaded_q;
                    attention_query_vector = attention_query_vector_q;
                    attention_query_last = (attention_head_q == 3'd3);
                    if (service_start_seen_q && !input_done_q &&
                        !attention_query_loaded_q &&
                        !attention_query_read_valid_q) begin
                        query_ram_read_enable = 1'b1;
                        query_ram_read_address =
                            {attention_head_q[1:0], 6'd0} +
                            {2'd0, attention_query_load_lane_q};
                    end
                    // The child owns a held 1024-bit response.  Consume it
                    // only after all 64 coordinates have been privately
                    // serialized into the fixed synchronous vector RAM.
                    attention_result_ready =
                        (attention_store_lane_q == 6'd63);
                    attention_done_ready = 1'b1;
                end

                E_ELEM: begin
                    norm_job = (current_stage_q == STAGE_SILU_MUL) ? 4'd4 :
                                                                          4'd0;
                    norm_start_valid = !norm_start_seen_q;
                    norm_result_ready = 1'b1;
                    norm_done_ready = 1'b1;
                    if (elem_phase_q == EL_RAM_REQ) begin
                        if (current_stage_q == STAGE_SILU_MUL) begin
                            scratch_read_enable = 1'b1;
                            scratch_read_address = elem_index_q;
                        end else begin
                            output_ram_read_enable = 1'b1;
                            output_ram_read_address = elem_index_q[7:0];
                            hidden_ram_read_enable = 1'b1;
                            hidden_ram_read_address = elem_index_q[7:0];
                        end
                    end else if (elem_phase_q == EL_LOOK_REQ) begin
                        lookup_request_valid = 1'b1;
                        lookup_kind = 2'd2;
                        lookup_index = silu_index_for(
                            gate_read_data, gate_exponent_q);
                    end else if (elem_phase_q == EL_LOOK_WAIT) begin
                        lookup_response_ready = 1'b1;
                    end else if (elem_phase_q == EL_LANE_REQ) begin
                        lane_request_valid = 1'b1;
                    end else if (elem_phase_q == EL_LANE_WAIT) begin
                        norm_input_valid = lane_result_valid;
                        norm_input_index = elem_index_q;
                        norm_input_raw = lane_raw0;
                        norm_input_exponent = lane_source_exponent;
                        norm_input_last = (current_stage_q == STAGE_SILU_MUL)
                            ? (elem_index_q == 10'd681)
                            : (elem_index_q == 10'd255);
                        lane_result_ready = norm_input_ready;
                    end
                    if (current_stage_q == STAGE_SILU_MUL) begin
                        lane_operation = 3'd2;
                        lane_first = gate_read_data;
                        lane_second = up_read_data;
                        lane_first_exponent = gate_exponent_q;
                        lane_second_exponent = up_exponent_q;
                        lane_common_exponent = 8'sd0;
                    end else begin
                        lane_operation = 3'd3;
                        lane_first = hidden_ram_read_data;
                        lane_second = output_ram_read_data;
                        lane_first_exponent = hidden_exponent_q;
                        lane_second_exponent = output_exponent_q;
                        lane_common_exponent = maximum_exponent(
                            hidden_exponent_q, output_exponent_q);
                        lane_safety_exponent =
                            (lane_common_exponent < 8'sd31) ?
                            (lane_common_exponent + 1'b1) : 8'sd31;
                    end
                end

                E_COMMIT: kv_commit_valid = 1'b1;
                default: begin end
            endcase
            if (engine_state_q == E_IDLE) begin
                hidden_ram_read_enable = 1'b1;
                hidden_ram_read_address = private_result_index_i;
            end
        end
    end

    // Gate and up scratch payloads are true private synchronous memories.
    // Both share the schedule-derived read coordinate; the up read is needed
    // only for SiLU*up, while harmless extra gate-only reads serve DOWN.
    board1_fixed_semantic_scratch_ram u_gate_scratch (
        .clk(clk),
        .private_read_enable_i(scratch_read_enable),
        .private_read_address_i(scratch_read_address),
        .private_read_data_o(gate_read_data),
        .private_write_enable_i(gate_write_enable),
        .private_write_address_i(output_index_q),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_scratch_ram u_up_scratch (
        .clk(clk),
        .private_read_enable_i(scratch_read_enable &&
            (engine_state_q == E_ELEM) &&
            (current_stage_q == STAGE_SILU_MUL)),
        .private_read_address_i(scratch_read_address),
        .private_read_data_o(up_read_data),
        .private_write_enable_i(up_write_enable),
        .private_write_address_i(output_index_q),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_vector256_ram u_attention_scratch (
        .clk(clk),
        .private_read_enable_i(attention_ram_read_enable),
        .private_read_address_i(attention_ram_read_address),
        .private_read_data_o(attention_ram_read_data),
        .private_write_enable_i(attention_ram_write_enable),
        .private_write_address_i(attention_ram_write_address),
        .private_write_data_i(attention_ram_write_data)
    );

    board1_fixed_semantic_vector256_ram u_rms_scratch (
        .clk(clk),
        .private_read_enable_i(rms_ram_read_enable),
        .private_read_address_i(rms_ram_read_address),
        .private_read_data_o(rms_ram_read_data),
        .private_write_enable_i(rms_ram_write_enable),
        .private_write_address_i(output_index_q[7:0]),
        .private_write_data_i(rms_result_mantissa)
    );

    board1_fixed_semantic_vector256_ram u_output_scratch (
        .clk(clk),
        .private_read_enable_i(output_ram_read_enable),
        .private_read_address_i(output_ram_read_address),
        .private_read_data_o(output_ram_read_data),
        .private_write_enable_i(output_ram_write_enable),
        .private_write_address_i(output_index_q[7:0]),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_vector256_ram u_hidden_state (
        .clk(clk),
        .private_read_enable_i(hidden_ram_read_enable),
        .private_read_address_i(hidden_ram_read_address),
        .private_read_data_o(hidden_ram_read_data),
        .private_write_enable_i(hidden_ram_write_enable),
        .private_write_address_i(hidden_ram_write_address),
        .private_write_data_i(hidden_ram_write_data)
    );

    board1_fixed_semantic_vector256_ram u_query_state (
        .clk(clk),
        .private_read_enable_i(query_ram_read_enable),
        .private_read_address_i(query_ram_read_address),
        .private_read_data_o(query_ram_read_data),
        .private_write_enable_i(query_ram_write_enable),
        .private_write_address_i(output_index_q[7:0]),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_vector128_ram u_key_state (
        .clk(clk),
        .private_read_enable_i(key_ram_read_enable),
        .private_read_address_i(key_ram_read_address),
        .private_read_data_o(key_ram_read_data),
        .private_write_enable_i(key_ram_write_enable),
        .private_write_address_i(output_index_q[6:0]),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_vector128_ram u_value_state (
        .clk(clk),
        .private_read_enable_i(value_ram_read_enable),
        .private_read_address_i(value_ram_read_address),
        .private_read_data_o(value_ram_read_data),
        .private_write_enable_i(value_ram_write_enable),
        .private_write_address_i(output_index_q[6:0]),
        .private_write_data_i(norm_result_mantissa)
    );

    board1_fixed_semantic_rope_raw_ram u_rope_raw_scratch (
        .clk(clk),
        .private_read_enable_i(rope_raw_ram_read_enable),
        .private_read_address_i(rope_second_index_q),
        .private_read_data_o(rope_raw_ram_read_data),
        .private_write_enable_i(rope_raw_ram_write_enable),
        .private_write_address_i(rope_half_q),
        .private_write_data_i(lane_raw1)
    );

    // RMSNorm has its own exact whole-vector arithmetic and sealed one-DSP
    // application of the immutable per-row weights.
    board1_fixed_vector_rmsnorm_service u_rmsnorm (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || fault_q),
        .start_valid_i(rms_start_valid), .start_ready_o(rms_start_ready),
        .fixed_layer_i(current_layer_q),
        .fixed_norm_kind_i((current_stage_q == STAGE_INPUT_RMS) ? 2'd0 :
                                                                    2'd1),
        .input_exponent_i(hidden_exponent_q),
        .input_valid_i(rms_input_valid), .input_ready_o(rms_input_ready),
        .input_row_index_i(input_index_q[7:0]),
        .input_mantissa_i(hidden_ram_read_data),
        .input_last_i(input_index_q == 10'd255),
        .result_valid_o(rms_result_valid),
        .result_ready_i(rms_result_ready),
        .result_row_index_o(rms_result_index),
        .result_mantissa_o(rms_result_mantissa),
        .result_exponent_o(rms_result_exponent),
        .result_last_o(rms_result_last),
        .done_valid_o(rms_done_valid), .done_ready_i(rms_done_ready),
        .busy_o(rms_busy), .range_fault_o(rms_fault)
    );

    board1_fixed_group_projection_scale_job #(.ADDR_W(ADDR_W)) u_projection (
        .clk(clk), .reset_n(rst_n), .clear_i(clear_i),
        .model_locked_i(model_lock_i),
        .upstream_fail_closed_i(upstream_fault_i || fault_q),
        .start_valid_i(projection_start_valid),
        .start_ready_o(projection_start_ready),
        .fixed_layer_i(projection_layer), .fixed_job_i(projection_job),
        .activation_exponent_i(
            projection_is_head ? head_activation_exponent_q :
            (current_stage_q == STAGE_Q || current_stage_q == STAGE_K ||
             current_stage_q == STAGE_V) ? rms_exponent_q :
            (current_stage_q == STAGE_O) ? attention_exponent_q :
            (current_stage_q == STAGE_GATE || current_stage_q == STAGE_UP) ?
                rms_exponent_q : gate_exponent_q),
        .activation_valid_i(projection_activation_valid),
        .activation_ready_o(projection_activation_ready),
        .activation_i(projection_activation),
        .activation_last_i(projection_activation_last),
        .private_word_req_valid_o(projection_word_req_valid),
        .private_word_req_ready_i(projection_word_req_ready),
        .private_word_req_index_o(projection_word_req_index),
        .private_word_rsp_valid_i(projection_word_rsp_valid),
        .private_word_rsp_ready_o(projection_word_rsp_ready),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .result_valid_o(projection_result_valid),
        .result_ready_i(projection_result_ready),
        .result_row_index_o(projection_result_index),
        .result_scaled_raw_o(projection_result_raw),
        .result_source_exponent_o(projection_result_exponent),
        .result_last_o(projection_result_last),
        .done_valid_o(projection_done_valid),
        .done_ready_i(projection_done_ready),
        .busy_o(projection_busy), .fail_closed_o(projection_fault)
    );

    board1_fixed_vector_normalizer u_normalizer (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || fault_q),
        .start_valid_i(norm_start_valid), .start_ready_o(norm_start_ready),
        .fixed_layer_i(current_layer_q), .fixed_job_i(norm_job),
        .input_valid_i(norm_input_valid), .input_ready_o(norm_input_ready),
        .input_row_index_i(norm_input_index), .input_raw_i(norm_input_raw),
        .input_source_exponent_i(norm_input_exponent),
        .input_last_i(norm_input_last),
        .result_valid_o(norm_result_valid),
        .result_ready_i(norm_result_ready),
        .result_row_index_o(norm_result_index),
        .result_mantissa_o(norm_result_mantissa),
        .result_exponent_o(norm_result_exponent),
        .result_last_o(norm_result_last),
        .done_valid_o(norm_done_valid), .done_ready_i(norm_done_ready),
        .busy_o(norm_busy), .range_fault_o(norm_fault)
    );

    board1_fixed_elementwise_lane_core u_elementwise_lane (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .request_valid_i(lane_request_valid),
        .request_ready_o(lane_request_ready), .operation_i(lane_operation),
        .first_i(lane_first), .second_i(lane_second),
        .coefficient_i(10'sd0), .multiplier_i(16'd0),
        .cosine_i(rope_cosine_q), .sine_i(rope_sine_q),
        .first_exponent_i(lane_first_exponent),
        .second_exponent_i(lane_second_exponent),
        .common_exponent_i(lane_common_exponent),
        // The normalized lane result is discarded for stages that feed the
        // vector normalizer.  +31 guarantees a right-normalizing safety
        // target for the authenticated model while raw0/raw1 stay exact.
        .target_exponent_i(lane_safety_exponent),
        .lut_request_o(lane_lut_request), .lut_index_o(lane_lut_index),
        .lut_response_valid_i(lane_lut_response_q),
        .lut_value_i(silu_value_q), .lut_fault_i(1'b0),
        .result_valid_o(lane_result_valid),
        .result_ready_i(lane_result_ready),
        .result0_o(lane_result0), .result1_o(lane_result1),
        .auxiliary_o(lane_auxiliary),
        .raw0_o(lane_raw0), .raw1_o(lane_raw1),
        .source_exponent_o(lane_source_exponent),
        .range_fault_o(lane_fault)
    );

    board1_context2048_semantic_lookup #(.ADDR_W(ADDR_W)) u_lookup (
        .clk(clk), .reset_n(rst_n), .clear_i(clear_i),
        .model_locked_i(model_lock_i),
        .upstream_fail_closed_i(upstream_fault_i || fault_q),
        .request_valid_i(lookup_request_valid),
        .request_ready_o(lookup_request_ready), .fixed_kind_i(lookup_kind),
        .rope_position_i(current_position_q),
        .rope_coordinate_i(lookup_index[4:0]),
        .silu_index_i(lookup_index),
        .response_valid_o(lookup_response_valid),
        .response_ready_i(lookup_response_ready),
        .response_value_o(lookup_response_value),
        .response_fault_o(lookup_response_fault),
        .private_word_req_valid_o(lookup_word_req_valid),
        .private_word_req_ready_i(lookup_word_req_ready),
        .private_word_req_index_o(lookup_word_req_index),
        .private_word_rsp_valid_i(lookup_word_rsp_valid),
        .private_word_rsp_ready_o(lookup_word_rsp_ready),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .busy_o(lookup_busy), .fail_closed_o(lookup_fault)
    );

    board1_context2048_atomic_kv_typed u_kv_cache (
        .clk(clk), .reset_n(rst_n), .clear_i(clear_i),
        .model_locked_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || fault_q),
        .endpoint_fault_i(kv_endpoint_fault_i),
        .stage_begin_valid_i(kv_stage_begin_valid),
        .stage_begin_ready_o(kv_stage_begin_ready),
        .stage_layer_i(current_layer_q),
        .stage_position_i({1'b0, current_position_q}),
        .stage_key_exponents_i({key_exponent_q, key_exponent_q}),
        .stage_value_exponents_i({value_exponent_q, value_exponent_q}),
        .stage_payload_valid_i(kv_stage_payload_valid),
        .stage_payload_ready_o(kv_stage_payload_ready),
        .stage_coordinate_i(input_index_q[6:0]),
        .stage_key_i(key_ram_read_data),
        .stage_value_i(value_ram_read_data),
        .stage_last_i(input_index_q == 10'd127),
        .pending_complete_o(kv_pending_complete),
        .commit_valid_i(kv_commit_valid), .commit_ready_o(kv_commit_ready),
        .commit_layer_i(current_layer_q),
        .commit_position_i({1'b0, current_position_q}),
        .attention_req_valid_i(attention_cache_req_valid),
        .attention_req_ready_o(attention_cache_req_ready),
        .attention_req_kind_i(attention_cache_req_kind),
        .attention_layer_i(current_layer_q),
        .attention_position_i({1'b0, attention_cache_req_position}),
        .attention_kv_head_i({1'b0, attention_cache_req_head}),
        .attention_rsp_valid_o(attention_cache_rsp_valid),
        .attention_rsp_ready_i(attention_cache_rsp_ready),
        .attention_rsp_kind_o(),
        .attention_rsp_key_vector_o(attention_cache_key),
        .attention_rsp_key_exponent_o(attention_cache_key_exp),
        .attention_rsp_value_vector_o(attention_cache_value),
        .attention_rsp_value_exponent_o(attention_cache_value_exp),
        .attention_rsp_fault_o(attention_cache_rsp_fault),
        .attention_rsp_from_pending_o(
            attention_cache_rsp_from_pending),
        .kv_write_req_valid_o(kv_write_req_valid_o),
        .kv_write_req_ready_i(kv_write_req_ready_i),
        .kv_write_req_layer_o(kv_write_req_layer_o),
        .kv_write_req_position_o(kv_write_req_position_o),
        .kv_write_req_head_o(kv_write_req_head_o),
        .kv_write_req_row_word_o(kv_write_req_row_word_o),
        .kv_write_req_shadow_address_o(
            kv_write_req_shadow_address_o),
        .kv_write_req_data_o(kv_write_req_data_o),
        .kv_write_cpl_valid_i(kv_write_cpl_valid_i),
        .kv_write_cpl_ready_o(kv_write_cpl_ready_o),
        .kv_write_cpl_fault_i(kv_write_cpl_fault_i),
        .kv_read_req_valid_o(kv_read_req_valid_o),
        .kv_read_req_ready_i(kv_read_req_ready_i),
        .kv_read_req_layer_o(kv_read_req_layer_o),
        .kv_read_req_position_o(kv_read_req_position_o),
        .kv_read_req_head_o(kv_read_req_head_o),
        .kv_read_req_row_word_o(kv_read_req_row_word_o),
        .kv_read_req_shadow_address_o(kv_read_req_shadow_address_o),
        .kv_read_rsp_valid_i(kv_read_rsp_valid_i),
        .kv_read_rsp_ready_o(kv_read_rsp_ready_o),
        .kv_read_rsp_data_i(kv_read_rsp_data_i),
        .kv_read_rsp_fault_i(kv_read_rsp_fault_i),
        .committed_prefixes_o(kv_committed_prefixes),
        .busy_o(kv_busy), .fail_closed_o(kv_fault)
    );

    board1_context2048_attention u_attention (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || fault_q),
        .start_valid_i(attention_start_valid),
        .start_ready_o(attention_start_ready),
        .fixed_position_i(current_position_q),
        .query_exponent_i(query_exponent_q),
        .query_valid_i(attention_query_valid),
        .query_ready_o(attention_query_ready),
        .query_vector_i(attention_query_vector),
        .query_last_i(attention_query_last),
        .private_cache_request_valid_o(attention_cache_req_valid),
        .private_cache_request_kind_o(attention_cache_req_kind),
        .private_cache_request_ready_i(attention_cache_req_ready),
        .private_cache_request_position_o(attention_cache_req_position),
        .private_cache_request_kv_head_o(attention_cache_req_head),
        .private_cache_response_valid_i(attention_cache_rsp_valid),
        .private_cache_response_ready_o(attention_cache_rsp_ready),
        .private_cache_response_key_vector_i(attention_cache_key),
        .private_cache_response_key_exponent_i(attention_cache_key_exp),
        .private_cache_response_value_vector_i(attention_cache_value),
        .private_cache_response_value_exponent_i(attention_cache_value_exp),
        .private_cache_response_fault_i(attention_cache_rsp_fault),
        .result_valid_o(attention_result_valid),
        .result_ready_i(attention_result_ready),
        .result_vector_o(attention_result_vector),
        .result_exponent_o(attention_result_exponent),
        .result_last_o(attention_result_last),
        .done_valid_o(attention_done_valid),
        .done_ready_i(attention_done_ready),
        .busy_o(attention_busy), .range_fault_o(attention_fault)
    );

    // Private bounded projection-read window. All accepted requests in a
    // window have the same structural owner. Lookup stays single-outstanding.
    // CLEAR/fault prevents new requests; accepted ownership is never cleared.
    wire ddr_request_fire = private_word_req_valid_o && private_word_req_ready_i;
    wire ddr_response_fire = private_word_rsp_valid_i && private_word_rsp_ready_o;
    wire ddr_admission_live = !fault_q && !clear_i && !upstream_fault_i &&
        !ddr_arbiter_fault_q &&
        !(private_word_rsp_valid_i && private_word_rsp_fault_i);

    always @* begin
        private_word_req_valid_o = 1'b0;
        private_word_req_index_o = {ADDR_W{1'b0}};
        projection_word_req_ready = 1'b0;
        lookup_word_req_ready = 1'b0;
        projection_word_rsp_valid = 1'b0;
        lookup_word_rsp_valid = 1'b0;
        private_word_rsp_ready_o = 1'b0;
        if (ddr_admission_live) begin
            if (((ddr_owner_q == DDR_NONE) ||
                 ((ddr_owner_q == DDR_PROJ) && ddr_pending_q < 4'd8)) &&
                projection_word_req_valid && !lookup_word_req_valid) begin
                private_word_req_valid_o = 1'b1;
                private_word_req_index_o = projection_word_req_index;
                projection_word_req_ready = private_word_req_ready_i;
            end else if ((ddr_owner_q == DDR_NONE) && lookup_word_req_valid &&
                         !projection_word_req_valid) begin
                private_word_req_valid_o = 1'b1;
                private_word_req_index_o = lookup_word_req_index;
                lookup_word_req_ready = private_word_req_ready_i;
            end
        end
        // Responses and requests may transfer together, but only within a
        // projection window. Payload follows the existing authenticated path.
        if (ddr_owner_q == DDR_PROJ) begin
            projection_word_rsp_valid = private_word_rsp_valid_i;
            private_word_rsp_ready_o = projection_word_rsp_ready;
        end else if (ddr_owner_q == DDR_LOOK) begin
            lookup_word_rsp_valid = private_word_rsp_valid_i;
            private_word_rsp_ready_o = lookup_word_rsp_ready;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ddr_owner_q <= DDR_NONE;
            ddr_pending_q <= 4'd0;
            ddr_arbiter_fault_q <= 1'b0;
        end else begin
            if ((ddr_owner_q == DDR_NONE) && private_word_rsp_valid_i)
                ddr_arbiter_fault_q <= 1'b1;
            if (projection_word_req_valid && lookup_word_req_valid)
                ddr_arbiter_fault_q <= 1'b1;
            if ((ddr_pending_q == 0) != (ddr_owner_q == DDR_NONE) ||
                ddr_pending_q > 4'd8 ||
                ((ddr_owner_q == DDR_LOOK) && ddr_pending_q != 4'd1) ||
                ddr_owner_q == 2'd3)
                ddr_arbiter_fault_q <= 1'b1;
            case ({ddr_request_fire, ddr_response_fire})
                2'b10: begin
                    ddr_pending_q <= ddr_pending_q + 1'b1;
                    if (ddr_owner_q == DDR_NONE)
                        ddr_owner_q <= projection_word_req_valid ? DDR_PROJ : DDR_LOOK;
                end
                2'b01: begin
                    ddr_pending_q <= ddr_pending_q - 1'b1;
                    if (ddr_pending_q == 4'd1)
                        ddr_owner_q <= DDR_NONE;
                end
                default: begin end
            endcase
        end
    end

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

            if (clear_i) begin
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
            if (upstream_fault_i || child_fault ||
                (lock_seen_q && !model_lock_i)
`ifndef SYNTHESIS
                || simulation_x_fault
`endif
            ) begin
                fault_q <= 1'b1;
                engine_state_q <= E_FAULT;
            end
        end
    end

    // Private staging, not permission to use a query. A cancelled RAM
    // return may be copied, but the original guarded lane/loaded/valid state
    // below remains the sole authority. Every new query overwrites all 64
    // lanes before publication; faults/CLEAR never make this payload live.
    always_ff @(posedge clk) begin
        if (rst_n && (engine_state_q == E_ATTN) &&
            attention_query_read_valid_q) begin
            attention_query_vector_q[
                attention_query_load_lane_q*16 +: 16] <=
                query_ram_read_data;
        end
    end

    // Suppress lint-only complaints for normalized lane values that are
    // deliberately discarded when whole-vector normalization owns exponent
    // selection.  Their validity/range is still checked inside the lane.
    wire _unused_lane_results = &{1'b0, lane_result0, lane_result1,
        lane_auxiliary, attention_cache_rsp_from_pending};
endmodule

`default_nettype wire
