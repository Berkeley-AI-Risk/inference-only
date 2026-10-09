`timescale 1ns/1ps
module tb_frame_refinement;
    localparam integer CPB = 217;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg uart_rx_i = 1;
    wire uart_tx_o, clear_command_o, cmd_valid_o, out_ready_o;
    reg cmd_ready_i = 1;
    wire [1:0] cmd_o;
    wire [11:0] in_token_o;
    reg out_valid_i = 0;
    reg [11:0] out_token_i = 0;
    token_only_model0_uart_bridge #(.CLKS_PER_BIT(CPB)) dut (.*);

    reg [7:0] expected_bytes [0:511];
    reg [13:0] expected_commands [0:127];
    integer byte_head = 0, byte_tail = 0, command_head = 0, command_tail = 0;
    integer cases = 0;
    function automatic [7:0] checksum(input [31:0] word_in);
        reg [7:0] rem;
        integer byte_index, bit_index;
        begin
            rem = 0;
            for (byte_index = 3; byte_index >= 0; byte_index = byte_index - 1) begin
                rem = rem ^ ((word_in >> (8 * byte_index)) & 8'hff);
                for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                    rem = rem[7] ? (rem << 1) ^ 8'h07 : rem << 1;
            end
            checksum = rem;
        end
    endfunction
    task automatic command(input [1:0] opcode, input [11:0] token);
        begin
            expected_commands[command_tail] = {opcode, token};
            command_tail = command_tail + 1;
        end
    endtask
    task automatic reply(input [7:0] kind, input [11:0] token);
        reg [31:0] word_out;
        begin
            word_out = {8'h5a, kind, token[7:0], 4'b0, token[11:8]};
            expected_bytes[byte_tail] = 8'h5a;
            expected_bytes[byte_tail+1] = kind;
            expected_bytes[byte_tail+2] = token[7:0];
            expected_bytes[byte_tail+3] = {4'b0, token[11:8]};
            expected_bytes[byte_tail+4] = checksum(word_out);
            byte_tail = byte_tail + 5;
        end
    endtask
    task automatic send_byte(input [7:0] value);
        integer bit_index;
        begin
            @(negedge clk); uart_rx_i = 0;
            repeat(CPB) @(negedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx_i = value[bit_index];
                repeat(CPB) @(negedge clk);
            end
            uart_rx_i = 1;
            repeat(CPB * 2) @(negedge clk);
        end
    endtask
    task automatic request(input [7:0] opcode, input [15:0] operand, input corrupt);
        reg [31:0] word_in;
        begin
            word_in = {8'ha5, opcode, operand[7:0], operand[15:8]};
            send_byte(8'ha5);
            send_byte(opcode);
            send_byte(operand[7:0]);
            send_byte(operand[15:8]);
            send_byte(checksum(word_in) ^ (corrupt ? 8'h01 : 8'h00));
        end
    endtask
    task automatic drain;
        integer budget;
        begin
            budget = CPB * 200;
            while (byte_head != byte_tail || command_head != command_tail || dut.state_q != 0) begin
                @(negedge clk);
                budget = budget - 1;
                if (budget == 0) $fatal(1, "TEST_TIMEOUT");
            end
            repeat(CPB * 2) @(negedge clk);
            cases = cases + 1;
        end
    endtask

    // These are external scoreboards. Icarus assertions inside the formal-only
    // combinational blocks are disabled to avoid delta-cycle race artifacts.
    // Key proved predicates are also sampled here at settled negative edges.
    always @(posedge clk) if (rst_n) begin
        if (cmd_valid_o && cmd_ready_i) begin
            if (command_head == command_tail ||
                {cmd_o, in_token_o} !== expected_commands[command_head])
                $fatal(1, "COMMAND_SCOREBOARD_MISMATCH index=%0d got=%h", command_head, {cmd_o, in_token_o});
            command_head = command_head + 1;
        end
        if (dut.tx_valid && dut.tx_ready) begin
            if (byte_head == byte_tail || dut.tx_byte !== expected_bytes[byte_head])
                $fatal(1, "REPLY_SCOREBOARD_MISMATCH index=%0d got=%h", byte_head, dut.tx_byte);
            byte_head = byte_head + 1;
        end
    end
    always @(negedge clk) if (rst_n) begin
        if (cmd_valid_o && !((cmd_o == 2 && dut.f_clear_credit) ||
            (dut.f_command_credit && cmd_o == dut.f_command && in_token_o == dut.f_command_token)))
            $fatal(1, "PROVEN_COMMAND_PROVENANCE_FAILED");
        if (dut.f_reply_live != dut.tx_valid)
            $fatal(1, "PROVEN_REPLY_OWNERSHIP_FAILED");
        if (dut.tx_valid && (dut.tx_byte != dut.f_reply_byte ||
            dut.response_token_q != dut.f_reply_token || dut.response_kind_q != dut.f_reply_kind))
            $fatal(1, "PROVEN_REPLY_CONTENT_FAILED");
    end

    initial begin
        repeat(5) @(negedge clk);
        rst_n = 1;
        repeat(5) @(negedge clk);
        command(0, 378); reply(8'h80, 0); request(0, 378, 0); drain();
        command(1, 0); request(1, 0, 0);
        reply(8'h81, 200);
        @(negedge clk); out_token_i = 200; out_valid_i = 1;
        @(negedge clk); out_valid_i = 0;
        drain();
        reply(8'hc1, 0); request(1, 7, 0); drain();
        reply(8'hcf, 0); request(7, 0, 0); drain();
        reply(8'hcf, 0); request(0, 16'h1000, 0); drain();
        reply(8'hc0, 0); request(0, 4019, 0); drain();
        reply(8'hcf, 0); request(0, 378, 1); drain();
        cmd_ready_i = 0;
        reply(8'hc0, 0); request(0, 378, 0); drain();
        cmd_ready_i = 1;
        command(2, 0); reply(8'h82, 0); request(2, 0, 0); drain();
        // A busy APPEND is ignored; a subsequent CLEAR can cancel STEP.
        command(1, 0); request(1, 0, 0);
        request(0, 378, 0);
        command(2, 0); reply(8'h82, 0); request(2, 0, 0); drain();
        // Pending CLEAR plus an output while CLEAR is stalled: token reply,
        // then recovery CLEAR holds its credit until the sink accepts it.
        command(1, 0); request(1, 0, 0);
        cmd_ready_i = 0;
        request(2, 0, 0);
        reply(8'h81, 15); reply(8'h82, 0); command(2, 0);
        @(negedge clk); out_token_i = 15; out_valid_i = 1;
        @(negedge clk); out_valid_i = 0;
        wait (dut.recovery_clear_q);
        repeat(CPB * 2) @(negedge clk);
        cmd_ready_i = 1;
        drain();
        // Unsolicited model outputs in IDLE must not create token replies.
        out_valid_i = 1; out_token_i = 3000;
        repeat(CPB * 20) @(negedge clk);
        out_valid_i = 0;
        drain();
        // 12 replies (60 bytes); accepted commands are APPEND, three STEPs,
        // and three CLEARs. Busy/rejected requests add no accepted command.
        if (cases != 12 || byte_head != 60 || command_head != 7)
            $fatal(1, "COVERAGE_COUNTS cases=%0d bytes=%0d commands=%0d", cases, byte_head, command_head);
        $display("PASS_FRAME_TRACE cases=%0d bytes=%0d commands=%0d cpb=%0d", cases, byte_head, command_head, CPB);
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1, "GLOBAL_TIMEOUT");
    end
endmodule
