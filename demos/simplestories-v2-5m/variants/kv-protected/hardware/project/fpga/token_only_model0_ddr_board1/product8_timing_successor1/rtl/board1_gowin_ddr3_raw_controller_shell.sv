`timescale 1ns/1ps
`default_nettype none

// Additive Board1 timing/safety successor raw controller shell.
//
// Relative to timing_successor0, raw DDR calibration is qualified by a
// standard asynchronously-asserted, synchronously-released two-FF chain.
// A loss therefore clears the private controller-good level immediately;
// recovery still needs two clean application-clock edges and the enclosing
// locked boundary makes any post-calibration loss terminal and sticky.
// Successor3 additionally obeys the DDR IP's documented reset contract: the
// reset delivered to the IP asserts asynchronously with the package button but
// can release only after three clean rising edges of the IP's continuous
// low-speed clk input.
module board1_gowin_ddr3_raw_controller_shell (
    input  wire         clk_50mhz,
    input  wire         reset_button_n,

    output wire         trusted_clk_25mhz_o,
    output wire         core_clk_25mhz_o,
    output wire         trusted_reset_n_o,
    output wire         app_clk_100mhz_o,
    output wire         app_reset_n_o,
    output wire         controller_pll_lock_o,
    output wire         controller_init_calib_complete_o,

    output wire         app_cmd_ready_o,
    input  wire [2:0]   app_cmd_i,
    input  wire         app_cmd_en_i,
    input  wire [28:0]  app_addr_i,
    output wire         app_wr_data_ready_o,
    input  wire [255:0] app_wr_data_i,
    input  wire         app_wr_data_en_i,
    input  wire         app_wr_data_end_i,
    input  wire [31:0]  app_wr_data_mask_i,
    output wire [255:0] app_rd_data_o,
    output wire         app_rd_data_valid_o,
    output wire         app_rd_data_end_o,
    input  wire         app_burst_i,
    input  wire         app_self_refresh_req_i,
    input  wire         app_refresh_req_i,

    output wire [14:0]  ddr_addr,
    output wire [2:0]   ddr_bank,
    output wire         ddr_cs,
    output wire         ddr_ras,
    output wire         ddr_cas,
    output wire         ddr_we,
    output wire         ddr_ck,
    output wire         ddr_ck_n,
    output wire         ddr_cke,
    output wire         ddr_odt,
    output wire         ddr_reset_n,
    output wire [3:0]   ddr_dm,
    inout  wire [31:0]  ddr_dq,
    inout  wire [3:0]   ddr_dqs,
    inout  wire [3:0]   ddr_dqs_n
);
    wire pll_lock;
    wire pll_clkout0_400mhz;
    wire pll_clkout1_50mhz;
    wire memory_clk_400mhz;
    wire pll_stop;
    wire app_clk_100mhz;
    wire controller_ddr_reset;
    wire controller_init_calib_complete_raw;
    wire app_self_refresh_ack;
    wire app_refresh_ack;

    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] trusted_reset_release_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] app_reset_release_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic [2:0] ddr_ip_reset_release_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic controller_pll_lock_app_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic controller_pll_lock_app_sync2_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic controller_calib_app_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic controller_calib_app_sync2_q;

    // Separate private permission; vendor PLL/IP startup wiring is unchanged.
    wire controller_clock_reset_n;
    board1_pll_lock_qualifier u_private_pll_qualifier (
        .clk_50mhz(clk_50mhz), .reset_button_n(reset_button_n),
        .pll_lock_i(pll_lock), .qualified_o(controller_clock_reset_n)
    );
    // Terminate the long board-reset route in the 50-MHz domain.
    // This preserved local stage drives only the five application
    // reset/status synchronizer registers. Assertion does not wait
    // for either clock; release waits for a board edge followed by
    // the existing application-domain release chain.
    (* syn_preserve = 1 *) logic app_reset_local_q;
    always_ff @(posedge clk_50mhz or negedge controller_clock_reset_n) begin
        if (!controller_clock_reset_n)
            app_reset_local_q <= 1'b0;
        else
            app_reset_local_q <= 1'b1;
    end

    wire ddr_ip_reset_n = ddr_ip_reset_release_q[2];
    // Calibration-good is a permission.  Its removal must be fail-fast, while
    // its grant may be delayed.  Holding this two-FF chain in asynchronous
    // reset while raw calibration is low provides exactly that polarity.
    // Assert via the existing asynchronous app-reset chain, but release
    // permission only after that local three-edge release is complete.
    // Raw calibration loss still clears both status stages without
    // waiting for an application-clock edge.
    wire controller_calib_status_reset_n =
        app_reset_release_q[2] && controller_init_calib_complete_raw;

    // The DDR IP requires rst_n deassertion synchronized to its low-speed clk,
    // which is this continuous board 50 MHz clock. Assertion remains
    // asynchronous so reset during controller activity closes immediately.
    always_ff @(posedge clk_50mhz or negedge reset_button_n) begin
        if (!reset_button_n)
            ddr_ip_reset_release_q <= 3'b000;
        else
            ddr_ip_reset_release_q <=
                {ddr_ip_reset_release_q[1:0], 1'b1};
    end

    // Package reset or raw PLL loss asserts both domain resets
    // asynchronously.  Release takes three clean local-domain edges.
    always_ff @(posedge trusted_clk_25mhz_o or
               negedge controller_clock_reset_n) begin
        if (!controller_clock_reset_n)
            trusted_reset_release_q <= 3'b000;
        else
            trusted_reset_release_q <=
                {trusted_reset_release_q[1:0], 1'b1};
    end

    always_ff @(posedge app_clk_100mhz or
               negedge app_reset_local_q) begin
        if (!app_reset_local_q) begin
            app_reset_release_q <= 3'b000;
            controller_pll_lock_app_sync1_q <= 1'b0;
            controller_pll_lock_app_sync2_q <= 1'b0;
        end else begin
            app_reset_release_q <= {app_reset_release_q[1:0], 1'b1};
            controller_pll_lock_app_sync1_q <= pll_lock;
            controller_pll_lock_app_sync2_q <=
                controller_pll_lock_app_sync1_q;
        end
    end

    // Standard asynchronous-assert/synchronous-release synchronizer.  A raw
    // calibration loss clears both stages without waiting for app_clk.  A raw
    // rise only shifts a one through the two stages on clean app-clock edges.
    always_ff @(posedge app_clk_100mhz or
               negedge controller_calib_status_reset_n) begin
        if (!controller_calib_status_reset_n) begin
            controller_calib_app_sync1_q <= 1'b0;
            controller_calib_app_sync2_q <= 1'b0;
        end else begin
            controller_calib_app_sync1_q <= 1'b1;
            controller_calib_app_sync2_q <= controller_calib_app_sync1_q;
        end
    end

    assign trusted_reset_n_o = trusted_reset_release_q[2];
    assign app_clk_100mhz_o = app_clk_100mhz;
    assign app_reset_n_o = app_reset_release_q[2];
    assign controller_pll_lock_o = controller_pll_lock_app_sync2_q;
    assign controller_init_calib_complete_o =
        controller_calib_app_sync2_q;

    Gowin_PLL u_board_ddr_pll (
        .lock(pll_lock),
        .clkout0(pll_clkout0_400mhz),
        .clkout1(pll_clkout1_50mhz),
        .clkout2(memory_clk_400mhz),
        .clkin(clk_50mhz),
        .init_clk(clk_50mhz),
        .reset(!reset_button_n),
        .enclk0(1'b1),
        .enclk1(1'b1),
        .enclk2(pll_stop)
    );

    // A native clock-tree divide-by-four produces the conservative 12.5 MHz
    // semantic/trusted clock selected by timing_successor0.
    CLKDIV u_trusted_clkdiv (
        .HCLKIN(pll_clkout1_50mhz),
        .RESETN(reset_button_n && pll_lock),
        .CALIB(1'b0),
        .CLKOUT(trusted_clk_25mhz_o)
    );
    defparam u_trusted_clkdiv.DIV_MODE = "4";

    // Separate fixed inference clock; DDR reference/app/memory clocks stay unchanged.
    CLKDIV u_core_clkdiv (
        .HCLKIN(pll_clkout1_50mhz),
        .RESETN(reset_button_n && pll_lock),
        .CALIB(1'b0),
        .CLKOUT(core_clk_25mhz_o)
    );
    defparam u_core_clkdiv.DIV_MODE = "2";

    DDR3_Memory_Interface_Top u_ddr3 (
        .clk(clk_50mhz),
        .pll_stop(pll_stop),
        .memory_clk(memory_clk_400mhz),
        .pll_lock(pll_lock),
        .rst_n(ddr_ip_reset_n),
        .clk_out(app_clk_100mhz),
        .ddr_rst(controller_ddr_reset),
        .init_calib_complete(controller_init_calib_complete_raw),
        .cmd_ready(app_cmd_ready_o),
        .cmd(app_cmd_i),
        .cmd_en(app_cmd_en_i),
        .addr(app_addr_i),
        .wr_data_rdy(app_wr_data_ready_o),
        .wr_data(app_wr_data_i),
        .wr_data_en(app_wr_data_en_i),
        .wr_data_end(app_wr_data_end_i),
        .wr_data_mask(app_wr_data_mask_i),
        .rd_data(app_rd_data_o),
        .rd_data_valid(app_rd_data_valid_o),
        .rd_data_end(app_rd_data_end_o),
        .sr_req(app_self_refresh_req_i),
        .ref_req(app_refresh_req_i),
        .sr_ack(app_self_refresh_ack),
        .ref_ack(app_refresh_ack),
        .burst(app_burst_i),
        .O_ddr_addr(ddr_addr),
        .O_ddr_ba(ddr_bank),
        .O_ddr_cs_n(ddr_cs),
        .O_ddr_ras_n(ddr_ras),
        .O_ddr_cas_n(ddr_cas),
        .O_ddr_we_n(ddr_we),
        .O_ddr_clk(ddr_ck),
        .O_ddr_clk_n(ddr_ck_n),
        .O_ddr_cke(ddr_cke),
        .O_ddr_odt(ddr_odt),
        .O_ddr_reset_n(ddr_reset_n),
        .O_ddr_dqm(ddr_dm),
        .IO_ddr_dq(ddr_dq),
        .IO_ddr_dqs(ddr_dqs),
        .IO_ddr_dqs_n(ddr_dqs_n)
    );

    // Audited but intentionally non-public controller status/clock outputs.
    wire _unused_controller_reset = controller_ddr_reset;
    wire _unused_self_refresh_ack = app_self_refresh_ack;
    wire _unused_refresh_ack = app_refresh_ack;
    wire _unused_pll_clkout0 = pll_clkout0_400mhz;

`ifdef FORMAL
    // Once raw calibration is absent, permission must be absent regardless of
    // application-clock progress.  Command suppression itself is asserted in
    // the enclosing locked-boundary formal harness, where app_cmd_en exists.
    always_comb begin
        if (!controller_init_calib_complete_raw)
            assert (!controller_init_calib_complete_o);
        if (!pll_lock)
            assert (!controller_pll_lock_o && !app_reset_n_o);
        if (!reset_button_n)
            assert (!ddr_ip_reset_n);
    end

    logic formal_board_past_valid_q = 1'b0;
    always_ff @(posedge clk_50mhz) begin
        formal_board_past_valid_q <= 1'b1;
        if (formal_board_past_valid_q && $past(!reset_button_n))
            assert(!ddr_ip_reset_n);
        if (formal_board_past_valid_q && reset_button_n &&
            $past(reset_button_n &&
                  ddr_ip_reset_release_q != 3'b111))
            assert(ddr_ip_reset_release_q ==
                   {$past(ddr_ip_reset_release_q[1:0]), 1'b1});
    end
`endif
endmodule

`default_nettype wire

`timescale 1ns/1ns
`default_nettype none
// Private fixed startup permission, bundled with the raw wrapper.
// The board clock is the continuous 50 MHz oscillator, not a PLL output.
// 110,000 counted edges: over 2.2 ms at 50 MHz, at least 2 ms up to 55 MHz.
// The physical oscillator bound still needs board-level qualification.
// Any loss revokes permission asynchronously, including with stopped clocks.
module board1_pll_lock_qualifier (
    input wire clk_50mhz,
    input wire reset_button_n,
    input wire pll_lock_i,
    output wire qualified_o
);
    wire raw_good = reset_button_n && pll_lock_i;
    (* async_reg = "true", syn_preserve = 1 *) logic [1:0] release_q;
    logic [16:0] stable_edges_q;
    logic qualified_q;

    always_ff @(posedge clk_50mhz or negedge raw_good) begin
        if (!raw_good) release_q <= 2'b00;
        else release_q <= {release_q[0], 1'b1};
    end

    always_ff @(posedge clk_50mhz or negedge raw_good) begin
        if (!raw_good) begin
            stable_edges_q <= 17'd0;
            qualified_q <= 1'b0;
        end else if (!release_q[1]) begin
            stable_edges_q <= 17'd0;
            qualified_q <= 1'b0;
        end else if (!qualified_q) begin
            if (stable_edges_q == 17'd110_000) qualified_q <= 1'b1;
            else stable_edges_q <= stable_edges_q + 1'b1;
        end
    end
    assign qualified_o = raw_good && qualified_q;
endmodule
`default_nettype wire
