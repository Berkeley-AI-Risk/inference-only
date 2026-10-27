`timescale 1ns/1ps
`default_nettype none
// Compile-fixed singleton banks. Public top has no model/address/loader port.
// Functional synchronous ROMs; qualified macro/clock/area mapping is pending.
module hwic_fixed_model_rom (
 input wire clk,reset_n,enabled_i,request_valid_i,
 output wire request_ready_o,
 input wire [18:0] request_word_i,
 output logic response_valid_o,
 input wire response_ready_i,
 output logic [639:0] response_data_o,
 output logic response_fault_o,fault_o
);
 (* rom_style="block" *) logic [639:0] fixed_weights640[0:84719];
 (* rom_style="block" *) logic [255:0] fixed_misc256[0:14615];
 initial $readmemh("fixed/weights640.memh",fixed_weights640);
 initial $readmemh("fixed/misc256.memh",fixed_misc256);
 logic misc_valid;logic[13:0] misc_address;
 always_comb begin
  misc_valid=1;misc_address=0;
  if(request_word_i>=211920 && request_word_i<214248)misc_address=14'(request_word_i-211920);
  else if(request_word_i>=214261 && request_word_i<214773)misc_address=14'(2328+request_word_i-214261);
  else if(request_word_i>=215286 && request_word_i<227062)misc_address=14'(2840+request_word_i-215286);
  else misc_valid=0;
 end
 assign request_ready_o=reset_n && enabled_i && !fault_o && (!response_valid_o || response_ready_i);
 always_ff @(posedge clk or negedge reset_n)begin
  if(!reset_n)begin response_valid_o<=0;response_data_o<=0;response_fault_o<=0;fault_o<=0;end
  else begin
   if(response_valid_o && response_ready_i)response_valid_o<=0;
   if(request_valid_i && request_ready_o)begin
    response_valid_o<=1;response_fault_o<=0;
    if(request_word_i<84720)response_data_o<=fixed_weights640[request_word_i];
    else if(misc_valid)response_data_o<={384'd0,fixed_misc256[misc_address]};
    else begin response_data_o<=0;response_fault_o<=1;fault_o<=1;end
   end
  end
 end
endmodule
`default_nettype wire
