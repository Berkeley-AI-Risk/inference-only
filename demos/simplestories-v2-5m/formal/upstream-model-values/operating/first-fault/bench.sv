
`timescale 1ns/1ps
module wrapper_tb;
    reg clk=0,resetn=0,valid=0,rawvalid=0,good=1;
    reg[255:0]rawdata=256'd4660;
    always #5 clk=~clk;
    wire ready,reply,error,locked,fault;wire[255:0]data;
    wire[2:0]cmd;wire enable;
    board1_private_booted_shared_ddr dut(
      .trusted_clk_i(clk),.app_clk_i(clk),.trusted_reset_n_i(resetn),.app_reset_n_i(resetn),
      .private_fixed_source_ready_i(1'b0),.private_boot_progress_i(1'b0),
      .private_loader_done_i(1'b0),.private_loader_valid_i(1'b0),.private_loader_data_i(256'd0),
      .private_source_fault_i(!good),.private_runtime_app_fault_i(1'b0),
      .private_req_valid_i(valid),.private_req_write_i(1'b0),.private_req_word_i(19'd0),.private_req_data_i(256'd0),
      .private_req_ready_o(ready),.private_rsp_valid_o(reply),.private_rsp_error_o(error),.private_rsp_data_o(data),
      .private_model_locked_o(locked),.private_fail_closed_o(fault),
      .controller_pll_lock_i(good),.controller_init_calib_complete_i(good),
      .app_cmd_ready_i(1'b1),.app_wr_data_ready_i(1'b1),.app_cmd_o(cmd),.app_cmd_en_o(enable),
      .app_rd_data_i(rawdata),.app_rd_data_valid_i(rawvalid),.app_rd_data_end_i(1'b1),
      .f_boot_private_loader_ready_o_i(1'b0),.f_boot_boot_cmd_i(3'd1),.f_boot_boot_cmd_en_i(1'b0),
      .f_boot_boot_addr_i(29'd0),.f_boot_boot_data_i(256'd0),.f_boot_boot_data_en_i(1'b0),
      .f_boot_boot_data_end_i(1'b0),.f_boot_boot_mask_i(32'd0),.f_boot_boot_burst_i(1'b0),
      .f_boot_boot_self_refresh_i(1'b0),.f_boot_boot_refresh_i(1'b0),.f_boot_boot_locked_i(1'b1),
      .f_boot_boot_fault_i(1'b0),.f_boot_boot_watchdog_i(1'b0));
    integer issues=0;
    always @(posedge clk)if(resetn && enable)begin
      if(cmd!=1)$fatal(1,"WRONG_RUNTIME_COMMAND");issues<=issues+1;
    end
    initial begin
      #13;resetn=1;wait(locked && ready);@(negedge clk);valid=1;
      @(posedge clk);while(!ready)@(posedge clk);
      @(negedge clk);valid=0;repeat(3)@(negedge clk);
      if(issues!=1)$fatal(1,"MISSING_READ_OWNER");
      rawvalid=1;
      if(__FAILED__)begin good=0;rawdata=256'd4661;end
      #1;
      if(!reply || data!==( __FAILED__ ? 256'd4661:256'd4660))$fatal(1,"MISSING_NATIVE_RETURN");
      if(__FAILED__ && !error)$fatal(1,"UNMARKED_BAD_RETURN");
      if(!__FAILED__ && error)$fatal(1,"HEALTHY_RETURN_REJECTED");
      $display("EDGE_PASS failed=%0d data=%0d error=%0d registered_fault=%0d",__FAILED__,data,error,fault);
      @(negedge clk);rawvalid=0;repeat(4)@(negedge clk);
      if(__FAILED__ && !fault)$fatal(1,"FAULT_NOT_STICKY");
      $finish;
    end
    initial begin #2000;$fatal(1,"EDGE_TIMEOUT");end
endmodule
