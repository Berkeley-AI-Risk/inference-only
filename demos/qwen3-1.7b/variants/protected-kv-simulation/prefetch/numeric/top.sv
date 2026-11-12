// Test-only composition: one separately compiled store and the original
// numerical attention pair. No runtime protection-selection input exists.
module operand_test(
 input wire clk,rst_n,session_clear,pair_clear,pair_start,
 input wire [4:0] fixture_write_layer,input wire [14:0] fixture_write_position,
 input wire [2:0] fixture_head,input wire [15:0] fixture_context,
 output wire follow_pending,output wire [4:0] follow_layer,output wire [2:0] follow_head,output wire [10:0] follow_group,
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
 output wire verification_event,verification_root,verification_ok,
 output wire [4:0] verification_node,output wire [63:0] verification_epoch,
 output wire [4:0] verification_layer,verification_count,
 output wire [15:0] verification_group,
 output wire [4:0] published_layer,output wire [14:0] published_position,
 output wire allocation_event,allocation_old_valid,output wire [7:0] allocation_slot,
 output wire [19:0] allocation_old_tag,allocation_new_tag,
 output wire fill_event,output wire [4:0] fill_node,fill_count,
 output wire [15:0] fill_group,output wire [63:0] fill_epoch,
 output wire [3:0] observed_read_node,output wire [10:0] observed_read_group,
 output wire [4:0] observed_read_count,
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
  .context_length(fixture_context),.query0(query0),.query1(query1),
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
  .write_start_valid(write_start_valid),.write_start_ready(write_start_ready),.write_layer(fixture_write_layer),.write_position(fixture_write_position),
  .write_valid(write_valid),.write_ready(write_ready),.write_value(write_value),.write_index(write_index),.write_data(write_data),
  .write_done_valid(write_done_valid),.write_done_ready(write_done_ready),.write_done_error(write_done_error),
  .error(store_error),.quiescent(store_quiescent),.attention_abort(attention_abort),.memory_layer(5'd0),.memory_head(fixture_head),
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
`ifdef FOLLOW_READER
 assign follow_pending=store.reader.follow_valid;assign follow_layer=store.reader.follow_layer;
 assign follow_head=store.reader.follow_head;assign follow_group=store.reader.follow_group;
`else
 assign follow_pending=0;assign follow_layer=0;assign follow_head=0;assign follow_group=0;
`endif
 // Passive observations of the real comparisons and published cache validity.
 // No observer drives the DUT.
 assign verification_event=store.reader.verifier.result_take && store.reader.verifier.result_legal && store.reader.verifier.result_final;
 assign verification_root=store.reader.verifier.result_root;
 assign verification_ok=!store.reader.verifier.mismatch;
 assign verification_node=store.reader.verifier.nodes[store.reader.verifier.result_slot];
 assign verification_epoch=store.reader.verifier.epochs[store.reader.verifier.result_slot];
 assign verification_layer=store.reader.verifier.layers[store.reader.verifier.result_slot];
 assign verification_group=store.reader.verifier.groups[store.reader.verifier.result_slot];
 assign verification_count=store.reader.verifier.counts[store.reader.verifier.result_slot];
 assign published_layer=store.owner_commit_layer;assign published_position=store.owner_commit_position[14:0];
 assign allocation_event=!store.reader.stopped && !store.reader.fault_event && store.reader.fetch_state==4'd8;
 assign allocation_slot=store.reader.fetch_slot;
 assign allocation_old_valid=store.reader.cache_valid[store.reader.fetch_slot];
 assign allocation_old_tag=store.reader.cache_tag[store.reader.fetch_slot];
 assign allocation_new_tag={store.reader.fetch_layer,store.reader.fetch_node,store.reader.fetch_group};
 assign fill_event=store.reader.fill_take && store.reader.auth_last;
 assign fill_node=store.reader.auth_node;assign fill_group=store.reader.auth_group;
 assign fill_count=store.reader.auth_count;assign fill_epoch=store.reader.auth_epoch;
 assign observed_read_node=store.reader.fetch_node;assign observed_read_group=store.reader.fetch_group;
 assign observed_read_count=store.reader.fetch_count;
`else
 assign authentication_error=1'b0;assign root_publish=1'b0;assign published_root=256'b0;assign published_epoch=64'b0;
`endif
endmodule
