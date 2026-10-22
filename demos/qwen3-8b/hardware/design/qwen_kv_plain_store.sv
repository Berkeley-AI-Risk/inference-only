// PRIVATE baseline K/V store. The application never sees these memory ports.
// A separately compiled comparison to qwen_kv_protected_store: no runtime
// integrity bypass and no authenticity claim for external K/V contents.
module qwen_kv_plain_store #(
    parameter integer CACHE_GROUPS=128,
    parameter integer PREFETCH_GROUPS=128
) (
    input wire clk,input wire rst_n,input wire session_clear,
    input wire write_start_valid,output wire write_start_ready,
    input wire [5:0] write_layer,input wire [14:0] write_position,
    input wire write_valid,output wire write_ready,
    input wire write_value,input wire [9:0] write_index,input wire [15:0] write_data,
    output wire write_done_valid,input wire write_done_ready,output wire write_done_error,
    output wire error,output wire quiescent,
    input wire attention_abort,input wire [5:0] memory_layer,input wire [2:0] memory_head,
    input wire key_ready,input wire [14:0] key_position,output wire key_valid,output wire [2047:0] keys,
    input wire value_ready,input wire [14:0] value_position,input wire value_group,
    output wire value_valid,output wire [1023:0] values,
    output wire attention_error,output wire attention_quiescent,

    output wire update_request_valid,input wire update_request_ready,output wire update_request_write,
    output wire [33:0] update_address,output wire [16:0] update_bytes,
    input wire update_read_valid,output wire update_read_ready,input wire [2047:0] update_read_data,
    input wire update_read_last,input wire update_read_error,
    output wire update_write_valid,input wire update_write_ready,output wire [2047:0] update_write_data,
    output wire update_write_last,input wire update_done_valid,output wire update_done_ready,input wire update_done_error,
    input wire update_error,output wire update_abort,input wire update_quiescent,

    output wire read_request_valid,input wire read_request_ready,output wire [33:0] read_address,output wire [12:0] read_bytes,
    input wire read_data_valid,output wire read_data_ready,input wire [2047:0] read_data,
    input wire read_last,input wire read_data_error,input wire read_error,
    output wire read_abort,input wire read_quiescent
);
    wire writer_error,reader_error,owner_abort,reader_quiescent;
    wire [5:0] lookup_layer;
    wire metadata_valid;
    wire [15:0] committed_positions;
    assign error=writer_error || reader_error;
    assign attention_error=error;
    assign attention_quiescent=reader_quiescent;
    assign update_read_ready=1'b0; // The baseline writer never requests reads.
    qwen_kv_plain_writer #(.ZERO_METADATA_WHEN_INVALID(0)) writer(
        .clk(clk),.rst_n(rst_n),.clear(session_clear),
        .write_start_valid(write_start_valid),.write_start_ready(write_start_ready),
        .write_layer(write_layer),.write_position(write_position),.write_valid(write_valid),.write_ready(write_ready),
        .write_value(write_value),.write_index(write_index),.write_data(write_data),
        .write_done_valid(write_done_valid),.write_done_ready(write_done_ready),.write_done_error(write_done_error),
        .error(writer_error),.quiescent(quiescent),.reader_fault(reader_error),
        .reader_quiescent(reader_quiescent),.reader_abort(owner_abort),
        .lookup_layer(lookup_layer),.metadata_valid(metadata_valid),.committed_positions(committed_positions),
        .raw_request_valid(update_request_valid),.raw_request_ready(update_request_ready),
        .raw_request_write(update_request_write),.raw_address(update_address),.raw_bytes(update_bytes),
        .raw_read_valid(update_read_valid),
        .raw_write_valid(update_write_valid),.raw_write_ready(update_write_ready),
        .raw_write_data(update_write_data),.raw_write_last(update_write_last),
        .raw_done_valid(update_done_valid),.raw_done_ready(update_done_ready),.raw_done_error(update_done_error),
        .raw_error(update_error),.raw_abort(update_abort),.raw_quiescent(update_quiescent));
    qwen_kv_plain_reader #(.CACHE_GROUPS(CACHE_GROUPS),.PREFETCH_GROUPS(PREFETCH_GROUPS),.ZERO_WHEN_INVALID(0),.FACTOR_VALID_GUARD(1),.ZERO_METADATA_WHEN_INVALID(0)) reader(
        .clk(clk),.rst_n(rst_n),
        .read_abort(attention_abort || session_clear || write_start_valid),.owner_abort(owner_abort),
        .memory_layer(memory_layer),.memory_head(memory_head),
        .key_ready(key_ready),.key_position(key_position),.key_valid(key_valid),.keys(keys),
        .value_ready(value_ready),.value_position(value_position),.value_group(value_group),
        .value_valid(value_valid),.values(values),.error(reader_error),.quiescent(reader_quiescent),
        .lookup_layer(lookup_layer),.metadata_valid(metadata_valid),.committed_positions(committed_positions),
        .raw_request_valid(read_request_valid),.raw_request_ready(read_request_ready),
        .raw_address(read_address),.raw_bytes(read_bytes),
        .raw_data_valid(read_data_valid),.raw_data_ready(read_data_ready),.raw_data(read_data),
        .raw_last(read_last),.raw_data_error(read_data_error),.raw_error(read_error),
        .raw_abort(read_abort),.raw_quiescent(read_quiescent));
endmodule

