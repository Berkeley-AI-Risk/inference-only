`timescale 1ns/1ps
module port_tb;
    reg clk = 0, rst_n = 0, clear_i = 0;
    board1_context2048_semantic_datapath dut(
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(1'b1), .upstream_fault_i(1'b0)
    );
    reg [15:0] old_word;
    reg [15:0] initial_read_data = 16'h532e;
    reg guarded;
    task tick;
        #2 clk = 1;
        #2 clk = 0;
    endtask
    task check_ports(input bit expected);
        if (dut.u_key_state.private_read_enable_i !== expected ||
            dut.u_value_state.private_read_enable_i !== expected)
            $fatal(1,"unexpected physical RAM enables at time %0t", $time);
        if (expected && dut.u_value_state.private_read_address_i !== 7'd43)
            $fatal(1,"unexpected V address");
    endtask
    initial begin
        guarded = $test$plusargs("guarded");
        if (!$value$plusargs("word=%h",old_word)) $fatal(1,"missing test word");
        // Choose the pending row from the original board startup witness.
        // Hold its control fields to resample the same request on active cycles.
        force dut.engine_state_q = dut.E_KV;
        force dut.fault_q = 0;
        force dut.service_start_seen_q = 1;
        force dut.input_done_q = 0;
        force dut.kv_read_valid_q = 0;
        force dut.input_index_q = 43;
        dut.u_value_state.payload_mem[43] = old_word;
        dut.u_value_state.private_read_data_o = initial_read_data;
        #2;
        check_ports(!guarded);
        tick;
        if (dut.value_ram_read_data !== (guarded ? initial_read_data : old_word))
            $fatal(1,"wrong V register on reset edge");
        rst_n = 1;
        #2;
        check_ports(1);
        tick;
        if (dut.value_ram_read_data !== old_word) $fatal(1,"active read failed");
        clear_i = 1;
        dut.u_value_state.payload_mem[43] = ~old_word;
        #2;
        check_ports(0);
        tick;
        if (dut.value_ram_read_data !== old_word) $fatal(1,"CLEAR captured V");
        clear_i = 0;
        #2;
        check_ports(1);
        tick;
        if (dut.value_ram_read_data !== ~old_word) $fatal(1,"read failed after CLEAR");
        $display("PASS guarded=%0d startup_word=%h reset_capture=%0d active_and_clear_controls=pass",
                 guarded,old_word,!guarded);
        $finish;
    end
endmodule
