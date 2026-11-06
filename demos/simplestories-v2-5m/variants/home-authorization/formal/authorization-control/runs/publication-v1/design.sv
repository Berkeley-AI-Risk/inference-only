`timescale 1ns/1ps
`default_nettype none

// Private transport adapter for the exact token-only command boundary.
// Request:  A5 opcode token_lo 0000_token_hi crc8
// Response: 5A result token_lo 0000_token_hi crc8
// Opcodes are 00 APPEND, 01 STEP, 02 CLEAR.  Results are 80 APPEND accepted,
// 81 generated token, 82 CLEAR accepted, C0..C2 rejected, or CF malformed.
// No frame can select a model, tensor, address, cache, lane, or arithmetic op.
module token_only_model0_uart_bridge #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire        clk,
    input  wire        rst_n,
    input wire transport_pause_i, publication_allowed_i,
    output wire uart_quiet_o,
    input  wire        uart_rx_i,
    output wire        uart_tx_o,

    output wire        clear_command_o,
    output wire        cmd_valid_o,
    input  wire        cmd_ready_i,
    output wire [1:0]  cmd_o,
    output wire [11:0] in_token_o,
    input  wire        out_valid_i,
    output wire        out_ready_o,
    input  wire [11:0] out_token_i
);
    localparam [7:0] REQUEST_MAGIC = 8'ha5;
    localparam [7:0] RESPONSE_MAGIC = 8'h5a;
    localparam [7:0] OP_APPEND = 8'h00;
    localparam [7:0] OP_STEP = 8'h01;
    localparam [7:0] OP_CLEAR = 8'h02;
    localparam [12:0] VOCAB_SIZE = 13'd4019;

    function automatic [7:0] crc8_next(
        input [7:0] crc_in,
        input [7:0] data_in
    );
        integer i;
        reg [7:0] value;
        begin
            value = crc_in ^ data_in;
            for (i = 0; i < 8; i = i + 1)
                value = value[7] ? ((value << 1) ^ 8'h07) : (value << 1);
            crc8_next = value;
        end
    endfunction

    wire rx_valid;
    wire [7:0] rx_byte;
    wire tx_ready;
    wire tx_valid;
    wire [7:0] tx_byte;

    fixed_uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) receiver (
        .clk(clk), .rst_n(rst_n && !transport_pause_i), .serial_i(uart_rx_i),
        .byte_valid_o(rx_valid), .byte_o(rx_byte)
    );

    fixed_uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) transmitter (
        .clk(clk), .rst_n(rst_n && !transport_pause_i), .byte_valid_i(tx_valid),
        .byte_ready_o(tx_ready), .byte_i(tx_byte), .serial_o(uart_tx_o)
    );

    typedef enum logic [2:0] {
        BRIDGE_IDLE,
        BRIDGE_OFFER,
        BRIDGE_WAIT_RESULT,
        BRIDGE_SEND,
        BRIDGE_DRAIN
    } bridge_state_t;
    bridge_state_t state_q;

    logic [2:0] request_index_q;
    logic [7:0] request_crc_q;
    logic [7:0] request_opcode_q;
    logic [7:0] request_token_low_q;
    logic [7:0] request_token_high_q;

    logic [1:0] command_q;
    logic [11:0] command_token_q;
    logic [7:0] response_kind_q;
    logic [11:0] response_token_q;
    logic [7:0] response_crc_q;
    logic [2:0] response_index_q;
    logic clear_pending_q;
    logic recovery_clear_q;

    wire [7:0] response_byte0 = RESPONSE_MAGIC;
    wire [7:0] response_byte1 = response_kind_q;
    wire [7:0] response_byte2 = response_token_q[7:0];
    wire [7:0] response_byte3 = {4'b0000, response_token_q[11:8]};
    wire [7:0] computed_response_crc =
        crc8_next(crc8_next(crc8_next(crc8_next(8'h00,
        response_byte0), response_byte1), response_byte2), response_byte3);
    wire request_unknown;
`ifndef SYNTHESIS
    assign request_unknown = $isunknown({rx_byte, request_crc_q,
                                         request_opcode_q,
                                         request_token_low_q,
                                         request_token_high_q});
`else
    assign request_unknown = 1'b0;
`endif

    assign cmd_valid_o = !transport_pause_i && ((state_q == BRIDGE_OFFER) ||
                         (state_q == BRIDGE_WAIT_RESULT && clear_pending_q));
    assign cmd_o = (state_q == BRIDGE_WAIT_RESULT && clear_pending_q) ?
                   OP_CLEAR[1:0] : command_q;
    assign in_token_o = (state_q == BRIDGE_WAIT_RESULT && clear_pending_q) ?
                        12'b0 : command_token_q;
    assign out_ready_o = !transport_pause_i && publication_allowed_i && (state_q == BRIDGE_WAIT_RESULT);
    assign tx_valid = !transport_pause_i && (state_q == BRIDGE_SEND) && (response_index_q!=0 || publication_allowed_i);
    assign uart_quiet_o = tx_ready && state_q!=BRIDGE_DRAIN &&
        (state_q!=BRIDGE_SEND || (response_index_q==0 && !publication_allowed_i));
    assign tx_byte = (response_index_q == 0) ? response_byte0 :
                     (response_index_q == 1) ? response_byte1 :
                     (response_index_q == 2) ? response_byte2 :
                     (response_index_q == 3) ? response_byte3 :
                                                response_crc_q;

    task automatic prepare_response(
        input [7:0] kind,
        input [11:0] token
    );
        begin
            response_kind_q <= kind;
            response_token_q <= token;
            response_index_q <= 3'b0;
            // This is recomputed in BRIDGE_SEND after kind/token registers
            // have settled; the value here is intentionally overwritten.
            response_crc_q <= 8'b0;
            state_q <= BRIDGE_SEND;
        end
    endtask

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= BRIDGE_IDLE;
            request_index_q <= 3'b0;
            request_crc_q <= 8'b0;
            request_opcode_q <= 8'b0;
            request_token_low_q <= 8'b0;
            request_token_high_q <= 8'b0;
            command_q <= 2'b0;
            command_token_q <= 12'b0;
            response_kind_q <= 8'b0;
            response_token_q <= 12'b0;
            response_crc_q <= 8'b0;
            response_index_q <= 3'b0;
            clear_pending_q <= 1'b0;
            recovery_clear_q <= 1'b0;
        end else if (!transport_pause_i) begin
            if ((state_q == BRIDGE_IDLE ||
                 (state_q == BRIDGE_WAIT_RESULT && !clear_pending_q &&
                  !out_valid_i)) && rx_valid) begin
                case (request_index_q)
                    3'd0: begin
                        if (rx_byte == REQUEST_MAGIC) begin
                            request_crc_q <= crc8_next(8'h00, rx_byte);
                            request_index_q <= 3'd1;
                        end
                    end
                    3'd1: begin
                        request_opcode_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd2;
                    end
                    3'd2: begin
                        request_token_low_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd3;
                    end
                    3'd3: begin
                        request_token_high_q <= rx_byte;
                        request_crc_q <= crc8_next(request_crc_q, rx_byte);
                        request_index_q <= 3'd4;
                    end
                    3'd4: begin
                        request_index_q <= 3'd0;
                        if (state_q == BRIDGE_WAIT_RESULT) begin
                            // CLEAR remains available after a silent model
                            // fault. Other commands cannot overtake STEP.
                            if (!request_unknown &&
                                rx_byte == request_crc_q &&
                                request_opcode_q == OP_CLEAR &&
                                request_token_low_q == 8'b0 &&
                                request_token_high_q == 8'b0)
                                clear_pending_q <= 1'b1;
                        end else if (request_unknown ||
                            rx_byte != request_crc_q ||
                            request_token_high_q[7:4] != 4'b0 ||
                            request_opcode_q > OP_CLEAR) begin
                            prepare_response(8'hcf, 12'b0);
                        end else if (request_opcode_q == OP_APPEND &&
                                     {1'b0, request_token_high_q[3:0],
                                      request_token_low_q} >= VOCAB_SIZE) begin
                            prepare_response(8'hc0, 12'b0);
                        end else if (request_opcode_q != OP_APPEND &&
                                     {request_token_high_q[3:0],
                                      request_token_low_q} != 12'b0) begin
                            prepare_response(8'hc0 | request_opcode_q,
                                             12'b0);
                        end else begin
                            command_q <= request_opcode_q[1:0];
                            command_token_q <= {
                                request_token_high_q[3:0],
                                request_token_low_q
                            };
                            state_q <= BRIDGE_OFFER;
                        end
                    end
                    default: request_index_q <= 3'b0;
                endcase
            end

            case (state_q)
                BRIDGE_OFFER: begin
                    if (cmd_ready_i) begin
                        recovery_clear_q <= 1'b0;
                        if (command_q == OP_CLEAR[1:0])
                            clear_pending_q <= 1'b0;
                        if (command_q == OP_STEP[1:0])
                            state_q <= BRIDGE_WAIT_RESULT;
                        else if (command_q == OP_APPEND[1:0])
                            prepare_response(8'h80, 12'b0);
                        else
                            prepare_response(8'h82, 12'b0);
                    end else if (!recovery_clear_q) begin
                        prepare_response(8'hc0 | {6'b0, command_q}, 12'b0);
                    end
                end
                BRIDGE_WAIT_RESULT: begin
                    if (clear_pending_q && cmd_ready_i) begin
                        clear_pending_q <= 1'b0;
                        prepare_response(8'h82, 12'b0);
                    end else if (out_valid_i && publication_allowed_i) begin
                        prepare_response(8'h81, out_token_i);
                    end
                end
                BRIDGE_SEND: begin
                    // Delay CRC capture until kind/token have settled.
                    if (response_index_q == 0)
                        response_crc_q <= computed_response_crc;
                    if (tx_ready && tx_valid) begin
                        if (response_index_q == 3'd4)
                            state_q <= BRIDGE_DRAIN;
                        else
                            response_index_q <= response_index_q + 1'b1;
                    end
                end
                BRIDGE_DRAIN: begin
                    if (tx_ready) begin
                        if (clear_pending_q) begin
                            command_q <= OP_CLEAR[1:0];
                            command_token_q <= 12'b0;
                            recovery_clear_q <= 1'b1;
                            state_q <= BRIDGE_OFFER;
                        end else begin
                            state_q <= BRIDGE_IDLE;
                        end
                    end
                end
                default: begin end
            endcase
        end
    end
    // Predict exactly the old decoder's next-cycle CLEAR level from the
    // existing bridge transition. This is not a delayed or queued command.
    // The original state machine, CRC, rejection and recovery logic remain.
    (* syn_preserve = 1 *) logic clear_command_q;
    logic clear_command_next;
    wire received_clear_frame = rx_valid && (request_index_q == 3'd4) &&
        !request_unknown && (rx_byte == request_crc_q) &&
        (request_opcode_q == OP_CLEAR) && (request_token_low_q == 8'b0) &&
        (request_token_high_q == 8'b0);
    always_comb begin
        clear_command_next = 1'b0;
        case (state_q)
            BRIDGE_IDLE: begin
                if (received_clear_frame) clear_command_next = 1'b1;
            end
            BRIDGE_OFFER: begin
                if (cmd_ready_i) clear_command_next = 1'b0;
                else if (!recovery_clear_q) clear_command_next = 1'b0;
                else clear_command_next = (command_q == OP_CLEAR[1:0]);
            end
            BRIDGE_WAIT_RESULT: begin
                if (clear_pending_q && cmd_ready_i) clear_command_next = 1'b0;
                else if (out_valid_i) clear_command_next = 1'b0;
                else if (clear_pending_q) clear_command_next = 1'b1;
                else if (received_clear_frame) clear_command_next = 1'b1;
            end
            BRIDGE_DRAIN: begin
                if (tx_ready && clear_pending_q) clear_command_next = 1'b1;
            end
            default: begin end
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) clear_command_q <= 1'b0;
        else if (transport_pause_i) clear_command_q <= 1'b0;
        else clear_command_q <= clear_command_next;
    end
    assign clear_command_o = clear_command_q && !transport_pause_i;

    // Only frame admission is gated by publication_allowed_i. Subsequent
    // bytes intentionally drain. The chip-level mux separately clamps token
    // serial output as soon as the lease fails/expires.
    always_comb begin
        if(out_ready_o) assert(publication_allowed_i && !transport_pause_i);
        if(tx_valid && tx_ready && response_index_q==0)
            assert(publication_allowed_i && !transport_pause_i);
        if(transport_pause_i) assert(!tx_valid && !out_ready_o && !cmd_valid_o);
        if(uart_quiet_o) begin
            assert(tx_ready);
            assert(state_q!=BRIDGE_DRAIN);
            if(state_q==BRIDGE_SEND) assert(response_index_q==0 && !publication_allowed_i);
        end
        if(!rst_n) assert(!cmd_valid_o && !out_ready_o);
    end
    logic publication_past=0;
    always_ff @(posedge clk) begin
        publication_past<=1;
        if(publication_past && rst_n && $past(rst_n)) begin
            if($past(state_q)==BRIDGE_SEND && $past(response_index_q)==0 &&
               !$past(publication_allowed_i)) assert(response_index_q==0);
        end
    end

endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module fixed_uart_tx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       byte_valid_i,
    output wire       byte_ready_o,
    input  wire [7:0] byte_i,
    output wire       serial_o
);
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);
    logic [COUNTER_BITS-1:0] counter_q;
    logic [3:0] bit_q;
    logic [9:0] shift_q;
    logic busy_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    assign byte_ready_o = !busy_q;
    assign serial_o = busy_q ? shift_q[0] : 1'b1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= 10'h3ff;
            busy_q <= 1'b0;
        end else if (!busy_q) begin
            if (byte_valid_i) begin
                shift_q <= {1'b1, byte_i, 1'b0};
                counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                bit_q <= 4'b0;
                busy_q <= 1'b1;
            end
        end else if (counter_q != 0) begin
            counter_q <= counter_q - 1'b1;
        end else if (bit_q == 4'd9) begin
            busy_q <= 1'b0;
        end else begin
            shift_q <= {1'b1, shift_q[9:1]};
            counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
            bit_q <= bit_q + 1'b1;
        end
    end
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

module fixed_uart_rx #(
    parameter integer CLKS_PER_BIT = 234
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       serial_i,
    output logic      byte_valid_o,
    output logic [7:0] byte_o
);
    localparam integer HALF_BIT = CLKS_PER_BIT / 2;
    localparam integer COUNTER_BITS = $clog2(CLKS_PER_BIT + 1);

    typedef enum logic [1:0] {RX_IDLE, RX_START, RX_DATA, RX_STOP} rx_state_t;
    rx_state_t state_q;
    logic [COUNTER_BITS-1:0] counter_q;
    logic [2:0] bit_q;
    logic [7:0] shift_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_meta_q;
    (* async_reg = "true", syn_preserve = 1 *) logic serial_sync_q;

    initial begin
        if (CLKS_PER_BIT < 4)
            $fatal(1, "CLKS_PER_BIT must be at least four");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= RX_IDLE;
            counter_q <= '0;
            bit_q <= '0;
            shift_q <= '0;
            byte_o <= '0;
            byte_valid_o <= 1'b0;
            serial_meta_q <= 1'b1;
            serial_sync_q <= 1'b1;
        end else begin
            serial_meta_q <= serial_i;
            serial_sync_q <= serial_meta_q;
            byte_valid_o <= 1'b0;
            case (state_q)
                RX_IDLE: begin
                    if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(HALF_BIT - 1);
                        state_q <= RX_START;
                    end
                end
                RX_START: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else if (!serial_sync_q) begin
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        bit_q <= 3'b0;
                        state_q <= RX_DATA;
                    end else begin
                        state_q <= RX_IDLE;
                    end
                end
                RX_DATA: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        shift_q[bit_q] <= serial_sync_q;
                        counter_q <= COUNTER_BITS'(CLKS_PER_BIT - 1);
                        if (bit_q == 3'd7)
                            state_q <= RX_STOP;
                        else
                            bit_q <= bit_q + 1'b1;
                    end
                end
                RX_STOP: begin
                    if (counter_q != 0) begin
                        counter_q <= counter_q - 1'b1;
                    end else begin
                        if (serial_sync_q) begin
                            byte_o <= shift_q;
                            byte_valid_o <= 1'b1;
                        end
                        state_q <= RX_IDLE;
                    end
                end
                default: state_q <= RX_IDLE;
            endcase
        end
    end
endmodule

`default_nettype wire
