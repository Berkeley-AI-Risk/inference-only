`timescale 1ns/1ps
module tb_memory;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,bv=0,bl=0,rv=0,rl=0;
    reg [7:0] bb=0,rb=0;
    wire br,rr,model_ready,fault;
    reg pb=0,pfv=0,pfl=0,pr=0,cancel=0,resp_ready=0,mr=0;
    reg [10:0] page=0;reg [6:0] word_index=0;reg [255:0] fill_data=0;
    reg [11:0] ma=0;
    wire pbr,pfr,prr,rspv;wire [255:0] rspdata;wire [191:0] md;
    reg [7:0] frame[0:116692];
    reg [7:0] image[0:7265983];
    reg [191:0] metadata[0:2327];
    integer case_number=0;
    swic_verified_memory dut(.clk(clk),.reset_n(reset_n),
      .boot_valid_i(bv),.boot_last_i(bl),.boot_byte_i(bb),.boot_ready_o(br),
      .readback_valid_i(rv),.readback_last_i(rl),.readback_byte_i(rb),.readback_ready_o(rr),
      .model_ready_o(model_ready),.fault_o(fault),
      .page_begin_i(pb),.page_begin_ready_o(pbr),.page_i(page),
      .page_fill_valid_i(pfv),.page_fill_last_i(pfl),.page_fill_ready_o(pfr),.page_fill_data_i(fill_data),
      .cancel_read_i(cancel),.page_read_i(pr),.page_word_i(word_index),.page_read_ready_o(prr),
      .page_response_valid_o(rspv),.page_response_ready_i(resp_ready),.page_response_data_o(rspdata),
      .metadata_read_i(mr),.metadata_address_i(ma),.metadata_data_o(md));
    always @(negedge clk) if(reset_n) begin
        if(!model_ready && (rspv || rspdata!=0 || md!=0)) $fatal(1,"unadmitted data exposed");
        if(rspv && !dut.bank_verified) $fatal(1,"unverified page exposed");
    end
    task reset_dut;
        begin
            reset_n=0;bv=0;bl=0;rv=0;rl=0;pb=0;pfv=0;pfl=0;
            pr=0;cancel=0;resp_ready=0;mr=0;
            repeat(4) @(negedge clk);reset_n=1;@(negedge clk);
            if(model_ready || rspv || dut.sealed) $fatal(1,"reset retained admission");
        end
    endtask
    task boot_case(input integer number,input integer size,input expected);
        integer i,ticks;string path;
        begin
            reset_dut();case_number=number;
            path=$sformatf("@@OUT@@/frame-%0d.hex",number);
            $readmemh(path,frame,0,size-1);
            i=0;ticks=0;
            while(i<size && !fault && ticks<500000) begin
                bv=(ticks%17)!=0;bb=frame[i];bl=(i==size-1);
                @(posedge clk);if(bv && br) i=i+1;
                @(negedge clk);ticks=ticks+1;
                if(model_ready) $fatal(1,"ready before readback");
            end
            bv=0;bl=0;ticks=0;
            while(!dut.sealed && !fault && ticks<3000000) begin @(negedge clk);ticks=ticks+1;end
            if(dut.sealed!==expected || (!expected && !fault))
                $fatal(1,"boot case %0d sealed=%0d expected=%0d fault=%0d state=%0d received=%0d",number,dut.sealed,expected,fault,dut.u_admission.state_q,dut.u_admission.received_q);
            if(model_ready || rspv) $fatal(1,"ready without full readback");
            $display("PASS boot case=%0d accepted=%0d",number,expected);
        end
    endtask
    task reset_during_boot;
        integer i;
        begin
            reset_dut();$readmemh("@@OUT@@/frame-0.hex",frame,0,115395);
            for(i=0;i<500;i=i+1) begin
                bv=1;bb=frame[i];bl=0;@(negedge clk);
            end
            bv=0;reset_dut();repeat(100) @(negedge clk);
            if(dut.sealed || model_ready || rspv) $fatal(1,"partial frame survived reset");
            $display("PASS reset during frame load revokes partial state");
            // Deliver a complete frame, then reset during real SHA/LMS work.
            for(i=0;i<115396;i=i+1) begin
                bv=1;bb=frame[i];bl=(i==115395);@(negedge clk);
            end
            bv=0;bl=0;repeat(100) @(negedge clk);reset_dut();
            repeat(100) @(negedge clk);
            if(dut.sealed || model_ready || rspv) $fatal(1,"partial verification survived reset");
            $display("PASS reset during verification revokes partial state");
        end
    endtask
    task readback_image(input integer changed,input corrupt);
        integer i,ticks;
        begin
            i=0;ticks=0;
            while(i<7265984 && !fault && ticks<20000000) begin
                rv=1;rb=image[i];rl=i==7265983;
                if(i==0 && changed==1) rb=rb^8'h01;
                if(i==211920*32+7*4+2 && changed==2) rb=rb^8'h01;
                if(i==100 && corrupt) rb=rb^8'h01;
                @(posedge clk);if(rv && rr) i=i+1;
                @(negedge clk);ticks=ticks+1;
                if(model_ready && i<7265984) $fatal(1,"early image admission");
            end
            rv=0;rl=0;ticks=0;
            while(!model_ready && !fault && ticks<1000) begin @(negedge clk);ticks=ticks+1;end
            if(corrupt) begin if(!fault || model_ready) $fatal(1,"bad DDR readback accepted");end
            else if(!model_ready || fault) $fatal(1,"valid readback failed count=%0d state=%0d",i,dut.u_image.u_sha.state_q);
            $display("PASS full image changed=%0d corrupt=%0d",changed,corrupt);
        end
    endtask
    task check_metadata(input changed);
        integer i;reg [191:0] expected;
        begin
            for(i=0;i<2328;i=i+1) begin
                mr=1;ma=12'(i);@(negedge clk);
                expected=metadata[i];
                if(changed && i==0) expected[191:184]=expected[191:184]^8'h01;
                if(md!==expected) $fatal(1,"metadata word %0d mismatch",i);
            end
            mr=0;$display("PASS all 2328 sealed metadata words");
        end
    endtask
    task check_page(input integer p,input integer changed,input corrupt);
        integer words,w,b,ticks,offset;reg [255:0] expected;
        begin
            page=11'(p);pb=1;
            while(!pbr) @(negedge clk);
            @(negedge clk);pb=0;
            ticks=0;while(!pfr && !fault && ticks<100) begin @(negedge clk);ticks=ticks+1;end
            if(!pfr || fault) $fatal(1,"page setup failed");
            words=(p==1773)?118:128;
            for(w=0;w<words;w=w+1) begin
                for(b=0;b<32;b=b+1) begin
                    offset=p*4096+w*32+b;fill_data[b*8 +:8]=image[offset];
                    if(offset==0 && changed==1) fill_data[b*8 +:8]=fill_data[b*8 +:8]^8'h01;
                    if(offset==211920*32+7*4+2 && changed==2) fill_data[b*8 +:8]=fill_data[b*8 +:8]^8'h01;
                end
                if(w==0 && corrupt) fill_data=fill_data^256'h01;
                pfv=1;pfl=w==words-1;
                @(negedge clk);
            end
            pfv=0;pfl=0;ticks=0;
            while(!dut.bank_verified && !fault && ticks<20000) begin @(negedge clk);ticks=ticks+1;end
            if(corrupt) begin
                if(!fault || rspv) $fatal(1,"mutated page accepted");
            end else begin
                if(!dut.bank_verified || fault) $fatal(1,"valid page failed");
                word_index=7'(words-1);pr=1;resp_ready=0;
                while(!prr) @(negedge clk);
                @(negedge clk);pr=0;
                for(b=0;b<32;b=b+1) expected[b*8 +:8]=image[p*4096+(words-1)*32+b];
                if(!rspv || rspdata!==expected) $fatal(1,"page response mismatch");
                repeat(3) begin @(negedge clk);if(!rspv || rspdata!==expected) $fatal(1,"response changed under backpressure");end
                cancel=1;@(negedge clk);if(rspv || fault || !model_ready) $fatal(1,"cancel changed model admission");
                cancel=0;@(negedge clk);
            end
            $display("PASS page=%0d changed=%0d corrupt=%0d",p,changed,corrupt);
        end
    endtask
    initial begin
        $readmemh("@@OUT@@/image.hex",image);
        $readmemh("@@OUT@@/metadata.hex",metadata);
@@CASES@@
        reset_during_boot();
        // Each trust layer is exercised in the connected, real-crypto design.
        boot_case(0,115396,1);readback_image(0,0);check_metadata(0);
        check_page(0,0,0);check_page(1773,0,0);
        word_index=118;pr=1;@(negedge clk);pr=0;@(negedge clk);
        if(!fault || model_ready) $fatal(1,"tail out-of-range read accepted");
        $display("PASS final-page out-of-range read rejected");
        boot_case(1,115396,1);readback_image(1,0);check_page(0,1,0);
        // Input after seal is never interpreted as a runtime update.
        bv=1;bb=0;bl=1;@(negedge clk);bv=0;bl=0;@(negedge clk);
        if(!fault || model_ready) $fatal(1,"runtime boot write accepted");
        $display("PASS post-admission boot write fails closed");
        boot_case(2,115396,1);readback_image(2,0);check_metadata(1);check_page(1655,2,0);
        mr=1;ma=4095;@(negedge clk);mr=0;@(negedge clk);
        if(!fault || model_ready || md!=0) $fatal(1,"out-of-range metadata read accepted");
        $display("PASS out-of-range metadata read rejected");
        boot_case(0,115396,1);readback_image(0,0);check_page(0,0,1);
        boot_case(0,115396,1);readback_image(0,1);
        // A reset revokes the sealed root and all page validity.
        reset_dut();repeat(100) @(negedge clk);
        if(dut.sealed || model_ready || rspv) $fatal(1,"stale state survived reset");
        $display("PASS reset revokes admission");
        $display("PASS connected SWIC memory regression");$finish;
    end
endmodule
