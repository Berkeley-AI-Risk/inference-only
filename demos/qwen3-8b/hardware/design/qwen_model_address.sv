// Generated private fixed address decoder. No runtime model or shape input.
// One response register; reset/CLEAR cancels it, and stalls preserve it.
module qwen_model_address(
 input wire clk,input wire rst_n,input wire clear,
 input wire request_valid,output wire request_ready,
 input wire [2:0] request_region,input wire [2:0] request_operation,
 input wire [5:0] request_layer,input wire [17:0] request_index,
 output wire result_valid,input wire result_ready,
 output wire [33:0] result_address,output wire [18:0] result_bytes,
 output wire result_error
);
 reg pending;
 reg [33:0] address_reg,decoded_address,codes_base,scales_base,tile_stride;
 reg [18:0] bytes_reg,decoded_bytes;
 reg [17:0] tile_count;
 reg error_reg,decoded_error;
 wire enabled=rst_n && !clear;
 assign request_ready=enabled && (!pending || result_ready);
 assign result_valid=enabled && pending;
 assign result_address=result_valid ? address_reg : 34'd0;
 assign result_bytes=result_valid ? bytes_reg : 19'd0;
 assign result_error=result_valid && error_reg;
 wire [33:0] layer_wide={28'b0,request_layer};
 wire [33:0] index_wide={16'b0,request_index};
 wire [33:0] layer_codes=(layer_wide << 23) + (layer_wide << 24) + (layer_wide << 25) + (layer_wide << 27);
 wire [33:0] layer_scales=(layer_wide << 13) + (layer_wide << 14) + (layer_wide << 17);
 wire [33:0] layer_norms=(layer_wide << 9) + (layer_wide << 14);
 reg [33:0] tile_offset;
 always @* begin
  codes_base=0;scales_base=0;tile_count=0;tile_stride=0;tile_offset=0;
  case(request_operation)
  3'd0:begin codes_base=layer_codes + 34'd0; scales_base=layer_scales + 34'd7568097280; tile_count=18'd128; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd1:begin codes_base=layer_codes + 34'd16777216; scales_base=layer_scales + 34'd7568113664; tile_count=18'd32; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd2:begin codes_base=layer_codes + 34'd20971520; scales_base=layer_scales + 34'd7568117760; tile_count=18'd32; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd3:begin codes_base=layer_codes + 34'd25165824; scales_base=layer_scales + 34'd7568121856; tile_count=18'd128; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd4:begin codes_base=layer_codes + 34'd41943040; scales_base=layer_scales + 34'd7568138240; tile_count=18'd384; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd5:begin codes_base=layer_codes + 34'd92274688; scales_base=layer_scales + 34'd7568187392; tile_count=18'd384; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  3'd6:begin codes_base=layer_codes + 34'd142606336; scales_base=layer_scales + 34'd7568236544; tile_count=18'd128; tile_stride=34'd393216; tile_offset=(index_wide << 17) + (index_wide << 18); end
  3'd7:begin codes_base=34'd6945767424; scales_base=34'd7573700608; tile_count=18'd4748; tile_stride=34'd131072; tile_offset=(index_wide << 17); end
  default:begin end
  endcase
  decoded_address=0;decoded_bytes=0;decoded_error=1;
  case(request_region)
   3'd0,3'd1:if((request_operation==7 || {1'b0,request_layer}<7'd36) && request_index<tile_count)begin
    decoded_error=0;
    if(request_region==1)begin decoded_address=scales_base+(index_wide<<7);decoded_bytes=19'd128;end
    else begin decoded_address=codes_base+tile_offset;decoded_bytes=tile_stride[18:0];end
   end
   3'd2:if(request_index==0 && (request_operation==4 || (request_operation<4 && {1'b0,request_layer}<7'd36)))begin
    case(request_operation)
     3'd0:begin decoded_address=layer_norms + 34'd7574323200;decoded_bytes=19'd8192;decoded_error=0;end
     3'd1:begin decoded_address=layer_norms + 34'd7574331392;decoded_bytes=19'd256;decoded_error=0;end
     3'd2:begin decoded_address=layer_norms + 34'd7574331648;decoded_bytes=19'd256;decoded_error=0;end
     3'd3:begin decoded_address=layer_norms + 34'd7574331904;decoded_bytes=19'd8192;decoded_error=0;end
     3'd4:begin decoded_address=34'd7574931456;decoded_bytes=19'd8192;decoded_error=0;end
     default:begin end
    endcase
   end
   3'd3:if(request_operation==0 && {1'b0,request_index}<19'd151936)begin
    decoded_address=34'd7574978560+(index_wide << 13);
    decoded_bytes=19'd8192;decoded_error=0;
   end
   3'd4:if(request_operation==0 && request_index<18'd32768)begin
    decoded_address=34'd8819638272+(index_wide << 8);
    decoded_bytes=19'd256;decoded_error=0;
   end
   default:begin end
  endcase
 end
 always @(posedge clk)begin
  if(!rst_n || clear)begin pending<=0;address_reg<=0;bytes_reg<=0;error_reg<=0;end
  else if(request_ready)begin
   pending<=request_valid;
   if(request_valid)begin address_reg<=decoded_address;bytes_reg<=decoded_bytes;error_reg<=decoded_error;end
  end
 end
endmodule
