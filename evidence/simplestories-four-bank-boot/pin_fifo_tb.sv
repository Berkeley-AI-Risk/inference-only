`timescale 1ns/1ps

module pin_fifo_tb;
    logic clk = 0, app_clk = 0, reset_n = 0, app_reset_n = 0, loader_ready = 0;
    logic dq1 = 0;
    wire cs_n, sck;
    wire [3:0] drive, oe;
    always #5 clk = !clk;
    always #3 app_clk = !app_clk;

    board1_context2048_qspi_image_stream dut (
        .trusted_clk_i(clk), .trusted_reset_n_i(reset_n),
        .app_clk_i(app_clk), .app_reset_n_i(app_reset_n),
        .loader_ready_i(loader_ready), .qspi_cs_n_o(cs_n), .qspi_sck_o(sck),
        .qspi_dq_i({2'b0, dq1, 1'b0}), .qspi_dq_o(drive), .qspi_dq_oe_o(oe),
        .loader_valid_o(), .loader_done_o(), .loader_data_o(), .fail_closed_o(),
        .fixed_source_ready_o(), .boot_progress_o()
    );

    integer command_bits = 0, payload_bits = 0, accepted = 0, writes = 0, stalls = 0;
    integer total_writes = 0, identical_writes = 0, wrong_bit = 0;
    reg [31:0] header;
    reg [7:0] assembled;
    reg [7:0] received [0:511];
    reg [255:0] expected_word;
    reg repeat_data = 0;
    reg [15:0] lfsr = 16'hdb35;
    always @(negedge clk) begin
        lfsr = {lfsr[14:0], lfsr[15]^lfsr[13]^lfsr[12]^lfsr[10]};
        dq1 = repeat_data ? 1 : lfsr[15];
    end

    always @(negedge cs_n) begin
        command_bits = 0;
        payload_bits = 0;
        header = 0;
        assembled = 0;
    end
    // Neither the device's state nor its bit counter identifies payload here.
    // DQ1 is stable from the preceding falling trusted edge.
    always @(posedge sck) if (!cs_n) begin
        case (oe)
            4'b1101: begin
                header = {header[30:0], drive[0]};
                command_bits = command_bits + 1;
            end
            4'b1100: begin
                if (command_bits != 32 || header !== 32'h03801000)
                    $fatal(1, "wrong pin header %h, %0d clocks", header, command_bits);
                assembled = {assembled[6:0], dq1 ^ (wrong_bit != 0 && payload_bits == 2)};
                if (payload_bits % 8 == 7) received[payload_bits/8] = assembled;
                payload_bits = payload_bits + 1;
            end
            default: $fatal(1, "unexpected selected pin drive %h", oe);
        endcase
    end

    always @(posedge clk) begin : compare_ram
        reg [255:0] old_words [0:3];
        reg writing, taking;
        integer lane, slot;
        for (integer i = 0; i < 4; i = i+1) old_words[i] = dut.u_loader_cdc.storage_q[i];
        writing = reset_n && dut.u_loader_cdc.write_transfer;
        taking = reset_n && dut.qspi_data_valid && dut.qspi_data_ready;
        lane = accepted % 32;
        slot = writes % 4;
        if (writing !== (taking && lane == 31)) $fatal(1, "write strobe at wrong byte");
        if (reset_n && dut.qspi_data_valid && !dut.qspi_data_ready) stalls = stalls + 1;
        if (taking) begin
            if (!dut.internal_reset_n || cs_n || payload_bits != 8*(accepted+1))
                $fatal(1, "invalid accept at %0d pin bits, %0d preceding bytes", payload_bits, accepted);
            if (!wrong_bit && received[accepted] !== dut.qspi_data) $fatal(1, "pin/interface mismatch");
            expected_word[8*lane +: 8] = received[accepted];
            accepted = accepted + 1;
        end
        if (writing) begin
            if (dut.u_loader_cdc.write_binary_q[1:0] !== slot[1:0]) $fatal(1, "wrong FIFO slot");
            writes = writes + 1;
            total_writes = total_writes + 1;
        end
        if (!reset_n) begin
            accepted = 0;
            writes = 0;
            expected_word = 0;
        end
        #1;
        for (integer i = 0; i < 4; i = i+1) begin
            if (writing && i == slot) begin
                if (dut.u_loader_cdc.storage_q[i] !== expected_word)
                    $fatal(1, "sampled DQ1 disagrees with RAM slot %0d: observed=%h expected=%h",
                           i, dut.u_loader_cdc.storage_q[i], expected_word);
                if (old_words[i] === expected_word) identical_writes = identical_writes + 1;
            end else if (dut.u_loader_cdc.storage_q[i] !== old_words[i])
                $fatal(1, "unwritten slot %0d changed", i);
        end
    end

    task automatic restart;
        @(negedge clk);
        reset_n = 0;
        app_reset_n = 0;
        repeat (4) @(negedge clk);
        reset_n = 1;
        app_reset_n = 1;
    endtask

    initial begin
        if (!$value$plusargs("wrongbit=%d", wrong_bit)) wrong_bit = 0;
        restart();
        wait (dut.qspi_data_valid && !dut.qspi_data_ready);
        repeat (7) @(negedge clk);
        loader_ready = 1;
        wait (writes == 7 && payload_bits == 8*(7*32+4)+3);
        @(negedge clk);
        if (accepted != 228 || stalls < 5) $fatal(1, "missed backpressure or truncated byte");
        $display("PASS 7 pin-derived words across FIFO wrap, %0d stalls, 4 bytes and 3 trailing bits", stalls);
        restart();
        wait (dut.qspi_data_valid && dut.qspi_data_ready && dut.byte_q == 31);
        @(negedge clk);
        app_reset_n = 0;
        @(negedge clk);
        if (writes != 1 || accepted != 32 || dut.state_q != 7 || dut.internal_reset_n || !cs_n)
            $fatal(1, "application-reset boundary did not both store and release the reader");
        $display("PASS boundary word sampled before the same edge's derived reader reset");
        repeat_data = 1;
        restart();
        wait (writes == 6);
        @(negedge clk);
        if (identical_writes < 2 || total_writes != 14) $fatal(1, "missed same-content rewrites");
        $display("PASS 14 stores, %0d equal-content writes, three reset epochs", identical_writes);
        $finish;
    end
    initial #400000 $fatal(1, "timeout");
endmodule
