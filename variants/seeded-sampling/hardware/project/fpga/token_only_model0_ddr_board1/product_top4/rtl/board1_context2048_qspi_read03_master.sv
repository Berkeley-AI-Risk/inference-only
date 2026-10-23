`timescale 1ns/1ps
`default_nettype none

// Immutable single-output SPI reader for the Board1 semantic image.  Opcode,
// address, and length exist only as constants in this module: there is no
// caller-selected flash operation and no program/erase/status-write path.
// Legacy 0x03 needs no Quad Enable bit and no dummy-cycle configuration.
// Startup-only pulse spacing: each ordinary SCK half-period is at least two
// trusted clocks. Byte ownership still transfers on exactly one VALID/READY
// edge; ST_TURN completes the stretched last high phase after acceptance.
// No inference datapath, authentication, public operation or model change.
module board1_context2048_qspi_read03_master (
    input  wire        clk_i,
    input  wire        reset_n_i,
    input  wire        start_i,
    output logic       busy_o,
    output logic       fault_o,

    output logic       data_valid_o,
    input  wire        data_ready_i,
    output logic [7:0] data_o,
    output logic       data_last_o,

    output logic       qspi_cs_n_o,
    output logic       qspi_sck_o,
    input  wire        qspi_dq1_i,
    output logic [3:0] qspi_dq_o,
    output logic [3:0] qspi_dq_oe_o
);
    localparam logic [7:0] READ_OPCODE = 8'h03;
    localparam logic [23:0] IMAGE_BASE = 24'h801000;
    localparam logic [23:0] IMAGE_BYTES = 24'd7265984;

    typedef enum logic [2:0] {
        ST_IDLE  = 3'd0,
        ST_SEND  = 3'd1,
        ST_DATA  = 3'd2,
        ST_TURN  = 3'd3,
        ST_FAULT = 3'd7
    } state_t;

    state_t state_q;
    logic phase_high_q;
    logic edge_wait_q;
    logic [30:0] transmit_shift_q;
    logic [5:0] send_bits_left_q;
    logic [23:0] bytes_remaining_q;
    logic [2:0] data_bit_q;
    logic [6:0] data_shift_q;

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            state_q <= ST_IDLE;
            phase_high_q <= 1'b0;
            edge_wait_q <= 1'b0;
            transmit_shift_q <= 31'd0;
            send_bits_left_q <= 6'd0;
            bytes_remaining_q <= 24'd0;
            data_bit_q <= 3'd0;
            data_shift_q <= 7'd0;
            busy_o <= 1'b0;
            fault_o <= 1'b0;
            data_valid_o <= 1'b0;
            data_o <= 8'd0;
            data_last_o <= 1'b0;
            qspi_cs_n_o <= 1'b1;
            qspi_sck_o <= 1'b0;
            qspi_dq_o <= 4'b1100;
            qspi_dq_oe_o <= 4'b0000;
        end else begin
            case (state_q)
                ST_IDLE: begin
                    data_valid_o <= 1'b0;
                    data_last_o <= 1'b0;
                    qspi_cs_n_o <= 1'b1;
                    qspi_sck_o <= 1'b0;
                    qspi_dq_o <= 4'b1100;
                    qspi_dq_oe_o <= 4'b0000;
                    phase_high_q <= 1'b0;
                    edge_wait_q <= 1'b0;
                    busy_o <= 1'b0;
                    if (start_i) begin
                        transmit_shift_q <= {READ_OPCODE[6:0], IMAGE_BASE};
                        send_bits_left_q <= 6'd32;
                        bytes_remaining_q <= IMAGE_BYTES;
                        data_bit_q <= 3'd0;
                        data_shift_q <= 7'd0;
                        qspi_dq_o <= {2'b11, 1'b0, READ_OPCODE[7]};
                        // DQ0 is MOSI, DQ1 is MISO.  Hold legacy WP#/HOLD#
                        // (DQ2/DQ3) high during the complete transaction.
                        qspi_dq_oe_o <= 4'b1101;
                        qspi_cs_n_o <= 1'b0;
                        busy_o <= 1'b1;
                        state_q <= ST_SEND;
                    end
                end
                ST_SEND: begin
                    if (!edge_wait_q) begin
                        edge_wait_q <= 1'b1;
                    end else begin
                        edge_wait_q <= 1'b0;
                    if (!phase_high_q) begin
                        qspi_sck_o <= 1'b1;
                        phase_high_q <= 1'b1;
                    end else begin
                        qspi_sck_o <= 1'b0;
                        phase_high_q <= 1'b0;
                        if (send_bits_left_q == 6'd1) begin
                            send_bits_left_q <= 6'd0;
                            qspi_dq_o <= 4'b1100;
                            qspi_dq_oe_o <= 4'b1100;
                            data_bit_q <= 3'd0;
                            data_shift_q <= 7'd0;
                            state_q <= ST_DATA;
                        end else begin
                            transmit_shift_q <=
                                {transmit_shift_q[29:0], 1'b0};
                            qspi_dq_o[0] <= transmit_shift_q[30];
                            send_bits_left_q <= send_bits_left_q - 1'b1;
                        end
                    end
                    end
                end
                ST_DATA: begin
                    // The downstream stream must never see the same byte
                    // twice. Accept immediately, but delay its trailing SCK
                    // edge with a private state rather than holding VALID.
                    if (data_valid_o) begin
                        if (data_ready_i) begin
                            data_valid_o <= 1'b0;
                            state_q <= ST_TURN;
                        end
                    end else if (!edge_wait_q) begin
                        edge_wait_q <= 1'b1;
                    end else begin
                        edge_wait_q <= 1'b0;
                        if (!phase_high_q) begin
`ifndef SYNTHESIS
                        if ($isunknown(qspi_dq1_i)) begin
                            fault_o <= 1'b1;
                            qspi_cs_n_o <= 1'b1;
                            qspi_sck_o <= 1'b0;
                            qspi_dq_oe_o <= 4'b0000;
                            busy_o <= 1'b0;
                            state_q <= ST_FAULT;
                        end else begin
`endif
                            qspi_sck_o <= 1'b1;
                            phase_high_q <= 1'b1;
                            if (data_bit_q == 3'd7) begin
                                data_o <= {data_shift_q, qspi_dq1_i};
                                data_valid_o <= 1'b1;
                                data_last_o <=
                                    bytes_remaining_q == 24'd1;
                                data_bit_q <= 3'd0;
                            end else begin
                                data_shift_q <=
                                    {data_shift_q[5:0], qspi_dq1_i};
                                data_bit_q <= data_bit_q + 1'b1;
                            end
`ifndef SYNTHESIS
                        end
`endif
                        end else begin
                            qspi_sck_o <= 1'b0;
                            phase_high_q <= 1'b0;
                        end
                    end
                end
                ST_TURN: begin
                    // Even immediate acceptance leaves at least two complete
                    // trusted cycles between the sample and this falling edge.
                    edge_wait_q <= 1'b0;
                    qspi_sck_o <= 1'b0;
                    phase_high_q <= 1'b0;
                    if (data_last_o) begin
                        data_last_o <= 1'b0;
                        qspi_cs_n_o <= 1'b1;
                        qspi_dq_oe_o <= 4'b0000;
                        busy_o <= 1'b0;
                        state_q <= ST_IDLE;
                    end else begin
                        bytes_remaining_q <= bytes_remaining_q - 1'b1;
                        state_q <= ST_DATA;
                    end
                end
                default: begin
                    qspi_cs_n_o <= 1'b1;
                    qspi_sck_o <= 1'b0;
                    qspi_dq_oe_o <= 4'b0000;
                    busy_o <= 1'b0;
                    data_valid_o <= 1'b0;
                    data_last_o <= 1'b0;
                    fault_o <= 1'b1;
                    state_q <= ST_FAULT;
                end
            endcase

            if (start_i && state_q != ST_IDLE) begin
                qspi_cs_n_o <= 1'b1;
                qspi_sck_o <= 1'b0;
                qspi_dq_oe_o <= 4'b0000;
                busy_o <= 1'b0;
                data_valid_o <= 1'b0;
                data_last_o <= 1'b0;
                fault_o <= 1'b1;
                state_q <= ST_FAULT;
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (qspi_dq_oe_o == 4'b0000 ||
                    qspi_dq_oe_o == 4'b1101 ||
                    qspi_dq_oe_o == 4'b1100);
            assert (!qspi_dq_oe_o[1]);
            if (data_valid_o)
                assert (state_q == ST_DATA && busy_o);
            if (fault_o)
                assert (state_q == ST_FAULT);
        end
    end
`endif
endmodule

`default_nettype wire

