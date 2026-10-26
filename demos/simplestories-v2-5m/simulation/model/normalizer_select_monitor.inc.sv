    // Test-only literal prior controller for embedding.
    `define NS_LANE dut.u_machine.u_token_shell.u_fixed_embedding.u_embedding_normalizer
    wire ns0_ref_start_ready_o;
    wire ns0_ref_input_ready_o;
    wire ns0_ref_result_valid_o;
    wire [9:0]             ns0_ref_result_row_index_o;
    wire signed [15:0]     ns0_ref_result_mantissa_o;
    wire signed [7:0]      ns0_ref_result_exponent_o;
    wire ns0_ref_result_last_o;
    wire ns0_ref_done_valid_o;
    wire ns0_ref_busy_o;
    wire ns0_ref_range_fault_o;
    normalizer_selection_model_reference #(.MAX_COMPUTE_CYCLES(4000000)) ns0_ref(
        .clk(`NS_LANE.clk),
        .rst_n(`NS_LANE.rst_n),
        .clear_i(`NS_LANE.clear_i),
        .model_lock_i(`NS_LANE.model_lock_i),
        .upstream_fault_i(`NS_LANE.upstream_fault_i),
        .start_valid_i(`NS_LANE.start_valid_i && `NS_LANE.start_ready_o),
        .start_ready_o(ns0_ref_start_ready_o),
        .fixed_layer_i(`NS_LANE.fixed_layer_i),
        .fixed_job_i(`NS_LANE.fixed_job_i),
        .input_valid_i(`NS_LANE.input_valid_i && `NS_LANE.input_ready_o),
        .input_ready_o(ns0_ref_input_ready_o),
        .input_row_index_i(`NS_LANE.input_row_index_i),
        .input_raw_i(`NS_LANE.input_raw_i),
        .input_source_exponent_i(`NS_LANE.input_source_exponent_i),
        .input_last_i(`NS_LANE.input_last_i),
        .result_valid_o(ns0_ref_result_valid_o),
        .result_ready_i(`NS_LANE.result_valid_o && `NS_LANE.result_ready_i),
        .result_row_index_o(ns0_ref_result_row_index_o),
        .result_mantissa_o(ns0_ref_result_mantissa_o),
        .result_exponent_o(ns0_ref_result_exponent_o),
        .result_last_o(ns0_ref_result_last_o),
        .done_valid_o(ns0_ref_done_valid_o),
        .done_ready_i(`NS_LANE.done_valid_o && `NS_LANE.done_ready_i),
        .busy_o(ns0_ref_busy_o),
        .range_fault_o(ns0_ref_range_fault_o)
    );
    initial if (`NS_LANE.MAX_COMPUTE_CYCLES != 4000000) $fatal(1,"normalizer shadow deadline mismatch");

    longint ns0_clock=0, ns0_accepted=0, ns0_completed=0, ns0_cancelled=0;
    longint ns0_first_results=0, ns0_results=0, ns0_added_clocks=0;
    longint ns0_reference_cycle=0, ns0_rows=0;
    longint ns0_bits=0, ns0_exponents=0, ns0_evaluations=0;
    bit ns0_pending=0, ns0_reference_seen=0, ns0_first_seen=0;
    always @(posedge core_clk_i) begin
        ns0_clock++;
        if (!`NS_LANE.rst_n || `NS_LANE.clear_i ||
            `NS_LANE.upstream_fault_i || !`NS_LANE.model_lock_i) begin
            if (ns0_pending) ns0_cancelled++;
            ns0_pending=0; ns0_reference_seen=0; ns0_first_seen=0;
        end else begin
            if (`NS_LANE.start_valid_i && `NS_LANE.start_ready_o) begin
                if (ns0_pending || !ns0_ref_start_ready_o)
                    $fatal(1,"normalizer model shadow missed/overlapped a start");
                ns0_accepted++; ns0_pending=1; ns0_reference_seen=0; ns0_first_seen=0;
                ns0_rows=`NS_LANE.rows_for_job(`NS_LANE.fixed_job_i);
            end
            if (`NS_LANE.input_valid_i && `NS_LANE.input_ready_o && !ns0_ref_input_ready_o)
                $fatal(1,"normalizer model shadow missed an input");
            if (`NS_LANE.state_q == 4'd11) ns0_bits++;
            if (`NS_LANE.state_q == 4'd12) begin
                ns0_exponents++;
                if (`NS_LANE.fit_length_pipe_q !== `NS_LANE.first_fit_length50(`NS_LANE.selected_raw) ||
                    `NS_LANE.fit_source_pipe_q !== `NS_LANE.selected_source_exponent ||
                    `NS_LANE.fit_zero_pipe_q !== (`NS_LANE.selected_raw == 0))
                    $fatal(1,"model selection stage lost actual RAM ownership");
            end
            if (`NS_LANE.state_q == 4'd3) begin
                ns0_evaluations++;
                if (`NS_LANE.selected_first_fit !== ns0_ref.first_fit_exponent50(`NS_LANE.selected_raw,`NS_LANE.selected_source_exponent) ||
                    `NS_LANE.selected_nonzero !== (`NS_LANE.selected_raw != 0))
                    $fatal(1,"model selection stage differs from literal original function");
            end
            if (ns0_ref_result_valid_o && !ns0_reference_seen) begin
                if (!ns0_pending) $fatal(1,"normalizer model reference first result unowned");
                ns0_reference_seen=1; ns0_reference_cycle=ns0_clock;
            end
            if (`NS_LANE.result_valid_o) begin
                if (!ns0_pending || !ns0_ref_result_valid_o || {`NS_LANE.result_row_index_o,`NS_LANE.result_mantissa_o,`NS_LANE.result_exponent_o,`NS_LANE.result_last_o} !== {ns0_ref_result_row_index_o,ns0_ref_result_mantissa_o,ns0_ref_result_exponent_o,ns0_ref_result_last_o})
                    $fatal(1,"normalizer model result differs from literal prior controller");
                if (!ns0_first_seen) begin
                    if (!ns0_reference_seen || ns0_clock-ns0_reference_cycle != 2*ns0_rows)
                        $fatal(1,"normalizer model first-result latency not two extra clocks per row");
                    ns0_first_results++; ns0_added_clocks+=ns0_clock-ns0_reference_cycle;
                    ns0_first_seen=1;
                end
                if (`NS_LANE.result_ready_i) ns0_results++;
            end
            if (`NS_LANE.done_valid_o && `NS_LANE.done_ready_i) begin
                if (!ns0_pending || !ns0_first_seen || !ns0_ref_done_valid_o)
                    $fatal(1,"normalizer model completion ownership differs");
                ns0_pending=0; ns0_completed++;
            end
        end
    end
    final begin
        $display("NORMALIZER_MODEL_MONITOR instance=embedding accepted=%0d completed=%0d cancelled=%0d pending=%0d first_results=%0d rows=%0d added_clocks=%0d bits=%0d exponents=%0d evaluations=%0d actual_prior_rtl=1 native_ports_added=0",
            ns0_accepted,ns0_completed,ns0_cancelled,ns0_pending,ns0_first_results,ns0_results,ns0_added_clocks,ns0_bits,ns0_exponents,ns0_evaluations);
    end
    `undef NS_LANE

    // Test-only literal prior controller for projection.
    `define NS_LANE dut.u_machine.u_six_layers.u_datapath.u_normalizer
    wire ns1_ref_start_ready_o;
    wire ns1_ref_input_ready_o;
    wire ns1_ref_result_valid_o;
    wire [9:0]             ns1_ref_result_row_index_o;
    wire signed [15:0]     ns1_ref_result_mantissa_o;
    wire signed [7:0]      ns1_ref_result_exponent_o;
    wire ns1_ref_result_last_o;
    wire ns1_ref_done_valid_o;
    wire ns1_ref_busy_o;
    wire ns1_ref_range_fault_o;
    normalizer_selection_model_reference #(.MAX_COMPUTE_CYCLES(2000000)) ns1_ref(
        .clk(`NS_LANE.clk),
        .rst_n(`NS_LANE.rst_n),
        .clear_i(`NS_LANE.clear_i),
        .model_lock_i(`NS_LANE.model_lock_i),
        .upstream_fault_i(`NS_LANE.upstream_fault_i),
        .start_valid_i(`NS_LANE.start_valid_i && `NS_LANE.start_ready_o),
        .start_ready_o(ns1_ref_start_ready_o),
        .fixed_layer_i(`NS_LANE.fixed_layer_i),
        .fixed_job_i(`NS_LANE.fixed_job_i),
        .input_valid_i(`NS_LANE.input_valid_i && `NS_LANE.input_ready_o),
        .input_ready_o(ns1_ref_input_ready_o),
        .input_row_index_i(`NS_LANE.input_row_index_i),
        .input_raw_i(`NS_LANE.input_raw_i),
        .input_source_exponent_i(`NS_LANE.input_source_exponent_i),
        .input_last_i(`NS_LANE.input_last_i),
        .result_valid_o(ns1_ref_result_valid_o),
        .result_ready_i(`NS_LANE.result_valid_o && `NS_LANE.result_ready_i),
        .result_row_index_o(ns1_ref_result_row_index_o),
        .result_mantissa_o(ns1_ref_result_mantissa_o),
        .result_exponent_o(ns1_ref_result_exponent_o),
        .result_last_o(ns1_ref_result_last_o),
        .done_valid_o(ns1_ref_done_valid_o),
        .done_ready_i(`NS_LANE.done_valid_o && `NS_LANE.done_ready_i),
        .busy_o(ns1_ref_busy_o),
        .range_fault_o(ns1_ref_range_fault_o)
    );
    initial if (`NS_LANE.MAX_COMPUTE_CYCLES != 2000000) $fatal(1,"normalizer shadow deadline mismatch");

    longint ns1_clock=0, ns1_accepted=0, ns1_completed=0, ns1_cancelled=0;
    longint ns1_first_results=0, ns1_results=0, ns1_added_clocks=0;
    longint ns1_reference_cycle=0, ns1_rows=0;
    longint ns1_bits=0, ns1_exponents=0, ns1_evaluations=0;
    bit ns1_pending=0, ns1_reference_seen=0, ns1_first_seen=0;
    always @(posedge core_clk_i) begin
        ns1_clock++;
        if (!`NS_LANE.rst_n || `NS_LANE.clear_i ||
            `NS_LANE.upstream_fault_i || !`NS_LANE.model_lock_i) begin
            if (ns1_pending) ns1_cancelled++;
            ns1_pending=0; ns1_reference_seen=0; ns1_first_seen=0;
        end else begin
            if (`NS_LANE.start_valid_i && `NS_LANE.start_ready_o) begin
                if (ns1_pending || !ns1_ref_start_ready_o)
                    $fatal(1,"normalizer model shadow missed/overlapped a start");
                ns1_accepted++; ns1_pending=1; ns1_reference_seen=0; ns1_first_seen=0;
                ns1_rows=`NS_LANE.rows_for_job(`NS_LANE.fixed_job_i);
            end
            if (`NS_LANE.input_valid_i && `NS_LANE.input_ready_o && !ns1_ref_input_ready_o)
                $fatal(1,"normalizer model shadow missed an input");
            if (`NS_LANE.state_q == 4'd11) ns1_bits++;
            if (`NS_LANE.state_q == 4'd12) begin
                ns1_exponents++;
                if (`NS_LANE.fit_length_pipe_q !== `NS_LANE.first_fit_length50(`NS_LANE.selected_raw) ||
                    `NS_LANE.fit_source_pipe_q !== `NS_LANE.selected_source_exponent ||
                    `NS_LANE.fit_zero_pipe_q !== (`NS_LANE.selected_raw == 0))
                    $fatal(1,"model selection stage lost actual RAM ownership");
            end
            if (`NS_LANE.state_q == 4'd3) begin
                ns1_evaluations++;
                if (`NS_LANE.selected_first_fit !== ns1_ref.first_fit_exponent50(`NS_LANE.selected_raw,`NS_LANE.selected_source_exponent) ||
                    `NS_LANE.selected_nonzero !== (`NS_LANE.selected_raw != 0))
                    $fatal(1,"model selection stage differs from literal original function");
            end
            if (ns1_ref_result_valid_o && !ns1_reference_seen) begin
                if (!ns1_pending) $fatal(1,"normalizer model reference first result unowned");
                ns1_reference_seen=1; ns1_reference_cycle=ns1_clock;
            end
            if (`NS_LANE.result_valid_o) begin
                if (!ns1_pending || !ns1_ref_result_valid_o || {`NS_LANE.result_row_index_o,`NS_LANE.result_mantissa_o,`NS_LANE.result_exponent_o,`NS_LANE.result_last_o} !== {ns1_ref_result_row_index_o,ns1_ref_result_mantissa_o,ns1_ref_result_exponent_o,ns1_ref_result_last_o})
                    $fatal(1,"normalizer model result differs from literal prior controller");
                if (!ns1_first_seen) begin
                    if (!ns1_reference_seen || ns1_clock-ns1_reference_cycle != 2*ns1_rows)
                        $fatal(1,"normalizer model first-result latency not two extra clocks per row");
                    ns1_first_results++; ns1_added_clocks+=ns1_clock-ns1_reference_cycle;
                    ns1_first_seen=1;
                end
                if (`NS_LANE.result_ready_i) ns1_results++;
            end
            if (`NS_LANE.done_valid_o && `NS_LANE.done_ready_i) begin
                if (!ns1_pending || !ns1_first_seen || !ns1_ref_done_valid_o)
                    $fatal(1,"normalizer model completion ownership differs");
                ns1_pending=0; ns1_completed++;
            end
        end
    end
    final begin
        $display("NORMALIZER_MODEL_MONITOR instance=projection accepted=%0d completed=%0d cancelled=%0d pending=%0d first_results=%0d rows=%0d added_clocks=%0d bits=%0d exponents=%0d evaluations=%0d actual_prior_rtl=1 native_ports_added=0",
            ns1_accepted,ns1_completed,ns1_cancelled,ns1_pending,ns1_first_results,ns1_results,ns1_added_clocks,ns1_bits,ns1_exponents,ns1_evaluations);
    end
    `undef NS_LANE

    // Test-only literal prior controller for rms.
    `define NS_LANE dut.u_machine.u_six_layers.u_datapath.u_rmsnorm.u_frozen_vector_normalizer
    wire ns2_ref_start_ready_o;
    wire ns2_ref_input_ready_o;
    wire ns2_ref_result_valid_o;
    wire [9:0]             ns2_ref_result_row_index_o;
    wire signed [15:0]     ns2_ref_result_mantissa_o;
    wire signed [7:0]      ns2_ref_result_exponent_o;
    wire ns2_ref_result_last_o;
    wire ns2_ref_done_valid_o;
    wire ns2_ref_busy_o;
    wire ns2_ref_range_fault_o;
    normalizer_selection_model_reference #(.MAX_COMPUTE_CYCLES(2000000)) ns2_ref(
        .clk(`NS_LANE.clk),
        .rst_n(`NS_LANE.rst_n),
        .clear_i(`NS_LANE.clear_i),
        .model_lock_i(`NS_LANE.model_lock_i),
        .upstream_fault_i(`NS_LANE.upstream_fault_i),
        .start_valid_i(`NS_LANE.start_valid_i && `NS_LANE.start_ready_o),
        .start_ready_o(ns2_ref_start_ready_o),
        .fixed_layer_i(`NS_LANE.fixed_layer_i),
        .fixed_job_i(`NS_LANE.fixed_job_i),
        .input_valid_i(`NS_LANE.input_valid_i && `NS_LANE.input_ready_o),
        .input_ready_o(ns2_ref_input_ready_o),
        .input_row_index_i(`NS_LANE.input_row_index_i),
        .input_raw_i(`NS_LANE.input_raw_i),
        .input_source_exponent_i(`NS_LANE.input_source_exponent_i),
        .input_last_i(`NS_LANE.input_last_i),
        .result_valid_o(ns2_ref_result_valid_o),
        .result_ready_i(`NS_LANE.result_valid_o && `NS_LANE.result_ready_i),
        .result_row_index_o(ns2_ref_result_row_index_o),
        .result_mantissa_o(ns2_ref_result_mantissa_o),
        .result_exponent_o(ns2_ref_result_exponent_o),
        .result_last_o(ns2_ref_result_last_o),
        .done_valid_o(ns2_ref_done_valid_o),
        .done_ready_i(`NS_LANE.done_valid_o && `NS_LANE.done_ready_i),
        .busy_o(ns2_ref_busy_o),
        .range_fault_o(ns2_ref_range_fault_o)
    );
    initial if (`NS_LANE.MAX_COMPUTE_CYCLES != 2000000) $fatal(1,"normalizer shadow deadline mismatch");

    longint ns2_clock=0, ns2_accepted=0, ns2_completed=0, ns2_cancelled=0;
    longint ns2_first_results=0, ns2_results=0, ns2_added_clocks=0;
    longint ns2_reference_cycle=0, ns2_rows=0;
    longint ns2_bits=0, ns2_exponents=0, ns2_evaluations=0;
    bit ns2_pending=0, ns2_reference_seen=0, ns2_first_seen=0;
    always @(posedge core_clk_i) begin
        ns2_clock++;
        if (!`NS_LANE.rst_n || `NS_LANE.clear_i ||
            `NS_LANE.upstream_fault_i || !`NS_LANE.model_lock_i) begin
            if (ns2_pending) ns2_cancelled++;
            ns2_pending=0; ns2_reference_seen=0; ns2_first_seen=0;
        end else begin
            if (`NS_LANE.start_valid_i && `NS_LANE.start_ready_o) begin
                if (ns2_pending || !ns2_ref_start_ready_o)
                    $fatal(1,"normalizer model shadow missed/overlapped a start");
                ns2_accepted++; ns2_pending=1; ns2_reference_seen=0; ns2_first_seen=0;
                ns2_rows=`NS_LANE.rows_for_job(`NS_LANE.fixed_job_i);
            end
            if (`NS_LANE.input_valid_i && `NS_LANE.input_ready_o && !ns2_ref_input_ready_o)
                $fatal(1,"normalizer model shadow missed an input");
            if (`NS_LANE.state_q == 4'd11) ns2_bits++;
            if (`NS_LANE.state_q == 4'd12) begin
                ns2_exponents++;
                if (`NS_LANE.fit_length_pipe_q !== `NS_LANE.first_fit_length50(`NS_LANE.selected_raw) ||
                    `NS_LANE.fit_source_pipe_q !== `NS_LANE.selected_source_exponent ||
                    `NS_LANE.fit_zero_pipe_q !== (`NS_LANE.selected_raw == 0))
                    $fatal(1,"model selection stage lost actual RAM ownership");
            end
            if (`NS_LANE.state_q == 4'd3) begin
                ns2_evaluations++;
                if (`NS_LANE.selected_first_fit !== ns2_ref.first_fit_exponent50(`NS_LANE.selected_raw,`NS_LANE.selected_source_exponent) ||
                    `NS_LANE.selected_nonzero !== (`NS_LANE.selected_raw != 0))
                    $fatal(1,"model selection stage differs from literal original function");
            end
            if (ns2_ref_result_valid_o && !ns2_reference_seen) begin
                if (!ns2_pending) $fatal(1,"normalizer model reference first result unowned");
                ns2_reference_seen=1; ns2_reference_cycle=ns2_clock;
            end
            if (`NS_LANE.result_valid_o) begin
                if (!ns2_pending || !ns2_ref_result_valid_o || {`NS_LANE.result_row_index_o,`NS_LANE.result_mantissa_o,`NS_LANE.result_exponent_o,`NS_LANE.result_last_o} !== {ns2_ref_result_row_index_o,ns2_ref_result_mantissa_o,ns2_ref_result_exponent_o,ns2_ref_result_last_o})
                    $fatal(1,"normalizer model result differs from literal prior controller");
                if (!ns2_first_seen) begin
                    if (!ns2_reference_seen || ns2_clock-ns2_reference_cycle != 2*ns2_rows)
                        $fatal(1,"normalizer model first-result latency not two extra clocks per row");
                    ns2_first_results++; ns2_added_clocks+=ns2_clock-ns2_reference_cycle;
                    ns2_first_seen=1;
                end
                if (`NS_LANE.result_ready_i) ns2_results++;
            end
            if (`NS_LANE.done_valid_o && `NS_LANE.done_ready_i) begin
                if (!ns2_pending || !ns2_first_seen || !ns2_ref_done_valid_o)
                    $fatal(1,"normalizer model completion ownership differs");
                ns2_pending=0; ns2_completed++;
            end
        end
    end
    final begin
        $display("NORMALIZER_MODEL_MONITOR instance=rms accepted=%0d completed=%0d cancelled=%0d pending=%0d first_results=%0d rows=%0d added_clocks=%0d bits=%0d exponents=%0d evaluations=%0d actual_prior_rtl=1 native_ports_added=0",
            ns2_accepted,ns2_completed,ns2_cancelled,ns2_pending,ns2_first_results,ns2_results,ns2_added_clocks,ns2_bits,ns2_exponents,ns2_evaluations);
    end
    `undef NS_LANE

    // Test-only literal prior controller for final.
    `define NS_LANE dut.u_machine.u_token_shell.u_final_rmsnorm.u_frozen_vector_normalizer
    wire ns3_ref_start_ready_o;
    wire ns3_ref_input_ready_o;
    wire ns3_ref_result_valid_o;
    wire [9:0]             ns3_ref_result_row_index_o;
    wire signed [15:0]     ns3_ref_result_mantissa_o;
    wire signed [7:0]      ns3_ref_result_exponent_o;
    wire ns3_ref_result_last_o;
    wire ns3_ref_done_valid_o;
    wire ns3_ref_busy_o;
    wire ns3_ref_range_fault_o;
    normalizer_selection_model_reference #(.MAX_COMPUTE_CYCLES(2000000)) ns3_ref(
        .clk(`NS_LANE.clk),
        .rst_n(`NS_LANE.rst_n),
        .clear_i(`NS_LANE.clear_i),
        .model_lock_i(`NS_LANE.model_lock_i),
        .upstream_fault_i(`NS_LANE.upstream_fault_i),
        .start_valid_i(`NS_LANE.start_valid_i && `NS_LANE.start_ready_o),
        .start_ready_o(ns3_ref_start_ready_o),
        .fixed_layer_i(`NS_LANE.fixed_layer_i),
        .fixed_job_i(`NS_LANE.fixed_job_i),
        .input_valid_i(`NS_LANE.input_valid_i && `NS_LANE.input_ready_o),
        .input_ready_o(ns3_ref_input_ready_o),
        .input_row_index_i(`NS_LANE.input_row_index_i),
        .input_raw_i(`NS_LANE.input_raw_i),
        .input_source_exponent_i(`NS_LANE.input_source_exponent_i),
        .input_last_i(`NS_LANE.input_last_i),
        .result_valid_o(ns3_ref_result_valid_o),
        .result_ready_i(`NS_LANE.result_valid_o && `NS_LANE.result_ready_i),
        .result_row_index_o(ns3_ref_result_row_index_o),
        .result_mantissa_o(ns3_ref_result_mantissa_o),
        .result_exponent_o(ns3_ref_result_exponent_o),
        .result_last_o(ns3_ref_result_last_o),
        .done_valid_o(ns3_ref_done_valid_o),
        .done_ready_i(`NS_LANE.done_valid_o && `NS_LANE.done_ready_i),
        .busy_o(ns3_ref_busy_o),
        .range_fault_o(ns3_ref_range_fault_o)
    );
    initial if (`NS_LANE.MAX_COMPUTE_CYCLES != 2000000) $fatal(1,"normalizer shadow deadline mismatch");

    longint ns3_clock=0, ns3_accepted=0, ns3_completed=0, ns3_cancelled=0;
    longint ns3_first_results=0, ns3_results=0, ns3_added_clocks=0;
    longint ns3_reference_cycle=0, ns3_rows=0;
    longint ns3_bits=0, ns3_exponents=0, ns3_evaluations=0;
    bit ns3_pending=0, ns3_reference_seen=0, ns3_first_seen=0;
    always @(posedge core_clk_i) begin
        ns3_clock++;
        if (!`NS_LANE.rst_n || `NS_LANE.clear_i ||
            `NS_LANE.upstream_fault_i || !`NS_LANE.model_lock_i) begin
            if (ns3_pending) ns3_cancelled++;
            ns3_pending=0; ns3_reference_seen=0; ns3_first_seen=0;
        end else begin
            if (`NS_LANE.start_valid_i && `NS_LANE.start_ready_o) begin
                if (ns3_pending || !ns3_ref_start_ready_o)
                    $fatal(1,"normalizer model shadow missed/overlapped a start");
                ns3_accepted++; ns3_pending=1; ns3_reference_seen=0; ns3_first_seen=0;
                ns3_rows=`NS_LANE.rows_for_job(`NS_LANE.fixed_job_i);
            end
            if (`NS_LANE.input_valid_i && `NS_LANE.input_ready_o && !ns3_ref_input_ready_o)
                $fatal(1,"normalizer model shadow missed an input");
            if (`NS_LANE.state_q == 4'd11) ns3_bits++;
            if (`NS_LANE.state_q == 4'd12) begin
                ns3_exponents++;
                if (`NS_LANE.fit_length_pipe_q !== `NS_LANE.first_fit_length50(`NS_LANE.selected_raw) ||
                    `NS_LANE.fit_source_pipe_q !== `NS_LANE.selected_source_exponent ||
                    `NS_LANE.fit_zero_pipe_q !== (`NS_LANE.selected_raw == 0))
                    $fatal(1,"model selection stage lost actual RAM ownership");
            end
            if (`NS_LANE.state_q == 4'd3) begin
                ns3_evaluations++;
                if (`NS_LANE.selected_first_fit !== ns3_ref.first_fit_exponent50(`NS_LANE.selected_raw,`NS_LANE.selected_source_exponent) ||
                    `NS_LANE.selected_nonzero !== (`NS_LANE.selected_raw != 0))
                    $fatal(1,"model selection stage differs from literal original function");
            end
            if (ns3_ref_result_valid_o && !ns3_reference_seen) begin
                if (!ns3_pending) $fatal(1,"normalizer model reference first result unowned");
                ns3_reference_seen=1; ns3_reference_cycle=ns3_clock;
            end
            if (`NS_LANE.result_valid_o) begin
                if (!ns3_pending || !ns3_ref_result_valid_o || {`NS_LANE.result_row_index_o,`NS_LANE.result_mantissa_o,`NS_LANE.result_exponent_o,`NS_LANE.result_last_o} !== {ns3_ref_result_row_index_o,ns3_ref_result_mantissa_o,ns3_ref_result_exponent_o,ns3_ref_result_last_o})
                    $fatal(1,"normalizer model result differs from literal prior controller");
                if (!ns3_first_seen) begin
                    if (!ns3_reference_seen || ns3_clock-ns3_reference_cycle != 2*ns3_rows)
                        $fatal(1,"normalizer model first-result latency not two extra clocks per row");
                    ns3_first_results++; ns3_added_clocks+=ns3_clock-ns3_reference_cycle;
                    ns3_first_seen=1;
                end
                if (`NS_LANE.result_ready_i) ns3_results++;
            end
            if (`NS_LANE.done_valid_o && `NS_LANE.done_ready_i) begin
                if (!ns3_pending || !ns3_first_seen || !ns3_ref_done_valid_o)
                    $fatal(1,"normalizer model completion ownership differs");
                ns3_pending=0; ns3_completed++;
            end
        end
    end
    final begin
        $display("NORMALIZER_MODEL_MONITOR instance=final accepted=%0d completed=%0d cancelled=%0d pending=%0d first_results=%0d rows=%0d added_clocks=%0d bits=%0d exponents=%0d evaluations=%0d actual_prior_rtl=1 native_ports_added=0",
            ns3_accepted,ns3_completed,ns3_cancelled,ns3_pending,ns3_first_results,ns3_results,ns3_added_clocks,ns3_bits,ns3_exponents,ns3_evaluations);
    end
    `undef NS_LANE
