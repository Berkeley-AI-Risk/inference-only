`timescale 1ns/1ps
module tb_frontend;
    localparam integer CPB = 217;
    reg core_clk_i = 0;
    always #5 core_clk_i = ~core_clk_i;
    reg reset_n_i = 0, uart_rx_i = 1;
    wire uart_tx_o, append_valid, step_valid, clear, token_ready;
    wire [11:0] append_token;
    reg append_ready = 1, step_ready = 1, token_valid = 0;
    reg [11:0] token = 0;
    board1_public_command_frontend dut (.*);
    reg [13:0] commands [0:63];
    reg [7:0] bytes [0:255];
    integer command_head=0, command_tail=0, byte_head=0, byte_tail=0, cases=0;

    function automatic [7:0] checksum(input [31:0] word_in);
        reg [7:0] rem;
        integer byte_index, bit_index;
        begin
            rem = 0;
            for (byte_index=3; byte_index>=0; byte_index=byte_index-1) begin
                rem = rem ^ ((word_in >> (8*byte_index)) & 8'hff);
                for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                    rem = rem[7] ? (rem << 1) ^ 8'h07 : rem << 1;
            end
            checksum = rem;
        end
    endfunction
    task automatic expect_command(input [1:0] op, input [11:0] value);
        begin commands[command_tail]={op,value}; command_tail=command_tail+1; end
    endtask
    task automatic expect_reply(input [7:0] kind, input [11:0] value);
        reg [31:0] word_out;
        begin
            word_out={8'h5a,kind,value[7:0],4'b0,value[11:8]};
            bytes[byte_tail]=8'h5a; bytes[byte_tail+1]=kind;
            bytes[byte_tail+2]=value[7:0]; bytes[byte_tail+3]={4'b0,value[11:8]};
            bytes[byte_tail+4]=checksum(word_out); byte_tail=byte_tail+5;
        end
    endtask
    task automatic send_byte(input [7:0] value);
        integer i;
        begin
            @(negedge core_clk_i); uart_rx_i=0;
            repeat(CPB) @(negedge core_clk_i);
            for (i=0;i<8;i=i+1) begin
                uart_rx_i=value[i]; repeat(CPB) @(negedge core_clk_i);
            end
            uart_rx_i=1; repeat(CPB*2) @(negedge core_clk_i);
        end
    endtask
    task automatic request(input [7:0] op, input [15:0] value, input corrupt);
        reg [31:0] word_in;
        begin
            word_in={8'ha5,op,value[7:0],value[15:8]};
            send_byte(8'ha5); send_byte(op); send_byte(value[7:0]); send_byte(value[15:8]);
            send_byte(checksum(word_in) ^ (corrupt ? 8'h01 : 8'h00));
        end
    endtask
    task automatic drain;
        integer budget;
        begin
            budget=CPB*200;
            while(byte_head!=byte_tail || command_head!=command_tail || dut.u_fixed_uart.state_q!=0) begin
                @(negedge core_clk_i); budget=budget-1;
                if(budget==0) $fatal(1,"TRACE_TIMEOUT");
            end
            repeat(CPB*2) @(negedge core_clk_i);
            cases=cases+1;
        end
    endtask

    // Only external operation signals and actual transmit-byte handoffs are
    // observed. No internal production value or handshake is forced.
    always @(posedge core_clk_i) if(reset_n_i) begin
        if((append_valid && append_ready) || (step_valid && step_ready) || clear) begin
            if(command_head==command_tail) $fatal(1,"EXTRA_OPERATION");
            if(clear) begin
                if(commands[command_head] !== {2'd2,12'd0}) $fatal(1,"WRONG_CLEAR_OPERATION");
            end else if(step_valid && step_ready) begin
                if(commands[command_head] !== {2'd1,12'd0}) $fatal(1,"WRONG_STEP_OPERATION");
            end else if(commands[command_head] !== {2'd0,append_token})
                $fatal(1,"WRONG_APPEND_OPERAND");
            command_head=command_head+1;
        end
        if(dut.u_fixed_uart.tx_valid && dut.u_fixed_uart.tx_ready) begin
            if(byte_head==byte_tail || dut.u_fixed_uart.tx_byte !== bytes[byte_head])
                $fatal(1,"WRONG_REPLY_BYTE");
            byte_head=byte_head+1;
        end
    end
    initial begin
        repeat(5) @(negedge core_clk_i); reset_n_i=1;
        repeat(5) @(negedge core_clk_i);
        expect_command(0,378); expect_reply(8'h80,0); request(0,378,0); drain();
        expect_command(1,0); request(1,0,0); expect_reply(8'h81,200);
        @(negedge core_clk_i);
        if(!token_ready) $fatal(1,"TOKEN_READY_MISMATCH");
        token=200; token_valid=1;
        @(negedge core_clk_i); token_valid=0; drain();
        expect_command(2,0); expect_reply(8'h82,0); request(2,0,0); drain();
        expect_reply(8'hcf,0); request(7,0,0); drain();
        expect_reply(8'hc1,0); request(1,7,0); drain();
        expect_reply(8'hc0,0); request(0,4019,0); drain();
        expect_reply(8'hcf,0); request(0,378,1); drain();
        expect_command(1,0); request(1,0,0); request(0,378,0);
        expect_command(2,0); expect_reply(8'h82,0); request(2,0,0); drain();
        append_ready=0; expect_reply(8'hc0,0); request(0,378,0); drain(); append_ready=1;
        token_valid=1; token=3000; repeat(CPB*20) @(negedge core_clk_i); token_valid=0; drain();
        if(cases!=10 || byte_head!=45 || command_head!=5)
            $fatal(1,"COVERAGE_COUNT_MISMATCH");
        $display("PASS_COMMAND_FRONTEND cases=10 bytes=45 operations=5 cpb=217");
        $finish;
    end
    initial begin #20000000; $fatal(1,"GLOBAL_TIMEOUT"); end
endmodule
