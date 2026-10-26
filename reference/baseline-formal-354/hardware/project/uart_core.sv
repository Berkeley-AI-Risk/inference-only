`timescale 1ns/1ps
`default_nettype none

// Same frozen five-byte UART protocol and three-operation adapter as S25.
// The model/typed-KV endpoint is the four-bank shared private runtime.
module board1_private_shared_uart_core (
    input wire core_clk_i,app_clk_i,reset_n_i,uart_rx_i,
    output wire uart_tx_o,
    input wire private_model_locked_i,private_endpoint_upstream_fault_i,
    output wire private_endpoint_req_valid_o,private_endpoint_req_write_o,
    input wire private_endpoint_req_ready_i,
    output wire [18:0] private_endpoint_req_word_address_o,
    output wire [255:0] private_endpoint_req_write_data_o,
    input wire private_endpoint_rsp_valid_i,private_endpoint_rsp_error_i,
    input wire [255:0] private_endpoint_rsp_data_i,
    output wire private_fail_closed_o
);
    wire cmd_valid,cmd_ready,result_valid,result_ready;
    wire [1:0] cmd;
    wire [11:0] command_token,result_token;
    wire clear,decoded_clear,append_valid,append_ready,step_valid,step_ready,token_valid,token_ready;
    wire [11:0] append_token,token;
    // 25 MHz / 217 = 115207 baud (nominal). No run-time baud/mode selector.
    token_only_model0_uart_bridge #(.CLKS_PER_BIT(217)) u_fixed_uart (
        .clk(core_clk_i),.rst_n(reset_n_i),.uart_rx_i(uart_rx_i),.uart_tx_o(uart_tx_o),
        .clear_command_o(clear),.cmd_valid_o(cmd_valid),.cmd_ready_i(cmd_ready),.cmd_o(cmd),.in_token_o(command_token),
        .out_valid_i(result_valid),.out_ready_o(result_ready),.out_token_i(result_token));
    board1_fixed_command_adapter u_three_operations (
        .cmd_valid_i(cmd_valid),.cmd_ready_o(cmd_ready),.cmd_i(cmd),.cmd_token_i(command_token),
        .clear_o(decoded_clear),.append_valid_o(append_valid),.append_ready_i(append_ready),.append_token_o(append_token),
        .step_valid_o(step_valid),.step_ready_i(step_ready),.token_valid_i(token_valid),
        .token_ready_o(token_ready),.token_i(token),.result_valid_o(result_valid),
        .result_ready_i(result_ready),.result_token_o(result_token));
    board1_context2048_shared_token_probe #(.AUTH_BANKS(4)) u_machine (
        .core_clk_i(core_clk_i),.app_clk_i(app_clk_i),.reset_n_i(reset_n_i),.clear_i(clear),
        .append_valid_i(append_valid),.append_ready_o(append_ready),.append_token_i(append_token),
        .step_valid_i(step_valid),.step_ready_o(step_ready),.token_valid_o(token_valid),
        .token_ready_i(token_ready),.token_o(token),.busy_o(),.model_locked_o(),.fail_closed_o(private_fail_closed_o),
        .private_model_locked_i(private_model_locked_i),.private_endpoint_upstream_fault_i(private_endpoint_upstream_fault_i),
        .private_endpoint_req_valid_o(private_endpoint_req_valid_o),.private_endpoint_req_ready_i(private_endpoint_req_ready_i),
        .private_endpoint_req_word_address_o(private_endpoint_req_word_address_o),.private_endpoint_req_write_o(private_endpoint_req_write_o),
        .private_endpoint_req_write_data_o(private_endpoint_req_write_data_o),.private_endpoint_rsp_valid_i(private_endpoint_rsp_valid_i),
        .private_endpoint_rsp_ready_o(),.private_endpoint_rsp_data_i(private_endpoint_rsp_data_i),
        .private_endpoint_rsp_error_i(private_endpoint_rsp_error_i));
endmodule
`default_nettype wire
