// Runtime-only product. Board boot owns writes. All normal commands enter over UART.
module tlm_product #(parameter CLKS_PER_BIT=109, parameter HOLD_CYCLES=250000)(
 input wire clk,rst_n,uart_rx,output wire uart_tx,
 output wire rd_req,input wire rd_ready,output wire [21:0] rd_byte_addr,
 input wire rd_valid,input wire [255:0] rd_data);
 wire clr,cv,cs,cr,rv,wreq,wvalid,wfail,owed;
 wire [1:0] kind;wire [8:0] ct,rt;wire [20:0] wa;wire signed [15:0] wd;
 tlm_token_uart #(.CLKS_PER_BIT(CLKS_PER_BIT)) uart(clk,rst_n,uart_rx,uart_tx,clr,cv,cs,ct,cr,owed,rv,kind,rt);
 tlm_decoder decoder(clk,rst_n,clr,cv,cs,ct,cr,rv,kind,rt,wreq,wa,wvalid,wfail,wd);
 wire delayed_valid; wire [255:0] delayed_data;
 tlm_first_return #(.HOLD_CYCLES(HOLD_CYCLES)) hold_first(clk,rst_n,cv && cr,rd_valid,rd_data,delayed_valid,delayed_data);
 authenticated_weight_page cache(clk,rst_n,clr,wreq,wa,wvalid,wfail,wd,rd_req,rd_ready,rd_byte_addr,delayed_valid,delayed_data,owed);
endmodule
