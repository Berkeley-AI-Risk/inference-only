`timescale 1ns/1ps

module boot_loader_order_tb;
    reg wclk = 0, rclk = 0, reset_n = 1, ready = 0, dq1 = 1;
    wire valid, failed;
    wire [255:0] data;
    board1_context2048_qspi_image_stream dut (
        .trusted_clk_i(wclk), .app_clk_i(rclk),
        .trusted_reset_n_i(reset_n), .app_reset_n_i(reset_n),
        .qspi_dq_i({2'b00, dq1, 1'b0}), .qspi_dq_o(), .qspi_dq_oe_o(),
        .qspi_sck_o(), .qspi_cs_n_o(), .fixed_source_ready_o(), .boot_progress_o(),
        .loader_data_o(data), .loader_valid_o(valid), .loader_ready_i(ready),
        .loader_done_o(), .fail_closed_o(failed)
    );

    reg [255:0] writes [0:63];
    reg [15:0] random_bits = 16'h1a73;
    integer nw, nr, pops, equal_pairs, stalled, wraps, simultaneous;
    integer epoch, tick, schedule, wrong_order;
    reg draining, pause_loader;

    task automatic reset_epoch;
        reset_n = 0;
        ready = 0;
        #2; wclk = 0; rclk = 0;
        #2; reset_n = 1;
        nw = 0; nr = 0; pops = 0; equal_pairs = 0;
        stalled = 0; wraps = 0; simultaneous = 0; draining = 0; pause_loader = 0;
    endtask

    task automatic step(input integer i);
        reg wn, rn, we, re, write_strobe, pop, take;
        reg [1:0] slot;
        reg [255:0] offered, expected;
        begin
            // Schedule 1 pauses the destination with the source still running.
            wn = i % 2 == 0 ? !wclk : wclk;
            rn = schedule == 0 ? (i % 3 == 0 ? !rclk : rclk) :
                 (i % 7 == 0 && i % 89 < 69 ? !rclk : rclk);
            we = !wclk && wn;
            re = !rclk && rn;
            if (wclk && !wn) begin
                random_bits = {random_bits[14:0],
                               random_bits[15] ^ random_bits[13] ^ random_bits[12] ^ random_bits[10]};
                dq1 = nw < 6 ? 1 : random_bits[15];
            end
            if (stalled >= 7) draining = 1;
            ready = draining && !pause_loader && i % 19 < 13;
            #1; // settle external pins before sampling either domain
            write_strobe = we && dut.u_loader_cdc.write_transfer;
            slot = dut.u_loader_cdc.write_binary_q[1:0];
            offered = dut.u_loader_cdc.write_data_i;
            pop = re && dut.u_loader_cdc.read_transfer;
            take = re && ready && valid;
            if (failed || (re && pop && take)) $fatal(1, "fault or skid fallthrough");
            if (we && re) simultaneous = simultaneous + 1;
            if (we && dut.qspi_data_valid && !dut.qspi_data_ready) stalled = stalled + 1;
            if (take) begin
                if (nr >= nw || nr >= pops) $fatal(1, "loader accepted before RAM or prefetch");
                expected = writes[nr];
                if (wrong_order && nr > 0 && expected !== writes[nr-1]) expected = writes[nr-1];
                if (data !== expected) $fatal(1, "loader order mismatch at word %0d", nr);
                nr = nr + 1;
            end
            if (pop) pops = pops + 1;
            wclk = wn; rclk = rn;
            #1;
            if (write_strobe) begin
                if (nw >= 64 || slot !== nw[1:0] || dut.u_loader_cdc.storage_q[slot] !== offered)
                    $fatal(1, "storage strobe, slot, or data mismatch");
                writes[nw] = dut.u_loader_cdc.storage_q[slot];
                if (nw > 0 && writes[nw] === writes[nw-1]) equal_pairs = equal_pairs + 1;
                if (nw > 0 && slot == 0) wraps = wraps + 1;
                nw = nw + 1;
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("schedule=%d", schedule)) schedule = 0;
        if (!$value$plusargs("wrongorder=%d", wrong_order)) wrong_order = 0;
        #1;
        for (epoch = 0; epoch < 2; epoch = epoch+1) begin
            reset_epoch();
            for (tick = 0; tick < 500000 && nr < 16; tick = tick+1) step(tick);
            if (nr != 16 || equal_pairs < 4 || stalled < 7 || wraps < 3 || simultaneous == 0)
                $fatal(1, "incomplete schedule: loads=%0d equal=%0d stalls=%0d wraps=%0d both=%0d",
                       nr, equal_pairs, stalled, wraps, simultaneous);
            $display("PASS epoch=%0d schedule=%0d writes=%0d pops=%0d loads=%0d equal=%0d stalls=%0d wraps=%0d both=%0d",
                     epoch, schedule, nw, pops, nr, equal_pairs, stalled, wraps, simultaneous);
            if (epoch == 0) begin
                pause_loader = 1;
                for (; tick < 500000 && nw - nr < 5; tick = tick+1) step(tick);
                if (nw - nr != 5 || pops != nr + 1 || !dut.loader_skid_valid_q)
                    $fatal(1, "common reset did not interrupt a full FIFO and an occupied skid");
                $display("PASS common reset with four queued writes and one held loader word");
            end
        end
        $finish;
    end
endmodule
