// PRIVATE protected K/V store for the current released Qwen3-1.7B numerical core.
// Port-compatible with qwen_kv_plain_store apart from the added AUTH_SLOTS
// parameter. All memory channels are private HBM integration contracts, NOT
// application-accessible memory or arithmetic ports. The owner, writer and reader
// are connected only here, so no root, count or epoch leaves this module.
//
// Every write attempt first aborts and drains the reader, then keeps it stopped
// for the whole update (write_start_valid || update_active, the same window as
// the released plain writer). This does not rely on the attention controller's
// sequencing. The hold uses read_abort rather than owner_abort: read_abort still
// drains an owner response in flight, while owner_abort means the owner already
// discarded it. An attention-only abort never clears the trusted K/V session.
// session_clear is the core's global K/V cancellation/CLEAR signal, not the idle
// attention-reader signal.
//
// There is no runtime protection-disable input.
module qwen_kvp_store #(
    parameter integer CACHE_GROUPS=128,
    parameter integer AUTH_SLOTS=128,
    parameter integer PREFETCH_GROUPS=128,
    // Production values. The defaults on the sub-modules keep their older
    // masked payloads available for separately compiled component comparison.
    parameter integer ZERO_WHEN_INVALID=0,
    parameter integer FACTOR_VALID_GUARD=1,
    parameter integer ZERO_METADATA_WHEN_INVALID=0
) (
    input wire clk,input wire rst_n,input wire session_clear,
    input wire write_start_valid,output wire write_start_ready,
    input wire [4:0] write_layer,input wire [14:0] write_position,
    input wire write_valid,output wire write_ready,
    input wire write_value,input wire [9:0] write_index,input wire [15:0] write_data,
    output wire write_done_valid,input wire write_done_ready,output wire write_done_error,
    output wire error,output wire quiescent,
    input wire attention_abort,input wire [4:0] memory_layer,input wire [2:0] memory_head,
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
    wire writer_error,reader_error,owner_abort,reader_quiescent,update_active,writer_reader_abort;
    wire lookup_valid,lookup_ready,result_valid,result_ready;
    wire [4:0] lookup_layer,result_layer,result_count;
    wire [15:0] lookup_position,result_position,result_total_positions;
    wire [63:0] result_epoch;
    wire [255:0] result_root;
    wire owner_external_fault,owner_transport_quiescent,owner_transport_abort,owner_quiescent,owner_error;
    wire owner_begin_valid,owner_begin_ready,owner_metadata_valid,owner_metadata_ready;
    wire [4:0] owner_begin_layer,owner_metadata_layer,owner_metadata_count,owner_commit_layer;
    wire [15:0] owner_begin_position,owner_metadata_position,owner_commit_position;
    wire [63:0] owner_metadata_epoch,owner_commit_epoch;
    wire [255:0] owner_metadata_root,owner_commit_root;
    wire owner_commit_valid,owner_commit_ready,owner_published_valid,owner_published_ready;
    assign error=writer_error || reader_error;
    assign attention_error=error;
    assign attention_quiescent=reader_quiescent;
    assign owner_abort=writer_reader_abort;

    kvi_root_owner #(.LAYERS(28),.LAYER_BITS(5),.POSITION_BITS(15),.PAGE_POSITION_BITS(4),.ROOT_BITS(256),
        .ZERO_METADATA_WHEN_INVALID(ZERO_METADATA_WHEN_INVALID)) owner(
        .clk(clk),.rst_n(rst_n),.session_clear(session_clear),
        .external_fault(owner_external_fault),.transport_quiescent(owner_transport_quiescent),
        .transport_abort(owner_transport_abort),.quiescent(owner_quiescent),.error(owner_error),
        .begin_valid(owner_begin_valid),.begin_ready(owner_begin_ready),
        .begin_layer(owner_begin_layer),.begin_position(owner_begin_position),
        .metadata_valid(owner_metadata_valid),.metadata_ready(owner_metadata_ready),
        .metadata_epoch(owner_metadata_epoch),.metadata_layer(owner_metadata_layer),
        .metadata_position(owner_metadata_position),.metadata_old_count(owner_metadata_count),
        .metadata_old_root(owner_metadata_root),
        .commit_valid(owner_commit_valid),.commit_ready(owner_commit_ready),
        .commit_epoch(owner_commit_epoch),.commit_layer(owner_commit_layer),
        .commit_position(owner_commit_position),.commit_root(owner_commit_root),
        .published_valid(owner_published_valid),.published_ready(owner_published_ready),
        .lookup_valid(lookup_valid),.lookup_ready(lookup_ready),.lookup_layer(lookup_layer),.lookup_position(lookup_position),
        .result_valid(result_valid),.result_ready(result_ready),.result_epoch(result_epoch),.result_layer(result_layer),
        .result_position(result_position),.result_count(result_count),.result_total_positions(result_total_positions),.result_root(result_root));

    qwen_kvp_writer #(.ZERO_WHEN_INVALID(ZERO_WHEN_INVALID)) writer(
        .clk(clk),.rst_n(rst_n),.clear(session_clear),
        .write_start_valid(write_start_valid),.write_start_ready(write_start_ready),
        .write_layer(write_layer),.write_position(write_position),.write_valid(write_valid),.write_ready(write_ready),
        .write_value(write_value),.write_index(write_index),.write_data(write_data),
        .write_done_valid(write_done_valid),.write_done_ready(write_done_ready),.write_done_error(write_done_error),
        .error(writer_error),.quiescent(quiescent),.update_active(update_active),
        .reader_fault(reader_error),.reader_quiescent(reader_quiescent),.reader_abort(writer_reader_abort),
        .owner_external_fault(owner_external_fault),.owner_transport_quiescent(owner_transport_quiescent),
        .owner_abort(owner_transport_abort),.owner_quiescent(owner_quiescent),.owner_error(owner_error),
        .owner_begin_valid(owner_begin_valid),.owner_begin_ready(owner_begin_ready),
        .owner_begin_layer(owner_begin_layer),.owner_begin_position(owner_begin_position),
        .owner_metadata_valid(owner_metadata_valid),.owner_metadata_ready(owner_metadata_ready),
        .owner_epoch(owner_metadata_epoch),.owner_layer(owner_metadata_layer),
        .owner_position(owner_metadata_position),.owner_count(owner_metadata_count),.owner_root(owner_metadata_root),
        .owner_commit_valid(owner_commit_valid),.owner_commit_ready(owner_commit_ready),
        .owner_commit_epoch(owner_commit_epoch),.owner_commit_layer(owner_commit_layer),
        .owner_commit_position(owner_commit_position),.owner_commit_root(owner_commit_root),
        .owner_published_valid(owner_published_valid),.owner_published_ready(owner_published_ready),
        .raw_request_valid(update_request_valid),.raw_request_ready(update_request_ready),.raw_request_write(update_request_write),
        .raw_address(update_address),.raw_bytes(update_bytes),.raw_read_valid(update_read_valid),.raw_read_ready(update_read_ready),
        .raw_read_data(update_read_data),.raw_read_last(update_read_last),.raw_read_error(update_read_error),
        .raw_write_valid(update_write_valid),.raw_write_ready(update_write_ready),.raw_write_data(update_write_data),.raw_write_last(update_write_last),
        .raw_done_valid(update_done_valid),.raw_done_ready(update_done_ready),.raw_done_error(update_done_error),
        .raw_error(update_error),.raw_abort(update_abort),.raw_quiescent(update_quiescent));

    qwen_kvp_reader #(.CACHE_GROUPS(CACHE_GROUPS),.AUTH_SLOTS(AUTH_SLOTS),.PREFETCH_GROUPS(PREFETCH_GROUPS),
        .ZERO_WHEN_INVALID(ZERO_WHEN_INVALID),.FACTOR_VALID_GUARD(FACTOR_VALID_GUARD),
        .ZERO_METADATA_WHEN_INVALID(ZERO_METADATA_WHEN_INVALID)) reader(
        .clk(clk),.rst_n(rst_n),
        .read_abort(attention_abort || session_clear || write_start_valid || update_active),.owner_abort(owner_abort),
        .memory_layer(memory_layer),.memory_head(memory_head),.key_ready(key_ready),.key_position(key_position),.key_valid(key_valid),.keys(keys),
        .value_ready(value_ready),.value_position(value_position),.value_group(value_group),.value_valid(value_valid),.values(values),
        .error(reader_error),.quiescent(reader_quiescent),
        .lookup_valid(lookup_valid),.lookup_ready(lookup_ready),.lookup_layer(lookup_layer),.lookup_position(lookup_position),
        .result_valid(result_valid),.result_ready(result_ready),.result_epoch(result_epoch),.result_layer(result_layer),
        .result_position(result_position),.result_count(result_count),.result_total_positions(result_total_positions),.result_root(result_root),
        .raw_request_valid(read_request_valid),.raw_request_ready(read_request_ready),.raw_address(read_address),.raw_bytes(read_bytes),
        .raw_data_valid(read_data_valid),.raw_data_ready(read_data_ready),.raw_data(read_data),
        .raw_last(read_last),.raw_data_error(read_data_error),.raw_error(read_error),.raw_abort(read_abort),.raw_quiescent(read_quiescent));
endmodule
