    localparam integer CPB=217;
    always #5 core_clk_i=~core_clk_i;
    board1_public_shell_composition dut (.*);
    reg [13:0] commands [0:63];
    reg [7:0] replies [0:255];
    integer command_head=0,command_tail=0,byte_head=0,byte_tail=0,cases=0;
    reg pending_step=0;

    function automatic [7:0] crc(input [31:0] data);
        reg [39:0] polynomial;
        integer i;
        begin
            polynomial={data,8'd0};
            for(i=39;i>=8;i=i-1)
                if(polynomial[i]) polynomial=polynomial ^ (40'h107 << (i-8));
            crc=polynomial[7:0];
        end
    endfunction
    task automatic expect_command(input [1:0] op,input [11:0] token);
        begin commands[command_tail]={op,token}; command_tail=command_tail+1; end
    endtask
    task automatic expect_reply(input [7:0] kind);
        begin
            replies[byte_tail]=8'h5a; replies[byte_tail+1]=kind;
            replies[byte_tail+2]=0; replies[byte_tail+3]=0;
            replies[byte_tail+4]=crc({8'h5a,kind,16'd0}); byte_tail=byte_tail+5;
        end
    endtask
    task automatic send_byte(input [7:0] data);
        integer i;
        begin
            @(negedge core_clk_i); uart_rx_i=0;
            repeat(CPB) @(negedge core_clk_i);
            for(i=0;i<8;i=i+1) begin
                uart_rx_i=data[i]; repeat(CPB) @(negedge core_clk_i);
            end
            uart_rx_i=1; repeat(CPB*2) @(negedge core_clk_i);
        end
    endtask
    task automatic request(input [7:0] op,input [15:0] token,input corrupt);
        begin
            send_byte(8'ha5); send_byte(op); send_byte(token[7:0]); send_byte(token[15:8]);
            send_byte(crc({8'ha5,op,token[7:0],token[15:8]}) ^ (corrupt ? 8'h01 : 8'h00));
        end
    endtask
    // Sample the real serial output, not the transmitter's internal byte bus.
    // The expected CRC uses polynomial division, separately from the parser.
    reg [7:0] received;
    integer bit_number;
    always @(negedge uart_tx_o) if(reset_n_i) begin
        repeat(CPB+CPB/2) @(negedge core_clk_i);
        for(bit_number=0;bit_number<8;bit_number=bit_number+1) begin
            received[bit_number]=uart_tx_o;
            repeat(CPB) @(negedge core_clk_i);
        end
        if(uart_tx_o!==1'b1) $fatal(1,"BAD_SERIAL_STOP");
        if(byte_head==byte_tail || received!==replies[byte_head])
            $fatal(1,"WRONG_SERIAL_REPLY");
        byte_head=byte_head+1;
    end
    task automatic drain;
        integer budget;
        begin
            budget=CPB*200;
            while(byte_head!=byte_tail || command_head!=command_tail || dut.u_fixed_uart.state_q!=0) begin
                @(negedge core_clk_i); budget=budget-1;
                if(budget==0) $fatal(1,"TRACE_TIMEOUT");
            end
            repeat(CPB*2) @(negedge core_clk_i); cases=cases+1;
        end
    endtask
    task automatic tape(input integer length,input [11:0] a,input [11:0] b);
        begin
            if(dut.u_machine.u_token_shell.tape_count_q!==length)
                $fatal(1,"TAPE_COUNT");
            if(length>0 && dut.u_machine.u_token_shell.token_tape_q[0]!==a)
                $fatal(1,"TAPE_CONTENT");
            if(length>1 && dut.u_machine.u_token_shell.token_tape_q[1]!==b)
                $fatal(1,"TAPE_CONTENT");
        end
    endtask
    always @(posedge core_clk_i) if(reset_n_i) begin
        if(dut.token_valid && !pending_step) $fatal(1,"UNSOLICITED_CORE_RESULT");
        if((dut.append_valid && dut.append_ready) || (dut.step_valid && dut.step_ready) || dut.clear) begin
            if(command_head==command_tail) $fatal(1,"EXTRA_OPERATION");
            if(dut.clear) begin
                if(commands[command_head]!=={2'd2,12'd0}) $fatal(1,"WRONG_CLEAR");
                pending_step<=0;
            end else if(dut.step_valid && dut.step_ready) begin
                if(commands[command_head]!=={2'd1,12'd0}) $fatal(1,"WRONG_STEP");
                pending_step<=1;
            end else if(commands[command_head]!=={2'd0,dut.append_token}) $fatal(1,"WRONG_APPEND");
            command_head=command_head+1;
        end
    end
    initial begin
        // Only the read-only formal observation index is selected. No
        // production register, RAM value, token or handshake is forced.
        dut.u_machine.u_token_shell.f_tape_slot=0;
        uart_rx_i=1; model_lock_core_sync_q=1; model_req_ready=1;
        repeat(5) @(negedge core_clk_i); reset_n_i=1;
        repeat(20) @(negedge core_clk_i);
        expect_command(0,17); expect_reply(8'h80); request(0,17,0); drain(); tape(1,17,0);
        expect_command(0,29); expect_reply(8'h80); request(0,29,0); drain(); tape(2,17,29);
        expect_reply(8'hcf); request(7,0,0); drain(); tape(2,17,29);
        expect_reply(8'hc1); request(1,7,0); drain(); tape(2,17,29);
        expect_reply(8'hc0); request(0,4019,0); drain(); tape(2,17,29);
        expect_reply(8'hcf); request(0,65,1); drain(); tape(2,17,29);
        expect_command(2,0); expect_reply(8'h82); request(2,0,0); drain(); tape(0,0,0);
        if(dut.u_machine.u_token_shell.token_tape_q[0]!==12'd17)
            $fatal(1,"CLEAR_RETENTION_WITNESS");
        expect_command(0,43); expect_reply(8'h80); request(0,43,0); drain(); tape(1,43,0);
        expect_command(1,0); request(1,0,0); cases=cases+1;
        request(0,65,0); // Busy APPEND is ignored while the real shell is waiting.
        expect_command(2,0); expect_reply(8'h82); request(2,0,0); drain(); tape(0,0,0);
        // Explicit environmental reset removes the deliberately unreturned
        // private memory response before the independent terminal-fault case.
        @(negedge core_clk_i); reset_n_i=0; pending_step=0;
        repeat(5) @(negedge core_clk_i); reset_n_i=1;
        repeat(20) @(negedge core_clk_i); boundary_core_fault=1;
        repeat(10) @(negedge core_clk_i);
        expect_reply(8'hc0); request(0,55,0); drain(); tape(0,0,0);
        expect_command(2,0); expect_reply(8'h82); request(2,0,0); drain(); tape(0,0,0);
        boundary_core_fault=0; repeat(10) @(negedge core_clk_i);
        expect_reply(8'hc0); request(0,55,0); drain(); tape(0,0,0);
        if(cases!=13 || byte_head!=60 || command_head!=7) $fatal(1,"COVERAGE_COUNT");
        $display("PASS_PUBLIC_SHELL cases=13 serial_bytes=60 operations=7 cpb=217");
        $finish;
    end
    initial begin #20000000; $fatal(1,"GLOBAL_TIMEOUT"); end
endmodule
