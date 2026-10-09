`timescale 1ns/1ps
`default_nettype none

// Return the semantic machine's sticky terminal-fault state to the 100 MHz
// trusted DDR domain.  The source is a level, never a pulse; the destination
// synchronizes it and latches it until either domain is reset.  This is the
// only semantic status allowed to influence the boot/runtime memory boundary.
module board1_fixed_endpoint_fault_cdc (
    input  wire core_reset_n_i,
    input  wire core_fail_closed_i,
    input  wire app_clk_i,
    input  wire app_reset_n_i,
    output wire app_fail_closed_o
);
    (* async_reg = "true", syn_preserve = 1 *) logic [1:0] fail_sync_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] app_reset_release_q;
    logic app_fail_q;
    wire crossing_async_reset_n = core_reset_n_i && app_reset_n_i;
    wire app_local_reset_n = app_reset_release_q[2];

    // Assertion from either domain is asynchronous and therefore immediate;
    // release is delayed and aligned to app_clk_i before any status flop can
    // leave reset.
    always_ff @(posedge app_clk_i or negedge crossing_async_reset_n) begin
        if (!crossing_async_reset_n)
            app_reset_release_q <= 3'b000;
        else
            app_reset_release_q <= {app_reset_release_q[1:0], 1'b1};
    end

    always_ff @(posedge app_clk_i or negedge app_local_reset_n) begin
        if (!app_local_reset_n) begin
            fail_sync_q <= 2'b00;
            app_fail_q <= 1'b0;
        end else begin
            fail_sync_q <= {fail_sync_q[0], core_fail_closed_i};
            if (fail_sync_q[1])
                app_fail_q <= 1'b1;
        end
    end

    assign app_fail_closed_o = app_fail_q;

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge app_clk_i) begin
        formal_past_valid <= 1'b1;
        if (app_reset_n_i && core_reset_n_i && formal_past_valid &&
            $past(app_reset_n_i) && $past(core_reset_n_i) &&
            $past(app_fail_closed_o))
            assert (app_fail_closed_o);
    end
`endif
endmodule

`default_nettype wire
