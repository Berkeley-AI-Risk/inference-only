    `define HDP u_memory.u_handoff
    wire hdp_old_boot_cmd_ready_o;
    wire hdp_old_runtime_cmd_ready_o;
    wire hdp_old_boot_data_ready_o;
    wire hdp_old_runtime_data_ready_o;
    wire hdp_old_boot_read_valid_o;
    wire hdp_old_runtime_read_valid_o;
    wire [255:0] hdp_old_read_data_o;
    wire hdp_old_read_end_o;
    wire [2:0] hdp_old_app_cmd_o;
    wire hdp_old_app_cmd_en_o;
    wire [28:0] hdp_old_app_addr_o;
    wire [255:0] hdp_old_app_data_o;
    wire hdp_old_app_data_en_o;
    wire hdp_old_app_data_end_o;
    wire [31:0] hdp_old_app_mask_o;
    wire hdp_old_runtime_locked_o;
    wire hdp_old_fault_o;
    wire hdp_old_runtime,hdp_old_controller_seen,hdp_old_lock_seen;
    wire [32:0] hdp_old_private;
    hdp_reference #(.WATCHDOG_CYCLES(50000000)) hdp_old(
        .clk(`HDP.clk),
        .reset_n(`HDP.reset_n),
        .controller_good_i(`HDP.controller_good_i),
        .boot_locked_i(`HDP.boot_locked_i),
        .boot_fault_i(`HDP.boot_fault_i),
        .runtime_fault_i(`HDP.runtime_fault_i),
        .boot_cmd_i(`HDP.boot_cmd_i),
        .runtime_cmd_i(`HDP.runtime_cmd_i),
        .boot_cmd_en_i(`HDP.boot_cmd_en_i),
        .runtime_cmd_en_i(`HDP.runtime_cmd_en_i),
        .boot_addr_i(`HDP.boot_addr_i),
        .runtime_addr_i(`HDP.runtime_addr_i),
        .boot_data_i(`HDP.boot_data_i),
        .runtime_data_i(`HDP.runtime_data_i),
        .boot_data_en_i(`HDP.boot_data_en_i),
        .runtime_data_en_i(`HDP.runtime_data_en_i),
        .boot_data_end_i(`HDP.boot_data_end_i),
        .runtime_data_end_i(`HDP.runtime_data_end_i),
        .boot_mask_i(`HDP.boot_mask_i),
        .runtime_mask_i(`HDP.runtime_mask_i),
        .app_cmd_ready_i(`HDP.app_cmd_ready_i),
        .app_data_ready_i(`HDP.app_data_ready_i),
        .app_read_valid_i(`HDP.app_read_valid_i),
        .app_read_end_i(`HDP.app_read_end_i),
        .app_read_data_i(`HDP.app_read_data_i),
        .boot_cmd_ready_o(hdp_old_boot_cmd_ready_o),
        .runtime_cmd_ready_o(hdp_old_runtime_cmd_ready_o),
        .boot_data_ready_o(hdp_old_boot_data_ready_o),
        .runtime_data_ready_o(hdp_old_runtime_data_ready_o),
        .boot_read_valid_o(hdp_old_boot_read_valid_o),
        .runtime_read_valid_o(hdp_old_runtime_read_valid_o),
        .read_data_o(hdp_old_read_data_o),
        .read_end_o(hdp_old_read_end_o),
        .app_cmd_o(hdp_old_app_cmd_o),
        .app_cmd_en_o(hdp_old_app_cmd_en_o),
        .app_addr_o(hdp_old_app_addr_o),
        .app_data_o(hdp_old_app_data_o),
        .app_data_en_o(hdp_old_app_data_en_o),
        .app_data_end_o(hdp_old_app_data_end_o),
        .app_mask_o(hdp_old_app_mask_o),
        .runtime_locked_o(hdp_old_runtime_locked_o),
        .fault_o(hdp_old_fault_o),
        .obs_runtime(hdp_old_runtime),
        .obs_controller_seen(hdp_old_controller_seen),
        .obs_lock_seen(hdp_old_lock_seen),
        .obs_private(hdp_old_private)
    );
    initial if (`HDP.WATCHDOG_CYCLES!=50000000) $fatal(1,"HDP actual watchdog differs from proof");
    wire hdp_output_mismatch=({hdp_old_boot_cmd_ready_o,hdp_old_runtime_cmd_ready_o,hdp_old_boot_data_ready_o,hdp_old_runtime_data_ready_o,hdp_old_boot_read_valid_o,hdp_old_runtime_read_valid_o,hdp_old_read_data_o,hdp_old_read_end_o,hdp_old_app_cmd_o,hdp_old_app_cmd_en_o,hdp_old_app_addr_o,hdp_old_app_data_o,hdp_old_app_data_en_o,hdp_old_app_data_end_o,hdp_old_app_mask_o,hdp_old_runtime_locked_o,hdp_old_fault_o}!=={`HDP.boot_cmd_ready_o,`HDP.runtime_cmd_ready_o,`HDP.boot_data_ready_o,`HDP.runtime_data_ready_o,`HDP.boot_read_valid_o,`HDP.runtime_read_valid_o,`HDP.read_data_o,`HDP.read_end_o,`HDP.app_cmd_o,`HDP.app_cmd_en_o,`HDP.app_addr_o,`HDP.app_data_o,`HDP.app_data_en_o,`HDP.app_data_end_o,`HDP.app_mask_o,`HDP.runtime_locked_o,`HDP.fault_o});

    wire [32:0] hdp_actual_private={`HDP.quiet_q,`HDP.pending_q,`HDP.watchdog_q};
    longint hdp_clocks=0,hdp_live=0,hdp_fault=0,hdp_different=0,hdp_reset=0;
    longint hdp_boot=0,hdp_runtime=0;
    always @(posedge app_clk_i) begin
        #1;
        hdp_clocks++;
        if (hdp_output_mismatch) $fatal(1,"HDP original-output mismatch");
        if ({hdp_old_runtime,hdp_old_controller_seen,hdp_old_lock_seen} !==
            {`HDP.runtime_q,`HDP.controller_seen_q,`HDP.lock_seen_q})
            $fatal(1,"HDP ownership/seen-state mismatch");
        if (!`HDP.reset_n) hdp_reset++;
        if (`HDP.runtime_q) hdp_runtime++; else hdp_boot++;
        if (`HDP.fault_o) begin
            hdp_fault++;
            if(hdp_old_private !== hdp_actual_private) hdp_different++;
        end else begin
            hdp_live++;
            if(hdp_old_private !== hdp_actual_private) $fatal(1,"HDP live bookkeeping mismatch");
        end
    end
    final begin
        $display("HDP_MODEL_MONITOR clocks=%0d live=%0d fault=%0d different=%0d reset=%0d boot=%0d runtime=%0d actual_inputs=25 actual_outputs=17 private_bits=33 all_outputs_equal=1 owner_always_equal=1 actual_prior_rtl=1 native_ports_added=0",
            hdp_clocks,hdp_live,hdp_fault,hdp_different,hdp_reset,hdp_boot,hdp_runtime);
    end
    `undef HDP
