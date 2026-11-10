module tlm_token_uart #(parameter CLKS_PER_BIT=109)(
 input wire clk,rst_n, uart_rx, output wire uart_tx,
 output reg clear_o, cmd_valid, cmd_step, output reg [8:0] cmd_token,
 input wire ready_i,input wire outstanding_i,input wire rep_valid,input wire [1:0] rep_kind,input wire [8:0] rep_token);
 function automatic [7:0] crc8(input [7:0] a,input [7:0] b);
   integer i; reg [7:0] c; begin c=a^b; for(i=0;i<8;i=i+1)c=c[7]?((c<<1)^7):(c<<1);crc8=c;end
 endfunction
 wire [7:0] rx; wire rv,tr;
 reg [2:0] rxidx,txidx;reg [7:0] op,lo,hi,crc,kind,rcrc;reg [8:0] token;
 reg sending,waiting,clear_wait;
 wire [7:0] tx=txidx==0?8'h5a:txidx==1?kind:txidx==2?token[7:0]:txidx==3?{7'd0,token[8]}:rcrc;
 fixed_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) ur(.clk(clk),.rst_n(rst_n),.serial_i(uart_rx),.byte_valid_o(rv),.byte_o(rx));
 fixed_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) ut(.clk(clk),.rst_n(rst_n),.serial_o(uart_tx),.byte_valid_i(sending),.byte_ready_o(tr),.byte_i(tx));
 task automatic reply(input [7:0] k,input [8:0] t);
   begin sending<=1;txidx<=0;kind<=k;token<=t;rcrc<=0;end
 endtask
 wire valid_clear=rv && rxidx==4 && rx==crc && op==2 && {hi,lo}==0;
 always @(posedge clk) begin
   clear_o<=0;cmd_valid<=0;
   if(!rst_n) begin sending<=0;waiting<=0;clear_wait<=0;rxidx<=0;txidx<=0;end
   else begin
     if(sending && tr) begin
       rcrc<=crc8(rcrc,tx);
       if(txidx==4) sending<=0; else txidx<=txidx+1'b1;
     end
     if(clear_wait && !outstanding_i && !clear_o) begin clear_wait<=0;reply(8'h82,0);end
     if(rv && !sending && !clear_wait) begin
       case(rxidx)
         0: if(rx==8'ha5) begin rxidx<=1;crc<=crc8(0,rx);end
         1: begin op<=rx;crc<=crc8(crc,rx);rxidx<=2;end
         2: begin lo<=rx;crc<=crc8(crc,rx);rxidx<=3;end
         3: begin hi<=rx;crc<=crc8(crc,rx);rxidx<=4;end
         4: begin
           rxidx<=0;
           if(valid_clear) begin clear_o<=1;waiting<=0;clear_wait<=1;end
           else if(!waiting) begin
             if(rx!=crc || op>2 || hi[7:4]!=0) reply(8'hcf,0);
             else if(hi>1 || (op!=0 && {hi,lo}!=0) || !ready_i) reply(8'hc0|op,0);
             else begin cmd_step<=op[0];cmd_valid<=1;cmd_token<={hi[0],lo};waiting<=1;end
           end
         end
         default: rxidx<=0;
       endcase
     end
     if(waiting && rep_valid && !valid_clear && !clear_o) begin
       waiting<=0;rxidx<=0;
       if(rep_kind==3) reply(cmd_step?8'hc1:8'hc0,0);
       else if(rep_kind==2) reply(8'h81,rep_token);
       else reply(8'h80,0);
     end
   end
 end
endmodule
