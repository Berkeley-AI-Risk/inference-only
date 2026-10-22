// Fixed-model baseline: authenticated weights, PRIVATE UNPROTECTED K/V.
// Legacy module/parameter names preserve the integration hierarchy only.
// KV_AUTH_SLOTS is unused; there is no K/V authenticator or runtime bypass.
// Only cmd/response is the application boundary.
// All raw_model/kv_update/kv_read ports are PRIVATE physical-memory contracts;
// never expose them as host addresses, DMA destinations or arithmetic services.
// They still require a restricted physical HBM/AWS integration.
module qwen_verified_machine #(
    parameter integer MODEL_PREFETCH_PAGES=8,
    parameter integer KV_CACHE_GROUPS=128,
    parameter integer KV_AUTH_SLOTS=128,
    parameter integer KV_PREFETCH_GROUPS=128,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex",
    parameter ROOT_FILE="model-page-roots-bank"
) (
    input wire clk,input wire rst_n,input wire model_ready,
    input wire cmd_valid,input wire cmd_clear_valid,output wire cmd_ready,input wire [7:0] cmd_opcode,input wire [31:0] cmd_token,
    output wire response_valid,input wire response_ready,
    output wire [3:0] response_status,output wire [31:0] response_token,output wire busy,
    output wire raw_model_request_valid,input wire raw_model_request_ready,output wire [17:0] raw_model_page,
    input wire raw_model_data_valid,output wire raw_model_data_ready,input wire [2047:0] raw_model_data,
    input wire raw_model_last,input wire raw_model_error,output wire raw_model_abort,input wire raw_model_quiescent,

    output wire kv_update_request_valid,input wire kv_update_request_ready,output wire kv_update_request_write,
    output wire [33:0] kv_update_address,output wire [16:0] kv_update_bytes,
    input wire kv_update_read_valid,output wire kv_update_read_ready,input wire [2047:0] kv_update_read_data,
    input wire kv_update_read_last,input wire kv_update_read_error,
    output wire kv_update_write_valid,input wire kv_update_write_ready,output wire [2047:0] kv_update_write_data,
    output wire kv_update_write_last,input wire kv_update_done_valid,output wire kv_update_done_ready,input wire kv_update_done_error,
    input wire kv_update_error,output wire kv_update_abort,input wire kv_update_quiescent,

    output wire kv_read_request_valid,input wire kv_read_request_ready,output wire [33:0] kv_read_address,output wire [12:0] kv_read_bytes,
    input wire kv_read_data_valid,output wire kv_read_data_ready,input wire [2047:0] kv_read_data,
    input wire kv_read_last,input wire kv_read_data_error,input wire kv_read_error,
    output wire kv_read_abort,input wire kv_read_quiescent
);
    // Read-only simulator probes below create no synthesized application ports.
    wire kv_write_start_valid /* verilator public_flat_rd */;
    wire kv_write_start_ready /* verilator public_flat_rd */;
    wire [5:0] kv_write_layer /* verilator public_flat_rd */;
    wire [14:0] kv_write_position /* verilator public_flat_rd */;
    wire kv_write_valid /* verilator public_flat_rd */;
    wire kv_write_ready /* verilator public_flat_rd */;
    wire kv_write_value /* verilator public_flat_rd */;
    wire [9:0] kv_write_index /* verilator public_flat_rd */;
    wire [15:0] kv_write_data /* verilator public_flat_rd */;
    wire kv_write_done_valid /* verilator public_flat_rd */;
    wire kv_write_done_ready /* verilator public_flat_rd */;
    wire kv_write_done_error,kv_error,kv_quiescent;
    wire kv_abort /* verilator public_flat_rd */;
    wire key_valid /* verilator public_flat_rd */;
    wire key_ready /* verilator public_flat_rd */;
    wire [14:0] key_position /* verilator public_flat_rd */;
    wire [2047:0] keys /* verilator public_flat_rd */;
    wire value_valid /* verilator public_flat_rd */;
    wire value_ready /* verilator public_flat_rd */;
    wire [14:0] value_position /* verilator public_flat_rd */;
    wire value_group /* verilator public_flat_rd */;
    wire [1023:0] values /* verilator public_flat_rd */;
    wire [5:0] attention_memory_layer /* verilator public_flat_rd */;
    wire [2:0] attention_memory_head /* verilator public_flat_rd */;
    wire attention_memory_error,attention_memory_abort,attention_memory_quiescent;
    qwen_model_verified_machine #(.ATTENTION_CORES(1),.PREFETCH_PAGES(MODEL_PREFETCH_PAGES),
        .SILU_ROM_FILE(SILU_ROM_FILE),.EXP_ROM_FILE(EXP_ROM_FILE),.ROOT_FILE(ROOT_FILE)) model_machine(.cmd_clear_valid(cmd_clear_valid),.*);
    qwen_kv_plain_store #(.CACHE_GROUPS(KV_CACHE_GROUPS),
        .PREFETCH_GROUPS(KV_PREFETCH_GROUPS)) kv_memory(
        .clk(clk),.rst_n(rst_n),.session_clear(kv_abort),
        .write_start_valid(kv_write_start_valid),.write_start_ready(kv_write_start_ready),
        .write_layer(kv_write_layer),.write_position(kv_write_position),.write_valid(kv_write_valid),.write_ready(kv_write_ready),
        .write_value(kv_write_value),.write_index(kv_write_index),.write_data(kv_write_data),
        .write_done_valid(kv_write_done_valid),.write_done_ready(kv_write_done_ready),.write_done_error(kv_write_done_error),
        .error(kv_error),.quiescent(kv_quiescent),.attention_abort(attention_memory_abort),
        .memory_layer(attention_memory_layer),.memory_head(attention_memory_head),
        .key_ready(key_ready),.key_position(key_position),.key_valid(key_valid),.keys(keys),
        .value_ready(value_ready),.value_position(value_position),.value_group(value_group),.value_valid(value_valid),.values(values),
        .attention_error(attention_memory_error),.attention_quiescent(attention_memory_quiescent),
        .update_request_valid(kv_update_request_valid),.update_request_ready(kv_update_request_ready),.update_request_write(kv_update_request_write),
        .update_address(kv_update_address),.update_bytes(kv_update_bytes),.update_read_valid(kv_update_read_valid),.update_read_ready(kv_update_read_ready),
        .update_read_data(kv_update_read_data),.update_read_last(kv_update_read_last),.update_read_error(kv_update_read_error),
        .update_write_valid(kv_update_write_valid),.update_write_ready(kv_update_write_ready),.update_write_data(kv_update_write_data),
        .update_write_last(kv_update_write_last),.update_done_valid(kv_update_done_valid),.update_done_ready(kv_update_done_ready),.update_done_error(kv_update_done_error),
        .update_error(kv_update_error),.update_abort(kv_update_abort),.update_quiescent(kv_update_quiescent),
        .read_request_valid(kv_read_request_valid),.read_request_ready(kv_read_request_ready),.read_address(kv_read_address),.read_bytes(kv_read_bytes),
        .read_data_valid(kv_read_data_valid),.read_data_ready(kv_read_data_ready),.read_data(kv_read_data),
        .read_last(kv_read_last),.read_data_error(kv_read_data_error),.read_error(kv_read_error),.read_abort(kv_read_abort),.read_quiescent(kv_read_quiescent));
endmodule
