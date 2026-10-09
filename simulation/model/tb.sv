`timescale 1ns/1ps
`default_nettype none

// End-to-end real-model KAT through the widened public tape, actual six-layer
// semantic datapath, typed atomic K/V cache, dual-clock capability boundary,
// and one private DDR endpoint.  The endpoint seam is physical-wrapper-only;
// APPEND, STEP, and CLEAR remain the complete user operation set.
module tb_board1_booted_shared_semantic #(parameter integer AUTH_BANKS=8);
    `define FP_DP dut.u_machine.u_six_layers.u_datapath
    bit fp_inject_fault=0,fp_expect_fault=0;
    `define SP_SHELL dut.u_machine.u_token_shell
    bit sp_inject_fault=0,sp_expect_fault=0;
    localparam integer IMAGE_WORDS = 227062;
    localparam integer SCRATCH_WORDS = 221184;
    localparam longint WATCHDOG_CYCLES = 64'd1_000_000_000_000;

    logic core_clk_i = 1'b0;
    wire app_clk_i = core_clk_i;
    logic phy_clk_i = 1'b0;
    always #20 core_clk_i = ~core_clk_i;
    always #5 phy_clk_i = ~phy_clk_i;
    logic reset_n_i = 1'b0;
    logic clear_i = 1'b0;
    logic append_valid_i = 1'b0;
    wire append_ready_o;
    logic [11:0] append_token_i = 12'd0;
    logic step_valid_i = 1'b0;
    wire step_ready_o;
    wire token_valid_o;
    logic token_ready_i = 1'b0;
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

    board1_context2048_shared_token_probe #(.AUTH_BANKS(AUTH_BANKS)) dut (.*);

    logic [255:0] semantic_image [0:IMAGE_WORDS-1];
    logic [255:0] scratch_memory [0:SCRATCH_WORDS-1];
    string image_memh_path;
    // Independent, ordered scoreboard for EVERY accepted semantic model read,
    // including local metadata ROM and all nonlinear/norm/embedding lookups.
    logic [18:0] expected_words [0:511];
    logic [8:0] expected_wr_q,expected_rd_q;
    longint expected_count_q,model_requests_q,model_responses_q;
    wire active_clear_test=$test$plusargs("CLEAR_AT_MODEL_RESPONSE") || $test$plusargs("QUERY_CAPTURE_CLEAR") || $test$plusargs("ELEMENTWISE_PIPE_CLEAR") || $test$plusargs("NORMALIZER_SELECT_CLEAR") || $test$plusargs("FCP_FAULT") || $test$plusargs("SHP_FAULT");
    wire checked_req=dut.model_req_valid&&dut.model_req_ready;
    wire checked_rsp=dut.model_rsp_valid&&dut.model_rsp_ready;
    always_ff @(posedge core_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin
            expected_wr_q<=0;expected_rd_q<=0;expected_count_q<=0;
            model_requests_q<=0;model_responses_q<=0;
        end else begin
            if(!sp_expect_fault && !fp_expect_fault && !corrupt_boot && !corrupt_runtime && (dut.auth_fault || dut.model_cdc_core_fault)) $fatal(1,"authentication/model CDC fault");
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
                    if(dut.model_req_word>=IMAGE_WORDS || expected_count_q>=512)
                        $fatal(1,"semantic model address/scoreboard bound");
                    expected_words[expected_wr_q]<=dut.model_req_word;
                    expected_wr_q<=expected_wr_q+9'd1;model_requests_q<=model_requests_q+1;
                end
                if(checked_rsp) begin
                    if(expected_count_q==0 || dut.model_rsp_data!==semantic_image[expected_words[expected_rd_q]])
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
                    dut.u_machine.u_token_shell.state_q,
                    dut.u_machine.u_six_layers.u_datapath.current_layer_q,
                    dut.u_machine.u_six_layers.u_datapath.current_stage_q,
                    dut.u_machine.u_six_layers.u_datapath.engine_state_q,
                    endpoint_model_reads_q, endpoint_kv_reads_q,
                    endpoint_kv_writes_q);
            if (token_valid_o && !token_ready_i)
                token_hold_cycles_q <= token_hold_cycles_q + 1;
        end
    end

    // Only this test's fixed source reads semantic_image. DDR begins without
    // that image; every word must be written through the real boot path.
    bit zero_stall,corrupt_boot,corrupt_runtime;
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
        (semantic_image[loader_words_q] ^ ((corrupt_boot && loader_words_q==0) ? 256'd1 : 256'd0)) : 256'd0;
    wire loader_done=loader_words_q==IMAGE_WORDS;
    (* async_reg="true" *) logic [1:0] core_fault_sync_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) core_fault_sync_q<=0;
        else core_fault_sync_q<={core_fault_sync_q[0],fail_closed_o};
    end
    board1_private_booted_shared_ddr u_memory (
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
            if(!sp_expect_fault && !fp_expect_fault && !corrupt_boot && !corrupt_runtime && (private_endpoint_upstream_fault_i ||
                    dut.shared_app_fault || dut.model_cdc_app_fault))
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
                                app_wdata!==(semantic_image[boot_writes_q] ^
                                    ((corrupt_boot && boot_writes_q==0) ? 256'd1 : 256'd0)))
                            $fatal(1,"boot did not write the exact ordered fixed source");
                        model_memory[app_addr[21:3]]<=app_wdata;boot_writes_q<=boot_writes_q+1;
                    end else begin
                        if(app_addr[21:3]<227072 || app_addr[21:3]>=448256)
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
                    else if(app_addr[21:3]>=227072 && app_addr[21:3]<448256) endpoint_kv_reads_q<=endpoint_kv_reads_q+1;
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

    task automatic append_token(input logic [11:0] token);
        begin
            @(negedge core_clk_i);
            while (append_ready_o !== 1'b1) begin
                if (fail_closed_o) $fatal(1, "failed while waiting to APPEND");
                @(negedge core_clk_i);
            end
            append_token_i = token;
            append_valid_i = 1'b1;
            @(negedge core_clk_i);
            append_valid_i = 1'b0;
            append_token_i = 12'd0;
        end
    endtask

    task automatic launch_step;
        begin
            @(negedge core_clk_i);
            while (step_ready_o !== 1'b1) begin
                if (fail_closed_o) $fatal(1, "failed while waiting to STEP");
                @(negedge core_clk_i);
            end
            step_valid_i = 1'b1;
            @(negedge core_clk_i);
            step_valid_i = 1'b0;
        end
    endtask

    task automatic accept_token(input logic [11:0] expected);
        longint hold;
        begin
            while (token_valid_o !== 1'b1) begin
                if (fail_closed_o)
                    $fatal(1, "machine failed before expected token %0d",
                           expected);
                @(negedge core_clk_i);
            end
            if (token_o !== expected)
                $fatal(1, "real greedy token got=%0d expected=%0d",
                       token_o, expected);
            for (hold = 0; hold < 7; hold = hold + 1) begin
                @(negedge core_clk_i);
                if (!token_valid_o || (token_o !== expected))
                    $fatal(1, "real token not held under backpressure");
            end
            token_ready_i = 1'b1;
            @(negedge core_clk_i);
            token_ready_i = 1'b0;
        end
    endtask

    always @(posedge core_clk_i) begin
        if ((core_cycle_q != 0) && ((core_cycle_q % 1_000_000) == 0)) begin
            $display("CONTEXT2048_CONNECTED_PROGRESS cycle=%0d shell=%0d L%0d/S%0d/E%0d prefixes=%h model=%0d kvr=%0d kvw=%0d rsp=%0d",
                core_cycle_q, dut.u_machine.u_token_shell.state_q,
                dut.u_machine.u_six_layers.u_datapath.current_layer_q,
                dut.u_machine.u_six_layers.u_datapath.current_stage_q,
                dut.u_machine.u_six_layers.u_datapath.engine_state_q,
                dut.u_machine.layer_committed_prefixes,
                endpoint_model_reads_q, endpoint_kv_reads_q,
                endpoint_kv_writes_q, endpoint_responses_q);
            $fflush();
        end
    end


    // Private simulation observations only; never added to production ports.
    longint unsigned profile_total_cycles;
    longint unsigned profile_model_accepts, profile_model_replies;
    longint unsigned profile_model_request_blocked, profile_model_owner_wait;
    longint unsigned profile_auth_head_miss, profile_auth_response_blocked;
    longint unsigned profile_auth_request_full, profile_auth_response_full;
    longint unsigned profile_raw_accepts, profile_raw_replies, profile_raw_blocked;
    longint unsigned profile_auth_dma [0:7];
    longint unsigned profile_hash_concurrency [0:AUTH_BANKS];
    longint unsigned profile_stage_cycles [0:31];
    longint unsigned profile_stage_misses [0:31];
    longint unsigned profile_stage_owner_wait [0:31];
    longint unsigned profile_attention_states [0:63];
    wire [AUTH_BANKS-1:0] profile_sha_busy;
    generate for(genvar profile_bank=0;profile_bank<AUTH_BANKS;profile_bank=profile_bank+1) begin: g_profile_bank
        assign profile_sha_busy[profile_bank]=dut.u_auth.g_bank[profile_bank].u_bank.sha_busy;
    end endgenerate
    wire profile_head_unverified=dut.u_auth.head_valid_q && !dut.u_auth.metadata_head &&
        !(dut.u_auth.bank_verified[dut.u_auth.head_bank] &&
          dut.u_auth.bank_page[dut.u_auth.head_bank]==dut.u_auth.head_page);
    wire profile_owner_without_response=
        dut.u_machine.u_private_ddr_arbiter.owner_count_q!=0 && !dut.model_rsp_valid;

    task automatic reset_private_profile;
        begin
            profile_total_cycles=0;
            profile_model_accepts=0;profile_model_replies=0;
            profile_model_request_blocked=0;profile_model_owner_wait=0;
            profile_auth_head_miss=0;profile_auth_response_blocked=0;
            profile_auth_request_full=0;profile_auth_response_full=0;
            profile_raw_accepts=0;profile_raw_replies=0;profile_raw_blocked=0;
            for(integer i=0;i<8;i=i+1) profile_auth_dma[i]=0;
            for(integer i=0;i<=AUTH_BANKS;i=i+1) profile_hash_concurrency[i]=0;
            for(integer i=0;i<32;i=i+1) begin
                profile_stage_cycles[i]=0;profile_stage_misses[i]=0;
                profile_stage_owner_wait[i]=0;
            end
            for(integer i=0;i<64;i=i+1) profile_attention_states[i]=0;
        end
    endtask

    always @(posedge core_clk_i) begin: observe_private_profile
        integer stage_index;
        if(profiling) begin
            stage_index=dut.u_machine.u_six_layers.u_datapath.current_stage_q;
            profile_total_cycles=profile_total_cycles+1;
            profile_stage_cycles[stage_index]=profile_stage_cycles[stage_index]+1;
            profile_auth_dma[dut.u_auth.dma_state_q]=profile_auth_dma[dut.u_auth.dma_state_q]+1;
            profile_hash_concurrency[$countones(profile_sha_busy)]=
                profile_hash_concurrency[$countones(profile_sha_busy)]+1;
            if(dut.model_req_valid && dut.model_req_ready)
                profile_model_accepts=profile_model_accepts+1;
            if(dut.model_rsp_valid && dut.model_rsp_ready)
                profile_model_replies=profile_model_replies+1;
            if(dut.model_req_valid && !dut.model_req_ready)
                profile_model_request_blocked=profile_model_request_blocked+1;
            if(profile_owner_without_response) begin
                profile_model_owner_wait=profile_model_owner_wait+1;
                profile_stage_owner_wait[stage_index]=profile_stage_owner_wait[stage_index]+1;
            end
            if(profile_head_unverified) begin
                profile_auth_head_miss=profile_auth_head_miss+1;
                profile_stage_misses[stage_index]=profile_stage_misses[stage_index]+1;
            end
            if(dut.model_rsp_valid && !dut.model_rsp_ready)
                profile_auth_response_blocked=profile_auth_response_blocked+1;
            if(dut.u_auth.request_count_q==64)
                profile_auth_request_full=profile_auth_request_full+1;
            if(dut.u_auth.response_count_q==32)
                profile_auth_response_full=profile_auth_response_full+1;
            if(dut.private_raw_req_valid_o && dut.private_raw_req_ready_i)
                profile_raw_accepts=profile_raw_accepts+1;
            if(dut.private_raw_rsp_valid_i)
                profile_raw_replies=profile_raw_replies+1;
            if(dut.private_raw_req_valid_o && !dut.private_raw_req_ready_i)
                profile_raw_blocked=profile_raw_blocked+1;
            if(stage_index==7)
                profile_attention_states[dut.u_machine.u_six_layers.u_datapath.u_attention.state_q]=
                    profile_attention_states[dut.u_machine.u_six_layers.u_datapath.u_attention.state_q]+1;
        end
    end

    task automatic emit_private_profile(input integer ordinal);
        begin
            $display("PRIVATE_PROFILE_SUMMARY ordinal=%0d cycles=%0d model_accepts=%0d model_replies=%0d model_request_blocked=%0d model_owner_wait=%0d head_unverified=%0d response_blocked=%0d request_full=%0d response_full=%0d raw_accepts=%0d raw_replies=%0d raw_blocked=%0d",
                ordinal,profile_total_cycles,profile_model_accepts,profile_model_replies,
                profile_model_request_blocked,profile_model_owner_wait,profile_auth_head_miss,
                profile_auth_response_blocked,profile_auth_request_full,profile_auth_response_full,
                profile_raw_accepts,profile_raw_replies,profile_raw_blocked);
            for(integer i=0;i<32;i=i+1)
                if(profile_stage_cycles[i]!=0)
                    $display("PRIVATE_PROFILE_STAGE ordinal=%0d bin=%0d cycles=%0d head_unverified=%0d owner_wait=%0d",
                        ordinal,i,profile_stage_cycles[i],profile_stage_misses[i],profile_stage_owner_wait[i]);
            for(integer i=0;i<8;i=i+1)
                $display("PRIVATE_PROFILE_DMA ordinal=%0d bin=%0d cycles=%0d",ordinal,i,profile_auth_dma[i]);
            for(integer i=0;i<=AUTH_BANKS;i=i+1)
                $display("PRIVATE_PROFILE_HASH ordinal=%0d bin=%0d cycles=%0d",ordinal,i,profile_hash_concurrency[i]);
            for(integer i=0;i<64;i=i+1)
                if(profile_attention_states[i]!=0)
                    $display("PRIVATE_PROFILE_ATTENTION ordinal=%0d bin=%0d cycles=%0d",ordinal,i,profile_attention_states[i]);
        end
    endtask
    longint step_start,step_cycles,step_number;
    longint stage_clocks [0:31];
    longint norm_shift_busy_clocks,norm_shift_requests;
    bit profiling=0;
    always @(posedge core_clk_i) begin
        if(profiling) begin
            stage_clocks[dut.u_machine.u_six_layers.u_datapath.current_stage_q]=
                stage_clocks[dut.u_machine.u_six_layers.u_datapath.current_stage_q]+1;
            if(dut.u_machine.u_six_layers.u_datapath.u_normalizer.u_shift.busy_q)
                norm_shift_busy_clocks=norm_shift_busy_clocks+1;
            if(dut.u_machine.u_six_layers.u_datapath.u_normalizer.shift_request_valid &&
                dut.u_machine.u_six_layers.u_datapath.u_normalizer.shift_request_ready)
                norm_shift_requests=norm_shift_requests+1;
        end
    end
    task automatic measured_step(input logic [11:0] expected);
        begin
            for(integer bin_index=0;bin_index<32;bin_index=bin_index+1) stage_clocks[bin_index]=0;
            norm_shift_busy_clocks=0;norm_shift_requests=0;
            reset_private_profile();
            profiling=1;step_start=core_cycle_q;
            launch_step();accept_token(expected);
            profiling=0;
            step_cycles=core_cycle_q-step_start;
            step_number=step_number+1;
            $display("SEMANTIC_STEP banks=%0d zero_stall=%0d ordinal=%0d token=%0d core_cycles=%0d tape=%0d prefixes=%h",
                AUTH_BANKS,zero_stall,step_number,expected,step_cycles,
                dut.u_machine.u_token_shell.tape_count_q,dut.u_machine.layer_committed_prefixes);
            for(integer bin_index=0;bin_index<32;bin_index=bin_index+1)
                if(stage_clocks[bin_index]!=0)
                    $display("SEMANTIC_STAGE ordinal=%0d stage=%0d clocks=%0d",step_number,bin_index,stage_clocks[bin_index]);
            $display("SEMANTIC_RNE ordinal=%0d projection_normalizer_shift_requests=%0d serial_shift_busy_clocks=%0d",
                step_number,norm_shift_requests,norm_shift_busy_clocks);
            emit_private_profile(step_number);
            repeat(20) @(negedge core_clk_i);
            if(fail_closed_o||busy_o||expected_count_q!=0)
                $fatal(1,"semantic step did not fully retire");
        end
    endtask
    task automatic clear_tape;
        begin
            @(negedge core_clk_i);clear_i=1;
            repeat(4) begin
                @(negedge core_clk_i);
                $display("CLEAR_TRACE auth=%b boundary=%b core=%b shell=%b layer=%b arbiter=%b dp=%b rms=%b projection=%b norm=%b lane=%b attention=%b kv=%b lookup=%b ddr=%b",
                    dut.auth_fault,dut.boundary_core_fault,dut.core_machine_fault,
                    dut.u_machine.shell_fail,dut.u_machine.layer_fail,dut.u_machine.arbiter_fail,
                    dut.u_machine.u_six_layers.u_datapath.fault_q,
                    dut.u_machine.u_six_layers.u_datapath.rms_fault,
                    dut.u_machine.u_six_layers.u_datapath.projection_fault,
                    dut.u_machine.u_six_layers.u_datapath.norm_fault,
                    dut.u_machine.u_six_layers.u_datapath.lane_fault,
                    dut.u_machine.u_six_layers.u_datapath.attention_fault,
                    dut.u_machine.u_six_layers.u_datapath.kv_fault,
                    dut.u_machine.u_six_layers.u_datapath.lookup_fault,
                    dut.u_machine.u_six_layers.u_datapath.ddr_arbiter_fault_q);
            end
            clear_i=0;
            while(!append_ready_o) begin
                if(fail_closed_o) $fatal(1,"CLEAR caused a fault");
                @(negedge core_clk_i);
            end
            if(dut.u_machine.u_token_shell.tape_count_q!=0 || dut.u_machine.layer_committed_prefixes!=0)
                $fatal(1,"CLEAR failed to revoke tape/KV validity");
        end
    endtask
    initial begin : test_campaign
        zero_stall=$test$plusargs("ZERO_STALL");step_number=0;
        corrupt_boot=$test$plusargs("CORRUPT_BOOT");corrupt_runtime=$test$plusargs("CORRUPT_RUNTIME");
        if(corrupt_boot && corrupt_runtime) $fatal(1,"one tamper mode at a time");
        if(!$value$plusargs("IMAGE_MEMH=%s",image_memh_path)) $fatal(1,"IMAGE_MEMH required");
        $readmemh(image_memh_path,semantic_image);
        repeat(8) @(posedge app_clk_i);
        @(negedge app_clk_i);reset_n_i=1;
        repeat(8) @(negedge core_clk_i);
        if(append_ready_o||step_ready_o||token_valid_o||model_locked_o||fail_closed_o)
            $fatal(1,"public machine opened before private lock");
        // No injected lock or seeded hash state: wait for the actual fixed
        // image to cross the loader, DDR readback and compact SHA pipeline.
        while(!model_locked_o && !fail_closed_o) begin
            @(negedge core_clk_i);
            if(!model_locked_o && (append_ready_o || step_ready_o || token_valid_o))
                $fatal(1,"public action available before successful boot");
        end
        if(corrupt_boot) begin
            repeat(40) @(negedge core_clk_i);
            if(!fail_closed_o || model_locked_o || append_ready_o || step_ready_o || token_valid_o ||
                    !u_memory.u_boot.digest_failure_app || u_memory.u_boot.digest_success_app ||
                    u_memory.u_handoff.runtime_q || loader_words_q!=IMAGE_WORDS ||
                    boot_writes_q!=IMAGE_WORDS || boot_reads_q!=IMAGE_WORDS || boot_returns_q!=IMAGE_WORDS ||
                    model_requests_q!=0 || endpoint_model_reads_q!=0 || endpoint_kv_writes_q!=0)
                $fatal(1,"corrupt boot rejection was incomplete or for the wrong reason");
            $display("PASS booted_semantic_negative mode=boot_corruption fixed_words=%0d public_tokens=0 actual_boot_sha=1",IMAGE_WORDS);
            $finish;
            disable test_campaign;
        end
        if(fail_closed_o) $fatal(1,"valid fixed-image boot failed");
        $display("BOOT_AUTHENTICATED words=%0d core_cycles=%0d app_cycles=%0d real_sha=1 handoff_drained=1",
            boot_returns_q,core_cycle_q,app_cycle_q);
        repeat(12) @(negedge core_clk_i);
        if(corrupt_runtime) begin
            append_token(12'd378);launch_step();
            begin : wait_page_rejection
                longint rejection_clocks;
                rejection_clocks=0;
                while(!fail_closed_o && rejection_clocks<1000000) begin
                    @(negedge core_clk_i);rejection_clocks=rejection_clocks+1;
                    if(token_valid_o) $fatal(1,"tampered post-boot page produced a token");
                end
                if(!fail_closed_o || !dut.auth_fault || runtime_corrupt_returns_q!=1 || token_valid_o)
                    $fatal(1,"post-boot corruption did not fail at live page verification");
            end
            repeat(40) @(negedge core_clk_i);
            if(model_locked_o || append_ready_o || step_ready_o || token_valid_o || app_cmd_en || app_wr_en)
                $fatal(1,"post-boot tamper failure did not remain closed");
            $display("PASS booted_semantic_negative mode=post_boot_corruption fixed_words=%0d public_tokens=0 actual_boot_sha=1 live_page_sha=1",IMAGE_WORDS);
            $finish;
            disable test_campaign;
        end
        if(!model_locked_o||!append_ready_o||step_ready_o||token_valid_o||fail_closed_o)
            $fatal(1,"locked machine did not open correctly");
        `include "shp_fault.inc.sv"
        `include "fcp_fault.inc.sv"
        `include "normalizer_select_clear.inc.sv"
        `include "elementwise_pipe_clear.inc.sv"
        `include "query_capture_clear.inc.sv"
        `include "active_clear.inc.sv"
        begin : profile_workload
            longint case_id;
            if (!$value$plusargs("PROFILE_CASE=%d",case_id)) $fatal(1,"PROFILE_CASE required");
            case(case_id)
            0: begin
                append_token(12'd378);
                #1;
                if(dut.u_machine.u_token_shell.tape_count_q!=1 || dut.u_machine.layer_committed_prefixes!=0 || !step_ready_o || token_valid_o)
                    $fatal(1,"profile prompt admission");
                measured_step(12'd200);
                measured_step(12'd15);
                measured_step(12'd103);
                measured_step(12'd157);
                if(dut.u_machine.u_token_shell.tape_count_q!=5 || dut.u_machine.layer_committed_prefixes!=={6{12'd4}} || endpoint_kv_writes_q!=432)
                    $fatal(1,"profile tape/prefix/write census");
                $display("PROFILE_WORKLOAD case=around4 prompt=1 outputs=4 kv_reads=%0d model_reads=%0d raw_reads=%0d",
                    endpoint_kv_reads_q,model_requests_q,raw_requests_q);
            end
            1: begin
                append_token(12'd308);
                append_token(12'd94);
                append_token(12'd317);
                append_token(12'd542);
                append_token(12'd93);
                append_token(12'd85);
                append_token(12'd346);
                append_token(12'd539);
                append_token(12'd15);
                append_token(12'd111);
                append_token(12'd354);
                append_token(12'd32);
                append_token(12'd1520);
                append_token(12'd852);
                append_token(12'd108);
                append_token(12'd32);
                append_token(12'd524);
                append_token(12'd15);
                append_token(12'd85);
                append_token(12'd852);
                append_token(12'd1121);
                append_token(12'd13);
                append_token(12'd94);
                append_token(12'd85);
                append_token(12'd1081);
                append_token(12'd355);
                append_token(12'd15);
                append_token(12'd308);
                append_token(12'd94);
                append_token(12'd317);
                append_token(12'd542);
                append_token(12'd93);
                append_token(12'd85);
                append_token(12'd346);
                append_token(12'd539);
                append_token(12'd15);
                append_token(12'd111);
                append_token(12'd354);
                append_token(12'd32);
                append_token(12'd1520);
                append_token(12'd852);
                append_token(12'd108);
                append_token(12'd32);
                append_token(12'd524);
                append_token(12'd15);
                append_token(12'd85);
                append_token(12'd852);
                append_token(12'd1121);
                append_token(12'd13);
                append_token(12'd94);
                append_token(12'd85);
                append_token(12'd1081);
                append_token(12'd355);
                append_token(12'd15);
                append_token(12'd308);
                append_token(12'd94);
                append_token(12'd317);
                append_token(12'd542);
                append_token(12'd93);
                append_token(12'd85);
                append_token(12'd346);
                append_token(12'd539);
                append_token(12'd15);
                append_token(12'd111);
                append_token(12'd354);
                append_token(12'd32);
                append_token(12'd1520);
                append_token(12'd852);
                append_token(12'd108);
                append_token(12'd32);
                append_token(12'd524);
                append_token(12'd15);
                append_token(12'd85);
                append_token(12'd852);
                append_token(12'd1121);
                append_token(12'd13);
                append_token(12'd94);
                append_token(12'd85);
                append_token(12'd1081);
                append_token(12'd355);
                append_token(12'd15);
                append_token(12'd308);
                append_token(12'd94);
                append_token(12'd317);
                append_token(12'd542);
                append_token(12'd93);
                append_token(12'd85);
                append_token(12'd346);
                append_token(12'd539);
                append_token(12'd15);
                append_token(12'd111);
                append_token(12'd354);
                append_token(12'd32);
                append_token(12'd1520);
                append_token(12'd852);
                append_token(12'd108);
                append_token(12'd32);
                append_token(12'd524);
                append_token(12'd15);
                append_token(12'd85);
                append_token(12'd852);
                append_token(12'd1121);
                append_token(12'd13);
                append_token(12'd94);
                append_token(12'd85);
                append_token(12'd1081);
                append_token(12'd355);
                append_token(12'd15);
                append_token(12'd308);
                append_token(12'd94);
                append_token(12'd317);
                append_token(12'd542);
                append_token(12'd93);
                append_token(12'd85);
                append_token(12'd346);
                append_token(12'd539);
                append_token(12'd15);
                append_token(12'd111);
                append_token(12'd354);
                append_token(12'd32);
                append_token(12'd1520);
                append_token(12'd852);
                append_token(12'd108);
                append_token(12'd32);
                append_token(12'd524);
                append_token(12'd15);
                append_token(12'd85);
                append_token(12'd852);
                #1;
                if(dut.u_machine.u_token_shell.tape_count_q!=128 || dut.u_machine.layer_committed_prefixes!=0 || !step_ready_o || token_valid_o)
                    $fatal(1,"profile prompt admission");
                measured_step(12'd326);
                measured_step(12'd547);
                if(dut.u_machine.u_token_shell.tape_count_q!=130 || dut.u_machine.layer_committed_prefixes!=={6{12'd129}} || endpoint_kv_writes_q!=13932)
                    $fatal(1,"profile tape/prefix/write census");
                $display("PROFILE_WORKLOAD case=prefix128-two prompt=128 outputs=2 kv_reads=%0d model_reads=%0d raw_reads=%0d",
                    endpoint_kv_reads_q,model_requests_q,raw_requests_q);
            end
            default: $fatal(1,"unknown profile case");
            endcase
            while(thin_accepted!=thin_issued || u_transport.reserved_q!=0 ||
                  raw_count_q!=0 || dut.u_model_cdc.reserved_q!=0 ||
                  dut.u_shared.busy_o || dut.u_auth.dma_state_q!=0)
                @(negedge core_clk_i);
            if(fail_closed_o || raw_requests_q!=raw_returns_q ||
               model_requests_q!=model_responses_q || expected_count_q!=0)
                $fatal(1,"profile drain failed");
            clear_tape();append_token(12'd378);measured_step(12'd200);
            while(thin_accepted!=thin_issued || u_transport.reserved_q!=0 ||
                  raw_count_q!=0 || dut.u_model_cdc.reserved_q!=0 ||
                  dut.u_shared.busy_o || dut.u_auth.dma_state_q!=0)
                @(negedge core_clk_i);
            if(fail_closed_o || raw_requests_q!=raw_returns_q ||
               model_requests_q!=model_responses_q || expected_count_q!=0)
                $fatal(1,"profile drain failed");
            if(dut.u_machine.u_token_shell.tape_count_q!=2 ||
               dut.u_machine.layer_committed_prefixes!=={6{12'd1}})
                $fatal(1,"profile CLEAR/replay failed");
            $display("PASS selective_reads_model case=%0d clear_replay=1 actual_sha=1 production_changes=2",case_id);
        end
        $finish;
    end
    `include "query_capture_monitor.inc.sv"
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
        if(reset_n_i && dut.u_machine.u_six_layers.u_datapath.attention_cache_req_valid) begin
            case(dut.u_machine.u_six_layers.u_datapath.u_attention.state_q)
                6'd4: if(dut.u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_kind_i !== 2'b01)
                    $fatal(1,"selective score request is not KEY_ONLY");
                6'd2,6'd13: if(dut.u_machine.u_six_layers.u_datapath.u_kv_cache.attention_req_kind_i !== 2'b10)
                    $fatal(1,"selective value request is not VALUE_ONLY");
                default: $fatal(1,"selective request outside fixed attention roles");
            endcase
        end
    end

endmodule
`default_nettype wire
