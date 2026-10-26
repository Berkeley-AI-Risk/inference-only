    `define EP_LANE dut.u_machine.u_six_layers.u_datapath.u_elementwise_lane.u_fixed_elementwise_product_compact_lane
    wire ep_ref_request_ready_o;
    wire ep_ref_lut_request_o;
    wire [15:0]            ep_ref_lut_index_o;
    wire ep_ref_result_valid_o;
    wire signed [15:0]     ep_ref_result0_o;
    wire signed [15:0]     ep_ref_result1_o;
    wire signed [15:0]     ep_ref_auxiliary_o;
    wire signed [49:0]     ep_ref_raw0_o;
    wire signed [49:0]     ep_ref_raw1_o;
    wire signed [7:0]      ep_ref_source_exponent_o;
    wire ep_ref_range_fault_o;
    elementwise_model_reference ep_ref(
        .clk(`EP_LANE.clk),
        .rst_n(`EP_LANE.rst_n),
        .clear_i(`EP_LANE.clear_i),
        .request_valid_i(`EP_LANE.request_valid_i && `EP_LANE.request_ready_o),
        .request_ready_o(ep_ref_request_ready_o),
        .operation_i(`EP_LANE.operation_i),
        .first_i(`EP_LANE.first_i),
        .second_i(`EP_LANE.second_i),
        .coefficient_i(`EP_LANE.coefficient_i),
        .multiplier_i(`EP_LANE.multiplier_i),
        .cosine_i(`EP_LANE.cosine_i),
        .sine_i(`EP_LANE.sine_i),
        .first_exponent_i(`EP_LANE.first_exponent_i),
        .second_exponent_i(`EP_LANE.second_exponent_i),
        .common_exponent_i(`EP_LANE.common_exponent_i),
        .target_exponent_i(`EP_LANE.target_exponent_i),
        .lut_request_o(ep_ref_lut_request_o),
        .lut_index_o(ep_ref_lut_index_o),
        .lut_response_valid_i(`EP_LANE.lut_response_valid_i),
        .lut_value_i(`EP_LANE.lut_value_i),
        .lut_fault_i(`EP_LANE.lut_fault_i),
        .result_valid_o(ep_ref_result_valid_o),
        .result_ready_i(`EP_LANE.result_valid_o && `EP_LANE.result_ready_i),
        .result0_o(ep_ref_result0_o),
        .result1_o(ep_ref_result1_o),
        .auxiliary_o(ep_ref_auxiliary_o),
        .raw0_o(ep_ref_raw0_o),
        .raw1_o(ep_ref_raw1_o),
        .source_exponent_o(ep_ref_source_exponent_o),
        .range_fault_o(ep_ref_range_fault_o)
    );

    longint ep_clock=0, ep_accepted=0, ep_completed=0, ep_cancelled=0;
    longint ep_rope=0, ep_silu=0, ep_residual=0, ep_added_clocks=0;
    longint ep_reference_cycle=0;
    logic [2:0] ep_operation=0;
    bit ep_pending=0, ep_reference_seen=0, ep_result_seen=0;
    always @(posedge core_clk_i) begin
        ep_clock=ep_clock+1;
        if (!`EP_LANE.rst_n || `EP_LANE.clear_i) begin
            if (ep_pending) ep_cancelled=ep_cancelled+1;
            ep_pending=0; ep_reference_seen=0; ep_result_seen=0;
        end else begin
            if (ep_ref_request_ready_o !== `EP_LANE.request_ready_o)
                $fatal(1,"elementwise actual-model request ownership mismatch");
            if (ep_ref_lut_request_o !== `EP_LANE.lut_request_o ||
                ep_ref_lut_index_o !== `EP_LANE.lut_index_o)
                $fatal(1,"elementwise actual-model LUT request mismatch");
            if (`EP_LANE.request_valid_i && `EP_LANE.request_ready_o) begin
                if (ep_pending || !ep_ref_request_ready_o)
                    $fatal(1,"elementwise shadow missed/overlapped a real request");
                ep_accepted=ep_accepted+1; ep_pending=1;
                ep_operation=`EP_LANE.operation_i;
                ep_reference_seen=0; ep_result_seen=0;
            end
            if (ep_ref_result_valid_o && !ep_reference_seen) begin
                if (!ep_pending) $fatal(1,"elementwise shadow produced an unowned result");
                ep_reference_seen=1; ep_reference_cycle=ep_clock;
            end
            if (`EP_LANE.result_valid_o) begin
                if (!ep_ref_result_valid_o || {`EP_LANE.result0_o,`EP_LANE.result1_o,`EP_LANE.auxiliary_o,`EP_LANE.raw0_o,`EP_LANE.raw1_o,`EP_LANE.source_exponent_o} !== {ep_ref_result0_o,ep_ref_result1_o,ep_ref_auxiliary_o,ep_ref_raw0_o,ep_ref_raw1_o,ep_ref_source_exponent_o})
                    $fatal(1,"elementwise actual-model result differs from literal previous RTL");
                if (!ep_result_seen) begin
                    if (!ep_pending || !ep_reference_seen)
                        $fatal(1,"elementwise candidate produced an unowned result");
                    case (ep_operation)
                        0: begin
                            if (ep_clock-ep_reference_cycle!=2) $fatal(1,"RoPE pipeline latency changed unexpectedly");
                            ep_rope=ep_rope+1;
                        end
                        2: begin
                            if (ep_clock-ep_reference_cycle!=2) $fatal(1,"SiLU pipeline latency changed unexpectedly");
                            ep_silu=ep_silu+1;
                        end
                        3: begin
                            if (ep_clock-ep_reference_cycle!=1) $fatal(1,"residual pipeline latency changed unexpectedly");
                            ep_residual=ep_residual+1;
                        end
                        default: $fatal(1,"unexpected operation in actual-model lane");
                    endcase
                    ep_added_clocks=ep_added_clocks+ep_clock-ep_reference_cycle;
                    ep_completed=ep_completed+1; ep_pending=0; ep_result_seen=1;
                end
            end
        end
    end
    final begin
        $display("ELEMENTWISE_MODEL_MONITOR accepted=%0d completed=%0d cancelled=%0d pending=%0d rope=%0d silu=%0d residual=%0d added_clocks=%0d actual_old_rtl=1 actual_dsp=1 native_ports_added=0",
            ep_accepted,ep_completed,ep_cancelled,ep_pending,ep_rope,ep_silu,ep_residual,ep_added_clocks);
    end
    `undef EP_LANE
