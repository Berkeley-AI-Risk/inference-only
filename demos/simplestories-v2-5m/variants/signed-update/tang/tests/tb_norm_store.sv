`timescale 1ns/1ps
module tb_norm_store;
    reg clk=0;always #5 clk=~clk;
    reg reset_n=0,valid=0,locked=0,ar=0,br=0;
    reg [17:0] index=0;reg [255:0] data=0;
    reg [11:0] aa=0,ba=0;
    wire ready,loaded,fault;wire [33:0] ad,bd;
    reg [7:0] image[0:7265983];reg [33:0] expected[0:3327];
    string fixtures,path;
    swic_norm_store dut(.clk(clk),.reset_n(reset_n),.word_valid_i(valid),.word_ready_o(ready),
        .word_index_i(index),.word_data_i(data),.loaded_o(loaded),.fault_o(fault),
        .model_locked_i(locked),.body_read_i(ar),.head_read_i(br),.body_address_i(aa),.head_address_i(ba),
        .body_data_o(ad),.head_data_o(bd));
    task reset_dut;
        begin reset_n=0;valid=0;locked=0;ar=0;br=0;repeat(3) @(negedge clk);
            reset_n=1;@(negedge clk);if(loaded || fault || ad!=0 || bd!=0) $fatal(1,"reset admission");end
    endtask
    task word(input integer address,input integer mutation);
        begin
            while(!ready && !fault) @(negedge clk);
            if(fault) $fatal(1,"unexpected norm fault before word");
            index=18'(address);for(integer b=0;b<32;b=b+1)data[b*8 +:8]=image[address*32+b];
            if(mutation==1)data[9:0]=10'h200;
            if(mutation==2)data[23:8]=0;
            valid=1;@(negedge clk);valid=0;
        end
    endtask
    task positive(input integer n);
        begin
            reset_dut();
            path=$sformatf("%s/case-%0d.image.hex",fixtures,n);$readmemh(path,image);
            path=$sformatf("%s/case-%0d.norm.hex",fixtures,n);$readmemh(path,expected);
            for(integer a=211800;a<211920;a=a+1)word(a,0);
            word(214248,0);word(214249,0);
            for(integer a=214250;a<=214260;a=a+1)word(a,0);
            while(!loaded && !fault) @(negedge clk);
            if(fault) $fatal(1,"valid norm extraction failed");
            locked=1;ar=1;br=1;
            for(integer i=0;i<3328;i=i+1) begin
                aa=12'(i);ba=12'(3327-i);@(negedge clk);
                if(ad!==expected[i] || bd!==expected[3327-i]) $fatal(1,"dual port mismatch %0d",i);
            end
            locked=0;@(negedge clk);if(ad!=0 || bd!=0) $fatal(1,"unlocked norm data");
            $display("PASS norm model=%0d all_3328_rows_both_ports",n);
        end
    endtask
    initial begin
        if(!$value$plusargs("FIXTURES=%s",fixtures)) $fatal(1,"missing fixtures");
        positive(0);positive(1);
        reset_dut();word(211800,1);for(integer a=211801;a<211810;a=a+1)word(a,0);
        repeat(3) @(negedge clk);if(!fault || loaded) $fatal(1,"forbidden coefficient accepted");
        $display("PASS forbidden norm coefficient rejected");
        reset_dut();word(214260,2);@(negedge clk);if(!fault || loaded) $fatal(1,"zero multiplier accepted");
        $display("PASS zero norm multiplier rejected");
        reset_dut();$display("PASS norm-store regression");$finish;
    end
endmodule
