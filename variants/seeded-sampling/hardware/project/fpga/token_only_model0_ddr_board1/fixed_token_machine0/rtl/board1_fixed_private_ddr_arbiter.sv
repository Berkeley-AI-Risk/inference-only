`timescale 1ns/1ps
`default_nettype none

// Fixed two-client read-only arbiter for the named SimpleStories machine.
// The two clients are structural children, not programmable requesters:
//   * the token shell (embedding and tied output head), and
//   * the exact six-layer semantic service.
// Request ownership is retained in an in-order FIFO so the DDR boundary may
// pipeline reads without ever exposing an address, write, or arbitration
// control above the fixed machine.  CLEAR is deliberately absent: accepted
// reads remain owned until their responses are consumed.
module board1_fixed_private_ddr_arbiter #(
    parameter integer ADDR_W = 25,
    parameter integer MODEL_WORDS = 219382,
    parameter integer OWNER_DEPTH = 16
) (
    input  wire                   clk,
    input  wire                   reset_n,
    input  wire                   model_locked_i,
    input  wire                   upstream_fail_closed_i,
    input  wire                   endpoint_fail_closed_i,

    input  wire                   shell_req_valid_i,
    output logic                  shell_req_ready_o,
    input  wire [ADDR_W-1:0]      shell_req_index_i,
    output logic                  shell_rsp_valid_o,
    input  wire                   shell_rsp_ready_i,
    output logic [255:0]          shell_rsp_data_o,
    output logic                  shell_rsp_fault_o,

    input  wire                   layer_req_valid_i,
    output logic                  layer_req_ready_o,
    input  wire [ADDR_W-1:0]      layer_req_index_i,
    output logic                  layer_rsp_valid_o,
    input  wire                   layer_rsp_ready_i,
    output logic [255:0]          layer_rsp_data_o,
    output logic                  layer_rsp_fault_o,

    output logic                  private_req_valid_o,
    input  wire                   private_req_ready_i,
    output logic [ADDR_W-1:0]     private_req_index_o,
    input  wire                   private_rsp_valid_i,
    output logic                  private_rsp_ready_o,
    input  wire [255:0]           private_rsp_data_i,
    input  wire                   private_rsp_fault_i,

    output logic                  busy_o,
    output logic                  fail_closed_o
);
    localparam integer PTR_W = $clog2(OWNER_DEPTH);
    localparam integer COUNT_W = $clog2(OWNER_DEPTH + 1);
    localparam logic OWNER_SHELL = 1'b0;
    localparam logic OWNER_LAYER = 1'b1;
    localparam logic [ADDR_W-1:0] MODEL_WORD_COUNT = ADDR_W'(MODEL_WORDS);
    localparam logic [COUNT_W:0] OWNER_DEPTH_COUNT =
        (COUNT_W + 1)'(OWNER_DEPTH);

    logic [OWNER_DEPTH-1:0] owner_fifo_q;
    logic [PTR_W-1:0] owner_write_pointer_q;
    logic [PTR_W-1:0] owner_read_pointer_q;
    logic [COUNT_W-1:0] owner_count_q;
    logic lock_seen_q;
    logic fail_q;

    wire have_owner = owner_count_q != {COUNT_W{1'b0}};
    wire owner_is_layer = have_owner ?
        owner_fifo_q[owner_read_pointer_q] : OWNER_SHELL;
    wire owner_space = {1'b0, owner_count_q} < OWNER_DEPTH_COUNT;
    wire exactly_one_request = shell_req_valid_i ^ layer_req_valid_i;
    wire simultaneous_requests = shell_req_valid_i && layer_req_valid_i;
    wire selected_index_valid = shell_req_valid_i ?
        (shell_req_index_i < MODEL_WORD_COUNT) :
        (layer_req_index_i < MODEL_WORD_COUNT);
    wire lock_lost = lock_seen_q && !model_locked_i;
    // A child endpoint failure is combinationally terminal for new requests.
    // Waiting for fail_q to latch would otherwise leave a one-cycle window in
    // which a failed child could still transfer a read into the trusted DDR
    // boundary.  CLEAR is deliberately absent from this arbiter, so ordinary
    // CLEAR drain still routes every saved owner.  Once a terminal fault is
    // present, however, children may be reset and unable to accept a late
    // response; those responses are consumed below solely to retire the saved
    // FIFO ownership and can never be delivered to either child.
    wire request_transfer = private_req_valid_o && private_req_ready_i;
    wire response_transfer = private_rsp_valid_i && private_rsp_ready_o;
    wire response_has_owner = response_transfer && have_owner;

`ifndef SYNTHESIS
    logic simulation_x_fault;
    always_comb begin
        simulation_x_fault = $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(endpoint_fail_closed_i) ||
            $isunknown(shell_req_valid_i) ||
            $isunknown(layer_req_valid_i) ||
            $isunknown(shell_rsp_ready_i) ||
            $isunknown(layer_rsp_ready_i) ||
            $isunknown(private_req_ready_i) ||
            $isunknown(private_rsp_valid_i) ||
            $isunknown(private_rsp_fault_i) ||
            $isunknown(owner_count_q) || $isunknown(fail_q);
        if (shell_req_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(shell_req_index_i);
        if (layer_req_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(layer_req_index_i);
        if (private_rsp_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                                 $isunknown(private_rsp_data_i);
        if (have_owner)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(owner_fifo_q[owner_read_pointer_q]);
    end
`else
    wire simulation_x_fault = 1'b0;
`endif

    // Include same-cycle protocol/integrity evidence, not merely the latched
    // fail bit, so a response coincident with a newly observed terminal fault
    // is never exposed to a child before fail_q updates.
    wire terminal_now = fail_q || upstream_fail_closed_i ||
                        endpoint_fail_closed_i || lock_lost ||
                        simultaneous_requests || simulation_x_fault ||
                        (exactly_one_request && !selected_index_valid) ||
                        (private_rsp_valid_i && !have_owner) ||
                        (private_rsp_valid_i && private_rsp_fault_i);

    always_comb begin
        shell_req_ready_o = 1'b0;
        layer_req_ready_o = 1'b0;
        shell_rsp_valid_o = 1'b0;
        layer_rsp_valid_o = 1'b0;
        // Integration-private payload is meaningful only with VALID.
        // Keep fault/ownership gating on VALID, not these 256 data wires.
        shell_rsp_data_o = private_rsp_data_i;
        // Integration-private payload is meaningful only with VALID.
        // Keep fault/ownership gating on VALID, not these 256 data wires.
        layer_rsp_data_o = private_rsp_data_i;
        shell_rsp_fault_o = 1'b0;
        layer_rsp_fault_o = 1'b0;
        private_req_valid_o = 1'b0;
        private_req_index_o = {ADDR_W{1'b0}};

        if (!terminal_now && model_locked_i && owner_space &&
            exactly_one_request && selected_index_valid) begin
            if (shell_req_valid_i) begin
                private_req_valid_o = 1'b1;
                private_req_index_o = shell_req_index_i;
                shell_req_ready_o = private_req_ready_i;
            end else begin
                private_req_valid_o = 1'b1;
                private_req_index_o = layer_req_index_i;
                layer_req_ready_o = private_req_ready_i;
            end
        end

        // Ordinary operation (including a child-local CLEAR) routes a response
        // to its exact saved owner.  Any terminal fault instead drains/discards
        // late responses and retires their FIFO entries.  This is safe because
        // the arithmetic domain is permanently fail-closed until reset, and it
        // prevents reset children from wedging the authenticated DDR response
        // FIFO.  An unowned response is likewise consumed only to close rather
        // than wedge the private boundary.
        if (terminal_now || !have_owner) begin
            private_rsp_ready_o = 1'b1;
        end else if (owner_is_layer == OWNER_LAYER) begin
            layer_rsp_valid_o = private_rsp_valid_i;
            layer_rsp_data_o = private_rsp_data_i;
            layer_rsp_fault_o = private_rsp_valid_i &&
                                private_rsp_fault_i;
            private_rsp_ready_o = layer_rsp_ready_i;
        end else begin
            shell_rsp_valid_o = private_rsp_valid_i;
            shell_rsp_data_o = private_rsp_data_i;
            shell_rsp_fault_o = private_rsp_valid_i &&
                                private_rsp_fault_i;
            private_rsp_ready_o = shell_rsp_ready_i;
        end

        busy_o = have_owner;
        fail_closed_o = fail_q || upstream_fail_closed_i || lock_lost;
    end

    initial begin
        if ((OWNER_DEPTH < 2) ||
            ((OWNER_DEPTH & (OWNER_DEPTH - 1)) != 0))
            $fatal(1, "OWNER_DEPTH must be a power of two >= 2");
        if ((MODEL_WORDS <= 0) || (ADDR_W < 19) ||
            (MODEL_WORDS > (1 << ADDR_W)))
            $fatal(1, "fixed semantic image does not fit address space");
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            owner_fifo_q <= {OWNER_DEPTH{1'b0}};
            owner_write_pointer_q <= {PTR_W{1'b0}};
            owner_read_pointer_q <= {PTR_W{1'b0}};
            owner_count_q <= {COUNT_W{1'b0}};
            lock_seen_q <= 1'b0;
            fail_q <= 1'b0;
        end else begin
            if (model_locked_i)
                lock_seen_q <= 1'b1;

            if (upstream_fail_closed_i || endpoint_fail_closed_i ||
                lock_lost || simultaneous_requests || simulation_x_fault ||
                (exactly_one_request && !selected_index_valid) ||
                (private_rsp_valid_i && !have_owner) ||
                (private_rsp_valid_i && private_rsp_fault_i))
                fail_q <= 1'b1;

            if (request_transfer) begin
                owner_fifo_q[owner_write_pointer_q] <= layer_req_valid_i ?
                    OWNER_LAYER : OWNER_SHELL;
                owner_write_pointer_q <= owner_write_pointer_q + 1'b1;
            end

            if (response_has_owner)
                owner_read_pointer_q <= owner_read_pointer_q + 1'b1;

            case ({request_transfer, response_has_owner})
                2'b10: owner_count_q <= owner_count_q + 1'b1;
                2'b01: owner_count_q <= owner_count_q - 1'b1;
                default: begin end
            endcase
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n) begin
            assert ({1'b0, owner_count_q} <= OWNER_DEPTH_COUNT);
            assert (!(shell_req_ready_o && layer_req_ready_o));
            assert (!(shell_rsp_valid_o && layer_rsp_valid_o));
            if (private_req_valid_o)
                assert (private_req_index_o < MODEL_WORD_COUNT);
            if (private_rsp_valid_i && have_owner && !terminal_now)
                assert (shell_rsp_valid_o ^ layer_rsp_valid_o);
            if (formal_past_valid && $past(reset_n) &&
                $past(fail_closed_o))
                assert (fail_closed_o);
        end
    end
`endif
endmodule

`default_nettype wire
