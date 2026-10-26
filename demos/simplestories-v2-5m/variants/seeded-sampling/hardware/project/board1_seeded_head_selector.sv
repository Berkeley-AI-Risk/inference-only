// PRIVATE ROM packing: k4096 sentinel never consumes ROM value.
// PRIVATE compact arithmetic contingency. Original source retained separately.
`timescale 1ns/1ps
`default_nettype none

// PRIVATE fixed-model component, not a chip-level arithmetic or logit API.
// See ../README.md for finite distribution and ownership/reset contract.
module board1_seeded_head_selector #(
    parameter EXP_FILE = "model_rtl_evidence/attention_sublayer/exp_neg_q30.memh"
) (
    input wire clk, reset_n, clear_i, model_locked_i, upstream_fail_closed_i,
    input wire settings_valid_i,
    output wire settings_ready_o,
    input wire settings_empty_boundary_i,
    input wire [2:0] settings_temperature_i,
    input wire [127:0] settings_seed_i,
    output logic settings_accepted_o, settings_rejected_o,
    input wire start_valid_i,
    output wire start_ready_o,
    input wire row_valid_i,
    output wire row_ready_o,
    input wire [12:0] row_index_i,
    input wire signed [49:0] row_scaled_raw_i,
    input wire signed [7:0] row_source_exponent_i,
    input wire row_last_i,
    output wire winner_valid_o,
    input wire winner_ready_i,
    output wire [11:0] winner_token_id_o,
    output wire signed [49:0] winner_scaled_raw_o,
    output wire signed [7:0] winner_source_exponent_o,
    output wire busy_o, fail_closed_o
);
    localparam [4:0] IDLE=0, COLLECT=1, ROW_READ=2, GAP=3, INDEX=4,
        LUT_READ=5, STORE=6, RNG_ADD=7, RNG_OUT=8, MULTIPLY=9,
        CDF_READ=10, CDF_CHECK=11, WINNER=12, FAIL=31;
    logic [4:0] state_q;
    logic fail_q;
    logic [1:0] temperature_q;
    logic [127:0] seed_q;
    logic [63:0] rng_lo_q, rng_hi_q;
    logic signed [8:0] zero_exponent_q;
    logic signed [51:0] maximum_q, row_read_q;
    logic [52:0] gap_q;
    logic [12:0] lut_index_q;
    logic [31:0] lut_read_q;
    logic [11:0] cursor_q, sampled_token_q;
    logic [41:0] total_q, target_q, cumulative_q;
    logic [30:0] weight_read_q;
    logic [105:0] product_q;
    logic [5:0] multiply_bit_q;
    (* ram_style="block", syn_ramstyle="block_ram" *)
        logic signed [51:0] logits [0:4018];
    (* ram_style="block", syn_ramstyle="block_ram" *)
        logic [30:0] mass [0:4018];
    (* ram_style="block", rom_style="block", nomem2reg *)
        logic [31:0] exponential [0:4096];
    initial $readmemh(EXP_FILE, exponential);

    wire greedy_start_ready, greedy_row_ready, greedy_winner_valid;
    wire [11:0] greedy_token;
    wire signed [49:0] greedy_raw;
    wire signed [7:0] greedy_exponent;
    wire greedy_busy, greedy_fault;
    wire live = model_locked_i && !clear_i && !upstream_fail_closed_i &&
                !fail_q && !greedy_fault;
    assign settings_ready_o = state_q == IDLE && live;
    assign start_ready_o = state_q == IDLE && live &&
                           !settings_valid_i && greedy_start_ready;
    wire start_fire = start_valid_i && start_ready_o;
    assign row_ready_o = state_q == COLLECT && live && greedy_row_ready;
    wire row_fire = row_valid_i && row_ready_o;
    wire greedy_mode = temperature_q == 0;
    wire internal_greedy_ready = state_q == COLLECT && live &&
                                (!greedy_mode || winner_ready_i);
    assign winner_valid_o = live && ((greedy_mode && state_q == COLLECT &&
                                  greedy_winner_valid) || state_q == WINNER);
    assign winner_token_id_o = !winner_valid_o ? 12'd0 :
                              (greedy_mode ? greedy_token : sampled_token_q);
    // Numerical winner carriers are meaningful only in greedy mode. The
    // production shell does not consume them, and no chip pin exposes them.
    assign winner_scaled_raw_o = winner_valid_o && greedy_mode ? greedy_raw : 50'sd0;
    assign winner_source_exponent_o = winner_valid_o && greedy_mode ? greedy_exponent : 8'sd0;
    assign busy_o = state_q != IDLE && state_q != FAIL;
    assign fail_closed_o = fail_q || greedy_fault || upstream_fail_closed_i;

    // This is the byte-identical released implementation, including checks,
    // strict tie behavior and ready/valid timing. Never replace T=0 by a
    // rounded approximation of its signed/exponent comparison.
    board1_fixed_head_argmax u_original_argmax (
        .clk(clk), .reset_n(reset_n), .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(upstream_fail_closed_i || fail_q),
        .start_valid_i(start_fire), .start_ready_o(greedy_start_ready),
        .row_valid_i(row_valid_i && state_q == COLLECT),
        .row_ready_o(greedy_row_ready), .row_index_i(row_index_i),
        .row_scaled_raw_i(row_scaled_raw_i),
        .row_source_exponent_i(row_source_exponent_i), .row_last_i(row_last_i),
        .winner_valid_o(greedy_winner_valid),
        .winner_ready_i(internal_greedy_ready), .winner_token_id_o(greedy_token),
        .winner_scaled_raw_o(greedy_raw),
        .winner_source_exponent_o(greedy_exponent),
        .busy_o(greedy_busy), .fail_closed_o(greedy_fault)
    );

    function automatic [63:0] rotate(input [63:0] value, input integer amount);
        rotate = (value << amount) | (value >> (64-amount));
    endfunction
    function automatic signed [51:0] align_logit(
        input signed [49:0] raw, input signed [8:0] exponent,
        input signed [8:0] zero_exponent);
        case (exponent - zero_exponent)
            0: align_logit = {raw, 2'b00};
            -1: align_logit = {raw[49], raw, 1'b0};
            -2: align_logit = {{2{raw[49]}},raw};
            default: align_logit = 52'sd0; // original selector faults first
        endcase
    endfunction
    function automatic [12:0] quantize_gap(
        input [52:0] gap, input signed [9:0] shift);
        reg [52:0] shifted;
        integer right_shift;
        begin
            shifted = 0;
            right_shift = 0;
            if (gap == 0) quantize_gap = 0;
            else if (shift >= 12) quantize_gap = 4096;
            else if (shift >= 0) begin
                // Clip first. A left shift is never allowed to discard a
                // high bit and accidentally turn a far-tail row into max.
                if (gap >= (53'd4096 >> shift)) quantize_gap = 4096;
                else quantize_gap = 13'(gap << shift);
            end else begin
                right_shift = -integer'(shift);
                if (right_shift >= 53) quantize_gap = 0;
                else begin
                    shifted = gap >> right_shift;
                    quantize_gap = shifted >= 4096 ? 13'd4096 : shifted[12:0];
                end
            end
        end
    endfunction
    wire signed [9:0] gap_shift =
        $signed({zero_exponent_q[8],zero_exponent_q}) + 10'sd6 +
        (temperature_q == 1 ? 10'sd1 : temperature_q == 3 ? -10'sd1 : 10'sd0);
    wire [63:0] mixed_rng = rng_lo_q ^ rng_hi_q;
    // Combined-register exact64-step product. total_q is frozen
    // throughout RNG_ADD..WINNER; no duplicate mass register is necessary.
    wire [42:0] multiply_high_sum = {1'b0,product_q[105:64]} +
        (product_q[0] ? {1'b0,total_q} : 43'd0);
    wire [105:0] product_next = {multiply_high_sum,product_q[63:1]};
    wire [63:0] prepared_random = rotate(product_q[63:0],17) + rng_lo_q;
    wire [41:0] cumulative_next = cumulative_q + {11'd0,weight_read_q};
    wire invalid_lut = lut_index_q < 4096 &&
        (lut_read_q == 0 || lut_read_q > 32'd1073741824);
    wire [30:0] next_weight = lut_index_q == 4096 ? 31'd0 : lut_read_q[30:0];
`ifndef SYNTHESIS
    wire settings_x_fault = $isunknown(settings_valid_i) || $isunknown(state_q) ||
        (settings_valid_i === 1'b1 && $isunknown({settings_temperature_i,
                                               settings_seed_i,settings_empty_boundary_i}));
`else
    wire settings_x_fault = 1'b0;
`endif

    // No reset or CLEAR writes to RAM. State and monotonically checked row
    // ownership authorize reads only after the entire new head is accepted.
    always_ff @(posedge clk) begin
        if (row_fire && !greedy_mode && row_index_i < 4019)
            logits[row_index_i[11:0]] <= align_logit(row_scaled_raw_i,
                $signed({row_source_exponent_i[7],row_source_exponent_i}),
                row_index_i == 0 ?
                    $signed({row_source_exponent_i[7],row_source_exponent_i}) : zero_exponent_q);
        if (state_q == ROW_READ) row_read_q <= logits[cursor_q];
        if (state_q == LUT_READ) lut_read_q <= exponential[{1'b0,lut_index_q[11:0]}];
        if (state_q == STORE && live && !invalid_lut) mass[cursor_q] <= next_weight;
        if (state_q == CDF_READ) weight_read_q <= mass[cursor_q];
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE; fail_q <= 0; temperature_q <= 0; seed_q <= 128'd1;
            rng_lo_q <= 1; rng_hi_q <= 0;
            settings_accepted_o <= 0; settings_rejected_o <= 0;
            zero_exponent_q <= 0; maximum_q <= 0; gap_q <= 0;
            lut_index_q <= 0; cursor_q <= 0; sampled_token_q <= 0;
            total_q <= 0; target_q <= 0; cumulative_q <= 0;
            product_q <= 0; multiply_bit_q <= 0;
        end else begin
            settings_accepted_o <= 0; settings_rejected_o <= 0;
            if (fail_q || greedy_fault || upstream_fail_closed_i || settings_x_fault ||
                (state_q != IDLE && !model_locked_i)) begin
                state_q <= FAIL; fail_q <= 1;
            end else if (clear_i) begin
                state_q <= IDLE;
                rng_lo_q <= seed_q[63:0]; rng_hi_q <= seed_q[127:64];
                cursor_q <= 0; total_q <= 0; cumulative_q <= 0;
            end else begin
                case (state_q)
                    IDLE: begin
                        if (settings_valid_i && settings_ready_o) begin
                            if (!settings_empty_boundary_i || settings_temperature_i > 3)
                                settings_rejected_o <= 1;
                            else begin
                                temperature_q <= settings_temperature_i[1:0];
                                seed_q <= settings_seed_i == 0 ? 128'd1 : settings_seed_i;
                                rng_lo_q <= settings_seed_i == 0 ? 64'd1 : settings_seed_i[63:0];
                                rng_hi_q <= settings_seed_i[127:64];
                                settings_accepted_o <= 1;
                            end
                        end else if (start_fire) begin
                            state_q <= COLLECT;
                            cursor_q <= 0; total_q <= 0; cumulative_q <= 0;
                        end
                    end
                    COLLECT: begin
                        if (row_fire && row_index_i == 0)
                            zero_exponent_q <= $signed({row_source_exponent_i[7],row_source_exponent_i});
                        if (greedy_winner_valid && internal_greedy_ready) begin
                            if (greedy_mode) state_q <= IDLE;
                            else begin
                                maximum_q <= align_logit(greedy_raw,
                                    $signed({greedy_exponent[7],greedy_exponent}),zero_exponent_q);
                                state_q <= ROW_READ;
                            end
                        end
                    end
                    ROW_READ: state_q <= GAP;
                    GAP: begin
                        gap_q <= $signed({maximum_q[51],maximum_q}) -
                                 $signed({row_read_q[51],row_read_q});
                        state_q <= INDEX;
                    end
                    INDEX: begin lut_index_q <= quantize_gap(gap_q,gap_shift); state_q <= LUT_READ; end
                    LUT_READ: state_q <= STORE;
                    STORE: begin
                        if (invalid_lut) begin state_q <= FAIL; fail_q <= 1; end
                        else begin
                            total_q <= total_q + {11'd0,next_weight};
                            if (cursor_q == 4018) begin cursor_q <= 0; state_q <= RNG_ADD; end
                            else begin cursor_q <= cursor_q + 1'b1; state_q <= ROW_READ; end
                        end
                    end
                    RNG_ADD: begin
                        product_q <= {42'd0,rng_lo_q + rng_hi_q}; state_q <= RNG_OUT;
                    end
                    RNG_OUT: begin
                        product_q <= {42'd0,prepared_random}; multiply_bit_q <= 0;
                        state_q <= MULTIPLY;
                    end
                    MULTIPLY: begin
                        product_q <= product_next;
                        if (multiply_bit_q == 63) begin
                            target_q <= product_next[105:64]; state_q <= CDF_READ;
                        end else multiply_bit_q <= multiply_bit_q + 1'b1;
                    end
                    CDF_READ: state_q <= CDF_CHECK;
                    CDF_CHECK: begin
                        if (cumulative_next > target_q) begin
                            sampled_token_q <= cursor_q; state_q <= WINNER;
                        end else if (cursor_q == 4018) begin state_q <= FAIL; fail_q <= 1; end
                        else begin
                            cumulative_q <= cumulative_next; cursor_q <= cursor_q + 1'b1;
                            state_q <= CDF_READ;
                        end
                    end
                    WINNER: if (winner_valid_o && winner_ready_i) begin
                        // State was unchanged since RNG_OUT, so f(state) here is
                        // exactly the old pending next-state. Commit ONLY on
                        // this owned winner handshake; stall/CLEAR/fault rules
                        // and greedy bypass remain unchanged.
                        rng_lo_q <= rotate(rng_lo_q,49) ^ mixed_rng ^ (mixed_rng << 21);
                        rng_hi_q <= rotate(mixed_rng,28); state_q <= IDLE;
                    end
                    default: begin state_q <= FAIL; fail_q <= 1; end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
