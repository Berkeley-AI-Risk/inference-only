`timescale 1ns/1ps
module test_settings_uart #(parameter integer CPB=8);
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0,uart_rx_i=1,cmd_ready_i=1,out_valid_i=0;
    reg [11:0] out_token_i=0;
    wire uart_tx_o,clear_command_o,cmd_valid_o,out_ready_o;
    wire [1:0] cmd_o;
    wire [11:0] in_token_o;
    wire settings_valid_o;
    reg settings_ready_i=1,settings_accepted_i=0,settings_rejected_i=0;
    wire [2:0] settings_temperature_o;
    wire [127:0] settings_seed_o;
    token_only_model0_uart_bridge #(.CLKS_PER_BIT(CPB)) dut (.*);
    reg [7:0] expected [0:4];
    integer received=5,configurations=0,cases=0,feedback=0;
    bit expect_configuration=0;
    bit allow_legacy=0;
    integer legacy_commands=0;
    reg [2:0] wanted_temperature;
    reg [127:0] wanted_seed;
    function automatic [7:0] crc_next(input [7:0] crc,input [7:0] value);
        reg [7:0] rem;
        begin
            rem=crc^value;
            for(integer i=0;i<8;i=i+1) rem=rem[7]?(rem<<1)^8'h07:rem<<1;
            crc_next=rem;
        end
    endfunction
    task automatic reply(input [7:0] kind,input [7:0] operand);
        reg [7:0] crc;
        begin
            if(received!=5) $fatal(1,"prior response not drained");
            expected[0]=8'h5a;expected[1]=kind;expected[2]=operand;expected[3]=0;
            crc=0;for(integer i=0;i<4;i=i+1) crc=crc_next(crc,expected[i]);
            expected[4]=crc;received=0;
        end
    endtask
    task automatic send_byte(input [7:0] value);
        begin
            @(negedge clk);uart_rx_i=0;repeat(CPB) @(negedge clk);
            for(integer i=0;i<8;i=i+1) begin uart_rx_i=value[i];repeat(CPB) @(negedge clk);end
            uart_rx_i=1;repeat(CPB*2) @(negedge clk);
        end
    endtask
    task automatic request(input [7:0] temperature,input [127:0] seed,input bit corrupt);
        reg [7:0] crc,value;
        begin
            crc=0;value=8'ha5;send_byte(value);crc=crc_next(crc,value);
            value=3;send_byte(value);crc=crc_next(crc,value);
            value=temperature;send_byte(value);crc=crc_next(crc,value);
            for(integer i=0;i<16;i=i+1) begin value=seed[i*8+:8];send_byte(value);crc=crc_next(crc,value);end
            send_byte(crc^(corrupt?8'h01:8'h00));
        end
    endtask
    task automatic legacy(input [7:0] opcode);
        reg [7:0] crc,value;
        begin
            crc=0;value=8'ha5;send_byte(value);crc=crc_next(crc,value);
            send_byte(opcode);crc=crc_next(crc,opcode);
            send_byte(0);crc=crc_next(crc,0);
            send_byte(0);crc=crc_next(crc,0);send_byte(crc);
        end
    endtask
    task automatic crc_mutated_request(input integer position);
        reg [7:0] bytes [0:19];
        reg [7:0] crc;
        begin
            bytes[0]=8'ha5;bytes[1]=3;bytes[2]=2;
            for(integer i=3;i<19;i=i+1) bytes[i]=0;
            crc=0;for(integer i=0;i<19;i=i+1) crc=crc_next(crc,bytes[i]);bytes[19]=crc;
            for(integer i=0;i<20;i=i+1) send_byte(bytes[i]^(i==position?8'h01:8'h00));
        end
    endtask
    task automatic model_result;
        begin
            @(negedge clk);out_token_i=13;out_valid_i=1;
            while(!out_ready_o) @(negedge clk);
            @(negedge clk);out_valid_i=0;
        end
    endtask
    task automatic drain;
        integer guard;
        begin
            guard=0;
            while(received!=5 || dut.state_q!=0) begin
                @(negedge clk);guard=guard+1;
                if(guard>CPB*100) $fatal(1,"settings UART response timeout");
            end
            if(expect_configuration) $fatal(1,"configuration never issued");
            repeat(CPB*2) @(negedge clk);cases=cases+1;
        end
    endtask
    always @(posedge clk) begin
        settings_accepted_i<=0;settings_rejected_i<=0;
        if(rst_n) begin
            if((cmd_valid_o || clear_command_o) && !allow_legacy)
                $fatal(1,"seed payload escaped into legacy commands");
            if(cmd_valid_o && cmd_ready_i) legacy_commands=legacy_commands+1;
            if(settings_valid_o && settings_ready_i) begin
                if(!expect_configuration || settings_temperature_o!==wanted_temperature || settings_seed_o!==wanted_seed)
                    $fatal(1,"wrong/unowned settings payload");
                expect_configuration=0;configurations=configurations+1;
                if(feedback==0) settings_accepted_i<=1;
                if(feedback==1) settings_rejected_i<=1;
            end
            if(dut.tx_valid && dut.tx_ready) begin
                if(received>=5 || dut.tx_byte!==expected[received])
                    $fatal(1,"settings response mismatch byte=%0d got=%h",received,dut.tx_byte);
                received=received+1;
            end
        end
    end
    initial begin
        repeat(5) @(negedge clk);rst_n=1;repeat(5) @(negedge clk);
        for(integer t=0;t<4;t=t+1) begin
            // Wire-order bytes are three COMPLETE valid legacy requests:
            // CLEAR, STEP and APPEND(378), each with its correct CRC, then00.
            wanted_seed=t==0?128'd0:t==1?~128'd0:128'h0096017a00a5da000001a567000002a5;
            wanted_temperature=t;expect_configuration=1;
            reply(8'h83,t);request(t,wanted_seed,0);drain();
        end
        for(integer t=4;t<256;t=t+1) begin reply(8'hc3,0);request(t,128'd0,0);drain();end
        wanted_seed=128'h0123456789abcdef0123456789abcdef;wanted_temperature=2;
        reply(8'hcf,0);request(2,wanted_seed,1);drain();
        settings_ready_i=0;reply(8'hc3,0);request(2,wanted_seed,0);drain();settings_ready_i=1;
        feedback=1;expect_configuration=1;reply(8'hc3,0);request(2,wanted_seed,0);drain();
        feedback=2;expect_configuration=1;reply(8'hc3,0);request(2,wanted_seed,0);drain();feedback=0;
        // Truncation timeout is new-frame-only and applies nothing partially.
        reply(8'hcf,0);send_byte(8'ha5);send_byte(3);send_byte(2);drain();
        // Timeout relinquishes framing ownership. A later complete valid
        // legacy frame is a NEW operation, not authenticated old seed data.
        allow_legacy=1;reply(8'h82,0);legacy(2);drain();allow_legacy=0;
        // A complete settings frame during WAIT_RESULT is discarded, not
        // deferred. It cannot cancel the STEP or produce an extra response.
        allow_legacy=1;legacy(1);allow_legacy=0;
        reply(8'h81,13);request(2,wanted_seed,0);
        if(dut.state_q!=2 || dut.request_index_q!=0)
            $fatal(1,"busy-complete settings were not discarded");
        model_result();drain();
        // Admission is at complete CRC-valid frame, not initial A5. This
        // frame starts in WAIT_RESULT, spans STEP reply/drain, and finishes
        // in IDLE. Parser may forward; owning shell must STILL certify empty.
        allow_legacy=1;legacy(1);allow_legacy=0;
        wanted_temperature=2;expect_configuration=1;reply(8'h81,13);
        fork
            request(2,wanted_seed,0);
            begin
                repeat(CPB*36) @(negedge clk);model_result();
                while(received!=5 || dut.state_q!=0) @(negedge clk);
                reply(8'h83,2);
            end
        join
        drain();
        // Every CRC-covered field after recognized opcode is independently
        // corrupted: temperature, each seed byte, and final CRC itself.
        for(integer field=2;field<20;field=field+1) begin
            reply(8'hcf,0);crc_mutated_request(field);drain();
        end
        // Extra non-magic bytes after a drained frame do not issue a request.
        send_byte(8'h3f);send_byte(0);send_byte(8'h7e);
        repeat(CPB*50) @(negedge clk);cases=cases+1;
        // A complete duplicate after drain is a NEW valid settings command;
        // the protocol has no transaction ID or exactly-once retransmission.
        wanted_temperature=2;wanted_seed=0;expect_configuration=1;
        reply(8'h83,2);request(2,0,0);drain();
        // Reset at each incomplete frame position must revoke frame ownership.
        for(integer cut=0;cut<20;cut=cut+1) begin
            for(integer i=0;i<cut;i=i+1) send_byte(i==0?8'ha5:i==1?8'h03:8'h00);
            @(negedge clk);rst_n=0;repeat(3) @(negedge clk);rst_n=1;
            repeat(CPB*3) @(negedge clk);
            if(dut.state_q!=0 || settings_valid_o || dut.request_index_q!=0) $fatal(1,"reset retained partial frame");
        end
        if(configurations!=8 || cases!=284 || legacy_commands!=3)
            $fatal(1,"wrong UART coverage configurations=%0d cases=%0d commands=%0d",configurations,cases,legacy_commands);
        $display("PASS_SETTINGS_UART cases=%0d configurations=%0d invalid_temperatures=252 reset_positions=20 busy_spanning=2 timeout_tail_legacy=1 crc_fields=18 extra_bytes=1 duplicate_frame=1 cpb=%0d",cases,configurations,CPB);
        $finish;
    end
    initial begin #1000000000;$fatal(1,"settings UART global timeout");end
endmodule
