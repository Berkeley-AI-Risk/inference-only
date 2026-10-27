`timescale 1ns/1ps
`default_nettype none
// Exact signed64 contract of the baseline iterative lane, registered once.
// A variable barrel shifter and rounding adder require new mapped timing.
module board1_fixed_vector_rne_shift_pipeline1 (
 input wire clk,rst_n,clear_i,request_valid_i,
 output wire request_ready_o,
 input wire signed [63:0] request_value_i,
 input wire signed [8:0] request_shift_i,
 output logic response_valid_o,
 input wire response_ready_i,
 output logic signed [63:0] response_result_o,
 output logic response_fault_o
);
 logic signed [63:0] result;
 logic fault;
 logic [63:0] magnitude,quotient,remainder,mask,halfway,rounded;
 logic signed [127:0] wide;
 integer amount;
 assign request_ready_o=rst_n && !clear_i && !response_valid_o;
 always_comb begin
  result=0;fault=0;amount=0;magnitude=0;quotient=0;
  remainder=0;mask=0;halfway=0;rounded=0;wide=0;
  if(request_shift_i==0)result=request_value_i;
  else if(request_shift_i < -9'sd62)fault=1;
  else if(request_shift_i > 9'sd62)result=0;
  else if(request_shift_i<0)begin
   amount=-int'(request_shift_i);
   wide=$signed({{64{request_value_i[63]}},request_value_i}) <<< amount;
   if(wide[127:64]!={64{wide[63]}})fault=1;
   else result=wide[63:0];
  end else begin
   amount=int'(request_shift_i);
   magnitude=request_value_i[63] ? $unsigned(-request_value_i) : $unsigned(request_value_i);
   quotient=magnitude >> amount;
   mask=(64'd1 << amount)-1'b1;
   remainder=magnitude & mask;
   halfway=64'd1 << (amount-1);
   rounded=quotient+64'((remainder>halfway) || ((remainder==halfway) && quotient[0]));
   result=request_value_i[63] ? -$signed(rounded) : $signed(rounded);
  end
 end
 always_ff @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin response_valid_o<=0;response_result_o<=0;response_fault_o<=0;end
  else if(clear_i)begin response_valid_o<=0;response_result_o<=0;response_fault_o<=0;end
  else begin
   if(response_valid_o && response_ready_i)begin
    response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
   end
   if(request_valid_i && request_ready_o)begin
    response_valid_o<=1;response_result_o<=result;response_fault_o<=fault;
   end
  end
 end
endmodule
`default_nettype wire
