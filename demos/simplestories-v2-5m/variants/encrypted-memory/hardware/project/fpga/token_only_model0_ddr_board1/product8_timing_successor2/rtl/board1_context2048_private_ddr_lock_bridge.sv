`timescale 1ns/1ps
`default_nettype none

// Product4's sole private DDR ownership state machine. Boot is a fixed,
// authenticated write/readback of the immutable model interval. After LOCK,
// the only legal traffic is a model/scratch read or a scratch-only write from
// the independently checked context2048 typed endpoint. No signal here is a
// package or host operation, and CLEAR deliberately has no port here.
module board1_context2048_private_ddr_lock_bridge #(
    parameter integer ADDR_W = 19,
    parameter integer MODEL_BASE_WORD = 0,
    parameter integer MODEL_WORDS = 227062,
    parameter integer SCRATCH_BASE_WORD = 227072,
    parameter integer SCRATCH_WORDS = 221184
) (
    input  wire                   clk,
    input  wire                   reset_n,
    input  wire                   calib_done,
    input  wire                   calib_error,
    input  wire                   fixed_source_done,
    input  wire                   fixed_source_ok,
    input  wire [255:0]           loader_data,
    input  wire                   loader_valid,
    output logic                  loader_ready,
    output logic [255:0]          readback_word_data,
    output logic                  readback_word_valid,
    output logic                  readback_word_last,
    input  wire                   readback_word_ready,
    input  wire                   readback_digest_done,
    input  wire                   readback_digest_ok,
    input  wire                   runtime_req_valid,
    output logic                  runtime_req_ready,
    input  wire [ADDR_W-1:0]      runtime_req_word_address,
    input  wire                   runtime_req_write,
    input  wire [255:0]           runtime_req_write_data,
    output logic [255:0]          runtime_rsp_data,
    output logic                  runtime_rsp_valid,
    input  wire                   runtime_rsp_ready,
    output logic                  runtime_rsp_error,
    output logic                  phy_req_valid,
    input  wire                   phy_req_ready,
    output logic                  phy_req_write,
    output logic [ADDR_W-1:0]     phy_req_word_addr,
    output logic [255:0]          phy_req_wdata,
    input  wire                   phy_rsp_valid,
    input  wire [255:0]           phy_rsp_data,
    input  wire                   phy_rsp_error,
    output logic                  model_locked,
    output logic                  fail_closed
);
    localparam logic [ADDR_W-1:0] MODEL_BASE =
        ADDR_W'(MODEL_BASE_WORD);
    localparam logic [ADDR_W-1:0] MODEL_END =
        ADDR_W'(MODEL_BASE_WORD + MODEL_WORDS);
    localparam logic [ADDR_W-1:0] MODEL_LAST =
        ADDR_W'(MODEL_BASE_WORD + MODEL_WORDS - 1);
    localparam logic [ADDR_W-1:0] SCRATCH_BASE =
        ADDR_W'(SCRATCH_BASE_WORD);
    localparam logic [ADDR_W-1:0] SCRATCH_END =
        ADDR_W'(SCRATCH_BASE_WORD + SCRATCH_WORDS);

    typedef enum logic [3:0] {
        ST_WAIT_CAL    = 4'd0,
        ST_WAIT_SOURCE = 4'd1,
        ST_LOAD        = 4'd2,
        ST_READBACK    = 4'd3,
        ST_WAIT_DIGEST = 4'd4,
        ST_LOCKED      = 4'd5,
        ST_FAIL        = 4'd15
    } state_t;

    state_t state_q;
    logic fixed_source_seen_q;
    logic [ADDR_W-1:0] load_word_q;
    logic [ADDR_W-1:0] readback_issue_word_q;
    logic [ADDR_W-1:0] readback_receive_word_q;
    logic readback_outstanding_q;
    logic [255:0] readback_data_q;
    logic readback_valid_q;
    logic readback_last_q;
    logic runtime_read_outstanding_q;
    logic [255:0] runtime_rsp_data_q;
    logic runtime_rsp_valid_q;
    logic runtime_rsp_error_q;
    // A registered runtime ingress owner terminates the independent address
    // policy comparison before either the wide response registers or the
    // final physical-suppression fanout.  The payload is captured atomically;
    // only a captured descriptor whose registered policy bit is true may be
    // presented to the existing lower request FIFO.
    (* syn_preserve = 1 *) logic runtime_offer_valid_q;
    (* syn_preserve = 1 *) logic runtime_offer_legal_q;
    logic runtime_offer_write_q;
    logic [ADDR_W-1:0] runtime_offer_address_q;
    logic [255:0] runtime_offer_data_q;

    wire runtime_input_address_is_model =
        runtime_req_word_address < MODEL_END;
    wire runtime_input_address_is_scratch =
        (runtime_req_word_address >= SCRATCH_BASE) &&
        (runtime_req_word_address < SCRATCH_END);
    wire runtime_input_descriptor_legal =
        (runtime_req_write === 1'b1) ? runtime_input_address_is_scratch :
        (runtime_req_write === 1'b0) ?
            (runtime_input_address_is_model ||
             runtime_input_address_is_scratch) : 1'b0;
    wire runtime_offer_can_issue = (state_q == ST_LOCKED) &&
        !fail_closed && runtime_offer_valid_q && runtime_offer_legal_q;
    wire runtime_offer_pop = runtime_offer_can_issue && phy_req_ready;
    wire runtime_ingress_has_space = !runtime_offer_valid_q ||
                                     runtime_offer_pop;
    // At most one read may be owned because responses are untagged.  A write
    // may still queue behind an owned read: the registered ingress and lower
    // FIFO retain request order, and writes consume no response owner.
    wire runtime_read_slot_free = !runtime_read_outstanding_q &&
        !runtime_rsp_valid_q &&
        !(runtime_offer_valid_q && !runtime_offer_write_q);
    wire runtime_input_operation_allowed =
        (runtime_req_write === 1'b1) || runtime_read_slot_free;
    wire runtime_input_accept = (state_q == ST_LOCKED) && !fail_closed &&
        (runtime_req_valid === 1'b1) && runtime_ingress_has_space &&
        runtime_input_operation_allowed;
    wire runtime_offer_policy_fault = runtime_offer_valid_q &&
                                      !runtime_offer_legal_q;
    wire runtime_read_issue = runtime_offer_pop &&
                              !runtime_offer_write_q;
    wire runtime_response_has_owner = runtime_read_outstanding_q ||
                                      runtime_read_issue;
    wire runtime_response_accept = (state_q == ST_LOCKED) &&
                                   (phy_rsp_valid === 1'b1) &&
                                   runtime_response_has_owner &&
                                   !runtime_rsp_valid_q;
    wire runtime_rsp_consume = runtime_rsp_valid_q &&
                               (runtime_rsp_ready === 1'b1);

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(calib_done) ||
            $isunknown(calib_error) || $isunknown(fixed_source_done) ||
            $isunknown(fixed_source_ok) || $isunknown(loader_valid) ||
            $isunknown(readback_word_ready) ||
            $isunknown(readback_digest_done) ||
            $isunknown(readback_digest_ok) ||
            $isunknown(runtime_req_valid) ||
            $isunknown(runtime_rsp_ready) || $isunknown(phy_req_ready) ||
            $isunknown(phy_rsp_valid) || $isunknown(phy_rsp_error);
        if (loader_valid === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(loader_data);
        if (runtime_req_valid === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(runtime_req_word_address) ||
                $isunknown(runtime_req_write) ||
                ((runtime_req_write === 1'b1) &&
                 $isunknown(runtime_req_write_data));
        if (phy_rsp_valid === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(phy_rsp_data);
    end
`else
    wire simulation_x_fault = 1'b0;
`endif

    always_comb begin
        loader_ready = 1'b0;
        readback_word_data = readback_data_q;
        readback_word_valid = readback_valid_q;
        readback_word_last = readback_last_q;
        runtime_req_ready = 1'b0;
        runtime_rsp_data = runtime_rsp_data_q;
        runtime_rsp_valid = runtime_rsp_valid_q;
        runtime_rsp_error = runtime_rsp_error_q;
        phy_req_valid = 1'b0;
        phy_req_write = 1'b0;
        phy_req_word_addr = {ADDR_W{1'b0}};
        phy_req_wdata = 256'd0;

        case (state_q)
            ST_LOAD: begin
                phy_req_valid = (loader_valid === 1'b1) && !fail_closed;
                phy_req_write = 1'b1;
                phy_req_word_addr = load_word_q;
                phy_req_wdata = loader_data;
                loader_ready = phy_req_ready && !fail_closed;
            end
            ST_READBACK: begin
                if (!readback_outstanding_q && !readback_valid_q &&
                    !fail_closed) begin
                    phy_req_valid = 1'b1;
                    phy_req_word_addr = readback_issue_word_q;
                end
            end
            ST_LOCKED: begin
                if (!fail_closed) begin
                    runtime_req_ready = runtime_ingress_has_space &&
                                        runtime_input_operation_allowed;
                end
                if (runtime_offer_can_issue) begin
                    phy_req_valid = 1'b1;
                    phy_req_write = runtime_offer_write_q;
                    phy_req_word_addr = runtime_offer_address_q;
                    phy_req_wdata = runtime_offer_data_q;
                end
            end
            default: begin
            end
        endcase
    end

    initial begin
        if (ADDR_W != 19 || MODEL_BASE_WORD != 0 || MODEL_WORDS != 227062 ||
            SCRATCH_BASE_WORD != 227072 || SCRATCH_WORDS != 221184 ||
            MODEL_END != ADDR_W'(227062) ||
            SCRATCH_END != ADDR_W'(448256) ||
            MODEL_END >= SCRATCH_BASE || SCRATCH_END <= SCRATCH_BASE)
            $fatal(1, "Product4 DDR interval policy differs");
    end

    // DRAFT: valid/error metadata below still owns every response.  This
    // private payload bank captures a raw return only while no response is
    // held; current owner/error/consume/policy decisions do not gate its D/CE.
    // The S17/S24 quarantine consumer permits arbitrary invalid/error data,
    // checks metadata first, and scrubs before exposing an error response.
    // Not compatible with older consumers requiring zero on this private
    // invalid/error seam.  No response latency or scalar guard is changed.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            runtime_rsp_data_q <= 256'd0;
        else if (!runtime_rsp_valid_q && (phy_rsp_valid === 1'b1))
            runtime_rsp_data_q <= phy_rsp_data;
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_WAIT_CAL;
            fixed_source_seen_q <= 1'b0;
            load_word_q <= MODEL_BASE;
            readback_issue_word_q <= MODEL_BASE;
            readback_receive_word_q <= MODEL_BASE;
            readback_outstanding_q <= 1'b0;
            readback_data_q <= 256'd0;
            readback_valid_q <= 1'b0;
            readback_last_q <= 1'b0;
            runtime_read_outstanding_q <= 1'b0;
            runtime_rsp_valid_q <= 1'b0;
            runtime_rsp_error_q <= 1'b0;
            runtime_offer_valid_q <= 1'b0;
            runtime_offer_legal_q <= 1'b0;
            runtime_offer_write_q <= 1'b0;
            runtime_offer_address_q <= {ADDR_W{1'b0}};
            runtime_offer_data_q <= 256'd0;
            model_locked <= 1'b0;
            fail_closed <= 1'b0;
        end else begin
            // Registered ready/valid ownership.  An invalid descriptor is
            // quarantined with legal_q=0; it cannot assert phy_req_valid and
            // the ST_LOCKED policy branch below makes the state terminal on
            // the following edge.  Simultaneous pop/capture replaces the
            // stage without a bubble for an all-write stream.
            if ((state_q != ST_LOCKED) || fail_closed) begin
                runtime_offer_valid_q <= 1'b0;
            end else begin
                case ({runtime_input_accept, runtime_offer_pop})
                    2'b10, 2'b11: begin
                        runtime_offer_valid_q <= 1'b1;
                        runtime_offer_legal_q <=
                            runtime_input_descriptor_legal;
                        runtime_offer_write_q <= runtime_req_write;
                        runtime_offer_address_q <=
                            runtime_req_word_address;
                        runtime_offer_data_q <= runtime_req_write_data;
                    end
                    2'b01: runtime_offer_valid_q <= 1'b0;
                    default: begin
                    end
                endcase
            end

            if (runtime_rsp_consume) begin
                runtime_rsp_valid_q <= 1'b0;
                runtime_rsp_error_q <= 1'b0;
            end

            if (calib_error || simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_closed <= 1'b1;
                model_locked <= 1'b0;
                if (runtime_read_outstanding_q && !runtime_rsp_valid_q) begin
                    runtime_read_outstanding_q <= 1'b0;
                    runtime_rsp_valid_q <= 1'b1;
                    runtime_rsp_error_q <= 1'b1;
                end
            end else begin
                case (state_q)
                    ST_WAIT_CAL: begin
                        if (phy_rsp_valid === 1'b1) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                        end else if (calib_done === 1'b1) begin
                            state_q <= ST_WAIT_SOURCE;
                        end
                    end
                    ST_WAIT_SOURCE: begin
                        if ((calib_done !== 1'b1) ||
                            (phy_rsp_valid === 1'b1)) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                        end else if (fixed_source_done === 1'b1) begin
                            if (fixed_source_ok === 1'b1) begin
                                fixed_source_seen_q <= 1'b1;
                                load_word_q <= MODEL_BASE;
                                state_q <= ST_LOAD;
                            end else begin
                                state_q <= ST_FAIL;
                                fail_closed <= 1'b1;
                            end
                        end
                    end
                    ST_LOAD: begin
                        if ((calib_done !== 1'b1) ||
                            !fixed_source_seen_q ||
                            (phy_rsp_valid === 1'b1)) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                        end else if (phy_req_valid && phy_req_ready) begin
                            if (load_word_q == MODEL_LAST) begin
                                readback_issue_word_q <= MODEL_BASE;
                                readback_receive_word_q <= MODEL_BASE;
                                readback_outstanding_q <= 1'b0;
                                readback_valid_q <= 1'b0;
                                state_q <= ST_READBACK;
                            end else begin
                                load_word_q <= load_word_q + 1'b1;
                            end
                        end
                    end
                    ST_READBACK: begin
                        if (calib_done !== 1'b1) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                        end else begin
                            if (phy_req_valid && phy_req_ready) begin
                                readback_outstanding_q <= 1'b1;
                                if (readback_issue_word_q != MODEL_LAST)
                                    readback_issue_word_q <=
                                        readback_issue_word_q + 1'b1;
                            end
                            if (phy_rsp_valid === 1'b1) begin
                                if ((phy_rsp_error !== 1'b0) ||
                                    !readback_outstanding_q ||
                                    readback_valid_q) begin
                                    state_q <= ST_FAIL;
                                    fail_closed <= 1'b1;
                                end else begin
                                    readback_outstanding_q <= 1'b0;
                                    readback_data_q <= phy_rsp_data;
                                    readback_valid_q <= 1'b1;
                                    readback_last_q <=
                                        (readback_receive_word_q ==
                                         MODEL_LAST);
                                    if (readback_receive_word_q != MODEL_LAST)
                                        readback_receive_word_q <=
                                            readback_receive_word_q + 1'b1;
                                end
                            end
                            if (readback_valid_q && readback_word_ready) begin
                                readback_valid_q <= 1'b0;
                                if (readback_last_q)
                                    state_q <= ST_WAIT_DIGEST;
                            end
                        end
                    end
                    ST_WAIT_DIGEST: begin
                        if ((calib_done !== 1'b1) ||
                            (phy_rsp_valid === 1'b1)) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                        end else if (readback_digest_done === 1'b1) begin
                            if (readback_digest_ok === 1'b1) begin
                                model_locked <= 1'b1;
                                runtime_read_outstanding_q <= 1'b0;
                                runtime_rsp_valid_q <= 1'b0;
                                state_q <= ST_LOCKED;
                            end else begin
                                state_q <= ST_FAIL;
                                fail_closed <= 1'b1;
                            end
                        end
                    end
                    ST_LOCKED: begin
                        if ((calib_done !== 1'b1) ||
                            runtime_offer_policy_fault ||
                            ((phy_rsp_valid === 1'b1) &&
                             (!runtime_response_has_owner ||
                              runtime_rsp_valid_q))) begin
                            state_q <= ST_FAIL;
                            fail_closed <= 1'b1;
                            model_locked <= 1'b0;
                            if (runtime_read_outstanding_q &&
                                !runtime_rsp_valid_q) begin
                                runtime_read_outstanding_q <= 1'b0;
                                runtime_rsp_valid_q <= 1'b1;
                                runtime_rsp_error_q <= 1'b1;
                            end
                        end else begin
                            if (runtime_read_issue)
                                runtime_read_outstanding_q <= 1'b1;
                            if (phy_rsp_valid === 1'b1) begin
                                runtime_read_outstanding_q <= 1'b0;
                                runtime_rsp_valid_q <= 1'b1;
                                runtime_rsp_error_q <=
                                    (phy_rsp_error !== 1'b0);
                                if (phy_rsp_error !== 1'b0) begin
                                    state_q <= ST_FAIL;
                                    fail_closed <= 1'b1;
                                    model_locked <= 1'b0;
                                end
                            end
                        end
                    end
                    default: begin
                        state_q <= ST_FAIL;
                        fail_closed <= 1'b1;
                        model_locked <= 1'b0;
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    logic formal_past_valid_q;
    always_ff @(posedge clk) begin
        formal_past_valid_q <= 1'b1;
        if (reset_n && phy_req_valid && phy_req_write) begin
            if (state_q == ST_LOAD)
                assert (phy_req_word_addr >= MODEL_BASE &&
                        phy_req_word_addr < MODEL_END);
            else begin
                assert (state_q == ST_LOCKED && model_locked);
                assert (phy_req_word_addr >= SCRATCH_BASE &&
                        phy_req_word_addr < SCRATCH_END);
            end
        end
        if (reset_n && state_q == ST_LOCKED && phy_req_valid &&
            !phy_req_write)
            assert ((phy_req_word_addr >= MODEL_BASE &&
                     phy_req_word_addr < MODEL_END) ||
                    (phy_req_word_addr >= SCRATCH_BASE &&
                     phy_req_word_addr < SCRATCH_END));
        // Boot load/readback traffic legitimately owns phy_req outside
        // ST_LOCKED. The runtime-offer assertions apply only to runtime use.
        if (reset_n && state_q == ST_LOCKED && phy_req_valid) begin
            assert (runtime_offer_valid_q && runtime_offer_legal_q);
            assert (phy_req_word_addr == runtime_offer_address_q);
            if (phy_req_write)
                assert (phy_req_word_addr >= SCRATCH_BASE &&
                        phy_req_word_addr < SCRATCH_END);
        end
        if (formal_past_valid_q && reset_n && $past(reset_n) &&
            $past(runtime_input_accept)) begin
            assert (runtime_offer_valid_q || fail_closed);
            if (!fail_closed) begin
                assert (runtime_offer_address_q ==
                        $past(runtime_req_word_address));
                assert (runtime_offer_write_q ==
                        $past(runtime_req_write));
                assert (runtime_offer_data_q ==
                        $past(runtime_req_write_data));
            end
        end
        if (formal_past_valid_q && reset_n && $past(reset_n) &&
            $past(runtime_input_accept &&
                  !runtime_input_descriptor_legal)) begin
            assert (runtime_offer_valid_q && !runtime_offer_legal_q);
            assert (!phy_req_valid);
        end
        if (formal_past_valid_q && reset_n && $past(reset_n) &&
            $past(runtime_offer_policy_fault))
            assert (fail_closed && !model_locked && !phy_req_valid);
        if (formal_past_valid_q && reset_n && $past(reset_n) &&
            $past(fail_closed))
            assert (fail_closed);
    end
`endif
endmodule

`default_nettype wire
