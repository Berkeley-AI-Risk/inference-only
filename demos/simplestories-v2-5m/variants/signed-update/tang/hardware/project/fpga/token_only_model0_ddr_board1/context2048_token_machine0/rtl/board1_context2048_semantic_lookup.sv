`timescale 1ns/1ps
`default_nettype none

// Private immutable lookup service for the semantic tables which are too
// costly to duplicate in FPGA BSRAM.  Callers select one of three named,
// fixed-model operations and supply only the coordinate naturally produced by
// that operation.  This block, not its caller, derives the authenticated DDR
// word address and the 16-bit lane.  It therefore exposes neither a raw
// address nor a general memory-read operation above the semantic controller.
//
// The accepted context-2,048 semantic-image layout preserves the complete
// context-128 image as a byte-identical prefix, then appends the remaining
// RoPE rows.  Consequently the logical RoPE tables are physically split:
//   cos positions    0..127: words 214261..214516
//   sin positions    0..127: words 214517..214772
//   SiLU (unchanged):         words 215286..219381
//   cos positions 128..2047: words 219382..223221
//   sin positions 128..2047: words 223222..227061
//
// At most one DDR request is outstanding.  Once accepted by DDR, it is always
// consumed exactly once.  CLEAR may suppress the semantic response, but it
// cannot cancel an already accepted DDR transaction; the service drains that
// response before accepting another request.  Faults are sticky until reset.
module board1_context2048_semantic_lookup #(
    parameter integer ADDR_W = 25,
    parameter logic [ADDR_W-1:0] ROPE_COS_BASE_WORD = 214261,
    parameter logic [ADDR_W-1:0] ROPE_SIN_BASE_WORD = 214517,
    parameter logic [ADDR_W-1:0] SILU_BASE_WORD = 215286,
    parameter logic [ADDR_W-1:0] ROPE_COS_TAIL_BASE_WORD = 219382,
    parameter logic [ADDR_W-1:0] ROPE_SIN_TAIL_BASE_WORD = 223222,
    parameter logic [ADDR_W-1:0] MODEL_WORDS = 227062
) (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    clear_i,
    input  wire                    model_locked_i,
    input  wire                    upstream_fail_closed_i,

    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    // 0 = RoPE cosine, 1 = RoPE sine, 2 = SiLU.  3 is invalid.
    input  wire [1:0]              fixed_kind_i,
    input  wire [10:0]             rope_position_i,
    input  wire [4:0]              rope_coordinate_i,
    input  wire [15:0]             silu_index_i,

    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [15:0]     response_value_o,
    output logic                   response_fault_o,

    output logic                   private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output logic [ADDR_W-1:0]      private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output logic                   private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    output logic                   busy_o,
    output logic                   fail_closed_o
);
    typedef enum logic [2:0] {
        ST_IDLE  = 3'd0,
        ST_ISSUE = 3'd1,
        ST_WAIT  = 3'd2,
        ST_HOLD  = 3'd3,
        ST_DRAIN = 3'd4,
        ST_FAIL  = 3'd7
    } state_t;

    state_t state_q;
    logic [ADDR_W-1:0] word_index_q;
    logic [3:0] lane_q;
    logic signed [15:0] value_q;
    logic response_fault_q;
    logic drain_to_fail_q;
    logic fail_q;

    wire descriptor_valid = fixed_kind_i != 2'd3;
    wire rope_uses_tail = rope_position_i >= 11'd128;
    wire [10:0] rope_tail_position = rope_position_i - 11'd128;
    wire [ADDR_W-1:0] rope_prefix_word_offset =
        {{(ADDR_W-12){1'b0}}, rope_position_i, 1'b0} +
        {{(ADDR_W-1){1'b0}}, rope_coordinate_i[4]};
    wire [ADDR_W-1:0] rope_tail_word_offset =
        {{(ADDR_W-12){1'b0}}, rope_tail_position, 1'b0} +
        {{(ADDR_W-1){1'b0}}, rope_coordinate_i[4]};
    wire [ADDR_W-1:0] silu_word_offset =
        {{(ADDR_W-12){1'b0}}, silu_index_i[15:4]};
    wire [ADDR_W-1:0] derived_word_index =
        (fixed_kind_i == 2'd0) ?
            (rope_uses_tail ? ROPE_COS_TAIL_BASE_WORD + rope_tail_word_offset
                            : ROPE_COS_BASE_WORD + rope_prefix_word_offset) :
        (fixed_kind_i == 2'd1) ?
            (rope_uses_tail ? ROPE_SIN_TAIL_BASE_WORD + rope_tail_word_offset
                            : ROPE_SIN_BASE_WORD + rope_prefix_word_offset) :
        (fixed_kind_i == 2'd2) ? SILU_BASE_WORD + silu_word_offset :
        {ADDR_W{1'b0}};
    wire [3:0] derived_lane = (fixed_kind_i == 2'd2) ?
                              silu_index_i[3:0] :
                              rope_coordinate_i[3:0];

    wire request_transfer = request_valid_i && request_ready_o;
    wire private_request_transfer = private_word_req_valid_o &&
                                    private_word_req_ready_i;
    wire private_response_transfer = private_word_rsp_valid_i &&
                                     private_word_rsp_ready_o;
    wire response_transfer = response_valid_o && response_ready_i;
    wire private_response_expected = (state_q == ST_WAIT) ||
                                     (state_q == ST_DRAIN);
    wire unsolicited_private_response = private_word_rsp_valid_i &&
                                        !private_response_expected;

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(request_valid_i) ||
            $isunknown(private_word_req_ready_i) ||
            $isunknown(private_word_rsp_valid_i) ||
            $isunknown(private_word_rsp_fault_i);
        if (request_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(fixed_kind_i) ||
                $isunknown(rope_position_i) ||
                $isunknown(rope_coordinate_i) ||
                $isunknown(silu_index_i);
        if (private_word_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(private_word_rsp_data_i);
        if (state_q == ST_HOLD)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(response_ready_i);
    end
`else
    wire simulation_x_fault = 1'b0;
`endif

    // A response-side fault is terminal even if CLEAR is asserted on the same
    // edge.  CLEAR must never hide a malformed or failed private transaction.
    wire response_side_fault = private_word_rsp_valid_i &&
        (private_word_rsp_fault_i ||
         (private_response_expected && simulation_x_fault));
    wire global_fault = upstream_fail_closed_i ||
        !model_locked_i || simulation_x_fault ||
        unsolicited_private_response;

    always_comb begin
        request_ready_o = (state_q == ST_IDLE) && model_locked_i &&
            !upstream_fail_closed_i && !fail_q && !clear_i;
        response_valid_o = (state_q == ST_HOLD);
        response_value_o = response_valid_o ? value_q : 16'sd0;
        response_fault_o = response_valid_o && response_fault_q;

        private_word_req_valid_o = (state_q == ST_ISSUE) && !fail_q &&
            !clear_i && model_locked_i && !upstream_fail_closed_i;
        private_word_req_index_o = private_word_req_valid_o ?
                                   word_index_q : {ADDR_W{1'b0}};
        // Never cancel a request after DDR has accepted it.  In both WAIT and
        // DRAIN the response is consumed even while CLEAR remains asserted.
        private_word_rsp_ready_o = (state_q == ST_WAIT) ||
                                   (state_q == ST_DRAIN);
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_q || upstream_fail_closed_i;
    end

    initial begin
        if (ADDR_W < 19)
            $fatal(1, "ADDR_W cannot represent the semantic image");
        if ((ROPE_COS_BASE_WORD + 256) != ROPE_SIN_BASE_WORD ||
            (ROPE_SIN_BASE_WORD + 256) != 214773 ||
            (SILU_BASE_WORD + 4096) != ROPE_COS_TAIL_BASE_WORD ||
            (ROPE_COS_TAIL_BASE_WORD + 3840) !=
                ROPE_SIN_TAIL_BASE_WORD ||
            (ROPE_SIN_TAIL_BASE_WORD + 3840) != MODEL_WORDS)
            $fatal(1, "semantic-image region geometry differs");
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            word_index_q <= {ADDR_W{1'b0}};
            lane_q <= 4'd0;
            value_q <= 16'sd0;
            response_fault_q <= 1'b0;
            drain_to_fail_q <= 1'b0;
            fail_q <= 1'b0;
        end else if (global_fault) begin
            fail_q <= 1'b1;
            response_fault_q <= 1'b1;
            if (((state_q == ST_WAIT) || (state_q == ST_DRAIN)) &&
                !private_response_transfer) begin
                state_q <= ST_DRAIN;
                drain_to_fail_q <= 1'b1;
            end else begin
                state_q <= ST_FAIL;
                drain_to_fail_q <= 1'b0;
            end
        end else if (response_side_fault) begin
            fail_q <= 1'b1;
            response_fault_q <= 1'b1;
            // The asserted response is accepted in WAIT/DRAIN because READY
            // is held high there.  Do not leave an outstanding transaction.
            state_q <= ST_FAIL;
            drain_to_fail_q <= 1'b0;
        end else if (clear_i) begin
            response_fault_q <= 1'b0;
            value_q <= 16'sd0;
            case (state_q)
                ST_WAIT: begin
                    if (private_response_transfer) begin
                        state_q <= ST_IDLE;
                        drain_to_fail_q <= 1'b0;
                    end else begin
                        state_q <= ST_DRAIN;
                        drain_to_fail_q <= 1'b0;
                    end
                end
                ST_DRAIN: begin
                    if (private_response_transfer) begin
                        if (drain_to_fail_q)
                            state_q <= ST_FAIL;
                        else
                            state_q <= ST_IDLE;
                        drain_to_fail_q <= 1'b0;
                    end
                end
                ST_FAIL: begin
                    state_q <= ST_FAIL;
                end
                default: begin
                    // IDLE, ISSUE (not accepted), and HOLD have no remaining
                    // DDR ownership and may abort immediately.
                    if (fail_q)
                        state_q <= ST_FAIL;
                    else
                        state_q <= ST_IDLE;
                    drain_to_fail_q <= 1'b0;
                end
            endcase
        end else begin
            case (state_q)
                ST_IDLE: begin
                    response_fault_q <= 1'b0;
                    if (request_transfer) begin
                        if (!descriptor_valid) begin
                            state_q <= ST_FAIL;
                            fail_q <= 1'b1;
                        end else begin
                            word_index_q <= derived_word_index;
                            lane_q <= derived_lane;
                            state_q <= ST_ISSUE;
                        end
                    end
                end

                ST_ISSUE: begin
                    if (private_request_transfer)
                        state_q <= ST_WAIT;
                end

                ST_WAIT: begin
                    if (private_response_transfer) begin
                        value_q <= $signed(
                            private_word_rsp_data_i[lane_q*16 +: 16]);
                        response_fault_q <= 1'b0;
                        state_q <= ST_HOLD;
                    end
                end

                ST_HOLD: begin
                    if (response_transfer) begin
                        response_fault_q <= 1'b0;
                        if (fail_q)
                            state_q <= ST_FAIL;
                        else
                            state_q <= ST_IDLE;
                    end
                end

                ST_DRAIN: begin
                    if (private_response_transfer) begin
                        if (drain_to_fail_q)
                            state_q <= ST_FAIL;
                        else
                            state_q <= ST_IDLE;
                        drain_to_fail_q <= 1'b0;
                    end
                end

                default: begin
                    state_q <= ST_FAIL;
                    fail_q <= 1'b1;
                end
            endcase
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            assert (!(private_word_req_valid_o &&
                      (state_q != ST_ISSUE)));
            if (private_word_req_valid_o) begin
                assert (private_word_req_index_o < MODEL_WORDS);
                assert (!((private_word_req_index_o >= 214773) &&
                          (private_word_req_index_o < SILU_BASE_WORD)));
            end
            assert (!(private_word_rsp_ready_o &&
                      (state_q != ST_WAIT) && (state_q != ST_DRAIN)));
            if (formal_past_valid && $past(reset_n)) begin
                if ($past(response_valid_o) &&
                    !$past(response_ready_i) && !$past(clear_i) &&
                    !$past(global_fault)) begin
                    assert (response_valid_o);
                    assert (response_value_o == $past(response_value_o));
                end
                if ($past(fail_q))
                    assert (fail_q);
            end
        end
    end
`endif
endmodule

`default_nettype wire
