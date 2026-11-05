`timescale 1ns/1ps
`default_nettype none

// Exact adapter from the frozen two-bit UART command encoding to the logical
// token-machine boundary.  This is deliberately only a decoder: it cannot
// create an address, job, tensor, weight, arithmetic mode, or runtime write.
//
//   2'b00 APPEND(token)
//   2'b01 STEP
//   2'b10 CLEAR
//   2'b11 invalid (never accepted)
//
// CLEAR is the token machine's synchronous sideband operation, so it is
// accepted in one clock even while STEP is busy.  It clears/replays the tape;
// it never resets a terminal fail-closed latch or reopens the model loader.
module board1_fixed_command_adapter (
    input  wire          cmd_valid_i,
    output logic         cmd_ready_o,
    input  wire [1:0]    cmd_i,
    input  wire [11:0]   cmd_token_i,

    output logic         clear_o,
    output logic         append_valid_o,
    input  wire          append_ready_i,
    output logic [11:0]  append_token_o,
    output logic         step_valid_o,
    input  wire          step_ready_i,

    input  wire          token_valid_i,
    output logic         token_ready_o,
    input  wire [11:0]   token_i,
    output logic         result_valid_o,
    input  wire          result_ready_i,
    output logic [11:0]  result_token_o
);
    localparam logic [1:0] CMD_APPEND = 2'b00;
    localparam logic [1:0] CMD_STEP   = 2'b01;
    localparam logic [1:0] CMD_CLEAR  = 2'b10;

    always_comb begin
        cmd_ready_o = 1'b0;
        clear_o = 1'b0;
        append_valid_o = 1'b0;
        append_token_o = cmd_token_i;
        step_valid_o = 1'b0;

        case (cmd_i)
            CMD_APPEND: begin
                cmd_ready_o = append_ready_i;
                append_valid_o = cmd_valid_i;
            end
            CMD_STEP: begin
                cmd_ready_o = step_ready_i;
                step_valid_o = cmd_valid_i;
            end
            CMD_CLEAR: begin
                cmd_ready_o = 1'b1;
                clear_o = cmd_valid_i;
            end
            default: begin
                // Reserved encoding remains inert and backpressured forever.
            end
        endcase

        result_valid_o = token_valid_i;
        result_token_o = token_valid_i ? token_i : 12'd0;
        token_ready_o = result_ready_i;
    end

`ifdef FORMAL
    always_comb begin
        assert (!(append_valid_o && step_valid_o));
        assert (!(clear_o && (append_valid_o || step_valid_o)));
        if (cmd_i == 2'b11) begin
            assert (!cmd_ready_o);
            assert (!clear_o && !append_valid_o && !step_valid_o);
        end
        if (clear_o)
            assert (cmd_valid_i && cmd_ready_o && cmd_i == CMD_CLEAR);
        if (append_valid_o)
            assert (cmd_valid_i && cmd_i == CMD_APPEND &&
                    append_token_o == cmd_token_i);
        if (step_valid_o)
            assert (cmd_valid_i && cmd_i == CMD_STEP);
        assert (token_ready_o == result_ready_i);
        assert (result_valid_o == token_valid_i);
    end
`endif
endmodule

`default_nettype wire
