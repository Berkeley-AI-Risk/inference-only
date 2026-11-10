// Exclusive configuration phase: accept a fixed 3 MiB stream in ascending order.
// Each 4096-byte chunk earns one ACK after 128 DDR writes have been admitted.
// No host-selected address, length, readback, or run-time write operation exists.
module volatile_model_loader #(parameter CLKS_PER_BIT=109)(
 input wire clk,rst_n,calibrated,uart_rx,output wire uart_tx,
 output reg loaded, output reg fault,
 output wire wr_req,input wire wr_ready,output reg [16:0] wordno,output reg [255:0] worddata
);
 wire rv;wire [7:0] rx;wire tr;
 reg [4:0] lane;reg full,ack,ack_busy,finishing,started,armed;reg [23:0] prefix;
 wire take=wr_req && wr_ready;
 wire tx_valid=ack && !fault;
 fixed_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) ur(.clk(clk),.rst_n(rst_n),.serial_i(uart_rx),.byte_valid_o(rv),.byte_o(rx));
 fixed_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) ut(.clk(clk),.rst_n(rst_n),.serial_o(uart_tx),.byte_valid_i(tx_valid),.byte_ready_o(tr),.byte_i(started?8'h79:8'h42));
 assign wr_req=full && calibrated && !loaded && !fault;
 always @(posedge clk) begin
   if(!rst_n) begin loaded<=0;fault<=0;wordno<=0;lane<=0;full<=0;ack<=0;ack_busy<=0;finishing<=0;started<=0;armed<=0;prefix<=0;end
   else if(!loaded && !fault) begin
     if(!armed && calibrated && rv) begin
       prefix<={prefix[15:0],rx};
       if({prefix,rx}==32'h544c4d31) armed<=1;  // ASCII TLM1 requests boot.
     end
     if(!started && armed && calibrated && !ack && !ack_busy) ack<=1;
     if(ack && tr) begin ack<=0;ack_busy<=1;end
     if(ack_busy && tr) begin
       ack_busy<=0;started<=1;
       if(finishing) loaded<=1;
     end
     if(rv && started) begin
       if(full || finishing || ack) fault<=1;
       else begin
         worddata[8*lane+:8]<=rx;lane<=lane+1'b1;
         if(lane==31) full<=1;
       end
     end
     if(take) begin
       full<=0;wordno<=wordno+1'b1;
       if(wordno[6:0]==127) ack<=1;
       if(wordno==98303) finishing<=1;
     end
   end
 end
endmodule
