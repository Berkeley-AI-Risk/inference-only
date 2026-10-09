`timescale 1ns/1ps
module guard_tb #(parameter integer PROGRAM_WORDS=65536);
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,clear_i=0,model_locked_i=1,upstream_fault_i=0;
    reg s_wr_valid=0,s_wr_cpl_ready=0,s_rd_valid=0,s_rd_rsp_ready=0;
    reg [2:0] s_wr_layer=0,s_rd_layer=0;
    reg [11:0] s_wr_position=0,s_rd_position=0;
    reg [1:0] s_wr_head=0,s_rd_head=0;
    reg [3:0] s_wr_word=0,s_rd_word=0;
    reg [18:0] s_wr_shadow=0,s_rd_shadow=0;
    reg [255:0] s_wr_data=0;
    wire s_wr_ready,s_wr_cpl_valid,s_wr_cpl_fault,s_rd_ready,s_rd_rsp_valid,s_rd_rsp_fault,fault_o;
    wire [255:0] s_rd_rsp_data;
    wire m_wr_valid,m_wr_cpl_ready,m_rd_valid,m_rd_rsp_ready;
    wire [2:0] m_wr_layer,m_rd_layer;
    wire [11:0] m_wr_position,m_rd_position;
    wire [1:0] m_wr_head,m_rd_head;
    wire [3:0] m_wr_word,m_rd_word;
    wire [18:0] m_wr_shadow,m_rd_shadow;
    wire [255:0] m_wr_data;
    reg m_wr_cpl_valid=0,m_wr_cpl_fault=0,m_rd_rsp_valid=0,m_rd_rsp_fault=0;
    reg [255:0] m_rd_rsp_data=0;
    reg memory_pending=0,memory_write=0;
    reg [18:0] memory_address=0;
    reg [255:0] memory_value=0;
    integer delay_q=0,cycles=0,ddr_reads=0,ddr_writes=0;
    integer service_start=0,last_service_cycles=0;
    reg hold_memory=0;
    wire m_wr_ready=reset_n && !memory_pending && (cycles%5!=2);
    wire m_rd_ready=reset_n && !memory_pending && (cycles%7!=3);
    reg [255:0] memory[0:221183];
    board1_kv_integrity_guard #(.DDR_TIMEOUT_CYCLES(2000)) dut(.*);
    always @(posedge clk) begin
        cycles<=cycles+1;
        if(!reset_n) begin
            memory_pending<=0;m_wr_cpl_valid<=0;m_rd_rsp_valid<=0;delay_q<=0;
            m_wr_cpl_fault<=0;m_rd_rsp_fault<=0;
        end else begin
            if(m_wr_cpl_valid && m_wr_cpl_ready) begin m_wr_cpl_valid<=0;memory_pending<=0;end
            if(m_rd_rsp_valid && m_rd_rsp_ready) begin m_rd_rsp_valid<=0;memory_pending<=0;end
            if(m_wr_valid && m_wr_ready) begin
                if(m_rd_valid || m_wr_shadow!==addr(m_wr_layer,m_wr_position,m_wr_head,m_wr_word))
                    $fatal(1,"Invalid write address/ownership");
                memory_pending<=1;memory_write<=1;memory_address<=m_wr_shadow;
                memory_value<=m_wr_data;delay_q<=3+cycles%4;ddr_writes<=ddr_writes+1;
            end
            if(m_rd_valid && m_rd_ready) begin
                if(m_wr_valid || m_rd_shadow!==addr(m_rd_layer,m_rd_position,m_rd_head,m_rd_word))
                    $fatal(1,"Invalid read address/ownership");
                memory_pending<=1;memory_write<=0;memory_address<=m_rd_shadow;
                delay_q<=3+cycles%5;ddr_reads<=ddr_reads+1;
            end
            if(memory_pending && !m_wr_cpl_valid && !m_rd_rsp_valid && !hold_memory) begin
                if(delay_q>0) delay_q<=delay_q-1;
                else if(memory_write) begin
                    memory[memory_address-227072]<=memory_value;m_wr_cpl_valid<=1;
                end else begin
                    m_rd_rsp_data<=memory[memory_address-227072];m_rd_rsp_valid<=1;
                end
            end
            if(s_rd_rsp_valid && !s_rd_rsp_fault && !clear_i && !dut.aborted_q && !dut.cache_valid_q)
                $fatal(1,"Response without verified cache ownership");
            if((clear_i || fault_o || dut.aborted_q) && s_rd_rsp_data!==256'd0)
                $fatal(1,"Canceled/fault data exposure");
        end
    end

    function automatic [18:0] addr(input integer l,p,h,w);
        addr=227072+18*(l*2048+p)+9*h+w;
    endfunction
    function automatic [255:0] known(input integer l,p,h,w);
        reg [255:0] value;
        begin
            value=0;
            for(integer k=0;k<16;k=k+1) value[k*16 +:16]=16'(l*101+p*17+h*33+w*16+k);
            if(w==8) value=0;
            known=value;
        end
    endfunction
    task reset;
        begin
            @(negedge clk);reset_n=0;clear_i=0;model_locked_i=1;upstream_fault_i=0;
            s_wr_valid=0;s_rd_valid=0;s_wr_cpl_ready=0;s_rd_rsp_ready=0;hold_memory=0;
            repeat(4) @(negedge clk);reset_n=1;repeat(2) @(negedge clk);
        end
    endtask
    task clear;
        begin @(negedge clk);clear_i=1;@(negedge clk);clear_i=0;@(negedge clk);end
    endtask
    task begin_write(input integer l,p,h,w,input [255:0] data,input bit bad_shadow);
        integer start_cycle;
        begin
            @(negedge clk);s_wr_layer=l;s_wr_position=p;s_wr_head=h;s_wr_word=w;
            s_wr_shadow=addr(l,p,h,w) ^ (bad_shadow ? 19'd1 : 19'd0);s_wr_data=data;s_wr_valid=1;
            start_cycle=cycles;
            while(!s_wr_ready) begin
                @(negedge clk);if(cycles-start_cycle>10000) $fatal(1,"Write ready timeout");
            end
            @(negedge clk);s_wr_valid=0;service_start=cycles;
        end
    endtask
    task end_write(input bit want_fault);
        integer start_cycle;
        begin
            start_cycle=cycles;
            while(!s_wr_cpl_valid) begin
                @(negedge clk);if(cycles-start_cycle>20000) $fatal(1,"Write completion timeout state %0d",dut.state_q);
            end
            if(s_wr_cpl_fault!==want_fault) $fatal(1,"Write fault mismatch state %0d",dut.state_q);
            last_service_cycles=cycles-service_start;
            repeat(2) begin @(negedge clk);if(!s_wr_cpl_valid) $fatal(1,"Lost held write completion");end
            s_wr_cpl_ready=1;@(negedge clk);s_wr_cpl_ready=0;@(negedge clk);
        end
    endtask
    task put_position(input integer l,p);
        begin
            for(integer h=0;h<2;h=h+1) for(integer w=0;w<9;w=w+1) begin
                begin_write(l,p,h,w,known(l,p,h,w),0);end_write(0);
            end
        end
    endtask
    task begin_read(input integer l,p,h,w,input bit bad_shadow);
        integer start_cycle;
        begin
            @(negedge clk);s_rd_layer=l;s_rd_position=p;s_rd_head=h;s_rd_word=w;
            s_rd_shadow=addr(l,p,h,w) ^ (bad_shadow ? 19'd1 : 19'd0);s_rd_valid=1;
            start_cycle=cycles;
            while(!s_rd_ready) begin
                @(negedge clk);if(cycles-start_cycle>10000) $fatal(1,"Read ready timeout");
            end
            @(negedge clk);s_rd_valid=0;service_start=cycles;
        end
    endtask
    task end_read(input bit want_fault,input [255:0] expected);
        integer start_cycle;
        begin
            start_cycle=cycles;
            while(!s_rd_rsp_valid) begin
                @(negedge clk);if(cycles-start_cycle>20000) $fatal(1,"Read completion timeout state %0d",dut.state_q);
            end
            if(s_rd_rsp_fault!==want_fault || s_rd_rsp_data!==expected)
                $fatal(1,"Read mismatch fault=%b want=%b got=%h expected=%h",s_rd_rsp_fault,want_fault,s_rd_rsp_data,expected);
            last_service_cycles=cycles-service_start;
            repeat(3) begin
                @(negedge clk);
                if(!s_rd_rsp_valid || s_rd_rsp_data!==expected || s_rd_rsp_fault!==want_fault)
                    $fatal(1,"Held read changed");
            end
            s_rd_rsp_ready=1;@(negedge clk);s_rd_rsp_ready=0;@(negedge clk);
        end
    endtask
    task check_tag(input integer l,p,h,role,input [255:0] expected);
        reg [255:0] actual;
        integer a;
        begin
            for(integer k=0;k<8;k=k+1) begin
                a=((p/16)*4+h*2+role)*8+k;
                case(l)
                    0: actual[k*32 +:32]=dut.g_tags[0].memory[a];
                    1: actual[k*32 +:32]=dut.g_tags[1].memory[a];
                    2: actual[k*32 +:32]=dut.g_tags[2].memory[a];
                    3: actual[k*32 +:32]=dut.g_tags[3].memory[a];
                    4: actual[k*32 +:32]=dut.g_tags[4].memory[a];
                    5: actual[k*32 +:32]=dut.g_tags[5].memory[a];
                endcase
            end
            if(actual!==expected) $fatal(1,"Trusted digest mismatch l=%0d p=%0d got=%h want=%h",l,p,actual,expected);
            if(dut.prefix_q[l]!==12'(p+1)) $fatal(1,"Prefix published incorrectly");
        end
    endtask
    task wait_state(input integer wanted);
        integer start_cycle;
        begin
            start_cycle=cycles;
            while(dut.state_q!=wanted) begin
                @(negedge clk);
                if(cycles-start_cycle>20000) $fatal(1,"Did not reach state %0d, current %0d",wanted,dut.state_q);
            end
        end
    endtask
    task clear_write_case(input integer target);
        begin
            reset;
            if(target>=10) begin
                for(integer i=0;i<17;i=i+1) begin
                    begin_write(0,0,i/9,i%9,known(0,0,i/9,i%9),0);end_write(0);
                end
                begin_write(0,0,1,8,known(0,0,1,8),0);
            end else begin_write(0,0,0,0,known(0,0,0,0),0);
            wait_state(target);
            clear_i=1;@(negedge clk);clear_i=0;
            end_write(0);
            for(integer k=0;k<6;k=k+1) if(dut.prefix_q[k]!==0) $fatal(1,"CLEAR kept prefix");
            put_position(0,0);
            begin_read(0,0,0,0,0);end_read(0,known(0,0,0,0));
            $display("CLEAR_WRITE_PASS state=%0d",target);
        end
    endtask
    task clear_read_case(input integer target);
        begin
            reset;put_position(0,0);begin_read(0,0,0,0,0);wait_state(target);
            clear_i=1;@(negedge clk);clear_i=0;end_read(0,256'd0);
            if(dut.cache_valid_q || dut.prefix_q[0]!=0) $fatal(1,"CLEAR kept readable state");
            put_position(0,0);begin_read(0,0,1,0,0);end_read(0,known(0,0,1,0));
            $display("CLEAR_READ_PASS state=%0d",target);
        end
    endtask

    task clear_later_tag(input integer group_index);
        integer started;
        begin
            reset;
            for(integer i=0;i<17;i=i+1) begin
                begin_write(0,0,i/9,i%9,known(0,0,i/9,i%9),0);end_write(0);
            end
            begin_write(0,0,1,8,known(0,0,1,8),0);started=cycles;
            while(!(dut.state_q==15 && {dut.group_head_q,dut.role_q}==2'(group_index) && dut.chunk_q==7)) begin
                @(negedge clk);
                if(cycles-started>20000) $fatal(1,"Tag group CLEAR not reached");
                if(dut.prefix_q[0]!=0 || s_wr_cpl_valid) $fatal(1,"Published before all four tags");
            end
            clear_i=1;@(negedge clk);clear_i=0;end_write(0);
            if(dut.prefix_q[0]!=0 || dut.cache_valid_q) $fatal(1,"Partial tag set survived CLEAR");
            put_position(0,0);
            begin_read(0,0,1,4,0);end_read(0,known(0,0,1,4));
            $display("CLEAR_TAG_GROUP_PASS group=%0d",group_index);
        end
    endtask

    reg [255:0] program_mem[0:PROGRAM_WORDS-1];
    reg [255:0] descriptor,expected;
    string path,metrics_path;
    integer entries=0,cursor=0,commands=0,op,l,p,h,w,started,reads_before,writes_before,metrics;
    initial begin
        if(!$value$plusargs("program=%s",path) || !$value$plusargs("entries=%d",entries) ||
           !$value$plusargs("metrics=%s",metrics_path)) $fatal(1,"Missing program arguments");
        $readmemh(path,program_mem,0,entries-1);
        metrics=$fopen(metrics_path,"w");
        if(metrics==0) $fatal(1,"Cannot open metrics");
        reset;
        while(cursor<entries) begin
            descriptor=program_mem[cursor];cursor=cursor+1;commands=commands+1;
            op=descriptor[255:252];l=descriptor[2:0];p=descriptor[14:3];h=descriptor[16:15];w=descriptor[20:17];
            started=cycles;reads_before=ddr_reads;writes_before=ddr_writes;last_service_cycles=0;
            case(op)
                0: reset;
                1: begin
                    expected=program_mem[cursor];cursor=cursor+1;
                    begin_write(l,p,h,w,expected,descriptor[22]);end_write(descriptor[21]);
                end
                2: begin
                    expected=program_mem[cursor];cursor=cursor+1;
                    begin_read(l,p,h,w,descriptor[22]);end_read(descriptor[21],expected);
                end
                3: clear;
                4: begin
                    memory[addr(l,p,h,w)-227072]=memory[addr(l,p,h,w)-227072]^program_mem[cursor];cursor=cursor+1;
                end
                5: begin memory[addr(l,p,h,w)-227072]=program_mem[cursor];cursor=cursor+1;end
                6: begin expected=program_mem[cursor];cursor=cursor+1;check_tag(l,p,h,w,expected);end
                7,8: $display("GUARD_TRACE_MARK op=%0d phase=%0d context=%0d cycle=%0d reads=%0d writes=%0d",op,l,p,cycles,ddr_reads,ddr_writes);
                default: $fatal(1,"Unknown test command");
            endcase
            $fdisplay(metrics,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",commands,op,l,p,h,w,cycles-started,ddr_reads-reads_before,ddr_writes-writes_before,last_service_cycles);
        end
        $fclose(metrics);
        $display("GUARD_PROGRAM_PASS commands=%0d",commands);
        for(integer s=1;s<=4;s=s+1) clear_write_case(s);
        for(integer s=10;s<=15;s=s+1) clear_write_case(s);
        for(integer s=5;s<=14;s=s+1) clear_read_case(s);
        for(integer s=16;s<=18;s=s+1) clear_read_case(s);
        for(integer group_index=0;group_index<4;group_index=group_index+1) clear_later_tag(group_index);
        reset;put_position(0,0);begin_read(0,0,0,0,0);wait_state(6);
        hold_memory=1;repeat(2005) @(negedge clk);
        if(!fault_o || s_rd_rsp_valid || s_rd_rsp_data!==0 || m_rd_valid || m_wr_valid) $fatal(1,"Watchdog failed closed");
        hold_memory=0;end_read(1,256'd0);clear;
        if(!fault_o || s_wr_ready || s_rd_ready) $fatal(1,"CLEAR erased terminal fault");
        reset;
        @(negedge clk);s_wr_valid=1;s_rd_valid=1;
        #1;if(s_wr_ready || s_rd_ready) $fatal(1,"Colliding requests accepted");
        @(negedge clk);s_wr_valid=0;s_rd_valid=0;
        if(!fault_o || m_wr_valid || m_rd_valid) $fatal(1,"Collision did not latch terminal fault");
        clear;if(!fault_o) $fatal(1,"CLEAR erased collision fault");
`ifndef SYNTHESIS
        reset;
        begin_write(0,0,0,0,256'bx,0);end_write(1);
        if(m_wr_valid || m_rd_valid || !fault_o) $fatal(1,"Unknown payload escaped");
        $display("GUARD_FOUR_STATE_PASS unknown_write_payload=1");
`endif
        $display("GUARD_ALL_PASS commands=%0d cancel_write=10 cancel_read=13 cancel_tag_groups=4 watchdog=1 collision=1",commands);
        $finish;
    end
    initial begin #10000000000;$fatal(1,"Global watchdog");end
endmodule
