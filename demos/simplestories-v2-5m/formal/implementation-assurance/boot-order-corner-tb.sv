`timescale 1ns/1ps
module boot_order_corner_tb;
    reg clk=0;
    always #5 clk=~clk;
    reg reset_n=0;
    reg calib_done=1,calib_error=0,fixed_source_done=1,fixed_source_ok=1;
    reg [255:0] loader_data=0;
    reg loader_valid=1;
    wire loader_ready;
    wire [255:0] readback_word_data;
    wire readback_word_valid,readback_word_last;
    reg readback_word_ready=1,readback_digest_done=0,readback_digest_ok=1;
    reg runtime_req_valid=0,runtime_req_write=0,runtime_rsp_ready=1;
    reg [18:0] runtime_req_word_address=0;
    reg [255:0] runtime_req_write_data=0;
    wire runtime_req_ready;
    wire [255:0] runtime_rsp_data;
    wire runtime_rsp_valid,runtime_rsp_error,phy_req_valid,phy_req_write;
    wire [18:0] phy_req_word_addr;
    wire [255:0] phy_req_wdata;
    reg phy_req_ready=1,phy_rsp_valid=0,phy_rsp_error=0;
    reg [255:0] phy_rsp_data=0;
    wire model_locked,fail_closed;
    board1_context2048_private_ddr_lock_bridge dut(.*);
    integer writes=0,reads=0,returns=0,cycles=0;
    reg pending=0;
    reg corner_seen=0;
    always @(posedge clk) begin
        if(reset_n)begin
            cycles=cycles+1;
            if(phy_req_valid&&phy_req_ready)begin
                if(phy_req_write)writes=writes+1;
                else reads=reads+1;
            end
            if(phy_rsp_valid&&!corner_seen)returns=returns+1;
            pending<=phy_req_valid&&phy_req_ready&&!phy_req_write;
        end
    end
    // Every boot word is loaded and read using the native full geometry.
    // One extra response is then placed on the held-final-word consume edge.
    always @(negedge clk) if(reset_n&&!corner_seen)begin
        phy_rsp_valid=pending;
        if(readback_word_valid&&readback_word_last)begin
            if(writes!=227062||reads!=227062||returns!=227062)
                $fatal(1,"Native full boot sequence incomplete");
            phy_rsp_valid=1;
            corner_seen=1;
            $display("CORNER full_boot writes=%0d reads=%0d returns=%0d cycles=%0d",writes,reads,returns,cycles);
        end
    end
    initial begin
        repeat(3)@(negedge clk);
        reset_n=1;
        wait(corner_seen);
        @(negedge clk);
        $display("AFTER_EXTRA_RETURN state=%0d fail=%0b lock=%0b phy_valid=%0b",dut.state_q,fail_closed,model_locked,phy_req_valid);
        if(dut.state_q!=4||!fail_closed||model_locked||phy_req_valid)
            $fatal(1,"Unexpected corner response");
        phy_rsp_valid=0;
        readback_digest_done=1;
        @(negedge clk);
        $display("AFTER_DIGEST state=%0d fail=%0b lock=%0b phy_valid=%0b",dut.state_q,fail_closed,model_locked,phy_req_valid);
        if(dut.state_q!=5||!fail_closed||!model_locked||phy_req_valid||runtime_req_ready)
            $fatal(1,"Unexpected post-digest response");
        runtime_req_valid=1;runtime_req_write=1;runtime_req_word_address=0;
        repeat(3)@(negedge clk);
        if(phy_req_valid||runtime_req_ready||!fail_closed)
            $fatal(1,"Fail-closed output gate did not suppress traffic");
        $display("PASS: state/lock corner reproduced; sticky fault still gates all physical and runtime traffic");
        $finish;
    end
    initial begin
        #20000000;
        $fatal(1,"Full native boot replay timed out");
    end
endmodule
