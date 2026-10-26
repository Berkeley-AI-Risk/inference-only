`timescale 1ns/1ps
`default_nettype none
module tb_readonly_flash_reader;
    parameter integer N = 257;
    parameter integer U = 16;
    parameter integer SPI_HALF = 3;
    logic clk = 0;
    always #10 clk = !clk;
    logic rst_n = 0, host_tx = 1;
    logic bad_id = 0;
    wire dut_tx, csn, sck, mosi;
    logic miso = 1;
    readonly_flash_reader_core #(.DUMP_BYTES(25'(N)), .UART_CLKS(U), .SPI_HALF_CLKS(SPI_HALF)) dut (
        .clk(clk), .rst_n(rst_n), .uart_rx(host_tx), .uart_tx(dut_tx),
        .flash_csn(csn), .flash_sclk(sck), .flash_mosi(mosi), .flash_miso(miso)
    );
    // Exercise the actual nonparameterized production top's power-on/reset path.
    logic probe_reset = 0;
    wire probe_tx, probe_csn, probe_sck;
    tri [3:0] probe_dq;
    assign probe_dq[1] = 1'b1;
    readonly_flash_reader probe (
        .clk_50mhz(clk), .reset_button(probe_reset), .uart_rx(1'b1),
        .uart_tx(probe_tx), .flash_csn(probe_csn), .flash_sclk(probe_sck),
        .flash_dq(probe_dq)
    );
    // Start before the first clock, not merely after startup has completed.
    initial begin
        #0.001;
        if (!probe_csn || probe_sck || !probe_tx)
            $fatal(1, "unsafe production pins before first clock");
    end
    always @(negedge clk) begin
        if (!probe.reset_release_q[1] && (!probe_csn || probe_sck || !probe_tx))
            $fatal(1, "unsafe production pins during startup/reset");
    end
    function automatic [7:0] datum(input integer address);
        datum = 8'((address * 73) ^ (address >> 3) ^ 8'ha6);
    endfunction
    function automatic [7:0] idbyte(input integer index);
        case(index)
            0: idbyte = bad_id ? 8'hff : 8'h0b;
            1: idbyte = 8'h40;
            2: idbyte = 8'h18;
            default: idbyte = 8'hff;
        endcase
    endfunction
    // Independent non-reflected, MSB-first CRC implementation; reverse only
    // bit traversal and final output to match the zlib/IEEE wire convention.
    function automatic [31:0] expected_crc();
        reg [31:0] crc, result;
        reg [7:0] value;
        reg feedback;
        integer i, j;
        begin
            crc = 32'hffffffff;
            for (i = 0; i < N; i = i + 1) begin
                value = datum(i);
                for (j = 0; j < 8; j = j + 1) begin
                    feedback = crc[31] ^ value[j];
                    crc = crc << 1;
                    if (feedback) crc = crc ^ 32'h04c11db7;
                end
            end
            for (j = 0; j < 32; j = j + 1) result[j] = !crc[31-j];
            expected_crc = result;
        end
    endfunction
    integer spi_bits = 0, complete_id = 0, complete_read = 0;
    integer starts = 0;
    reg [7:0] command = 0, spi_shift = 0;
    reg [7:0] selected_byte;
    logic allow_abort = 0;
    always @(negedge csn) begin
        if (sck !== 0) $fatal(1, "CS asserts while SCK high");
        spi_bits = 0; spi_shift = 0; command = 0; starts = starts + 1;
    end
    always @(posedge sck) begin
        if (csn !== 0) $fatal(1, "SCK toggled while deselected");
        spi_shift = {spi_shift[6:0], mosi};
        spi_bits = spi_bits + 1;
        if (spi_bits == 8) begin
            command = spi_shift;
            if (command != 8'h9f && command != 8'h03)
                $fatal(1, "FORBIDDEN SPI command %02x", command);
        end else if (spi_bits > 8) begin
            // All address and dummy/read MOSI bits must be zero.
            if (mosi !== 0) $fatal(1, "nonzero address/dummy bit");
        end
    end
    always @(negedge sck) begin
        if (!csn) begin
            if (command == 8'h9f && spi_bits >= 8) begin
                selected_byte = idbyte((spi_bits - 8) / 8);
                miso = selected_byte[7 - ((spi_bits - 8) % 8)];
            end else if (command == 8'h03 && spi_bits >= 32) begin
                selected_byte = datum((spi_bits - 32) / 8);
                miso = selected_byte[7 - ((spi_bits - 32) % 8)];
            end else miso = 1'b1;
        end
    end
    always @(posedge csn) begin
        if (rst_n && !allow_abort && starts > 0) begin
            if (sck !== 0) $fatal(1, "CS deasserts while SCK high");
            if (command == 8'h9f) begin
                if (spi_bits != 32) $fatal(1, "ID bit count %0d", spi_bits);
                complete_id = complete_id + 1;
            end else if (command == 8'h03) begin
                if (spi_bits != 32 + 8*N) $fatal(1, "data bit count %0d", spi_bits);
                complete_read = complete_read + 1;
            end else $fatal(1, "unexpected transaction");
        end
        miso = 1'b1;
    end
    task automatic send(input [7:0] value);
        integer i;
        begin
            @(negedge clk); host_tx = 0;
            repeat(U) @(negedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                host_tx = value[i]; repeat(U) @(negedge clk);
            end
            host_tx = 1; repeat(U) @(negedge clk);
        end
    endtask
    task automatic receive(output [7:0] value);
        integer i;
        begin
            @(negedge dut_tx);
            #(U*10);
            if (dut_tx !== 0) $fatal(1, "UART missing start");
            for (i = 0; i < 8; i = i + 1) begin
                #(U*20); value[i] = dut_tx;
            end
            #(U*20);
            if (dut_tx !== 1) $fatal(1, "UART missing stop");
        end
    endtask
    task automatic expect_byte(input [7:0] expected);
        reg [7:0] actual;
        begin
            receive(actual);
            if (actual !== expected) $fatal(1, "UART wanted %02x got %02x", expected, actual);
        end
    endtask
    task automatic receive_frame;
        integer i;
        reg [31:0] crc;
        begin
            expect_byte(8'h54); expect_byte(8'h46); expect_byte(8'h44); expect_byte(8'h31);
            expect_byte(8'h0b); expect_byte(8'h40); expect_byte(8'h18); expect_byte(0);
            expect_byte(8'(N)); expect_byte(8'(N>>8));
            expect_byte(8'(N>>16)); expect_byte(8'(N>>24));
            for (i = 0; i < N; i = i + 1) expect_byte(datum(i));
            crc = expected_crc();
            for (i = 0; i < 4; i = i + 1) expect_byte(8'(crc >> (8*i)));
            repeat(U*20) @(negedge clk);
        end
    endtask
    task automatic check_idle;
        begin
            repeat(U*20) begin
                @(negedge clk);
                if (!csn || sck || !dut_tx) $fatal(1, "not safely idle");
            end
        end
    endtask
    integer saved_starts;
    initial begin
        repeat(8) @(negedge clk); rst_n = 1;
        check_idle();
        send(8'h00); send(8'hff); send(8'h03); send(8'h06); send(8'h72);
        check_idle();
        if (starts != 0) $fatal(1, "unknown command caused SPI");
        // Normal dump, with commands injected during busy that must be ignored.
        fork
            begin send(8'h52); repeat(U*50) @(negedge clk); send(8'h52); send(8'h06); end
            receive_frame();
        join
        check_idle();
        if (complete_id != 1 || complete_read != 1 || starts != 2)
            $fatal(1, "busy command was not ignored or count mismatch");
        // Abort during an in-flight ID byte, then during the data transaction.
        allow_abort = 1;
        send(8'h52);
        wait(!csn); repeat(10) @(negedge clk);
        rst_n = 0; #1;
        if (!csn || sck || !dut_tx) $fatal(1, "reset did not quiesce pins");
        repeat(8) @(negedge clk); rst_n = 1; check_idle();
        send(8'h52);
        wait(command == 8'h03 && spi_bits > 32);
        @(negedge clk); rst_n = 0; #1;
        if (!csn || sck || !dut_tx) $fatal(1, "data reset did not quiesce pins");
        repeat(8) @(negedge clk); rst_n = 1; check_idle();
        allow_abort = 0;
        saved_starts = starts;
        fork send(8'h52); receive_frame(); join
        check_idle();
        if (starts != saved_starts + 2 || complete_read != 2)
            $fatal(1, "restart failed");
        // A physically inaccessible or wrong part gets its observed-ID header
        // only. It must not begin opcode 03, emit data, or emit a CRC trailer.
        bad_id = 1;
        saved_starts = starts;
        fork
            send(8'h52);
            begin
                expect_byte(8'h54); expect_byte(8'h46); expect_byte(8'h44); expect_byte(8'h31);
                expect_byte(8'hff); expect_byte(8'h40); expect_byte(8'h18); expect_byte(0);
                expect_byte(8'(N)); expect_byte(8'(N>>8));
                expect_byte(8'(N>>16)); expect_byte(8'(N>>24));
                repeat(U*20) @(negedge clk);
            end
        join
        check_idle();
        if (starts != saved_starts + 1 || complete_read != 2)
            $fatal(1, "mismatched ID issued a read");
        // Allow actual production top to finish startup, still no request.
        wait(probe.reset_release_q[1]);
        repeat(100) @(negedge clk);
        if (!probe_tx || !probe_csn || probe_sck || probe_dq[3:2] != 2'b11)
            $fatal(1, "production top not safely idle after startup");
        probe_reset = 1; #1;
        if (!probe_tx || !probe_csn || probe_sck) $fatal(1, "production reset unsafe");
        @(negedge clk); probe_reset = 0;
        wait(probe.reset_release_q[1]);
        if (!probe_tx || !probe_csn || probe_sck) $fatal(1, "production reset release unsafe");
        $display("PASS readonly SRAM flash reader bytes=%0d crc=%08x complete_reads=%0d", N, expected_crc(), complete_read);
        $finish;
    end
    initial begin #100000000; $fatal(1, "watchdog"); end
endmodule
`default_nettype wire
