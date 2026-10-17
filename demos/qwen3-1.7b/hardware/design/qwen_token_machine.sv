// Complete numerical schedule plus APPEND/STEP/CLEAR command boundary.
// Model and K/V ports below connect to PRIVATE authenticated memory logic,
// not AWS host registers. Those memory adapters and the AWS shell wrapper are
// not implemented by this module. Never map the private ports to the host.
module qwen_token_machine #(
    parameter integer ATTENTION_CORES=1,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex"
) (
    input wire clk,input wire rst_n,input wire model_ready,
    input wire cmd_valid,input wire cmd_clear_valid,output wire cmd_ready,
    input wire [7:0] cmd_opcode,input wire [31:0] cmd_token,
    output wire response_valid,input wire response_ready,
    output wire [3:0] response_status,output wire [31:0] response_token,output wire busy,
    output wire model_request_valid,input wire model_request_ready,
    output wire [31:0] model_address,output wire [17:0] model_bytes,
    input wire model_data_valid,output wire model_data_ready,
    input wire [2047:0] model_data,input wire model_data_last,
    input wire model_error,output wire model_abort,input wire model_quiescent,
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
    wire op_valid,op_ready,core_abort,core_quiescent;
    wire core_done /* verilator public_flat_rd */;
    wire core_error /* verilator public_flat_rd */;
    wire [4:0] op_code,op_layer;
    wire [14:0] op_position;
    wire [17:0] op_token;
    wire [31:0] core_next_token;
    wire engine_done,engine_error;
    wire [31:0] engine_next_token;
    // PRIVATE_COMPLETION_RETURN_BEGIN
    // The fixed sequencer has only one outstanding operation. Delay its
    // completion by one cycle to break the long return to token RAM.
    // An accepted CLEAR masks this private result immediately; the existing
    // engine cancellation and quiescence logic are deliberately unchanged.
    reg completion_valid,completion_error;
    reg [31:0] completion_token;
    assign core_done=rst_n && !core_abort && completion_valid;
    assign core_error=completion_error || engine_error;
    assign core_next_token=completion_token;
    always @(posedge clk)begin
        if(!rst_n || core_abort)begin
            completion_valid<=0;completion_error<=0;completion_token<=0;
        end else begin
            completion_valid<=engine_done;
            if(engine_done)begin
                completion_error<=engine_error;
                completion_token<=engine_next_token;
            end
        end
    end
    // PRIVATE_COMPLETION_RETURN_END
    fixed_qwen_sequencer sequencer(.cmd_clear_valid(cmd_clear_valid),.*);
    qwen_fixed_core #(.ATTENTION_CORES(ATTENTION_CORES),.SILU_ROM_FILE(SILU_ROM_FILE),
        .EXP_ROM_FILE(EXP_ROM_FILE)) engine(.core_done(engine_done),
        .core_error(engine_error),.core_next_token(engine_next_token),.*);
endmodule
