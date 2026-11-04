`undef FORMAL
module board1_gowin_ddr3_app_adapter #(
    parameter integer ADDR_W = 25,
    parameter integer MAX_OUTSTANDING_READS = 16
) (
    output wire [5:0] f_outstanding_o,
    input  wire                   clk,
    input  wire                   reset_n,

    // Private normalized seam from board1_private_ddr_lock_bridge.
    input  wire                   phy_req_valid_i,
    output logic                  phy_req_ready_o,
    input  wire                   phy_req_write_i,
    input  wire [ADDR_W-1:0]      phy_req_word_addr_i,
    input  wire [255:0]           phy_req_wdata_i,
    output logic                  phy_rsp_valid_o,
    output logic [255:0]          phy_rsp_data_o,
    output logic                  phy_rsp_error_o,

    // Status returned to the authenticated bridge.
    input  wire                   controller_pll_lock_i,
    input  wire                   controller_init_calib_complete_i,
    output logic                  calib_done_o,
    output logic                  calib_error_o,
    output logic                  protocol_fault_o,

    // Exact application seam of the official Gowin DDR3 IP.
    input  wire                   app_cmd_ready_i,
    output logic [2:0]            app_cmd_o,
    output logic                  app_cmd_en_o,
    output logic [28:0]           app_addr_o,
    input  wire                   app_wr_data_ready_i,
    output logic [255:0]          app_wr_data_o,
    output logic                  app_wr_data_en_o,
    output logic                  app_wr_data_end_o,
    output logic [31:0]           app_wr_data_mask_o,
    input  wire [255:0]           app_rd_data_i,
    input  wire                   app_rd_data_valid_i,
    input  wire                   app_rd_data_end_i,
    output logic                  app_burst_o,
    output logic                  app_self_refresh_req_o,
    output logic                  app_refresh_req_o
);
    localparam integer APP_ADDR_W = 29;
    localparam integer COLUMN_ZERO_BITS = 3;
    localparam integer TOP_ZERO_BITS =
        APP_ADDR_W - ADDR_W - COLUMN_ZERO_BITS;
    localparam integer OUTSTANDING_W =
        $clog2(MAX_OUTSTANDING_READS + 1);

    // The official example assigns command 000 to writes and 001 to reads.
    localparam logic [2:0] GOWIN_CMD_WRITE = 3'b000;
    localparam logic [2:0] GOWIN_CMD_READ  = 3'b001;

    logic calibration_seen_q;
    logic [OUTSTANDING_W-1:0] outstanding_reads_q;

    wire controller_known_good =
        (controller_pll_lock_i === 1'b1) &&
        (controller_init_calib_complete_i === 1'b1);
    wire request_accept = phy_req_valid_i && phy_req_ready_o;
    wire read_issue = request_accept && !phy_req_write_i;
    wire read_response_legal =
        (app_rd_data_valid_i === 1'b1) &&
        (app_rd_data_end_i === 1'b1) &&
        (outstanding_reads_q != 0) && controller_known_good;

    initial begin
        if (ADDR_W <= 0 || TOP_ZERO_BITS < 0)
            $fatal(1, "normalized word address does not fit Gowin app address");
        if (MAX_OUTSTANDING_READS <= 0 ||
            MAX_OUTSTANDING_READS >= (1 << OUTSTANDING_W))
            $fatal(1, "invalid maximum outstanding-read count");
    end

    always_comb begin
        phy_req_ready_o = 1'b0;
        phy_rsp_valid_o = (app_rd_data_valid_i === 1'b1);
        // Data buses need no idle-value mux: their valid/enables remain the
        // sole consumers' qualification and every seam here is private.
        phy_rsp_data_o = app_rd_data_i;
        phy_rsp_error_o = phy_rsp_valid_o &&
            ((app_rd_data_end_i !== 1'b1) ||
             (outstanding_reads_q == 0) || !controller_known_good ||
             protocol_fault_o);

        calib_done_o = calibration_seen_q && controller_known_good &&
                       !protocol_fault_o;
        calib_error_o = protocol_fault_o;

        app_cmd_o = GOWIN_CMD_READ;
        app_cmd_en_o = 1'b0;
        app_addr_o = {{TOP_ZERO_BITS{1'b0}},
                      phy_req_word_addr_i, 3'b000};
        app_wr_data_o = phy_req_wdata_i;
        app_wr_data_en_o = 1'b0;
        app_wr_data_end_o = 1'b0;
        app_wr_data_mask_o = 32'b0;
        app_burst_o = 1'b0;
        app_self_refresh_req_o = 1'b0;
        app_refresh_req_o = 1'b0;

        // Readiness is local capacity, not an acknowledgement of VALID.
        // Keep X/Z VALID closed in four-state simulation. For binary hardware
        // this known-value guard is constant true and creates no VALID path.
        // Command/data enables below STILL require the original known VALID.
        if (calib_done_o && ((phy_req_valid_i === 1'b0) ||
                            (phy_req_valid_i === 1'b1))) begin
            if ((phy_req_write_i === 1'b1) &&
                (app_cmd_ready_i === 1'b1) &&
                (app_wr_data_ready_i === 1'b1))
                phy_req_ready_o = 1'b1;
            else if ((phy_req_write_i === 1'b0) &&
                     (app_cmd_ready_i === 1'b1) &&
                     (outstanding_reads_q <
                      OUTSTANDING_W'(MAX_OUTSTANDING_READS)))
                phy_req_ready_o = 1'b1;
        end

        // Exact-equality guards make an X/Z request fail closed in
        // four-state simulation instead of emitting a controller command.
        if ((phy_req_valid_i === 1'b1) && calib_done_o) begin
            if ((phy_req_write_i === 1'b1) &&
                (app_cmd_ready_i === 1'b1) &&
                (app_wr_data_ready_i === 1'b1)) begin
                app_cmd_o = GOWIN_CMD_WRITE;
                app_cmd_en_o = 1'b1;
                app_wr_data_en_o = 1'b1;
                app_wr_data_end_o = 1'b1;
            end else if ((phy_req_write_i === 1'b0) &&
                         (app_cmd_ready_i === 1'b1) &&
                         (outstanding_reads_q <
                          OUTSTANDING_W'(MAX_OUTSTANDING_READS))) begin
                app_cmd_o = GOWIN_CMD_READ;
                app_cmd_en_o = 1'b1;
            end
        end
    end

    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            calibration_seen_q <= 1'b0;
            outstanding_reads_q <= '0;
            protocol_fault_o <= 1'b0;
        end else begin
            if (controller_known_good)
                calibration_seen_q <= 1'b1;

            if (calibration_seen_q && !controller_known_good)
                protocol_fault_o <= 1'b1;

            if ((app_rd_data_valid_i === 1'b1) &&
                ((app_rd_data_end_i !== 1'b1) ||
                 (outstanding_reads_q == 0) || !controller_known_good))
                protocol_fault_o <= 1'b1;

`ifndef SYNTHESIS
            if ($isunknown(controller_pll_lock_i) ||
                $isunknown(controller_init_calib_complete_i) ||
                $isunknown(phy_req_valid_i) ||
                ((phy_req_valid_i === 1'b1) &&
                 ($isunknown(phy_req_write_i) ||
                  $isunknown(phy_req_word_addr_i) ||
                  $isunknown(app_cmd_ready_i) ||
                  ((phy_req_write_i === 1'b1) &&
                   ($isunknown(phy_req_wdata_i) ||
                    $isunknown(app_wr_data_ready_i))))) ||
                $isunknown(app_rd_data_valid_i) ||
                ((app_rd_data_valid_i === 1'b1) &&
                 ($isunknown(app_rd_data_end_i) ||
                  $isunknown(app_rd_data_i))))
                protocol_fault_o <= 1'b1;
`endif

            if (!protocol_fault_o) begin
                case ({read_issue, read_response_legal})
                    2'b10: outstanding_reads_q <=
                        outstanding_reads_q + 1'b1;
                    2'b01: outstanding_reads_q <=
                        outstanding_reads_q - 1'b1;
                    default: begin
                    end
                endcase
            end
        end
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (reset_n && app_cmd_en_o) begin
            assert (phy_req_valid_i && phy_req_ready_o);
            assert (app_addr_o[2:0] == 3'b000);
            assert (app_cmd_o == (phy_req_write_i ?
                                  GOWIN_CMD_WRITE : GOWIN_CMD_READ));
        end
        if (reset_n && app_wr_data_en_o) begin
            assert (app_cmd_en_o && app_cmd_o == GOWIN_CMD_WRITE);
            assert (app_wr_data_end_o && app_wr_data_mask_o == 0);
        end
        if (reset_n && app_cmd_en_o && app_cmd_o == GOWIN_CMD_READ)
            assert (!app_wr_data_en_o);
        if (formal_past_valid && reset_n && $past(reset_n) &&
            $past(protocol_fault_o))
            assert (protocol_fault_o);
    end
`endif
    assign f_outstanding_o=outstanding_reads_q;
endmodule
module board1_private_ddr_boot_handoff #(
    parameter integer WATCHDOG_CYCLES=50000000
) (
    output wire f_runtime_o,f_switch_o,f_terminal_o,
    output wire [5:0] f_pending_o,
    input wire clk,reset_n,
    input wire controller_good_i,boot_locked_i,boot_fault_i,runtime_fault_i,
    input wire [2:0] boot_cmd_i,runtime_cmd_i,
    input wire boot_cmd_en_i,runtime_cmd_en_i,
    input wire [28:0] boot_addr_i,runtime_addr_i,
    input wire [255:0] boot_data_i,runtime_data_i,
    input wire boot_data_en_i,runtime_data_en_i,
    input wire boot_data_end_i,runtime_data_end_i,
    input wire [31:0] boot_mask_i,runtime_mask_i,
    output wire boot_cmd_ready_o,runtime_cmd_ready_o,
    output wire boot_data_ready_o,runtime_data_ready_o,
    output wire boot_read_valid_o,runtime_read_valid_o,
    output wire [255:0] read_data_o,
    output wire read_end_o,
    input wire app_cmd_ready_i,app_data_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_data_o,
    output wire app_data_en_o,app_data_end_o,
    output wire [31:0] app_mask_o,
    input wire app_read_valid_i,app_read_end_i,
    input wire [255:0] app_read_data_i,
    output wire runtime_locked_o,
    output logic fault_o
);
    localparam integer WW=$clog2(WATCHDOG_CYCLES+1);
    logic runtime_q,quiet_q,controller_seen_q,lock_seen_q;
    logic [5:0] pending_q;
    logic [WW-1:0] watchdog_q;
    logic x_error;
    wire selected_en=runtime_q ? runtime_cmd_en_i : boot_cmd_en_i;
    wire selected_data_en=runtime_q ? runtime_data_en_i : boot_data_en_i;
    wire selected_end=runtime_q ? runtime_data_end_i : boot_data_end_i;
    wire [31:0] selected_mask=runtime_q ? runtime_mask_i : boot_mask_i;
    wire [18:0] selected_word=app_addr_o[21:3];
    wire selected_write=app_cmd_o==3'd0;
    wire selected_read=app_cmd_o==3'd1;
    wire model_address=selected_word<19'd227062;
    wire kv_address=selected_word>=19'd227072 && selected_word<19'd448256;
    wire aligned=app_addr_o[28:22]==0 && app_addr_o[2:0]==0;
    wire valid_region=runtime_q ? ((selected_read && model_address) || kv_address) : model_address;
    wire bad_command=(selected_en && (!aligned || !valid_region || (!selected_read && !selected_write))) ||
        (selected_data_en && (!selected_en || !selected_write)) ||
        (selected_en && selected_write && (!selected_data_en || !selected_end || selected_mask!=0 ||
            (app_cmd_ready_i != app_data_ready_i)));
    wire return_legal=app_read_valid_i && pending_q!=0 && app_read_end_i;
    wire bad_return=app_read_valid_i && (pending_q==0 || !app_read_end_i || !controller_good_i);
    wire bad_credit=selected_en && selected_read && app_cmd_ready_i && pending_q==32 && !return_legal;
    wire waiting=boot_locked_i && !runtime_q;
    wire timeout_now=waiting && watchdog_q==WW'(WATCHDOG_CYCLES-1);
    wire terminal_now=boot_fault_i || runtime_fault_i || (controller_seen_q && !controller_good_i) ||
        (lock_seen_q && !boot_locked_i) || bad_command || bad_return || bad_credit || timeout_now || x_error;
    wire enabled=reset_n && controller_good_i && !fault_o;

    // Ready depends only on registered ownership/fault, not same-cycle
    // command checks. Otherwise adapter enable->policy->ready can loop.
    // Current violations suppress the final physical enables and set fault.
    assign boot_cmd_ready_o=enabled && !runtime_q && app_cmd_ready_i;
    assign runtime_cmd_ready_o=enabled && runtime_q && app_cmd_ready_i;
    assign boot_data_ready_o=enabled && !runtime_q && app_data_ready_i;
    assign runtime_data_ready_o=enabled && runtime_q && app_data_ready_i;
    assign app_cmd_o=runtime_q ? runtime_cmd_i : boot_cmd_i;
    assign app_addr_o=runtime_q ? runtime_addr_i : boot_addr_i;
    assign app_data_o=runtime_q ? runtime_data_i : boot_data_i;
    assign app_cmd_en_o=selected_en && enabled && !terminal_now;
    assign app_data_en_o=selected_data_en && enabled && !terminal_now;
    assign app_data_end_o=selected_end && app_data_en_o;
    assign app_mask_o=selected_mask;
    assign boot_read_valid_o=app_read_valid_i && !runtime_q && reset_n && !fault_o;
    assign runtime_read_valid_o=app_read_valid_i && runtime_q && reset_n && !fault_o;
    assign read_data_o=app_read_data_i;
    assign read_end_o=app_read_end_i;
    assign runtime_locked_o=runtime_q && boot_locked_i && !fault_o && reset_n;
    wire command_fire=app_cmd_en_o && app_cmd_ready_i;
    wire read_fire=command_fire && selected_read;
    wire can_switch=enabled && boot_locked_i && !runtime_q && pending_q==0 &&
        !boot_cmd_en_i && !boot_data_en_i && !app_read_valid_i && !terminal_now;

    // Speculative bookkeeping is private after the same irreversible fault.
    // Physical command/data enables retain every original terminal check.
    // The credit cap preserves the existing pending<=32 invariant even on a
    // rejected 33rd attempt. Runtime ownership still uses checked can_switch.
    wire switch_candidate=enabled && boot_locked_i && !runtime_q && pending_q==0 &&
        !boot_cmd_en_i && !boot_data_en_i && !app_read_valid_i;
    wire read_candidate=selected_en && enabled && app_cmd_ready_i && selected_read &&
        (pending_q!=6'd32 || return_legal);
    // When waiting is true, the selected owner is necessarily boot. Avoid
    // routing runtime command validation through the boot-only watchdog.
    wire watchdog_reset_candidate=!waiting ||
        (boot_cmd_en_i && enabled && app_cmd_ready_i) || return_legal || switch_candidate;

    always_comb begin
        x_error=0;
`ifndef SYNTHESIS
`ifndef FORMAL
        x_error=$isunknown(controller_good_i) || $isunknown(boot_locked_i) ||
            $isunknown(boot_fault_i) || $isunknown(runtime_fault_i) || $isunknown(app_cmd_ready_i) ||
            $isunknown(app_data_ready_i) || $isunknown(app_read_valid_i) ||
            $isunknown(selected_en) || $isunknown(selected_data_en);
        if(selected_en) x_error=x_error || $isunknown(app_cmd_o) || $isunknown(app_addr_o);
        if(selected_data_en) x_error=x_error || $isunknown(app_data_o) ||
            $isunknown(selected_end) || $isunknown(selected_mask);
        if(app_read_valid_i) x_error=x_error || $isunknown(app_read_end_i) || $isunknown(app_read_data_i);
`endif
`endif
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            runtime_q<=0;quiet_q<=0;controller_seen_q<=0;lock_seen_q<=0;
            pending_q<=0;watchdog_q<=0;fault_o<=0;
        end else begin
            if(controller_good_i) controller_seen_q<=1;
            if(boot_locked_i) lock_seen_q<=1;
            if(terminal_now) fault_o<=1;
            if(watchdog_reset_candidate) watchdog_q<=0;
            else if(!fault_o && !timeout_now) watchdog_q<=watchdog_q+1'b1;
            if(!fault_o) begin
                quiet_q<=switch_candidate;
                if(can_switch && quiet_q) runtime_q<=1;
                case({read_candidate,return_legal})
                    2'b10:pending_q<=pending_q+6'd1;
                    2'b01:pending_q<=pending_q-6'd1;
                    default: ;
                endcase
            end
        end
    end
    initial if(WATCHDOG_CYCLES<4) $fatal(1,"invalid boot handoff watchdog");
`ifdef FORMAL
    logic past_valid;
    always_ff @(posedge clk) begin
        past_valid<=1;
        if(reset_n) begin
            assert(pending_q<=32);
            assert(!(boot_read_valid_o && runtime_read_valid_o));
            if(runtime_locked_o) assert(!boot_cmd_ready_o && !boot_data_ready_o);
            if(app_cmd_en_o && selected_write && runtime_q) assert(kv_address);
            if(app_cmd_en_o && !runtime_q) assert(model_address);
            if(fault_o) assert(!app_cmd_en_o && !app_data_en_o && !runtime_locked_o);
            if(past_valid && $past(reset_n) && !$past(runtime_q) && runtime_q)
                assert($past(pending_q)==0 && !$past(app_read_valid_i) && $past(boot_locked_i));
            if(past_valid && $past(reset_n) && $past(runtime_q)) assert(runtime_q);
        end
    end
`endif
    assign f_runtime_o=runtime_q;
    assign f_switch_o=can_switch && quiet_q;
    assign f_pending_o=pending_q;
    assign f_terminal_o=terminal_now;
endmodule
module board1_private_booted_shared_ddr (
    input wire f_boot_private_loader_ready_o_i,
    input wire [2:0] f_boot_boot_cmd_i,
    input wire f_boot_boot_cmd_en_i,
    input wire [28:0] f_boot_boot_addr_i,
    input wire [255:0] f_boot_boot_data_i,
    input wire f_boot_boot_data_en_i,
    input wire f_boot_boot_data_end_i,
    input wire [31:0] f_boot_boot_mask_i,
    input wire f_boot_boot_burst_i,
    input wire f_boot_boot_self_refresh_i,
    input wire f_boot_boot_refresh_i,
    input wire f_boot_boot_locked_i,
    input wire f_boot_boot_fault_i,
    input wire f_boot_boot_watchdog_i,
    input wire trusted_clk_i,trusted_reset_n_i,app_clk_i,app_reset_n_i,
    input wire private_fixed_source_ready_i,private_boot_progress_i,
    input wire private_loader_done_i,private_loader_valid_i,
    input wire [255:0] private_loader_data_i,
    output wire private_loader_ready_o,
    input wire private_source_fault_i,private_runtime_app_fault_i,
    input wire private_req_valid_i,private_req_write_i,
    input wire [18:0] private_req_word_i,
    input wire [255:0] private_req_data_i,
    output wire private_req_ready_o,private_rsp_valid_o,private_rsp_error_o,
    output wire [255:0] private_rsp_data_o,
    output wire private_model_locked_o,private_fail_closed_o,
    input wire controller_pll_lock_i,controller_init_calib_complete_i,
    input wire app_cmd_ready_i,app_wr_data_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_wr_data_o,
    output wire app_wr_data_en_o,app_wr_data_end_o,
    output wire [31:0] app_wr_data_mask_o,
    input wire [255:0] app_rd_data_i,
    input wire app_rd_data_valid_i,app_rd_data_end_i,
    output wire app_burst_o,app_self_refresh_req_o,app_refresh_req_o
);
    wire common_async_reset_n=trusted_reset_n_i && app_reset_n_i;
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_release_q;
    always_ff @(posedge app_clk_i or negedge common_async_reset_n) begin
        if(!common_async_reset_n) app_release_q<=0;
        else app_release_q<={app_release_q[1:0],1'b1};
    end
    // Matches the boot composition's own app release, avoiding a startup
    // false fault from its intentionally closed output during hard reset.
    wire app_domain_reset_n=app_release_q[2];
    wire f_runtime,f_switch,f_terminal;
    wire [5:0] f_pending,f_outstanding;
    logic fault_q;
    wire boot_locked,boot_fault,boot_watchdog,handoff_locked,handoff_fault;
    wire runtime_adapter_fault,runtime_adapter_error,runtime_adapter_ready;
    wire runtime_req_ready,runtime_rsp_error;
    wire [2:0] boot_cmd,runtime_cmd;
    wire boot_cmd_en,runtime_cmd_en,boot_cmd_ready,runtime_cmd_ready;
    wire [28:0] boot_addr,runtime_addr;
    wire [255:0] boot_data,runtime_data;
    wire boot_data_en,runtime_data_en,boot_data_end,runtime_data_end;
    wire boot_data_ready,runtime_data_ready,boot_read_valid,runtime_read_valid;
    wire [31:0] boot_mask,runtime_mask;
    wire [255:0] selected_read_data;
    wire selected_read_end;
    wire boot_burst,boot_self_refresh,boot_refresh;
    wire runtime_burst,runtime_self_refresh,runtime_refresh;
    wire controller_good=controller_pll_lock_i && controller_init_calib_complete_i;
    wire unexpected_control=boot_burst || boot_self_refresh || boot_refresh ||
        runtime_burst || runtime_self_refresh || runtime_refresh;
    always_ff @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if(!app_domain_reset_n) fault_q<=0;
        else if(private_source_fault_i || private_runtime_app_fault_i || boot_fault ||
                handoff_fault || runtime_adapter_fault || unexpected_control) fault_q<=1;
    end
    assign private_fail_closed_o=fault_q || handoff_fault;
    assign private_model_locked_o=handoff_locked && !fault_q;
    assign private_req_ready_o=runtime_req_ready && private_model_locked_o;
    assign private_rsp_error_o=runtime_rsp_error ||
        (private_rsp_valid_o && private_fail_closed_o);
    // The selected adapters never request manual refresh or a special burst;
    // the actual controller remains responsible for its normal auto-refresh.
    assign app_burst_o=1'b0;
    assign app_self_refresh_req_o=1'b0;
    assign app_refresh_req_o=1'b0;

    assign private_loader_ready_o=f_boot_private_loader_ready_o_i;
    assign boot_cmd=f_boot_boot_cmd_i;
    assign boot_cmd_en=f_boot_boot_cmd_en_i;
    assign boot_addr=f_boot_boot_addr_i;
    assign boot_data=f_boot_boot_data_i;
    assign boot_data_en=f_boot_boot_data_en_i;
    assign boot_data_end=f_boot_boot_data_end_i;
    assign boot_mask=f_boot_boot_mask_i;
    assign boot_burst=f_boot_boot_burst_i;
    assign boot_self_refresh=f_boot_boot_self_refresh_i;
    assign boot_refresh=f_boot_boot_refresh_i;
    assign boot_locked=f_boot_boot_locked_i;
    assign boot_fault=f_boot_boot_fault_i;
    assign boot_watchdog=f_boot_boot_watchdog_i;

    board1_gowin_ddr3_app_adapter #(.ADDR_W(19),.MAX_OUTSTANDING_READS(32)) u_runtime_adapter (
        .f_outstanding_o(f_outstanding),
        .clk(app_clk_i),.reset_n(app_domain_reset_n),
        .phy_req_valid_i(private_req_valid_i && private_model_locked_o),.phy_req_ready_o(runtime_req_ready),
        .phy_req_write_i(private_req_write_i),.phy_req_word_addr_i(private_req_word_i),.phy_req_wdata_i(private_req_data_i),
        .phy_rsp_valid_o(private_rsp_valid_o),.phy_rsp_data_o(private_rsp_data_o),.phy_rsp_error_o(runtime_rsp_error),
        .controller_pll_lock_i(controller_pll_lock_i),.controller_init_calib_complete_i(controller_init_calib_complete_i),
        .calib_done_o(runtime_adapter_ready),.calib_error_o(runtime_adapter_error),.protocol_fault_o(runtime_adapter_fault),
        .app_cmd_ready_i(runtime_cmd_ready),.app_cmd_o(runtime_cmd),.app_cmd_en_o(runtime_cmd_en),.app_addr_o(runtime_addr),
        .app_wr_data_ready_i(runtime_data_ready),.app_wr_data_o(runtime_data),.app_wr_data_en_o(runtime_data_en),
        .app_wr_data_end_o(runtime_data_end),.app_wr_data_mask_o(runtime_mask),
        .app_rd_data_i(selected_read_data),.app_rd_data_valid_i(runtime_read_valid),.app_rd_data_end_i(selected_read_end),
        .app_burst_o(runtime_burst),.app_self_refresh_req_o(runtime_self_refresh),.app_refresh_req_o(runtime_refresh));

    board1_private_ddr_boot_handoff u_handoff (
        .f_runtime_o(f_runtime),.f_switch_o(f_switch),.f_pending_o(f_pending),.f_terminal_o(f_terminal),
        .clk(app_clk_i),.reset_n(app_domain_reset_n),.controller_good_i(controller_good),
        .boot_locked_i(boot_locked),.boot_fault_i(boot_fault || private_source_fault_i || unexpected_control),
        .runtime_fault_i(fault_q || runtime_adapter_fault || private_runtime_app_fault_i),
        .boot_cmd_i(boot_cmd),.runtime_cmd_i(runtime_cmd),.boot_cmd_en_i(boot_cmd_en),.runtime_cmd_en_i(runtime_cmd_en),
        .boot_addr_i(boot_addr),.runtime_addr_i(runtime_addr),.boot_data_i(boot_data),.runtime_data_i(runtime_data),
        .boot_data_en_i(boot_data_en),.runtime_data_en_i(runtime_data_en),.boot_data_end_i(boot_data_end),
        .runtime_data_end_i(runtime_data_end),.boot_mask_i(boot_mask),.runtime_mask_i(runtime_mask),
        .boot_cmd_ready_o(boot_cmd_ready),.runtime_cmd_ready_o(runtime_cmd_ready),
        .boot_data_ready_o(boot_data_ready),.runtime_data_ready_o(runtime_data_ready),
        .boot_read_valid_o(boot_read_valid),.runtime_read_valid_o(runtime_read_valid),
        .read_data_o(selected_read_data),.read_end_o(selected_read_end),
        .app_cmd_ready_i(app_cmd_ready_i),.app_data_ready_i(app_wr_data_ready_i),
        .app_cmd_o(app_cmd_o),.app_cmd_en_o(app_cmd_en_o),.app_addr_o(app_addr_o),.app_data_o(app_wr_data_o),
        .app_data_en_o(app_wr_data_en_o),.app_data_end_o(app_wr_data_end_o),.app_mask_o(app_wr_data_mask_o),
        .app_read_valid_i(app_rd_data_valid_i),.app_read_end_i(app_rd_data_end_i),.app_read_data_i(app_rd_data_i),
        .runtime_locked_o(handoff_locked),.fault_o(handoff_fault));

    wire _unused_status=boot_watchdog || runtime_adapter_ready || runtime_adapter_error;
    (* anyconst *) reg [18:0] f_target;
    (* anyconst *) reg [255:0] f_initial;
    (* anyconst *) reg [4:0] f_slot;
    reg [255:0] f_memory;
    reg [6:0] f_lower_issue,f_lower_return,f_client_issue,f_client_return,f_base;
    reg f_record_seen,f_record_runtime;
    reg [6:0] f_record_sequence,f_record_client;
    reg [18:0] f_record_address,f_client_address;
    reg [255:0] f_record_word;
    wire f_lower_read=app_cmd_en_o && app_cmd_ready_i && app_cmd_o==1;
    wire f_lower_write=app_cmd_en_o && app_cmd_ready_i && app_cmd_o==0;
    wire f_client_read=private_req_valid_i && private_req_ready_o && !private_req_write_i;
    wire f_client_reply=private_rsp_valid_o;
    wire [6:0] f_debt=f_lower_issue-f_lower_return;
    wire [4:0] f_offset=f_slot-f_lower_return[4:0];
    wire f_record_live={2'd0,f_offset}<f_debt;
    wire f_alive=app_domain_reset_n && !private_fail_closed_o && !runtime_adapter_fault;
    always @(posedge app_clk_i or negedge app_domain_reset_n) begin
        if(!app_domain_reset_n) begin
            f_memory<=f_initial;f_lower_issue<=0;f_lower_return<=0;
            f_client_issue<=0;f_client_return<=0;f_base<=0;f_record_seen<=0;
        end else begin
            if(f_lower_write && app_addr_o[21:3]==f_target) f_memory<=app_wr_data_o;
            if(f_lower_read) begin
                f_lower_issue<=f_lower_issue+1'b1;
                if(f_lower_issue[4:0]==f_slot) begin
                    f_record_seen<=1;f_record_sequence<=f_lower_issue;
                    f_record_runtime<=f_runtime;f_record_client<=f_client_issue;
                    f_record_address<=app_addr_o[21:3];
                    f_client_address<=private_req_word_i;f_record_word<=f_memory;
                end
            end
            if(app_rd_data_valid_i) f_lower_return<=f_lower_return+1'b1;
            if(f_client_read) f_client_issue<=f_client_issue+1'b1;
            if(f_client_reply) f_client_return<=f_client_return+1'b1;
            if(f_switch) f_base<=f_lower_issue;
        end
    end
    // Imported lower contract: sampled successful core-side replies from the
    // qualified thin transport. controller_good implies clear transport fault
    // in the actual top binding. Post-failure raw fields remain arbitrary.
    always @(posedge app_clk_i) if(app_domain_reset_n && controller_good && app_rd_data_valid_i) begin
        assume(f_debt!=0);
        assume(app_rd_data_end_i);
        if(f_lower_return[4:0]==f_slot && f_record_address==f_target)
            assume(app_rd_data_i==f_record_word);
    end
    always @* begin
        assert(app_release_q==0 || app_release_q==1 || app_release_q==3 || app_release_q==7);
        if(private_req_valid_i && private_req_ready_o && !f_terminal) begin
            assert(f_runtime && app_cmd_en_o && app_cmd_ready_i);
            assert(app_cmd_o==(private_req_write_i ? 3'd0:3'd1));
            assert(app_addr_o=={7'd0,private_req_word_i,3'd0});
            if(private_req_write_i) assert(app_wr_data_o==private_req_data_i && app_wr_data_en_o && app_wr_data_end_o);
        end
        if(f_runtime && app_cmd_en_o) begin
            assert(private_req_valid_i && private_req_ready_o);
            assert(f_lower_read==f_client_read);
        end
        if(private_rsp_valid_o && !private_rsp_error_o) begin
            assert(controller_good && !private_fail_closed_o && !runtime_adapter_fault);
            assert(app_rd_data_valid_i && f_runtime && app_domain_reset_n);
            assert(private_rsp_data_o==app_rd_data_i && app_rd_data_end_i);
        end
        if(f_alive) begin
            assert(f_pending<=32);
            assert(f_debt=={1'b0,f_pending});
            assert(f_debt<=32);
            if(f_lower_read) assert(f_debt<32 || app_rd_data_valid_i);
            if(f_record_live) begin
                assert(f_record_seen);
                assert(f_record_sequence==f_lower_return+{2'd0,f_offset});
            end
            if(f_lower_read && f_lower_issue[4:0]==f_slot) assert(!f_record_live || app_rd_data_valid_i);
            if(!f_runtime) begin
                assert(f_client_issue==0 && f_client_return==0);
                assert(f_outstanding==0);
            end else begin
                assert(f_lower_issue-f_base==f_client_issue);
                assert(f_lower_return-f_base==f_client_return);
                assert(f_client_issue-f_client_return=={1'b0,f_outstanding});
                if(f_record_live) begin
                    assert(f_record_runtime);
                    assert(f_record_client==f_record_sequence-f_base);
                    assert(f_record_address==f_client_address);
                end
            end
        end
    end
    // Sampled ownership uses exactly the lower contract's sampling edge.
    always @(posedge app_clk_i) if(app_domain_reset_n && f_alive && controller_good && app_rd_data_valid_i) begin
        assert(f_pending!=0);
        if(f_lower_return[4:0]==f_slot) begin
            assert(f_record_live);
            assert(f_record_sequence==f_lower_return);
            if(private_rsp_valid_o && !private_rsp_error_o) begin
                assert(f_record_runtime);
                assert(f_record_client==f_client_return);
                assert(f_record_address==f_client_address);
                if(f_record_address==f_target) assert(private_rsp_data_o==f_record_word);
            end
        end
    end

    (* keep *) reg[4:0] f_sampled_base;
    always @(posedge app_clk_i) f_sampled_base<=f_base[4:0];

endmodule
