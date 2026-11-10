// Simulation boundary at the board's ordered memory command port.
module boot_product(input wire clk,rst_n,uart_rx,output wire uart_tx,
 output wire cmd,input wire ready,output wire wr,output wire [16:0] addr,
 output wire [255:0] write_data,input wire read_valid,input wire [255:0] read_data);
 wire done,fault,br,rr;wire [16:0] baddr;wire [21:0] raddr;wire bu,ru;
 volatile_model_loader #(.CLKS_PER_BIT(8)) loader(clk,rst_n,1'b1,uart_rx,bu,done,fault,br,ready,baddr,write_data);
 tlm_product #(.CLKS_PER_BIT(8)) product(clk,done && rst_n && !fault,uart_rx,ru,rr,ready,raddr,read_valid,read_data);
 assign cmd=done?rr:br;assign wr=!done;assign addr=done?raddr[21:5]:baddr;assign uart_tx=done?ru:bu;
endmodule
