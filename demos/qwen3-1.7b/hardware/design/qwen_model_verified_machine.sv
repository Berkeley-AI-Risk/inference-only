// The token machine with all external MODEL data routed through the fixed-root
// verifier and private caches. Only cmd/response are the application boundary.
// raw_model_* and all K/V wires are PRIVATE physical-memory integration ports;
// never map them to AWS host registers or expose a bypass around the verifier.
//
// K/V authentication and the physical HBM/AWS adapters are NOT implemented here.
// model_ready indicates provisioning availability, not permission to skip
// per-page verification. The model root table remains a compile-time constant.
module qwen_model_verified_machine #(
    parameter integer ATTENTION_CORES=1,
    parameter integer PREFETCH_PAGES=8,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter ROOT_FILE="model-page-roots.hex"
) (
    input wire clk,input wire rst_n,input wire model_ready,
    input wire cmd_valid,input wire cmd_clear_valid,output wire cmd_ready,
    input wire [7:0] cmd_opcode,input wire [31:0] cmd_token,
    output wire response_valid,input wire response_ready,
    output wire [3:0] response_status,output wire [31:0] response_token,output wire busy,
    output wire raw_model_request_valid,input wire raw_model_request_ready,
    output wire [15:0] raw_model_page,
    input wire raw_model_data_valid,output wire raw_model_data_ready,
    input wire [2047:0] raw_model_data,input wire raw_model_last,input wire raw_model_error,
    output wire raw_model_abort,input wire raw_model_quiescent,
    output wire kv_write_start_valid,input wire kv_write_start_ready,
    output wire [4:0] kv_write_layer,output wire [14:0] kv_write_position,
    output wire kv_write_valid,input wire kv_write_ready,
    output wire kv_write_value,output wire [9:0] kv_write_index,output wire [15:0] kv_write_data,
    input wire kv_write_done_valid,output wire kv_write_done_ready,input wire kv_write_done_error,
    input wire kv_error,output wire kv_abort,input wire kv_quiescent,
    input wire [ATTENTION_CORES-1:0] key_valid,output wire [ATTENTION_CORES-1:0] key_ready,
    output wire [ATTENTION_CORES*15-1:0] key_position,input wire [ATTENTION_CORES*2048-1:0] keys,
    input wire [ATTENTION_CORES-1:0] value_valid,output wire [ATTENTION_CORES-1:0] value_ready,
    output wire [ATTENTION_CORES*15-1:0] value_position,output wire [ATTENTION_CORES-1:0] value_group,
    input wire [ATTENTION_CORES*1024-1:0] values,
    output wire [4:0] attention_memory_layer,output wire [ATTENTION_CORES*3-1:0] attention_memory_head,
    input wire [ATTENTION_CORES-1:0] attention_memory_error,
    output wire [ATTENTION_CORES-1:0] attention_memory_abort,
    input wire [ATTENTION_CORES-1:0] attention_memory_quiescent
);
    wire model_request_valid /* verilator public_flat_rd */;
    wire model_request_ready /* verilator public_flat_rd */;
    wire [31:0] model_address /* verilator public_flat_rd */;
    wire [17:0] model_bytes /* verilator public_flat_rd */;
    wire model_data_valid,model_data_ready,model_data_last,model_error,model_abort,model_quiescent;
    wire [2047:0] model_data;
    qwen_token_machine #(.ATTENTION_CORES(ATTENTION_CORES),.SILU_ROM_FILE(SILU_ROM_FILE),
        .EXP_ROM_FILE(EXP_ROM_FILE)) machine(.cmd_clear_valid(cmd_clear_valid),.*);
    qwen_model_reader #(.WEIGHT_PAGES(64),.AUTH_SLOTS(32),.PREFETCH_PAGES(PREFETCH_PAGES),.ROOT_FILE(ROOT_FILE)) model_reader(
        .clk(clk),.rst_n(rst_n),.core_abort(model_abort),
        .request_valid(model_request_valid),.request_ready(model_request_ready),
        .request_address(model_address),.request_bytes(model_bytes),
        .data_valid(model_data_valid),.data_ready(model_data_ready),.data(model_data),.data_last(model_data_last),
        .error(model_error),.quiescent(model_quiescent),
        .raw_request_valid(raw_model_request_valid),.raw_request_ready(raw_model_request_ready),.raw_page(raw_model_page),
        .raw_data_valid(raw_model_data_valid),.raw_data_ready(raw_model_data_ready),.raw_data(raw_model_data),
        .raw_last(raw_model_last),.raw_error(raw_model_error),.raw_abort(raw_model_abort),.raw_quiescent(raw_model_quiescent));
endmodule
