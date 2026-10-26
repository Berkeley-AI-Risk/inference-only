`timescale 1ns/1ps
`default_nettype none

// PRIVATE building block, not a public interface or standalone trust root.
// The parent supplies the expected digest from its FPGA-local fixed ROM.
// The same RAM is written, sealed, hashed, and only then read by inference.
// Cancel drops read validity only; it never clears an integrity fault.
module board1_verified_page_bank #(
    parameter integer IMAGE_WORDS=227062
) (
    input wire clk, reset_n, cancel_read_i,
    input wire begin_valid_i,
    output wire begin_ready_o,
    input wire [10:0] begin_page_i,
    input wire [255:0] expected_digest_i,
    input wire fill_valid_i,
    output wire fill_ready_o,
    input wire [255:0] fill_data_i,
    input wire fill_last_i,
    input wire read_valid_i,
    output wire read_ready_o,
    input wire [6:0] read_word_i,
    output wire response_valid_o,
    input wire response_ready_i,
    output wire [255:0] response_data_o,
    output wire assigned_o, verified_o,
    output logic [10:0] page_o,
    output logic fault_o
);
    localparam integer PAGES=(IMAGE_WORDS+127)/128;
    localparam [3:0] EMPTY=0,FILL=1,ZERO=2,READ0=3,READ1=4,CAP1=5,
        LAUNCH=6,HASH=7,COMPARE=8,READY=9,FAILED=15;
    localparam [255:0] SHA_IV=256'h6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19;
    localparam [511:0] PADDING={8'h80,440'd0,64'd32768};
    logic [3:0] state_q;
    logic [7:0] valid_words_q, fill_count_q;
    logic [6:0] block_q;
    logic [15:0] hash_watchdog_q;
    logic response_valid_q;
    logic [255:0] expected_q, chain_q;
    logic [7:0] digest_match_q;
    logic [511:0] sha_block_q;
    (* nomem2reg, ram_style="block" *) logic [255:0] memory_q [0:127];
    logic [255:0] read_data_q;
    wire sha_busy,sha_done;
    wire [255:0] sha_state;
    wire begin_fire=begin_valid_i && begin_ready_o;
    wire fill_fire=fill_valid_i && fill_ready_o;
    wire read_fire=read_valid_i && read_ready_o;
    wire fill_error=fill_fire && (fill_last_i != (fill_count_q==valid_words_q-8'd1));
    wire read_error=read_fire && ({1'b0,read_word_i}>=valid_words_q);
    wire digest_error=state_q==COMPARE && !(&digest_match_q);
    wire hash_active=state_q>=READ0 && state_q<=COMPARE;
    wire protocol_error=(fill_valid_i && !fill_ready_o) || fill_error || read_error ||
        (begin_fire && 32'(begin_page_i)>=PAGES) ||
        (state_q==LAUNCH && sha_busy) ||
        (hash_active && hash_watchdog_q==16'hffff);

    assign assigned_o=state_q!=EMPTY && state_q!=FAILED && !fault_o;
    assign verified_o=state_q==READY && !fault_o;
    // Refill owns this private arbitration when both inputs are asserted.
    // Begin readiness depends only on local state, never a consumer's address
    // decode. A held old response still prevents eviction; an unaccepted read
    // remains queued in the parent and is retried against the new page tag.
    assign begin_ready_o=(state_q==EMPTY || state_q==READY) && !fault_o &&
        !response_valid_q && !sha_busy;
    assign fill_ready_o=state_q==FILL && !fault_o;
    assign read_ready_o=verified_o && !cancel_read_i && !begin_valid_i &&
        (!response_valid_q || response_ready_i);
    assign response_valid_o=response_valid_q && verified_o && !cancel_read_i;
    assign response_data_o=response_valid_o ? read_data_q : 256'd0;

    function automatic [255:0] bytes_big_endian(input [255:0] word);
        integer i;
        for(i=0;i<32;i=i+1) bytes_big_endian[255-i*8 -: 8]=word[i*8 +: 8];
    endfunction

    // Present exactly one read port and one write port to native inference.
    // Multiple mutually exclusive array references otherwise mapped to DFFs
    // in Gowin 1.9.11.03, despite having the same sequential behavior.
    wire memory_write=fill_fire || state_q==ZERO;
    wire [255:0] memory_write_data=fill_fire ? fill_data_i : 256'd0;
    wire memory_read=state_q==READ0 || state_q==READ1 || (read_fire && !read_error);
    wire [6:0] memory_read_address=state_q==READ0 ? {block_q[5:0],1'b0} :
        (state_q==READ1 ? {block_q[5:0],1'b1} : read_word_i);
    // No RAM data reset; validity and the complete fill dominate every read.
    always_ff @(posedge clk) begin
        if(memory_write) memory_q[fill_count_q[6:0]]<=memory_write_data;
        if(memory_read) read_data_q<=memory_q[memory_read_address];
        if(begin_fire) begin
            expected_q<=expected_digest_i;chain_q<=SHA_IV;page_o<=begin_page_i;
            valid_words_q<=begin_page_i==11'(PAGES-1) ? 8'(IMAGE_WORDS-(PAGES-1)*128) : 8'd128;
        end
        if(state_q==READ1) sha_block_q[511:256]<=bytes_big_endian(read_data_q);
        if(state_q==CAP1) sha_block_q[255:0]<=bytes_big_endian(read_data_q);
        if(state_q==HASH && sha_done) begin
            chain_q<=sha_state;
            if(block_q==63) sha_block_q<=PADDING;
        end
    end

    board1_sha256_bank_owned_compress #(.REGISTER_RESULT(0)) u_sha (
        .clk_i(clk), .reset_n_i(reset_n), .start_i(state_q==LAUNCH && !fault_o),
        .block_i(sha_block_q), .state_i(chain_q), .busy_o(sha_busy),
        .done_o(sha_done), .state_o(sha_state));

    // The last HASH -> COMPARE edge already exists. Capture eight local
    // equality results there; COMPARE must see all eight before granting
    // VERIFIED. No unchecked data or extra externally visible operation is
    // introduced. These resetless bits are never read before this capture.
    generate for(genvar d=0;d<8;d=d+1) begin: g_digest_compare
        always_ff @(posedge clk) begin
            if(state_q==HASH && sha_done && block_q==64)
                digest_match_q[d]<=sha_state[d*32 +: 32]==expected_q[d*32 +: 32];
        end
    end endgenerate

`ifndef SYNTHESIS
    logic x_error;
    always @* begin
        x_error=$isunknown(cancel_read_i) || $isunknown(begin_valid_i) ||
            $isunknown(fill_valid_i) || $isunknown(read_valid_i);
        if(begin_valid_i) x_error=x_error || $isunknown(begin_page_i) || $isunknown(expected_digest_i);
        if(fill_valid_i) x_error=x_error || $isunknown(fill_data_i) || $isunknown(fill_last_i);
        if(read_valid_i) x_error=x_error || $isunknown(read_word_i);
        if(response_valid_o) x_error=x_error || $isunknown(response_ready_i);
        if(state_q==COMPARE) x_error=x_error || $isunknown(sha_state) ||
            $isunknown(expected_q) || $isunknown(digest_match_q);
    end
`endif
    // Counters describe private in-flight work, not permission to expose it.
    // Keep their local enables independent of the 256-bit digest comparator.
    // A failure still changes state/validity atomically in the block below;
    // any counter update on that edge is unreachable after FAILED.
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin fill_count_q<=0;block_q<=0;hash_watchdog_q<=0;end
        else begin
            if(begin_fire) begin fill_count_q<=0;block_q<=0;end
            else begin
                if(fill_fire || state_q==ZERO) fill_count_q<=fill_count_q+8'd1;
                if(state_q==HASH && sha_done && block_q!=64) block_q<=block_q+7'd1;
            end
            if(hash_active) hash_watchdog_q<=hash_watchdog_q+16'd1;
            else hash_watchdog_q<=0;
        end
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=EMPTY; fault_o<=0; response_valid_q<=0;
        end else if(fault_o || protocol_error || digest_error
`ifndef SYNTHESIS
                    || x_error
`endif
        ) begin
            state_q<=FAILED; fault_o<=1; response_valid_q<=0;
        end else begin
            if(cancel_read_i) response_valid_q<=0;
            // An old response must drain even while begin_valid blocks a new
            // read; otherwise a waiting refill and response would deadlock.
            else if(!response_valid_q || response_ready_i) response_valid_q<=read_fire;
            case(state_q)
                EMPTY,READY: if(begin_fire) begin
                    response_valid_q<=0; state_q<=FILL;
                end
                FILL: if(fill_fire) begin
                    if(fill_count_q==valid_words_q-8'd1)
                        state_q<=valid_words_q==128 ? READ0 : ZERO;
                end
                ZERO: begin
                    if(fill_count_q==127) state_q<=READ0;
                end
                READ0: state_q<=READ1;
                READ1: state_q<=CAP1;
                CAP1: state_q<=LAUNCH;
                LAUNCH: state_q<=HASH;
                HASH: if(sha_done) begin
                    if(block_q==64) state_q<=COMPARE;
                    else begin
                        state_q<=block_q==63 ? LAUNCH : READ0;
                    end
                end
                COMPARE: state_q<=READY;
                default: begin state_q<=FAILED; fault_o<=1; response_valid_q<=0; end
            endcase
        end
    end
    initial begin
        if(IMAGE_WORDS<1 || PAGES>2048) $fatal(1,"fixed image outside page geometry");
    end
endmodule
`default_nettype wire
