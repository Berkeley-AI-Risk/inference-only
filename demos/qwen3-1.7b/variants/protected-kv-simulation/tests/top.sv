// Test-only composition: one separately compiled store and the original
// numerical attention pair. No runtime protection-selection input exists.
module operand_test(
 input wire clk,rst_n,session_clear,pair_clear,pair_start,
 output wire pair_ready,pair_valid,pair_error,input wire pair_out_ready,
 input wire [2047:0] query0,query1,output wire [2047:0] result0,result1,
 input wire write_start_valid,output wire write_start_ready,
 input wire write_valid,write_value,input wire [9:0] write_index,input wire [15:0] write_data,
 output wire write_ready,write_done_valid,write_done_error,input wire write_done_ready,
 output wire store_error,store_quiescent,attention_quiescent,
 output wire key_valid,key_ready,value_valid,value_ready,
 output wire [14:0] key_position,value_position,output wire value_group,
 output wire [2047:0] keys,output wire [1023:0] values,
 output wire reader_fault_event,authentication_error,
 output wire root_publish,output wire [255:0] published_root,output wire [63:0] published_epoch,
 output wire update_request_valid,input wire update_request_ready,output wire update_request_write,
 output wire [33:0] update_address,output wire [16:0] update_bytes,
 input wire update_read_valid,output wire update_read_ready,input wire [2047:0] update_read_data,
 input wire update_read_last,update_read_error,
 output wire update_write_valid,input wire update_write_ready,output wire [2047:0] update_write_data,
 output wire update_write_last,input wire update_done_valid,output wire update_done_ready,input wire update_done_error,
 input wire update_error,output wire update_abort,input wire update_quiescent,
 output wire read_request_valid,input wire read_request_ready,output wire [33:0] read_address,output wire [12:0] read_bytes,
 input wire read_data_valid,output wire read_data_ready,input wire [2047:0] read_data,
 input wire read_last,read_data_error,read_error,output wire read_abort,input wire read_quiescent
);
 wire attention_error,attention_abort;
 qwen_attention_pair #(.EXP_ROM_FILE("softmax-exp2.hex")) consumer(
  .clk(clk),.rst_n(rst_n),.clear(pair_clear || session_clear),.start_valid(pair_start),.start_ready(pair_ready),
  .context_length(16'd1),.query0(query0),.query1(query1),
  .key_valid(key_valid),.key_ready(key_ready),.key_position(key_position),.key(keys),
  .value_valid(value_valid),.value_ready(value_ready),.value_position(value_position),.value_group(value_group),.values(values),
  .memory_error(attention_error),.memory_abort(attention_abort),.memory_quiescent(attention_quiescent),
  .out_valid(pair_valid),.out_ready(pair_out_ready),.result0(result0),.result1(result1),.out_error(pair_error));
`ifdef KV_PROTECTED
 qwen_kvp_store #(.CACHE_GROUPS(128),.AUTH_SLOTS(128),.PREFETCH_GROUPS(128),
  .ZERO_WHEN_INVALID(0),.FACTOR_VALID_GUARD(1),.ZERO_METADATA_WHEN_INVALID(0)) store(
`else
 qwen_kv_plain_store #(.CACHE_GROUPS(128),.PREFETCH_GROUPS(128)) store(
`endif
  .clk(clk),.rst_n(rst_n),.session_clear(session_clear),
  .write_start_valid(write_start_valid),.write_start_ready(write_start_ready),.write_layer(5'd0),.write_position(15'd0),
  .write_valid(write_valid),.write_ready(write_ready),.write_value(write_value),.write_index(write_index),.write_data(write_data),
  .write_done_valid(write_done_valid),.write_done_ready(write_done_ready),.write_done_error(write_done_error),
  .error(store_error),.quiescent(store_quiescent),.attention_abort(attention_abort),.memory_layer(5'd0),.memory_head(3'd0),
  .key_ready(key_ready),.key_position(key_position),.key_valid(key_valid),.keys(keys),
  .value_ready(value_ready),.value_position(value_position),.value_group(value_group),.value_valid(value_valid),.values(values),
  .attention_error(attention_error),.attention_quiescent(attention_quiescent),
  .update_request_valid(update_request_valid),.update_request_ready(update_request_ready),.update_request_write(update_request_write),
  .update_address(update_address),.update_bytes(update_bytes),.update_read_valid(update_read_valid),.update_read_ready(update_read_ready),
  .update_read_data(update_read_data),.update_read_last(update_read_last),.update_read_error(update_read_error),
  .update_write_valid(update_write_valid),.update_write_ready(update_write_ready),.update_write_data(update_write_data),
  .update_write_last(update_write_last),.update_done_valid(update_done_valid),.update_done_ready(update_done_ready),.update_done_error(update_done_error),
  .update_error(update_error),.update_abort(update_abort),.update_quiescent(update_quiescent),
  .read_request_valid(read_request_valid),.read_request_ready(read_request_ready),.read_address(read_address),.read_bytes(read_bytes),
  .read_data_valid(read_data_valid),.read_data_ready(read_data_ready),.read_data(read_data),.read_last(read_last),
  .read_data_error(read_data_error),.read_error(read_error),.read_abort(read_abort),.read_quiescent(read_quiescent));
 assign reader_fault_event=store.reader.fault_event;
`ifdef KV_PROTECTED
 assign authentication_error=store.reader.auth_error;
 assign root_publish=store.owner_commit_valid && store.owner_commit_ready;
 assign published_root=store.owner_commit_root;assign published_epoch=store.owner_commit_epoch;
`else
 assign authentication_error=1'b0;assign root_publish=1'b0;assign published_root=256'b0;assign published_epoch=64'b0;
`endif
endmodule
