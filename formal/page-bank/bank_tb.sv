`timescale 1ns/1ps
// Deterministic compressor fixture. This deliberately does not compute SHA.
module board1_sha256_bank_owned_compress #(parameter REGISTER_RESULT=0) (
    input wire clk_i, reset_n_i, start_i,
    input wire [511:0] block_i,
    input wire [255:0] state_i,
    output reg busy_o=0, done_o=0,
    output reg [255:0] state_o=0
);
    // Allow the three read/capture cycles of private next-block preparation.
    // The actual compressor takes 16 rounds of clocks; this fixture checks
    // sequencing and block bytes, not the SHA computation itself.
    reg [2:0] remaining=0;
    always @(posedge clk_i) begin
        if (!reset_n_i) begin
            busy_o<=0; done_o<=0; remaining<=0;
        end else begin
            done_o<=0;
            if (start_i) begin
                if (busy_o) $fatal(1,"SHA_RESTART_WHILE_BUSY");
                busy_o<=1; remaining<=4;
            end else if (busy_o) begin
                if (remaining==1) begin busy_o<=0; done_o<=1; remaining<=0; end
                else remaining<=remaining-1;
            end
        end
    end
endmodule

module bank_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0, cancel_read_i=0, begin_valid_i=0;
    wire begin_ready_o;
    reg [10:0] begin_page_i=0;
    reg [255:0] expected_digest_i=0;
    reg fill_valid_i=0, fill_last_i=0, read_valid_i=0, response_ready_i=0;
    reg [255:0] fill_data_i=0;
    reg [6:0] read_word_i=0;
    wire fill_ready_o, read_ready_o, response_valid_o, assigned_o, verified_o, fault_o;
    wire [255:0] response_data_o;
    wire [10:0] page_o;
    localparam [255:0] AUTH=256'h0123456789abcdef112233445566778899aabbccddeeff00fedcba9876543210;
    localparam [511:0] PAD={8'h80,440'd0,64'd32768};
    reg [255:0] expected_word [0:127];
    integer scenarios=0, launch_count=0;
    board1_verified_page_bank dut(.*);

    function automatic [255:0] pattern(input integer word_index, input integer epoch);
        pattern={8{32'h13579b00 + 32'(word_index) + (32'(epoch)<<16)}};
    endfunction
    function automatic [255:0] big_endian(input [255:0] word);
        integer i;
        for(i=0;i<32;i=i+1) big_endian[255-i*8 -:8]=word[i*8 +:8];
    endfunction
    task automatic tick;
        @(posedge clk); #1; @(negedge clk); #1;
    endtask
    task automatic reset_bank;
        reset_n=0; begin_valid_i=0; fill_valid_i=0; read_valid_i=0;
        cancel_read_i=0; response_ready_i=0; fill_last_i=0;
        tick(); tick(); reset_n=1; tick();
        if(fault_o || verified_o || !begin_ready_o) $fatal(1,"RESET_FAILED");
    endtask
    task automatic prepare_page(input integer page, input integer epoch, input bit corrupt);
        integer words, i, timeout_count;
        words=page==1773 ? 118 : 128;
        expected_digest_i=AUTH; begin_page_i=11'(page); begin_valid_i=1;
        if(!begin_ready_o) $fatal(1,"BEGIN_NOT_READY");
        tick(); begin_valid_i=0;
        // Changing the external expected-digest input must not change this epoch.
        expected_digest_i=~AUTH;
        dut.u_sha.state_o=corrupt ? (AUTH ^ 256'd1) : AUTH;
        for(i=0;i<128;i=i+1) expected_word[i]=i<words ? pattern(i,epoch) : 0;
        for(i=0;i<words;i=i+1) begin
            if(!fill_ready_o || verified_o) $fatal(1,"FILL_ADMISSION");
            fill_valid_i=1; fill_data_i=expected_word[i]; fill_last_i=i==words-1;
            tick(); fill_valid_i=0; fill_last_i=0;
            if(i%17==0) tick();
        end
        timeout_count=0;
        while(!verified_o && !fault_o && timeout_count<600) begin tick(); timeout_count=timeout_count+1; end
        if(corrupt) begin
            if(!fault_o || verified_o) $fatal(1,"BAD_DIGEST_ACCEPTED");
        end else begin
            if(!verified_o || fault_o) $fatal(1,"GOOD_DIGEST_REJECTED");
            for(i=0;i<128;i=i+1)
                if(dut.memory_q[i] !== expected_word[i]) $fatal(1,"RAM_OR_PADDING_MISMATCH");
        end
        scenarios=scenarios+1;
    endtask
    task automatic read_word(input integer index, input integer stalls);
        integer i;
        read_word_i=7'(index); read_valid_i=1; response_ready_i=0;
        if(!read_ready_o) $fatal(1,"READ_NOT_READY");
        tick(); read_valid_i=0;
        for(i=0;i<=stalls;i=i+1) begin
            if(!response_valid_o || response_data_o !== expected_word[index]) $fatal(1,"READ_DATA_MISMATCH");
            if(begin_ready_o) $fatal(1,"EVICTION_WHILE_REPLY_HELD");
            if(i<stalls) tick();
        end
        response_ready_i=1; tick(); response_ready_i=0;
        if(response_valid_o) $fatal(1,"DUPLICATE_REPLY");
    endtask
    task automatic check_sticky_fault;
        cancel_read_i=1; tick(); tick();
        if(!fault_o || begin_ready_o || response_valid_o) $fatal(1,"FAULT_CLEARED_BY_CANCEL");
        cancel_read_i=0; tick(); scenarios=scenarios+1;
    endtask

    always @(negedge clk) begin
        if(reset_n) begin
            if(verified_o && dut.state_q!=9) $fatal(1,"PREMATURE_VERIFIED");
            if((dut.hash_active || verified_o) && dut.memory_write) $fatal(1,"SEALED_WRITE");
            if(!response_valid_o && response_data_o!==0) $fatal(1,"HIDDEN_DATA_EXPOSED");
            if(dut.state_q==6) begin
                launch_count=launch_count+1;
                if(dut.block_q<64) begin
                    if(dut.sha_block_q !== {big_endian(expected_word[2*dut.block_q]),
                                           big_endian(expected_word[2*dut.block_q+1])})
                        $fatal(1,"SHA_BLOCK_MISMATCH");
                end else if(dut.sha_block_q!==PAD) $fatal(1,"SHA_PADDING_MISMATCH");
            end
        end
    end

    integer i;
    initial begin
        reset_bank();
        prepare_page(0,1,0);
        for(i=0;i<128;i=i+1) read_word(i,i%3);
        scenarios=scenarios+1;
        read_word_i=7; read_valid_i=1; tick(); read_valid_i=0;
        cancel_read_i=1; #1;
        if(response_valid_o || read_ready_o) $fatal(1,"CANCEL_NOT_MASKED");
        tick(); cancel_read_i=0; tick();
        if(!verified_o || response_valid_o) $fatal(1,"CANCEL_CHANGED_BANK");
        read_word(7,4); scenarios=scenarios+1;
        prepare_page(1773,2,0);
        for(i=0;i<118;i=i+1) read_word(i,0);
        scenarios=scenarios+1;
        read_word_i=118; read_valid_i=1; tick(); read_valid_i=0;
        if(!fault_o || response_valid_o) $fatal(1,"INVALID_READ_ACCEPTED");
        check_sticky_fault();
        reset_bank(); prepare_page(1,3,1); check_sticky_fault();
        reset_bank();
        begin_valid_i=1; begin_page_i=0; expected_digest_i=AUTH; tick(); begin_valid_i=0;
        fill_valid_i=1; fill_last_i=1; tick(); fill_valid_i=0; fill_last_i=0;
        if(!fault_o) $fatal(1,"BAD_FILL_LAST_ACCEPTED");
        check_sticky_fault();
        reset_bank(); begin_page_i=1774; begin_valid_i=1; tick(); begin_valid_i=0;
        if(!fault_o) $fatal(1,"INVALID_PAGE_ACCEPTED");
        check_sticky_fault();
        if(scenarios!=10 || launch_count!=195) $fatal(1,"TEST_CENSUS");
        $display("BANK_SCENARIOS_PASS scenarios=%0d hash_blocks=%0d",scenarios,launch_count);
        $finish;
    end
    initial begin #200000; $fatal(1,"TEST_TIMEOUT"); end
endmodule
