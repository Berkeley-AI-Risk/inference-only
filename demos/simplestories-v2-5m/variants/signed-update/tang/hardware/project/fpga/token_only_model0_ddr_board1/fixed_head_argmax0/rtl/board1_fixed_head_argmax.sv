`timescale 1ns/1ps
`default_nettype none

// Private exact greedy selector for the fixed 4,019-row tied vocabulary head.
//
// The input is the ordered scaled-row stream produced by the fixed head job.
// Row zero's tied-head exponent is immutably -10.  Every later row exponent in
// the selected model is -10, -11, or -12, so after adding the one common
// activation exponent every legal source exponent is row-zero's exponent,
// row-zero minus one, or row-zero minus two.  Enforcing that relation both
// keeps the exact comparison carrier bounded and rejects a corrupted metadata
// schedule.  Only a strictly larger logit replaces the incumbent; therefore
// the lowest token ID wins an exact tie, matching the accepted model oracle.
//
// This is an integration-private fixed-model service.  It is not a product
// operation and exposes no programmable length, address, exponent policy, or
// general comparison interface at the chip boundary.
module board1_fixed_head_argmax (
    input  wire                    clk,
    input  wire                    reset_n,
    input  wire                    clear_i,
    input  wire                    model_locked_i,
    input  wire                    upstream_fail_closed_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,

    input  wire                    row_valid_i,
    output logic                   row_ready_o,
    input  wire [12:0]             row_index_i,
    input  wire signed [49:0]      row_scaled_raw_i,
    input  wire signed [7:0]       row_source_exponent_i,
    input  wire                    row_last_i,

    output logic                   winner_valid_o,
    input  wire                    winner_ready_i,
    output logic [11:0]            winner_token_id_o,
    output logic signed [49:0]     winner_scaled_raw_o,
    output logic signed [7:0]      winner_source_exponent_o,

    output logic                   busy_o,
    output logic                   fail_closed_o
);
    localparam logic [12:0] FINAL_ROW = 13'd4018;

    typedef enum logic [2:0] {
        ST_IDLE   = 3'd0,
        ST_ROWS   = 3'd1,
        ST_WINNER = 3'd2,
        ST_FAIL   = 3'd3,
        ST_COMPARE = 3'd4
    } state_t;

    state_t state_q;
    logic [12:0] expected_row_q;
    logic best_valid_q;
    logic [11:0] best_token_q;
    logic signed [49:0] best_scaled_q;
    logic signed [7:0] best_exponent_q;
    logic signed [7:0] row_zero_exponent_q;
    logic fail_q;
    // One integration-private accepted row. State, not reset payload bits,
    // confers ownership; invalid or CLEAR-revoked rows can never be compared.
    logic [11:0] pending_token_q;
    logic signed [49:0] pending_scaled_q;
    logic signed [7:0] pending_exponent_q;

    logic row_fire;
    logic row_last_expected;
    logic row_exponent_legal;
    logic row_legal;
    logic row_better;
    wire exact_row_greater;
    logic signed [8:0] current_exponent_wide;
    logic signed [8:0] row_zero_exponent_wide;

`ifndef SYNTHESIS
    logic simulation_x_fault;
`endif

    board1_fixed_head_logit_greater u_exact_compare (
        .left_value_i(pending_scaled_q),
        .left_exponent_i(pending_exponent_q),
        .right_value_i(best_scaled_q),
        .right_exponent_i(best_exponent_q),
        .greater_o(exact_row_greater)
    );

    always @* begin
        start_ready_o = (state_q == ST_IDLE) && model_locked_i &&
                        !upstream_fail_closed_i && !fail_q && !clear_i;
        row_ready_o = (state_q == ST_ROWS) && model_locked_i &&
                      !upstream_fail_closed_i && !fail_q && !clear_i;
        winner_valid_o = (state_q == ST_WINNER) && model_locked_i &&
                         !upstream_fail_closed_i && !fail_q && !clear_i;
        winner_token_id_o = winner_valid_o ? best_token_q : 12'd0;
        winner_scaled_raw_o = winner_valid_o ? best_scaled_q : 50'sd0;
        winner_source_exponent_o = winner_valid_o ? best_exponent_q : 8'sd0;
        busy_o = (state_q != ST_IDLE) && (state_q != ST_FAIL);
        fail_closed_o = fail_q || upstream_fail_closed_i ||
                        (state_q == ST_FAIL);

        row_fire = row_valid_i && row_ready_o;
        row_last_expected = (expected_row_q == FINAL_ROW);
        current_exponent_wide = {row_source_exponent_i[7],
                                 row_source_exponent_i};
        row_zero_exponent_wide = {row_zero_exponent_q[7],
                                  row_zero_exponent_q};
        row_exponent_legal = (expected_row_q == 13'd0) ||
            (current_exponent_wide == row_zero_exponent_wide) ||
            (current_exponent_wide == row_zero_exponent_wide - 9'sd1) ||
            (current_exponent_wide == row_zero_exponent_wide - 9'sd2);
        row_legal = (row_index_i == expected_row_q) &&
                    (row_last_i == row_last_expected) &&
                    row_exponent_legal;
        row_better = !best_valid_q || exact_row_greater;
    end

`ifndef SYNTHESIS
    always @* begin
        simulation_x_fault = $isunknown(reset_n) || $isunknown(clear_i) ||
            $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) ||
            $isunknown(start_valid_i) || $isunknown(row_valid_i) ||
            $isunknown(winner_ready_i) || $isunknown(state_q) ||
            $isunknown(fail_q);
        if (row_valid_i === 1'b1)
            simulation_x_fault = simulation_x_fault ||
                $isunknown(row_index_i) ||
                $isunknown(row_scaled_raw_i) ||
                $isunknown(row_source_exponent_i) ||
                $isunknown(row_last_i);
    end
`endif

    always_ff @(posedge clk) begin
        if (reset_n && row_fire) begin
            pending_token_q <= row_index_i[11:0];
            pending_scaled_q <= row_scaled_raw_i;
            pending_exponent_q <= row_source_exponent_i;
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= ST_IDLE;
            expected_row_q <= 13'd0;
            best_valid_q <= 1'b0;
            best_token_q <= 12'd0;
            best_scaled_q <= 50'sd0;
            best_exponent_q <= 8'sd0;
            row_zero_exponent_q <= 8'sd0;
            fail_q <= 1'b0;
        end else begin
`ifndef SYNTHESIS
            if (simulation_x_fault) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else
`endif
            if ((state_q == ST_FAIL) || fail_q ||
                upstream_fail_closed_i) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else if (((state_q != ST_IDLE) && !model_locked_i) ||
                         (row_fire && !row_legal)) begin
                state_q <= ST_FAIL;
                fail_q <= 1'b1;
            end else if (clear_i) begin
                state_q <= ST_IDLE;
                expected_row_q <= 13'd0;
                best_valid_q <= 1'b0;
                best_token_q <= 12'd0;
                best_scaled_q <= 50'sd0;
                best_exponent_q <= 8'sd0;
                row_zero_exponent_q <= 8'sd0;
            end else begin
                case (state_q)
                    ST_IDLE: begin
                        expected_row_q <= 13'd0;
                        best_valid_q <= 1'b0;
                        best_token_q <= 12'd0;
                        best_scaled_q <= 50'sd0;
                        best_exponent_q <= 8'sd0;
                        row_zero_exponent_q <= 8'sd0;
                        if (start_valid_i && start_ready_o)
                            state_q <= ST_ROWS;
                    end

                    ST_ROWS: begin
                        if (row_fire)
                            state_q <= ST_COMPARE;
                    end

                    ST_COMPARE: begin
                        if (expected_row_q == 13'd0)
                            row_zero_exponent_q <=
                                pending_exponent_q;
                        if (row_better) begin
                            best_valid_q <= 1'b1;
                            best_token_q <= pending_token_q;
                            best_scaled_q <= pending_scaled_q;
                            best_exponent_q <= pending_exponent_q;
                        end
                        if (expected_row_q == FINAL_ROW) begin
                            state_q <= ST_WINNER;
                            expected_row_q <= 13'd0;
                        end else begin
                            expected_row_q <= expected_row_q + 13'd1;
                            state_q <= ST_ROWS;
                        end
                    end

                    ST_WINNER: begin
                        if (winner_valid_o && winner_ready_i)
                            state_q <= ST_IDLE;
                    end

                    default: begin
                        state_q <= ST_FAIL;
                        fail_q <= 1'b1;
                    end
                endcase
            end
        end
    end
`ifndef SYNTHESIS
    logic pending_owned_q;
    logic [69:0] pending_shadow_q;
    logic [12:0] pending_expected_row_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            pending_owned_q <= 1'b0;
        else if (clear_i || simulation_x_fault || upstream_fail_closed_i ||
                 !model_locked_i || fail_q || state_q == ST_FAIL)
            pending_owned_q <= 1'b0;
        else begin
            if (row_fire && row_legal) begin
                if (pending_owned_q !== 1'b0 || state_q != ST_ROWS)
                    $fatal(1,"head row accepted with an existing owner");
                pending_shadow_q <= {row_index_i[11:0], row_scaled_raw_i,
                                     row_source_exponent_i};
                pending_expected_row_q <= expected_row_q;
                pending_owned_q <= 1'b1;
            end
            if (state_q == ST_COMPARE) begin
                if (pending_owned_q !== 1'b1 || row_ready_o || row_fire ||
                    expected_row_q !== pending_expected_row_q ||
                    {pending_token_q,pending_scaled_q,pending_exponent_q} !== pending_shadow_q)
                    $fatal(1,"head compare lacks its exact owned row");
                pending_owned_q <= 1'b0;
            end
            if (state_q == ST_WINNER && pending_owned_q !== 1'b0)
                $fatal(1,"head winner published with an unconsumed row");
        end
    end
`endif
endmodule

`default_nettype wire
