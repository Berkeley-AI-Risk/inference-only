`timescale 1ns/1ps
`default_nettype none

// Temporary SRAM diagnostic ONLY. Never install as persistent configuration.
// Production top has no parameters: the host cannot choose an address, length,
// opcode, write data, clock rate, or pin direction.
module readonly_flash_reader (
    input wire clk_50mhz,
    input wire reset_button,
    input wire uart_rx,
    output wire uart_tx,
    output wire flash_csn,
    output wire flash_sclk,
    inout wire [3:0] flash_dq
);
    // Power-on delay also produces reset after SRAM configuration. External
    // reset asserts asynchronously; release is synchronized to the only clock.
    logic [15:0] poweron_q = 16'd0;
    (* async_reg = "true", syn_preserve = 1 *) logic [1:0] reset_release_q = 2'b00;
    always_ff @(posedge clk_50mhz or posedge reset_button) begin
        if (reset_button) poweron_q <= 16'd0;
        else if (!(&poweron_q)) poweron_q <= poweron_q + 1'b1;
    end
    wire reset_request = reset_button || !(&poweron_q);
    always_ff @(posedge clk_50mhz or posedge reset_request) begin
        if (reset_request) reset_release_q <= 2'b00;
        else reset_release_q <= {reset_release_q[0], 1'b1};
    end
    wire flash_mosi, reader_csn, reader_sclk, reader_uart;
    // Establish deselection before the first clock after SRAM configuration,
    // even before the core's asynchronous reset has propagated.
    assign flash_csn = reset_release_q[1] ? reader_csn : 1'b1;
    assign flash_sclk = reset_release_q[1] ? reader_sclk : 1'b0;
    assign uart_tx = reset_release_q[1] ? reader_uart : 1'b1;
    assign flash_dq[0] = !flash_csn ? flash_mosi : 1'bz;
    assign flash_dq[1] = 1'bz;
    assign flash_dq[2] = 1'b1; // WP# inactive; no quad mode.
    assign flash_dq[3] = 1'b1; // HOLD#/RESET# inactive.
    readonly_flash_reader_core #(
        .DUMP_BYTES(25'd16777216), .UART_CLKS(434), .SPI_HALF_CLKS(25)
    ) u_reader (
        .clk(clk_50mhz), .rst_n(reset_release_q[1]),
        .uart_rx(uart_rx), .uart_tx(reader_uart),
        .flash_csn(reader_csn), .flash_sclk(reader_sclk),
        .flash_mosi(flash_mosi), .flash_miso(flash_dq[1])
    );
endmodule

// Parameters permit a short simulation. Only the nonparameterized top above is
// included as synthesis top; its capacity is exactly 16 MiB, starting at zero.
module readonly_flash_reader_core #(
    parameter logic [24:0] DUMP_BYTES = 25'd16777216,
    parameter integer UART_CLKS = 434,
    parameter integer SPI_HALF_CLKS = 25
) (
    input wire clk, input wire rst_n,
    input wire uart_rx, output wire uart_tx,
    output logic flash_csn, output wire flash_sclk,
    output wire flash_mosi, input wire flash_miso
);
    typedef enum logic [3:0] {
        IDLE, ID_CMD, ID_CMD_WAIT, ID_BYTE, ID_BYTE_WAIT,
        HEADER, READ_CMD, READ_CMD_WAIT, ADDRESS, ADDRESS_WAIT,
        DATA_READ, DATA_WAIT, DATA_SEND, TRAILER, DRAIN
    } state_t;
    state_t state_q;
    wire rx_valid, tx_ready;
    wire [7:0] rx_byte;
    logic tx_valid;
    logic [7:0] tx_byte;
    fixed_uart_rx #(.CLKS_PER_BIT(UART_CLKS)) u_rx (
        .clk(clk), .rst_n(rst_n), .serial_i(uart_rx),
        .byte_valid_o(rx_valid), .byte_o(rx_byte)
    );
    fixed_uart_tx #(.CLKS_PER_BIT(UART_CLKS)) u_tx (
        .clk(clk), .rst_n(rst_n), .byte_valid_i(tx_valid),
        .byte_ready_o(tx_ready), .byte_i(tx_byte), .serial_o(uart_tx)
    );
    logic spi_start;
    logic [7:0] spi_tx;
    wire spi_done;
    wire [7:0] spi_rx;
    readonly_spi_byte #(.HALF_CLKS(SPI_HALF_CLKS)) u_spi (
        .clk(clk), .rst_n(rst_n), .start_i(spi_start), .tx_i(spi_tx),
        .done_o(spi_done), .rx_o(spi_rx), .sclk_o(flash_sclk),
        .mosi_o(flash_mosi), .miso_i(flash_miso)
    );
    logic [7:0] id_q [0:2];
    logic [1:0] index_q;
    logic [3:0] header_q;
    logic [24:0] count_q;
    logic [7:0] data_q;
    logic [31:0] crc_q;
    wire [31:0] final_crc = ~crc_q;
    localparam logic [31:0] LENGTH = {7'b0, DUMP_BYTES};
    function automatic [31:0] crc_byte(input [31:0] prior, input [7:0] value);
        reg [31:0] c;
        integer bit_index;
        begin
            c = prior ^ {24'b0, value};
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1)
                c = c[0] ? ((c >> 1) ^ 32'hedb88320) : (c >> 1);
            crc_byte = c;
        end
    endfunction
    always_comb begin
        spi_start = 1'b0;
        spi_tx = 8'h00;
        tx_valid = 1'b0;
        tx_byte = 8'h00;
        case (state_q)
            ID_CMD: begin spi_start = 1'b1; spi_tx = 8'h9f; end
            READ_CMD: begin spi_start = 1'b1; spi_tx = 8'h03; end
            ID_BYTE, ADDRESS, DATA_READ: spi_start = 1'b1;
            HEADER: begin
                tx_valid = 1'b1;
                case (header_q)
                    0: tx_byte = 8'h54;
                    1: tx_byte = 8'h46;
                    2: tx_byte = 8'h44;
                    3: tx_byte = 8'h31;
                    4: tx_byte = id_q[0];
                    5: tx_byte = id_q[1];
                    6: tx_byte = id_q[2];
                    7: tx_byte = 8'h00;
                    8: tx_byte = LENGTH[7:0];
                    9: tx_byte = LENGTH[15:8];
                    10: tx_byte = LENGTH[23:16];
                    11: tx_byte = LENGTH[31:24];
                    default: tx_byte = 8'h00;
                endcase
            end
            DATA_SEND: begin tx_valid = 1'b1; tx_byte = data_q; end
            TRAILER: begin
                tx_valid = 1'b1;
                case (index_q)
                    0: tx_byte = final_crc[7:0];
                    1: tx_byte = final_crc[15:8];
                    2: tx_byte = final_crc[23:16];
                    3: tx_byte = final_crc[31:24];
                endcase
            end
            default: begin end
        endcase
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= IDLE;
            flash_csn <= 1'b1;
            id_q[0] <= 0; id_q[1] <= 0; id_q[2] <= 0;
            index_q <= 0; header_q <= 0; count_q <= 0;
            data_q <= 0; crc_q <= 32'hffffffff;
        end else begin
            case (state_q)
                IDLE: if (rx_valid && rx_byte == 8'h52) begin
                    flash_csn <= 1'b0;
                    index_q <= 0; header_q <= 0; count_q <= 0;
                    crc_q <= 32'hffffffff;
                    state_q <= ID_CMD;
                end
                ID_CMD: state_q <= ID_CMD_WAIT;
                ID_CMD_WAIT: if (spi_done) state_q <= ID_BYTE;
                ID_BYTE: state_q <= ID_BYTE_WAIT;
                ID_BYTE_WAIT: if (spi_done) begin
                    id_q[index_q] <= spi_rx;
                    if (index_q == 2) begin
                        flash_csn <= 1'b1;
                        state_q <= HEADER;
                    end else begin
                        index_q <= index_q + 1'b1;
                        state_q <= ID_BYTE;
                    end
                end
                HEADER: if (tx_ready) begin
                    if (header_q == 11) begin
                        // Fitted XTX 128-Mbit device. A failed/mismatched ID
                        // still reports the header, but never starts data SPI.
                        if ({id_q[0], id_q[1], id_q[2]} == 24'h0b4018) begin
                            flash_csn <= 1'b0;
                            state_q <= READ_CMD;
                        end else state_q <= DRAIN;
                    end else header_q <= header_q + 1'b1;
                end
                READ_CMD: state_q <= READ_CMD_WAIT;
                READ_CMD_WAIT: if (spi_done) begin
                    index_q <= 0;
                    state_q <= ADDRESS;
                end
                ADDRESS: state_q <= ADDRESS_WAIT;
                ADDRESS_WAIT: if (spi_done) begin
                    if (index_q == 2) state_q <= DATA_READ;
                    else begin index_q <= index_q + 1'b1; state_q <= ADDRESS; end
                end
                DATA_READ: state_q <= DATA_WAIT;
                DATA_WAIT: if (spi_done) begin
                    data_q <= spi_rx;
                    crc_q <= crc_byte(crc_q, spi_rx);
                    state_q <= DATA_SEND;
                end
                DATA_SEND: if (tx_ready) begin
                    if (count_q == DUMP_BYTES - 1'b1) begin
                        flash_csn <= 1'b1;
                        index_q <= 0;
                        state_q <= TRAILER;
                    end else begin
                        count_q <= count_q + 1'b1;
                        state_q <= DATA_READ;
                    end
                end
                TRAILER: if (tx_ready) begin
                    if (index_q == 3) state_q <= DRAIN;
                    else index_q <= index_q + 1'b1;
                end
                DRAIN: if (tx_ready) state_q <= IDLE;
                default: begin state_q <= IDLE; flash_csn <= 1'b1; end
            endcase
        end
    end
endmodule

// Mode-0 byte engine. MOSI changes only with SCK low/falling; MISO samples on
// rising edges. SCK returns low after every byte, allowing arbitrary pauses.
module readonly_spi_byte #(parameter integer HALF_CLKS = 25) (
    input wire clk, input wire rst_n,
    input wire start_i, input wire [7:0] tx_i,
    output logic done_o, output logic [7:0] rx_o,
    output logic sclk_o, output logic mosi_o, input wire miso_i
);
    localparam integer CW = $clog2(HALF_CLKS + 1);
    logic [CW-1:0] divider_q;
    logic [2:0] bit_q;
    logic [7:0] tx_q, rx_q;
    logic busy_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            divider_q <= 0; bit_q <= 0; tx_q <= 0; rx_q <= 0;
            busy_q <= 1'b0; done_o <= 1'b0; rx_o <= 0;
            sclk_o <= 1'b0; mosi_o <= 1'b0;
        end else begin
            done_o <= 1'b0;
            if (!busy_q) begin
                if (start_i) begin
                    busy_q <= 1'b1; tx_q <= tx_i; rx_q <= 0;
                    mosi_o <= tx_i[7]; bit_q <= 7;
                    divider_q <= CW'(HALF_CLKS - 1);
                end
            end else if (divider_q != 0) divider_q <= divider_q - 1'b1;
            else begin
                divider_q <= CW'(HALF_CLKS - 1);
                if (!sclk_o) begin
                    sclk_o <= 1'b1;
                    rx_q <= {rx_q[6:0], miso_i};
                end else begin
                    sclk_o <= 1'b0;
                    if (bit_q == 0) begin
                        busy_q <= 1'b0; done_o <= 1'b1;
                        rx_o <= rx_q; mosi_o <= 1'b0;
                    end else begin
                        bit_q <= bit_q - 1'b1;
                        tx_q <= {tx_q[6:0], 1'b0};
                        mosi_o <= tx_q[6];
                    end
                end
            end
        end
    end
endmodule
`default_nettype wire
