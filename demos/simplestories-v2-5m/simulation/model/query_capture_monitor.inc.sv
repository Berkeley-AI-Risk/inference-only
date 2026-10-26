    localparam logic [3:0] QC_E_ATTN = 4'd5;

    // Testbench-only observation of the actual datapath, never a production port.
    `define QC_DP dut.u_machine.u_six_layers.u_datapath
    logic [1023:0] qc_original_payload;
    logic [63:0] qc_owned = 64'd0;
    longint qc_captures=0, qc_cancel_captures=0, qc_handshakes=0;
    longint qc_offers=0, qc_unowned_differences=0;
    wire qc_local_capture = `QC_DP.rst_n &&
        (`QC_DP.engine_state_q == QC_E_ATTN) &&
        `QC_DP.attention_query_read_valid_q;
    wire qc_fatal = `QC_DP.upstream_fault_i || `QC_DP.child_fault ||
        (`QC_DP.lock_seen_q && !`QC_DP.model_lock_i)
`ifndef SYNTHESIS
        || `QC_DP.simulation_x_fault
`endif
        ;
    always @(posedge core_clk_i or negedge reset_n_i) begin
        if (!reset_n_i) qc_owned <= 0;
        else begin
            if (qc_local_capture) qc_captures <= qc_captures+1;
            if (qc_local_capture && (qc_fatal || `QC_DP.clear_i || `QC_DP.fault_q))
                qc_cancel_captures <= qc_cancel_captures+1;
            // Exact predecessor priority, not a weakened valid-data oracle.
            if (!`QC_DP.rst_n) qc_owned <= 0;
            else if (qc_fatal) qc_owned <= 0;
            else if (`QC_DP.clear_i) qc_owned <= 0;
            else if (`QC_DP.fault_q) qc_owned <= 0;
            else if (`QC_DP.engine_state_q != QC_E_ATTN) qc_owned <= 0;
            else begin
                if (`QC_DP.attention_query_read_valid_q) begin
                    qc_original_payload[`QC_DP.attention_query_load_lane_q*16 +: 16]
                        <= `QC_DP.query_ram_read_data;
                    qc_owned[`QC_DP.attention_query_load_lane_q] <= 1;
                end
                if (`QC_DP.attention_query_fire) qc_owned <= 0;
            end
            if (`QC_DP.attention_query_fire) begin
                if (qc_owned !== {64{1'b1}} ||
                    qc_original_payload !== `QC_DP.attention_query_vector_q)
                    $fatal(1,"query capture consumed unowned/different actual payload");
                qc_handshakes <= qc_handshakes+1;
            end
        end
    end
    always @(negedge core_clk_i) begin
        #2;
        if (reset_n_i && `QC_DP.rst_n) begin
            if (`QC_DP.engine_state_q == QC_E_ATTN && !`QC_DP.clear_i && !`QC_DP.fault_q) begin
                if (`QC_DP.attention_query_loaded_q && qc_owned !== {64{1'b1}})
                    $fatal(1,"actual loaded query lacks complete overwrite ownership");
                if (`QC_DP.attention_query_loaded_q && `QC_DP.attention_query_read_valid_q)
                    $fatal(1,"actual query loaded/read-valid overlap");
            end
            if (`QC_DP.attention_query_valid) begin
                if (qc_owned !== {64{1'b1}} ||
                    qc_original_payload !== `QC_DP.attention_query_vector_q)
                    $fatal(1,"query capture offered unowned/different actual payload");
                qc_offers=qc_offers+1;
            end else if (qc_cancel_captures!=0 &&
                         qc_original_payload !== `QC_DP.attention_query_vector_q)
                qc_unowned_differences=qc_unowned_differences+1;
        end
    end
    final begin
        $display("QUERY_CAPTURE_MONITOR captures=%0d cancelled_captures=%0d handshakes=%0d offers=%0d unowned_differences=%0d actual_datapath=1 old_guard_shadow=1 native_ports_added=0",
            qc_captures,qc_cancel_captures,qc_handshakes,qc_offers,qc_unowned_differences);
    end
    `undef QC_DP
