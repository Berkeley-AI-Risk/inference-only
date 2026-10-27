`timescale 1ns/1ps
`default_nettype none
// Sealed SimpleStories W10/A16/KV16-v5-context2048 token machine.
// No weight, graph, tensor, address, kernel, K/V, scan or debug input/output.
// All learned parameters/tables are build-fixed; private SRAM holds K/V.
module hwic_simplestories (
    input wire clk, reset_n, clear_i,
    input wire append_valid_i,
    output wire append_ready_o,
    input wire [11:0] append_token_i,
    input wire step_valid_i,
    output wire step_ready_o,
    output wire token_valid_o,
    input wire token_ready_i,
    output wire [11:0] token_o,
    output wire busy_o, model_locked_o, fail_closed_o
);
    logic [3:0] release_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) release_q<=0;
        else release_q<={release_q[2:0],1'b1};
    end
    // Internal startup replaces the external flash/DDR weight-boot lock.
    wire model_locked_i;
    wire upstream_fail_closed_i;
    wire private_runtime_req_valid_o;
    wire private_runtime_req_ready_i;
    wire [19-1:0] private_runtime_req_word_index_o;
    wire private_runtime_rsp_valid_i;
    wire private_runtime_rsp_ready_o;
    wire [639:0] private_runtime_rsp_data_i;
    wire private_runtime_rsp_fault_i;
    wire kv_write_req_valid_o;
    wire kv_write_req_ready_i;
    wire [2:0] kv_write_req_layer_o;
    wire [11:0] kv_write_req_position_o;
    wire [1:0] kv_write_req_head_o;
    wire [3:0] kv_write_req_row_word_o;
    wire [18:0] kv_write_req_shadow_address_o;
    wire [255:0] kv_write_req_data_o;
    wire kv_write_cpl_valid_i;
    wire kv_write_cpl_ready_o;
    wire kv_write_cpl_fault_i;
    wire kv_read_req_valid_o;
    wire kv_read_req_ready_i;
    wire [2:0] kv_read_req_layer_o;
    wire [11:0] kv_read_req_position_o;
    wire [1:0] kv_read_req_head_o;
    wire [3:0] kv_read_req_row_word_o;
    wire [18:0] kv_read_req_shadow_address_o;
    wire kv_read_rsp_valid_i;
    wire kv_read_rsp_ready_o;
    wire [255:0] kv_read_rsp_data_i;
    wire kv_read_rsp_fault_i;
    wire kv_endpoint_fault_i;
    wire machine_busy;
    wire machine_locked;
    wire machine_fault;
    wire rom_fault, kv_ram_fault, boundary_core_fault, boundary_app_fault;
    wire boundary_busy, boundary_clear_pending, boundary_clear_drained;
    logic machine_fault_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) machine_fault_q<=0;
        else if(machine_fault || rom_fault || kv_ram_fault) machine_fault_q<=1;
    end
    assign model_locked_i=release_q[3];
    assign upstream_fail_closed_i=rom_fault || kv_ram_fault || boundary_core_fault;
    assign kv_endpoint_fault_i=boundary_core_fault;
    assign busy_o=machine_busy || boundary_busy || boundary_clear_pending;
    assign fail_closed_o=machine_fault || rom_fault || kv_ram_fault || boundary_core_fault;
    assign model_locked_o=machine_locked && model_locked_i && !fail_closed_o;
    board1_context2048_token_machine_core #(.ADDR_W(19),.MODEL_WORDS(227062)) u_core (
        .clk(clk),
        .reset_n(reset_n),
        .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fail_closed_i(upstream_fail_closed_i),
        .append_valid_i(append_valid_i),
        .append_ready_o(append_ready_o),
        .append_token_i(append_token_i),
        .step_valid_i(step_valid_i),
        .step_ready_o(step_ready_o),
        .token_valid_o(token_valid_o),
        .token_ready_i(token_ready_i),
        .token_o(token_o),
        .private_runtime_req_valid_o(private_runtime_req_valid_o),
        .private_runtime_req_ready_i(private_runtime_req_ready_i),
        .private_runtime_req_word_index_o(private_runtime_req_word_index_o),
        .private_runtime_rsp_valid_i(private_runtime_rsp_valid_i),
        .private_runtime_rsp_ready_o(private_runtime_rsp_ready_o),
        .private_runtime_rsp_data_i(private_runtime_rsp_data_i),
        .private_runtime_rsp_fault_i(private_runtime_rsp_fault_i),
        .kv_write_req_valid_o(kv_write_req_valid_o),
        .kv_write_req_ready_i(kv_write_req_ready_i),
        .kv_write_req_layer_o(kv_write_req_layer_o),
        .kv_write_req_position_o(kv_write_req_position_o),
        .kv_write_req_head_o(kv_write_req_head_o),
        .kv_write_req_row_word_o(kv_write_req_row_word_o),
        .kv_write_req_shadow_address_o(kv_write_req_shadow_address_o),
        .kv_write_req_data_o(kv_write_req_data_o),
        .kv_write_cpl_valid_i(kv_write_cpl_valid_i),
        .kv_write_cpl_ready_o(kv_write_cpl_ready_o),
        .kv_write_cpl_fault_i(kv_write_cpl_fault_i),
        .kv_read_req_valid_o(kv_read_req_valid_o),
        .kv_read_req_ready_i(kv_read_req_ready_i),
        .kv_read_req_layer_o(kv_read_req_layer_o),
        .kv_read_req_position_o(kv_read_req_position_o),
        .kv_read_req_head_o(kv_read_req_head_o),
        .kv_read_req_row_word_o(kv_read_req_row_word_o),
        .kv_read_req_shadow_address_o(kv_read_req_shadow_address_o),
        .kv_read_rsp_valid_i(kv_read_rsp_valid_i),
        .kv_read_rsp_ready_o(kv_read_rsp_ready_o),
        .kv_read_rsp_data_i(kv_read_rsp_data_i),
        .kv_read_rsp_fault_i(kv_read_rsp_fault_i),
        .kv_endpoint_fault_i(kv_endpoint_fault_i),
        .busy_o(machine_busy),
        .model_locked_o(machine_locked),
        .fail_closed_o(machine_fault)
    );
    hwic_fixed_model_rom u_model (
        .clk(clk),.reset_n(reset_n),.enabled_i(model_locked_i),
        .request_valid_i(private_runtime_req_valid_o),
        .request_ready_o(private_runtime_req_ready_i),
        .request_word_i(private_runtime_req_word_index_o),
        .response_valid_o(private_runtime_rsp_valid_i),
        .response_ready_i(private_runtime_rsp_ready_o),
        .response_data_o(private_runtime_rsp_data_i),
        .response_fault_o(private_runtime_rsp_fault_i),.fault_o(rom_fault));
    wire kv_req_valid,kv_req_ready,kv_req_write,kv_rsp_valid,kv_rsp_ready,kv_rsp_error;
    wire [18:0] kv_req_word;
    wire [255:0] kv_req_data,kv_rsp_data;
    board1_context2048_typed_ddr_boundary #(.FIFO_ADDR_BITS(2)) u_kv_boundary (
        .core_clk_i(clk),.core_reset_n_i(reset_n),.core_clear_i(clear_i),
        .core_upstream_fault_i(machine_fault_q),
        .model_req_valid_i(1'b0),.model_req_ready_o(),.model_req_word_i(19'd0),
        .model_rsp_valid_o(),.model_rsp_ready_i(1'b1),.model_rsp_data_o(),.model_rsp_fault_o(),
        .kv_write_req_valid_i(kv_write_req_valid_o),
        .kv_write_req_ready_o(kv_write_req_ready_i),
        .kv_write_req_layer_i(kv_write_req_layer_o),
        .kv_write_req_position_i(kv_write_req_position_o),
        .kv_write_req_head_i(kv_write_req_head_o),
        .kv_write_req_row_word_i(kv_write_req_row_word_o),
        .kv_write_req_shadow_address_i(kv_write_req_shadow_address_o),
        .kv_write_req_data_i(kv_write_req_data_o),
        .kv_write_cpl_valid_o(kv_write_cpl_valid_i),
        .kv_write_cpl_ready_i(kv_write_cpl_ready_o),
        .kv_write_cpl_fault_o(kv_write_cpl_fault_i),
        .kv_read_req_valid_i(kv_read_req_valid_o),
        .kv_read_req_ready_o(kv_read_req_ready_i),
        .kv_read_req_layer_i(kv_read_req_layer_o),
        .kv_read_req_position_i(kv_read_req_position_o),
        .kv_read_req_head_i(kv_read_req_head_o),
        .kv_read_req_row_word_i(kv_read_req_row_word_o),
        .kv_read_req_shadow_address_i(kv_read_req_shadow_address_o),
        .kv_read_rsp_valid_o(kv_read_rsp_valid_i),
        .kv_read_rsp_ready_i(kv_read_rsp_ready_o),
        .kv_read_rsp_data_o(kv_read_rsp_data_i),
        .kv_read_rsp_fault_o(kv_read_rsp_fault_i),
        .core_clear_pending_o(boundary_clear_pending),
        .core_clear_drained_o(boundary_clear_drained),.core_busy_o(boundary_busy),
        .core_fail_closed_o(boundary_core_fault),
        .app_clk_i(clk),.app_reset_n_i(reset_n),.app_model_locked_i(model_locked_i),
        .app_upstream_fault_i(machine_fault_q || kv_ram_fault),
        .endpoint_req_valid_o(kv_req_valid),.endpoint_req_ready_i(kv_req_ready),
        .endpoint_req_word_address_o(kv_req_word),.endpoint_req_write_o(kv_req_write),
        .endpoint_req_write_data_o(kv_req_data),.endpoint_rsp_valid_i(kv_rsp_valid),
        .endpoint_rsp_ready_o(kv_rsp_ready),.endpoint_rsp_data_i(kv_rsp_data),
        .endpoint_rsp_error_i(kv_rsp_error),.app_busy_o(),.app_fail_closed_o(boundary_app_fault));
    hwic_private_kv_ram u_kv_ram (
        .clk(clk),.reset_n(reset_n),.enabled_i(model_locked_i),
        .request_valid_i(kv_req_valid),.request_ready_o(kv_req_ready),
        .request_word_i(kv_req_word),.request_write_i(kv_req_write),.request_data_i(kv_req_data),
        .response_valid_o(kv_rsp_valid),.response_ready_i(kv_rsp_ready),
        .response_data_o(kv_rsp_data),.response_error_o(kv_rsp_error),.fault_o(kv_ram_fault));
endmodule
`default_nettype wire
