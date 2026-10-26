`timescale 1ns/1ps
`default_nettype none

// Fixed four-entry, 256-bit asynchronous FIFO used only between the trusted
// QSPI/authentication domain and the 100 MHz DDR application domain.  Neither
// pointer nor storage is externally addressable.
module board1_qspi_async_word_fifo4 (
    input  wire         write_clk_i,
    input  wire         write_reset_n_i,
    input  wire [255:0] write_data_i,
    input  wire         write_valid_i,
    output wire         write_ready_o,

    input  wire         read_clk_i,
    input  wire         read_reset_n_i,
    output wire [255:0] read_data_o,
    output wire         read_valid_o,
    input  wire         read_ready_i
);
    logic [255:0] storage_q [0:3];
    logic [2:0] write_binary_q;
    // Preserve all three named Gray source bits.  In particular Gray[2] is
    // equal to binary[2], so an unconstrained optimizer can merge the source
    // register and make a name-based CDC audit cover only two bits.
    (* keep = "true", syn_preserve = 1 *) logic [2:0] write_gray_q;
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] read_gray_write_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] read_gray_write_sync2_q;
    logic write_full_q;

    logic [2:0] read_binary_q;
    (* keep = "true", syn_preserve = 1 *) logic [2:0] read_gray_q;
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] write_gray_read_sync1_q;
    (* async_reg = "true", syn_preserve = 1 *) logic [2:0] write_gray_read_sync2_q;
    logic read_empty_q;
    // Destination-domain capture is intentional.  The synchronized Gray
    // pointer cannot make an entry visible until the corresponding storage
    // word has had two read-clock synchronizer intervals to settle.  Capture
    // the current/prefetched word in read-domain FFs before asserting valid;
    // never expose the dual-clock storage array combinationally.
    (* syn_preserve = 1 *) logic [255:0] read_data_q;

    wire write_transfer = write_valid_i && write_ready_o;
    wire [2:0] write_binary_next = write_binary_q + write_transfer;
    wire [2:0] write_gray_next =
        (write_binary_next >> 1) ^ write_binary_next;
    wire write_full_next =
        write_gray_next == {~read_gray_write_sync2_q[2:1],
                            read_gray_write_sync2_q[0]};

    wire read_transfer = read_valid_o && read_ready_i;
    wire [2:0] read_binary_next = read_binary_q + read_transfer;
    wire [2:0] read_gray_next =
        (read_binary_next >> 1) ^ read_binary_next;
    wire read_empty_next = read_gray_next == write_gray_read_sync2_q;

    assign write_ready_o = !write_full_q;
    assign read_valid_o = !read_empty_q;
    assign read_data_o = read_data_q;

    always_ff @(posedge write_clk_i or negedge write_reset_n_i) begin
        if (!write_reset_n_i) begin
            write_binary_q <= 3'd0;
            write_gray_q <= 3'd0;
            read_gray_write_sync1_q <= 3'd0;
            read_gray_write_sync2_q <= 3'd0;
            write_full_q <= 1'b0;
        end else begin
            read_gray_write_sync1_q <= read_gray_q;
            read_gray_write_sync2_q <= read_gray_write_sync1_q;
            if (write_transfer)
                storage_q[write_binary_q[1:0]] <= write_data_i;
            write_binary_q <= write_binary_next;
            write_gray_q <= write_gray_next;
            write_full_q <= write_full_next;
        end
    end

    always_ff @(posedge read_clk_i or negedge read_reset_n_i) begin
        if (!read_reset_n_i) begin
            read_binary_q <= 3'd0;
            read_gray_q <= 3'd0;
            write_gray_read_sync1_q <= 3'd0;
            write_gray_read_sync2_q <= 3'd0;
            read_empty_q <= 1'b1;
            read_data_q <= 256'd0;
        end else begin
            write_gray_read_sync1_q <= write_gray_q;
            write_gray_read_sync2_q <= write_gray_read_sync1_q;
            read_binary_q <= read_binary_next;
            read_gray_q <= read_gray_next;
            read_empty_q <= read_empty_next;
            // On empty->nonempty this captures the first settled word in the
            // same edge that makes valid visible.  On transfer it prefetches
            // the next word selected by read_binary_next.
            read_data_q <= storage_q[read_binary_next[1:0]];
        end
    end

`ifdef FORMAL
    always_ff @(posedge write_clk_i) begin
        if (write_reset_n_i)
            assert (!(write_transfer && write_full_q));
    end
    always_ff @(posedge read_clk_i) begin
        if (read_reset_n_i)
            assert (!(read_transfer && read_empty_q));
    end
`endif
endmodule

`default_nettype wire
