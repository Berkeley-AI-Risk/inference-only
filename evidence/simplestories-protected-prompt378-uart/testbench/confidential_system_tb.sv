`timescale 1ns/1ps
`default_nettype none

// End-to-end real-model KAT through the widened public tape, actual six-layer
// semantic datapath, typed atomic K/V cache, dual-clock capability boundary,
// and one private DDR endpoint.  The endpoint seam is physical-wrapper-only;
// APPEND, STEP, and CLEAR remain the complete user operation set.
module confidential_system_tb #(parameter integer AUTH_BANKS=8);
    // Actual vendor primitive simulation, after configuration GSR release.
    GSR GSR(.GSRI(1'b1));
    `define FP_DP u_uart.u_machine.u_machine.u_six_layers.u_datapath
    bit fp_inject_fault=0,fp_expect_fault=0;
    `define SP_SHELL u_uart.u_machine.u_machine.u_token_shell
    bit sp_inject_fault=0,sp_expect_fault=0;
    localparam integer IMAGE_WORDS = 227062;
    localparam integer SCRATCH_WORDS = 245760;
    localparam longint WATCHDOG_CYCLES = 64'd1_000_000_000_000;

    logic core_clk_i = 1'b0;
    wire app_clk_i = core_clk_i;
    logic phy_clk_i = 1'b0;
    always #20 core_clk_i = ~core_clk_i;
    always #5 phy_clk_i = ~phy_clk_i;
    logic reset_n_i = 1'b0;
    wire clear_i, append_valid_i;
    bit uart_rx = 1;
    wire uart_tx;
    wire append_ready_o;
    wire [11:0] append_token_i;
    wire step_valid_i;
    wire step_ready_o;
    wire token_valid_o;
    wire token_ready_i;
    wire [11:0] token_o;
    wire busy_o;
    wire model_locked_o;
    wire fail_closed_o;
    wire private_model_locked_i;
    wire private_endpoint_upstream_fault_i;
    wire private_endpoint_req_valid_o;
    wire private_endpoint_req_ready_i;
    wire [18:0] private_endpoint_req_word_address_o;
    wire private_endpoint_req_write_o;
    wire [255:0] private_endpoint_req_write_data_o;
    wire private_endpoint_rsp_valid_i;
    wire private_endpoint_rsp_ready_o;
    wire [255:0] private_endpoint_rsp_data_i;
    wire private_endpoint_rsp_error_i;

    board1_private_shared_uart_core u_uart (
        .core_clk_i(core_clk_i), .app_clk_i(app_clk_i), .reset_n_i(reset_n_i),
        .uart_rx_i(uart_rx), .uart_tx_o(uart_tx),
        .private_model_locked_i(private_model_locked_i),
        .private_endpoint_upstream_fault_i(private_endpoint_upstream_fault_i),
        .private_endpoint_req_valid_o(private_endpoint_req_valid_o),
        .private_endpoint_req_write_o(private_endpoint_req_write_o),
        .private_endpoint_req_ready_i(private_endpoint_req_ready_i),
        .private_endpoint_req_word_address_o(private_endpoint_req_word_address_o),
        .private_endpoint_req_write_data_o(private_endpoint_req_write_data_o),
        .private_endpoint_rsp_valid_i(private_endpoint_rsp_valid_i),
        .private_endpoint_rsp_error_i(private_endpoint_rsp_error_i),
        .private_endpoint_rsp_data_i(private_endpoint_rsp_data_i),
        .private_fail_closed_o(fail_closed_o));
    assign clear_i=u_uart.clear;
    assign append_valid_i=u_uart.append_valid;
    assign append_ready_o=u_uart.append_ready;
    assign append_token_i=u_uart.append_token;
    assign step_valid_i=u_uart.step_valid;
    assign step_ready_o=u_uart.step_ready;
    assign token_valid_o=u_uart.token_valid;
    assign token_ready_i=u_uart.token_ready;
    assign token_o=u_uart.token;
    assign busy_o=u_uart.u_machine.busy_o;
    assign model_locked_o=u_uart.u_machine.model_locked_o;
    assign private_endpoint_rsp_ready_o=u_uart.u_machine.private_endpoint_rsp_ready_o;

    logic [255:0] semantic_image [0:IMAGE_WORDS-1];
    logic [255:0] scratch_memory [0:SCRATCH_WORDS-1];
    string image_memh_path,cipher_memh_path;
    logic [255:0] ciphertext_image [0:IMAGE_WORDS-1];
    // Independent, ordered scoreboard for EVERY accepted semantic model read,
    // including local metadata ROM and all nonlinear/norm/embedding lookups.
    logic [18:0] expected_words [0:511];
    logic [8:0] expected_wr_q,expected_rd_q;
    longint expected_count_q,model_requests_q,model_responses_q;
    wire active_clear_test=$test$plusargs("CLEAR_AT_MODEL_RESPONSE") || $test$plusargs("QUERY_CAPTURE_CLEAR") || $test$plusargs("ELEMENTWISE_PIPE_CLEAR") || $test$plusargs("NORMALIZER_SELECT_CLEAR") || $test$plusargs("FCP_FAULT") || $test$plusargs("SHP_FAULT");
    wire checked_req=u_uart.u_machine.model_req_valid&&u_uart.u_machine.model_req_ready;
    wire checked_rsp=u_uart.u_machine.model_rsp_valid&&u_uart.u_machine.model_rsp_ready;
    always_ff @(posedge core_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            expected_wr_q<=0;expected_rd_q<=0;expected_count_q<=0;
            model_requests_q<=0;model_responses_q<=0;
        end else begin
            if(!sp_expect_fault && !fp_expect_fault && !different_model && (u_uart.u_machine.auth_fault || u_uart.u_machine.model_cdc_core_fault)) $fatal(1,"authentication/model CDC fault");
            if(clear_i && !active_clear_test) begin
                expected_wr_q<=0;expected_rd_q<=0;expected_count_q<=0;
                if(checked_req||checked_rsp) $fatal(1,"model transaction accepted during CLEAR");
            end else begin
                if(active_clear_test && clear_i && checked_req)
                    $fatal(1,"new model request accepted during active CLEAR");
                if(active_clear_test && clear_i && (append_ready_o || step_ready_o || token_valid_o))
                    $fatal(1,"public operation exposed during active CLEAR");
                case({checked_req,checked_rsp})
                    2'b10:expected_count_q<=expected_count_q+1;
                    2'b01:expected_count_q<=expected_count_q-1;
                    default: ;
                endcase
                if(checked_req) begin
                    if(u_uart.u_machine.model_req_word>=IMAGE_WORDS || expected_count_q>=512)
                        $fatal(1,"semantic model address/scoreboard bound");
                    expected_words[expected_wr_q]<=u_uart.u_machine.model_req_word;
                    expected_wr_q<=expected_wr_q+9'd1;model_requests_q<=model_requests_q+1;
                end
                if(checked_rsp) begin
                    if(expected_count_q==0 || u_uart.u_machine.model_rsp_data!==semantic_image[expected_words[expected_rd_q]])
                        $fatal(1,"semantic model response differs from exact image at word=%0d",expected_words[expected_rd_q]);
                    expected_rd_q<=expected_rd_q+9'd1;model_responses_q<=model_responses_q+1;
                end
            end
        end
    end

    logic read_pending_q = 1'b0;
    logic [18:0] read_address_q = 19'd0;
    longint read_delay_q = 0;
    longint core_cycle_q = 0;
    longint endpoint_model_reads_q = 0;
    longint endpoint_kv_reads_q = 0;
    longint endpoint_kv_writes_q = 0;
    longint endpoint_responses_q = 0;
    longint token_hold_cycles_q = 0;
    longint first_step_start_q = 0;
    longint first_step_cycles_q = 0;

    always_ff @(posedge core_clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            core_cycle_q <= 0;
            token_hold_cycles_q <= 0;
        end else begin
            core_cycle_q <= core_cycle_q + 1;
            if (core_cycle_q >= WATCHDOG_CYCLES)
                $fatal(1,
                    "context2048 connected KAT watchdog shell=%0d layer=%0d stage=%0d engine=%0d model=%0d kvr=%0d kvw=%0d",
                    u_uart.u_machine.u_machine.u_token_shell.state_q,
                    u_uart.u_machine.u_machine.u_six_layers.u_datapath.current_layer_q,
                    u_uart.u_machine.u_machine.u_six_layers.u_datapath.current_stage_q,
                    u_uart.u_machine.u_machine.u_six_layers.u_datapath.engine_state_q,
                    endpoint_model_reads_q, endpoint_kv_reads_q,
                    endpoint_kv_writes_q);
            if (token_valid_o && !token_ready_i)
                token_hold_cycles_q <= token_hold_cycles_q + 1;
        end
    end

    // Only this test's fixed source reads semantic_image. DDR begins without
    // that image; every word must be written through the real boot path.
    bit zero_stall;
    wire corrupt_boot=1'b0, corrupt_runtime=1'b0;
    logic trusted_clk_i=0;
    always #40 trusted_clk_i=~trusted_clk_i;
    logic [255:0] model_memory [0:IMAGE_WORDS-1];
    logic raw_owner_fifo [0:63];
    logic [18:0] raw_fifo [0:63];
    longint raw_due [0:63];
    logic [5:0] raw_wr_q=0,raw_rd_q=0;
    longint raw_count_q=0,raw_requests_q=0,raw_returns_q=0,max_raw_q=0,app_cycle_q=0;
    longint loader_words_q=0,boot_writes_q=0,boot_reads_q=0,boot_returns_q=0;
    longint runtime_corrupt_returns_q=0;
    logic [31:0] raw_lfsr_q=32'h9163d5b7;
    // All semantic state is now on core25. Physical app100 sees only u_transport.
    wire transport_good,transport_fault;
    wire [2:0] sem_cmd;
    wire [28:0] sem_addr;
    wire [255:0] sem_wr_data,sem_rd_data;
    wire [31:0] sem_wr_mask;
    wire sem_cmd_en,sem_cmd_ready,sem_wr_en,sem_wr_end,sem_wr_ready;
    wire sem_rd_valid,sem_rd_end,sem_burst,sem_sr,sem_ref;
    wire [2:0] app_cmd;
    wire app_cmd_en,app_wr_en,app_wr_end,app_burst,app_self_refresh,app_refresh;
    wire [28:0] app_addr;
    wire [255:0] app_wdata;
    wire [31:0] app_wmask;
    wire app_cmd_ready=zero_stall || raw_lfsr_q[2];
    wire app_data_ready=zero_stall || raw_lfsr_q[5];
    wire app_return=raw_count_q!=0 && app_cycle_q>=raw_due[raw_rd_q] && (zero_stall || raw_lfsr_q[7]);
    wire runtime_corrupt_return=app_return && private_model_locked_i && corrupt_runtime &&
        runtime_corrupt_returns_q==0 && raw_fifo[raw_rd_q]<IMAGE_WORDS;
    wire [255:0] app_rdata=(!app_return ? 256'd0 : (raw_fifo[raw_rd_q]<IMAGE_WORDS ?
        model_memory[raw_fifo[raw_rd_q]] : scratch_memory[raw_fifo[raw_rd_q]-227072])) ^
        (runtime_corrupt_return ? 256'd1 : 256'd0);
    wire raw_read_fire=app_cmd_en && app_cmd==1;
    wire loader_ready;
    wire source_ready=app_cycle_q>=16;
    wire loader_valid=source_ready && loader_words_q<IMAGE_WORDS;
    wire [255:0] loader_data=loader_words_q<IMAGE_WORDS ?
        (ciphertext_image[loader_words_q] ^ ((corrupt_boot && loader_words_q==0) ? 256'd1 : 256'd0)) : 256'd0;
    wire loader_done=loader_words_q==IMAGE_WORDS;
    (* async_reg="true" *) logic [1:0] core_fault_sync_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) core_fault_sync_q<=0;
        else core_fault_sync_q<={core_fault_sync_q[0],fail_closed_o};
    end
    tang_confidential_booted_shared_ddr u_memory (
        .trusted_clk_i(trusted_clk_i),.trusted_reset_n_i(reset_n_i),
        .app_clk_i(app_clk_i),.app_reset_n_i(reset_n_i),
        .private_fixed_source_ready_i(source_ready),.private_boot_progress_i(loader_valid && loader_ready),
        .private_loader_done_i(loader_done),.private_loader_valid_i(loader_valid),.private_loader_data_i(loader_data),
        .private_loader_ready_o(loader_ready),.private_source_fault_i(transport_fault),.private_runtime_app_fault_i(core_fault_sync_q[1]),
        .private_req_valid_i(private_endpoint_req_valid_o),.private_req_write_i(private_endpoint_req_write_o),
        .private_req_word_i(private_endpoint_req_word_address_o),.private_req_data_i(private_endpoint_req_write_data_o),
        .private_req_ready_o(private_endpoint_req_ready_i),.private_rsp_valid_o(private_endpoint_rsp_valid_i),
        .private_rsp_error_o(private_endpoint_rsp_error_i),.private_rsp_data_o(private_endpoint_rsp_data_i),
        .private_model_locked_o(private_model_locked_i),.private_fail_closed_o(private_endpoint_upstream_fault_i),
        .controller_pll_lock_i(transport_good),.controller_init_calib_complete_i(transport_good),
        .app_cmd_ready_i(sem_cmd_ready),.app_wr_data_ready_i(sem_wr_ready),
        .app_cmd_o(sem_cmd),.app_cmd_en_o(sem_cmd_en),.app_addr_o(sem_addr),
        .app_wr_data_o(sem_wr_data),.app_wr_data_en_o(sem_wr_en),.app_wr_data_end_o(sem_wr_end),
        .app_wr_data_mask_o(sem_wr_mask),.app_rd_data_i(sem_rd_data),.app_rd_data_valid_i(sem_rd_valid),.app_rd_data_end_i(sem_rd_end),
        .app_burst_o(sem_burst),.app_self_refresh_req_o(sem_sr),.app_refresh_req_o(sem_ref));
    board1_thin_ddr_app_transport u_transport (
        .core_clk_i(core_clk_i),
        .core_reset_n_i(reset_n_i),
        .app_clk_i(phy_clk_i),
        .app_reset_n_i(reset_n_i),
        .core_stop_i(private_endpoint_upstream_fault_i || fail_closed_o),
        .core_fault_o(transport_fault),
        .core_controller_good_o(transport_good),
        .core_cmd_i(sem_cmd),
        .core_cmd_en_i(sem_cmd_en),
        .core_addr_i(sem_addr),
        .core_wr_data_i(sem_wr_data),
        .core_wr_en_i(sem_wr_en),
        .core_wr_end_i(sem_wr_end),
        .core_wr_mask_i(sem_wr_mask),
        .core_burst_i(sem_burst),
        .core_self_refresh_i(sem_sr),
        .core_refresh_i(sem_ref),
        .core_cmd_ready_o(sem_cmd_ready),
        .core_wr_ready_o(sem_wr_ready),
        .core_rd_data_o(sem_rd_data),
        .core_rd_valid_o(sem_rd_valid),
        .core_rd_end_o(sem_rd_end),
        .controller_pll_lock_i(reset_n_i),
        .controller_calibrated_i(reset_n_i),
        .app_cmd_ready_i(app_cmd_ready),
        .app_wr_ready_i(app_data_ready),
        .app_cmd_o(app_cmd),
        .app_cmd_en_o(app_cmd_en),
        .app_addr_o(app_addr),
        .app_wr_data_o(app_wdata),
        .app_wr_en_o(app_wr_en),
        .app_wr_end_o(app_wr_end),
        .app_wr_mask_o(app_wmask),
        .app_rd_data_i(app_rdata),
        .app_rd_valid_i(app_return),
        .app_rd_end_i(1'b1),
        .app_burst_o(app_burst),
        .app_self_refresh_o(app_self_refresh),
        .app_refresh_o(app_refresh));
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) loader_words_q<=0;
        else if(loader_valid && loader_ready) loader_words_q<=loader_words_q+1;
    end
    always_ff @(posedge phy_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            raw_wr_q<=0;raw_rd_q<=0;raw_count_q<=0;raw_requests_q<=0;raw_returns_q<=0;max_raw_q<=0;
            raw_lfsr_q<=32'h9163d5b7;app_cycle_q<=0;
            endpoint_model_reads_q<=0;endpoint_kv_reads_q<=0;endpoint_kv_writes_q<=0;endpoint_responses_q<=0;
            boot_writes_q<=0;boot_reads_q<=0;boot_returns_q<=0;runtime_corrupt_returns_q<=0;
        end else begin
            app_cycle_q<=app_cycle_q+1;
            raw_lfsr_q<={raw_lfsr_q[30:0],raw_lfsr_q[31]^raw_lfsr_q[21]^raw_lfsr_q[1]^raw_lfsr_q[0]};
            if(runtime_corrupt_return) runtime_corrupt_returns_q<=runtime_corrupt_returns_q+1;
            if(!sp_expect_fault && !fp_expect_fault && !different_model && (private_endpoint_upstream_fault_i ||
                    u_uart.u_machine.shared_app_fault || u_uart.u_machine.model_cdc_app_fault))
                $fatal(1,"booted shared DDR fault boot=%b handoff=%b runtime=%b boot_protocol=%b",
                    u_memory.boot_fault,u_memory.handoff_fault,u_memory.runtime_adapter_fault,
                    u_memory.u_boot.loader_protocol_fault_q);
            if(app_burst || app_self_refresh || app_refresh) $fatal(1,"unexpected manual controller operation");
            if(app_cmd_en) begin
                if(!app_cmd_ready || app_addr[2:0]!=0 || app_addr[28:22]!=0 || (app_cmd!=0 && app_cmd!=1))
                    $fatal(1,"shared DDR command acceptance/encoding mismatch");
                if(app_cmd==0) begin
                    if(!app_data_ready || !app_wr_en || !app_wr_end || app_wmask!=0)
                        $fatal(1,"split command/data write");
                    if(!thin_issue_runtime) begin
                        if(app_addr[21:3]!=boot_writes_q || boot_writes_q>=IMAGE_WORDS ||
                                app_wdata!==(ciphertext_image[boot_writes_q] ^
                                    ((corrupt_boot && boot_writes_q==0) ? 256'd1 : 256'd0)))
                            $fatal(1,"boot did not write the exact ordered fixed source");
                        model_memory[app_addr[21:3]]<=app_wdata;boot_writes_q<=boot_writes_q+1;
                    end else begin
                        if(app_addr[21:3]<227072 || app_addr[21:3]>=472832)
                            $fatal(1,"runtime write escaped K/V region");
                        scratch_memory[app_addr[21:3]-227072]<=app_wdata;
                        endpoint_kv_writes_q<=endpoint_kv_writes_q+1;
                    end
                end else begin
                    if(!thin_issue_runtime) begin
                        if(boot_writes_q!=IMAGE_WORDS || app_addr[21:3]!=boot_reads_q || boot_reads_q>=IMAGE_WORDS)
                            $fatal(1,"boot readback omitted, reordered or preceded complete writes");
                        boot_reads_q<=boot_reads_q+1;
                    end else if(app_addr[21:3]<IMAGE_WORDS) endpoint_model_reads_q<=endpoint_model_reads_q+1;
                    else if(app_addr[21:3]>=227072 && app_addr[21:3]<472832) endpoint_kv_reads_q<=endpoint_kv_reads_q+1;
                    else $fatal(1,"runtime read outside fixed regions");
                    raw_owner_fifo[raw_wr_q]<=thin_issue_runtime;
                    raw_fifo[raw_wr_q]<=app_addr[21:3];raw_due[raw_wr_q]<=app_cycle_q+(zero_stall ? 1 : 53);
                    raw_wr_q<=raw_wr_q+6'd1;raw_requests_q<=raw_requests_q+1;
                end
            end
            if(app_return) begin
                raw_rd_q<=raw_rd_q+6'd1;raw_returns_q<=raw_returns_q+1;
                if(raw_owner_fifo[raw_rd_q]) endpoint_responses_q<=endpoint_responses_q+1;
                else boot_returns_q<=boot_returns_q+1;
            end
            case({raw_read_fire,app_return})
                2'b10:raw_count_q<=raw_count_q+1;
                2'b01:raw_count_q<=raw_count_q-1;
                default: ;
            endcase
            if(raw_count_q>max_raw_q) max_raw_q<=raw_count_q;
            if(raw_count_q<0 || raw_count_q>32) $fatal(1,"shared DDR credit overflow");
            if(private_model_locked_i && (boot_writes_q!=IMAGE_WORDS || boot_reads_q!=IMAGE_WORDS ||
                    boot_returns_q!=IMAGE_WORDS || loader_words_q!=IMAGE_WORDS || !u_memory.u_boot.digest_success_app))
                $fatal(1,"runtime opened without complete authenticated readback");
        end
    end

    logic token_was_stalled_q = 1'b0;
    logic [11:0] stalled_token_q = 12'd0;
    always_ff @(posedge core_clk_i or negedge reset_n_i) begin
        if (!reset_n_i || clear_i || sp_expect_fault) begin
            token_was_stalled_q <= 1'b0;
            stalled_token_q <= 12'd0;
        end else begin
            if (token_was_stalled_q &&
                (!token_valid_o || (token_o != stalled_token_q)))
                $fatal(1, "connected generated token changed under backpressure");
            token_was_stalled_q <= token_valid_o && !token_ready_i;
            stalled_token_q <= token_o;
        end
    end

    `include "confidential_system_kv_oracle.inc.sv"
    `include "matched-campaign.inc.sv"
    `include "query_capture_monitor.inc.sv"
    `include "final-layer-frame.inc.sv"
    `include "elementwise_pipe_monitor.inc.sv"
    `include "normalizer_select_monitor.inc.sv"
    `include "fcp_monitor.inc.sv"
    `undef FP_DP
    `include "shp_monitor.inc.sv"
    `undef SP_SHELL
    `include "hdp_monitor.inc.sv"
    time c25_core_last=0,c25_app_last=0,c25_trusted_last=0;
    always @(posedge core_clk_i) begin
        if(c25_core_last!=0 && $time-c25_core_last!=40)
            $fatal(1,"CORE25 observed core period mismatch");
        c25_core_last=$time;
    end
    always @(posedge app_clk_i) begin
        if(c25_app_last!=0 && $time-c25_app_last!=40)
            $fatal(1,"CORE25 observed app period mismatch");
        c25_app_last=$time;
    end
    always @(posedge trusted_clk_i) begin
        if(c25_trusted_last!=0 && $time-c25_trusted_last!=80)
            $fatal(1,"CORE25 observed trusted period mismatch");
        c25_trusted_last=$time;
    end
    final begin
        if(c25_core_last==0 || c25_app_last==0 || c25_trusted_last==0)
            $fatal(1,"CORE25 missing clock observations");
        $display("THIN_APP_MODEL_CLOCK core_period_ns=40 semantic_app_period_ns=40 phy_app_period_ns=10 trusted_period_ns=80 physical_phy=0");
    end
    `include "thin_monitor.inc.sv"
    // Test-only correspondence check; no force/cut or ideal-value substitution.
    always @(posedge core_clk_i) begin
        if(reset_n_i && u_uart.u_machine.u_machine.u_six_layers.u_datapath.attention_cache_req_valid) begin
            case(u_uart.u_machine.u_machine.u_six_layers.u_datapath.u_attention.state_q)
                6'd4: if(u_uart.u_machine.u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_kind_i !== 2'b01)
                    $fatal(1,"selective score request is not KEY_ONLY");
                6'd2,6'd13: if(u_uart.u_machine.u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_kind_i !== 2'b10)
                    $fatal(1,"selective value request is not VALUE_ONLY");
                default: $fatal(1,"selective request outside fixed attention roles");
            endcase
        end
    end

    `include "common-head-owner.inc.sv"
endmodule
`default_nettype wire
