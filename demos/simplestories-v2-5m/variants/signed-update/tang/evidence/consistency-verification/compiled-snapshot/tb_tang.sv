`timescale 1ns/1ps
module tb_tang;
    reg clk50=0;always #10 clk50=~clk50;
    reg button=1,rx=1;wire tx;
    tri [3:0] flash_dq;wire flash_cs,flash_sck;
    wire [14:0] da;wire [2:0] db;
    wire dc,dr,dcas,dw,dck,dckn,dcke,dodt,dreset;
    wire [3:0] dm;tri [31:0] dq;tri [3:0] dqs,dqsn;
    board1_fixed_swic_product_top dut(.clk_50mhz(clk50),.reset_button(button),.uart_rx(rx),.uart_tx(tx),
        .flash_dq(flash_dq),.flash_csn(flash_cs),.flash_sclk(flash_sck),
        .ddr_addr(da),.ddr_bank(db),.ddr_cs(dc),.ddr_ras(dr),.ddr_cas(dcas),.ddr_we(dw),
        .ddr_ck(dck),.ddr_ck_n(dckn),.ddr_cke(dcke),.ddr_odt(dodt),.ddr_reset_n(dreset),
        .ddr_dm(dm),.ddr_dq(dq),.ddr_dqs(dqs),.ddr_dqs_n(dqsn));
    reg [7:0] image[0:7265983],slot[0:262143];
    reg [33:0] expected_norm[0:3327];
    reg miso=1;assign flash_dq[1]=flash_cs ? 1'bz : miso;
    integer case_id,expected0,expected1;
    integer bit_count=0,read_address=0,data_bit=7;
    reg [31:0] command_q=0;
    reg reading=0;
    integer frame_transactions=0,image_transactions=0,flash_bytes=0;
    function automatic [7:0] flash_byte(input integer address);
        if(address>=24'h801000 && address<24'heeeec0) flash_byte=image[address-24'h801000];
        else if(address>=24'hf00000 && address<24'hf40000) flash_byte=slot[address-24'hf00000];
        else flash_byte=8'hff;
    endfunction
    always @(negedge flash_cs) begin bit_count=0;command_q=0;reading=0;data_bit=7;miso=1;end
    always @(posedge flash_sck) if(!flash_cs) begin
        if(!reading) begin
            command_q={command_q[30:0],flash_dq[0]};bit_count=bit_count+1;
            if(bit_count==32) begin
                if(command_q[31:24]!=8'h03) $fatal(1,"non-read SPI opcode %x",command_q);
                read_address=int'(command_q[23:0]);reading=1;data_bit=7;
                if(read_address==24'hf00000) frame_transactions=frame_transactions+1;
                else if(read_address==24'h801000) image_transactions=image_transactions+1;
                else $fatal(1,"unexpected flash address %x",read_address);
                $display("SPI START case=%0d address=%x time=%0t",case_id,read_address,$time);$fflush();
            end
        end
    end
    always @(negedge flash_sck) if(!flash_cs && reading) begin
        miso=(flash_byte(read_address)>>data_bit)&1;
        if(data_bit==0) begin data_bit=7;read_address=read_address+1;flash_bytes=flash_bytes+1;end
        else data_bit=data_bit-1;
    end
    reg [7:0] replies[0:127];integer reply_bytes=0;
    initial begin
        wait(dut.core_reset_n);repeat(5) @(negedge dut.core_clk);
        forever begin
            wait(tx==0);repeat(325) @(negedge dut.core_clk);
            for(integer b=0;b<8;b=b+1) begin
                replies[reply_bytes][b]=tx;
                repeat(217) @(negedge dut.core_clk);
            end
            if(tx!=1) $fatal(1,"UART stop bit");
            reply_bytes=reply_bytes+1;
        end
    end
    function automatic [7:0] crc(input [7:0] c,input [7:0] d);
        reg [7:0] v;begin v=c^d;for(integer i=0;i<8;i=i+1)v=v[7]?(v<<1)^8'h07:v<<1;crc=v;end
    endfunction
    task send_byte(input [7:0] v);
        begin
            rx=0;repeat(217) @(negedge dut.core_clk);
            for(integer i=0;i<8;i=i+1) begin rx=v[i];repeat(217) @(negedge dut.core_clk);end
            rx=1;repeat(217) @(negedge dut.core_clk);
        end
    endtask
    task command(input [7:0] op,input [11:0] tok,input [7:0] status,input integer expected);
        reg [7:0] c;integer before_count,ticks,actual;
        begin
            before_count=reply_bytes;c=crc(crc(crc(crc(0,8'ha5),op),tok[7:0]),{4'd0,tok[11:8]});
            send_byte(8'ha5);send_byte(op);send_byte(tok[7:0]);send_byte({4'd0,tok[11:8]});send_byte(c);
            ticks=0;
            while(reply_bytes<before_count+5 && ticks<20000000) begin
                @(negedge dut.core_clk);ticks=ticks+1;
                if(dut.core_fault || dut.memory_fault) $fatal(1,"fault during UART command %0d",op);
            end
            if(reply_bytes!=before_count+5) $fatal(1,"missing UART reply op=%0d",op);
            c=0;for(integer i=0;i<4;i=i+1)c=crc(c,replies[before_count+i]);
            actual={replies[before_count+3],replies[before_count+2]};
            if(replies[before_count]!=8'h5a || replies[before_count+1]!=status || replies[before_count+4]!=c || actual!=expected)
                $fatal(1,"UART mismatch op=%0d status=%x token=%0d expected=%0d crc=%x",op,replies[before_count+1],actual,expected,c);
            $display("PASS UART case=%0d op=%0d token=%0d cycles=%0d",case_id,op,actual,ticks);$fflush();
        end
    endtask
    integer ticks;
    string fixture,path;
    initial begin
        if(!$value$plusargs("CASE=%d",case_id)) case_id=0;
        if(!$value$plusargs("EXPECTED0=%d",expected0)) expected0=0;
        if(!$value$plusargs("EXPECTED1=%d",expected1)) expected1=0;
        if(!$value$plusargs("FIXTURES=%s",fixture)) $fatal(1,"fixtures missing");
        path=$sformatf("%s/case-%0d.image.hex",fixture,case_id==2?0:case_id);$readmemh(path,image);
        path=$sformatf("%s/case-%0d.slot.hex",fixture,case_id);$readmemh(path,slot);
        path=$sformatf("%s/case-%0d.norm.hex",fixture,case_id==2?0:case_id);$readmemh(path,expected_norm);
        repeat(10) @(negedge clk50);button=0;
        wait(dut.core_reset_n);repeat(8) @(negedge dut.core_clk);
        ticks=0;
        while(!dut.model_locked && !dut.memory_fault && !dut.source_fault && ticks<800000000) begin
            @(negedge dut.core_clk);ticks=ticks+1;
            if(ticks%50000000==0) begin $display("BOOT PROGRESS case=%0d cycles=%0d slot=%0d image=%0d word=%0d state=%0d",case_id,ticks,dut.u_signed_boot.slot_bytes_q,dut.u_signed_boot.image_bytes_q,dut.u_memory.u_boot.word_q,dut.u_memory.u_boot.state_q);$fflush();end
        end
        if(case_id==2) begin
            if(dut.model_locked || !(dut.memory_fault || dut.source_fault) || image_transactions!=0 || dut.u_raw_controller.model_writes!=0)
                $fatal(1,"invalid signature reached model loading");
            $display("PASS bad signature rejected before image transaction");$finish;
        end else begin
        if(!dut.model_locked || dut.memory_fault || dut.source_fault)
            $fatal(1,"boot failed case=%0d cycles=%0d ingress=%0d source=%0d boot=%0d state=%0d image_fault=%0d norm_fault=%0d",case_id,ticks,dut.swic_ingress_fault,dut.swic_qspi_fault,dut.u_memory.boot_fault,dut.u_memory.u_boot.state_q,dut.u_memory.u_boot.image_fault,dut.u_memory.u_boot.norm_fault);
`ifdef SWIC_FAST_FLASH
        if(dut.u_signed_boot.slot_bytes_q!=262144 || dut.u_signed_boot.image_bytes_q!=7265984 || dut.u_raw_controller.model_writes!=227062)
`else
        if(frame_transactions!=1 || image_transactions!=1 || dut.u_raw_controller.model_writes!=227062)
`endif
            $fatal(1,"incorrect physical transaction counts");
        for(integer i=0;i<3328;i=i+1)
            if({dut.u_memory.u_boot.u_norms.metadata_q[i/256],dut.u_memory.u_boot.u_norms.coefficients_q[i]}!==expected_norm[i])
                $fatal(1,"norm extraction mismatch row %0d",i);
        $display("PASS Tang boot case=%0d cycles=%0d all_norm_rows=3328",case_id,ticks);$fflush();
        repeat(20) @(negedge dut.core_clk);
        command(2,0,8'h82,0);command(0,1,8'h80,0);
        command(1,0,8'h81,expected0);command(1,0,8'h81,expected1);
        command(2,0,8'h82,0);command(0,1,8'h80,0);command(1,0,8'h81,expected0);
`ifdef SWIC_FAST_FLASH
        $display("PASS fast Tang SWIC case=%0d",case_id);$finish;
`else
        $display("PASS full Tang SWIC case=%0d",case_id);$finish;
`endif
        end
    end
endmodule
