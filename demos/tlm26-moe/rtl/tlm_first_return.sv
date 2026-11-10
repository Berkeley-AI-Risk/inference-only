// Give CLEAR a reproducible outstanding response on the physical UART.
// After a token command, hold its first actual DDR response in this one-entry
// buffer for approximately 20 ms at 12.5 MHz. Other responses pass directly.
// CLEAR does not reset the buffer. The page engine drains it; the UART
// acknowledges CLEAR only after the old response has been consumed.
module tlm_first_return #(parameter integer HOLD_CYCLES=250000)(
 input wire clk,rst_n,cmd_start, input wire raw_valid,input wire [255:0] raw_data,
 output wire valid_o,output wire [255:0] data_o);
 reg arm,held;reg [$clog2(HOLD_CYCLES+1)-1:0] delay_count;
 reg [255:0] held_data;
 assign valid_o = held ? delay_count==0 : raw_valid && !arm;
 assign data_o = held ? held_data : raw_data;
 always @(posedge clk) begin
   if(!rst_n) begin arm<=0;held<=0;delay_count<=0;end
   else begin
     if(cmd_start) arm<=1;
     if(raw_valid && arm) begin arm<=0;held<=1;held_data<=raw_data;delay_count<=HOLD_CYCLES;end
     if(held) begin
       if(delay_count!=0) delay_count<=delay_count-1'b1;
       else held<=0;
     end
   end
 end
endmodule
