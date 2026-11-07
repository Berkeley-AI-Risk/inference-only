`timescale 1ns/1ps
module tb_lookup_public;
    reg clk=0;always #5 clk=~clk;
    reg [7:0] a=0,b=0;
    wire [7:0] pa,pb;
    combined_public_aes_lookup_sim u_public(.clk(clk),.address_a_i(a),.address_b_i(b),.data_a_o(pa),.data_b_o(pb));
    reg [7:0] expected[0:255];integer pairs=0,prechecks=0;bit primed=0;reg [7:0] previous_a,previous_b;
    initial begin
        $readmemh("expected.memh",expected);
        for(integer ai=0;ai<256;ai=ai+1)begin
            for(integer bi=0;bi<256;bi=bi+1)begin
                @(negedge clk);a=8'(ai);b=8'(bi);#1;
                if(primed)begin
                    if(pa!==previous_a ||
                       pb!==previous_b)
                        $fatal(1,"lookup changed before its read edge A=%0d B=%0d",ai,bi);
                    prechecks=prechecks+1;
                end
                @(posedge clk);#1;
                if(pa!==expected[ai] ||
                   pb!==expected[bi])
                    $fatal(1,"lookup truth/one-edge latency mismatch A=%0d B=%0d",ai,bi);
                pairs=pairs+1;primed=1;previous_a=expected[ai];previous_b=expected[bi];
            end
        end
        if(pairs!=65536 || prechecks!=65535)$fatal(1,"incomplete lookup pair/latency census");
        $display("PASS_LOOKUP_PUBLIC pairs=65536 pre_edge_stability_checks=65535 two_ports=1 latency_edges=1 expected_GF_truth=1");$finish;
    end
endmodule
