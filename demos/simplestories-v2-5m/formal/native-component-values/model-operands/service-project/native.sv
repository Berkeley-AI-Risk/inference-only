`undef FORMAL
`default_nettype none
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
    // Private preparation of the next sealed 512-bit SHA block. The current
    // compressor captures its entire input at LAUNCH, so these later reads
    // cannot alter the compression in progress. Phase4 is the completed pair.
    logic [2:0] prefetch_q;
    wire [5:0] next_block=block_q[5:0]+6'd1;
    wire prefetch_read0=state_q==HASH && prefetch_q==3'd1;
    wire prefetch_read1=state_q==HASH && prefetch_q==3'd2;
    wire prefetch_capture1=state_q==HASH && prefetch_q==3'd3;
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
        (state_q==HASH && sha_done && block_q<63 && prefetch_q!=3'd4) ||
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
    wire memory_read=state_q==READ0 || state_q==READ1 ||
        prefetch_read0 || prefetch_read1 || (read_fire && !read_error);
    wire [6:0] memory_read_address=state_q==READ0 ? {block_q[5:0],1'b0} :
        (state_q==READ1 ? {block_q[5:0],1'b1} :
        (prefetch_read0 ? {next_block,1'b0} :
        (prefetch_read1 ? {next_block,1'b1} : read_word_i)));
    // No RAM data reset; validity and the complete fill dominate every read.
    always_ff @(posedge clk) begin
        if(memory_write) memory_q[fill_count_q[6:0]]<=memory_write_data;
        if(memory_read) read_data_q<=memory_q[memory_read_address];
        if(begin_fire) begin
            expected_q<=expected_digest_i;chain_q<=SHA_IV;page_o<=begin_page_i;
            valid_words_q<=begin_page_i==11'(PAGES-1) ? 8'(IMAGE_WORDS-(PAGES-1)*128) : 8'd128;
        end
        if(state_q==READ1 || prefetch_read1) sha_block_q[511:256]<=bytes_big_endian(read_data_q);
        if(state_q==CAP1 || prefetch_capture1) sha_block_q[255:0]<=bytes_big_endian(read_data_q);
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
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) prefetch_q<=0;
        else if(begin_fire) prefetch_q<=0;
        else if(state_q==LAUNCH) prefetch_q<=block_q<63 ? 3'd1 : 3'd0;
        else if(state_q==HASH && prefetch_q!=0 && prefetch_q<4)
            prefetch_q<=prefetch_q+3'd1;
    end

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
                        // The next data block was read while SHA was
                        // busy; block63 instead installs the fixed padding.
                        state_q<=LAUNCH;
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

module board1_sha256_bank_owned_compress #(parameter integer REGISTER_RESULT=0) (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] state_i,
    output logic        busy_o,
    output logic        done_o,
    output wire [255:0] state_o
);
    logic [31:0] schedule_q [0:15];
    logic [31:0] a_q, b_q, c_q, d_q, e_q, f_q, g_q, h_q;
    logic [5:0] round_q;
    integer index;

    function automatic [31:0] ror(input [31:0] value,
                                  input integer amount);
        ror = (value >> amount) | (value << (32 - amount));
    endfunction

    function automatic [31:0] choose(input [31:0] x, input [31:0] y,
                                      input [31:0] z);
        choose = (x & y) ^ (~x & z);
    endfunction

    function automatic [31:0] majority(input [31:0] x, input [31:0] y,
                                        input [31:0] z);
        majority = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = ror(x, 2) ^ ror(x, 13) ^ ror(x, 22);
    endfunction

    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = ror(x, 6) ^ ror(x, 11) ^ ror(x, 25);
    endfunction

    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = ror(x, 7) ^ ror(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = ror(x, 17) ^ ror(x, 19) ^ (x >> 10);
    endfunction

    function automatic [31:0] round_constant(input [5:0] n);
        case (n)
            6'd0:  round_constant = 32'h428a2f98;
            6'd1:  round_constant = 32'h71374491;
            6'd2:  round_constant = 32'hb5c0fbcf;
            6'd3:  round_constant = 32'he9b5dba5;
            6'd4:  round_constant = 32'h3956c25b;
            6'd5:  round_constant = 32'h59f111f1;
            6'd6:  round_constant = 32'h923f82a4;
            6'd7:  round_constant = 32'hab1c5ed5;
            6'd8:  round_constant = 32'hd807aa98;
            6'd9:  round_constant = 32'h12835b01;
            6'd10: round_constant = 32'h243185be;
            6'd11: round_constant = 32'h550c7dc3;
            6'd12: round_constant = 32'h72be5d74;
            6'd13: round_constant = 32'h80deb1fe;
            6'd14: round_constant = 32'h9bdc06a7;
            6'd15: round_constant = 32'hc19bf174;
            6'd16: round_constant = 32'he49b69c1;
            6'd17: round_constant = 32'hefbe4786;
            6'd18: round_constant = 32'h0fc19dc6;
            6'd19: round_constant = 32'h240ca1cc;
            6'd20: round_constant = 32'h2de92c6f;
            6'd21: round_constant = 32'h4a7484aa;
            6'd22: round_constant = 32'h5cb0a9dc;
            6'd23: round_constant = 32'h76f988da;
            6'd24: round_constant = 32'h983e5152;
            6'd25: round_constant = 32'ha831c66d;
            6'd26: round_constant = 32'hb00327c8;
            6'd27: round_constant = 32'hbf597fc7;
            6'd28: round_constant = 32'hc6e00bf3;
            6'd29: round_constant = 32'hd5a79147;
            6'd30: round_constant = 32'h06ca6351;
            6'd31: round_constant = 32'h14292967;
            6'd32: round_constant = 32'h27b70a85;
            6'd33: round_constant = 32'h2e1b2138;
            6'd34: round_constant = 32'h4d2c6dfc;
            6'd35: round_constant = 32'h53380d13;
            6'd36: round_constant = 32'h650a7354;
            6'd37: round_constant = 32'h766a0abb;
            6'd38: round_constant = 32'h81c2c92e;
            6'd39: round_constant = 32'h92722c85;
            6'd40: round_constant = 32'ha2bfe8a1;
            6'd41: round_constant = 32'ha81a664b;
            6'd42: round_constant = 32'hc24b8b70;
            6'd43: round_constant = 32'hc76c51a3;
            6'd44: round_constant = 32'hd192e819;
            6'd45: round_constant = 32'hd6990624;
            6'd46: round_constant = 32'hf40e3585;
            6'd47: round_constant = 32'h106aa070;
            6'd48: round_constant = 32'h19a4c116;
            6'd49: round_constant = 32'h1e376c08;
            6'd50: round_constant = 32'h2748774c;
            6'd51: round_constant = 32'h34b0bcb5;
            6'd52: round_constant = 32'h391c0cb3;
            6'd53: round_constant = 32'h4ed8aa4a;
            6'd54: round_constant = 32'h5b9cca4f;
            6'd55: round_constant = 32'h682e6ff3;
            6'd56: round_constant = 32'h748f82ee;
            6'd57: round_constant = 32'h78a5636f;
            6'd58: round_constant = 32'h84c87814;
            6'd59: round_constant = 32'h8cc70208;
            6'd60: round_constant = 32'h90befffa;
            6'd61: round_constant = 32'ha4506ceb;
            6'd62: round_constant = 32'hbef9a3f7;
            default: round_constant = 32'hc67178f2;
        endcase
    endfunction

    wire [31:0] schedule_next0 = small_sigma1(schedule_q[14]) + schedule_q[9] + small_sigma0(schedule_q[1]) + schedule_q[0];
    wire [31:0] schedule_next1 = small_sigma1(schedule_q[15]) + schedule_q[10] + small_sigma0(schedule_q[2]) + schedule_q[1];
    wire [31:0] temp1_r1 = h_q + big_sigma1(e_q) + choose(e_q, f_q, g_q) +
        round_constant(round_q + 6'd0) + schedule_q[0];
    wire [31:0] temp2_r1 = big_sigma0(a_q) + majority(a_q, b_q, c_q);
    wire [31:0] a_r1 = temp1_r1 + temp2_r1;
    wire [31:0] b_r1 = a_q;
    wire [31:0] c_r1 = b_q;
    wire [31:0] d_r1 = c_q;
    wire [31:0] e_r1 = d_q + temp1_r1;
    wire [31:0] f_r1 = e_q;
    wire [31:0] g_r1 = f_q;
    wire [31:0] h_r1 = g_q;
    wire [31:0] temp1_r2 = h_r1 + big_sigma1(e_r1) + choose(e_r1, f_r1, g_r1) +
        round_constant(round_q + 6'd1) + schedule_q[1];
    wire [31:0] temp2_r2 = big_sigma0(a_r1) + majority(a_r1, b_r1, c_r1);
    wire [31:0] a_r2 = temp1_r2 + temp2_r2;
    wire [31:0] b_r2 = a_r1;
    wire [31:0] c_r2 = b_r1;
    wire [31:0] d_r2 = c_r1;
    wire [31:0] e_r2 = d_r1 + temp1_r2;
    wire [31:0] f_r2 = e_r1;
    wire [31:0] g_r2 = f_r1;
    wire [31:0] h_r2 = g_r1;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            a_q <= 32'd0;
            b_q <= 32'd0;
            c_q <= 32'd0;
            d_q <= 32'd0;
            e_q <= 32'd0;
            f_q <= 32'd0;
            g_q <= 32'd0;
            h_q <= 32'd0;
            round_q <= 6'd0;
            for (index = 0; index < 16; index = index + 1)
                schedule_q[index] <= 32'd0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_o) begin
                for (index = 0; index < 16; index = index + 1)
                    schedule_q[index] <=
                        block_i[511 - index * 32 -: 32];
                a_q <= state_i[255:224];
                b_q <= state_i[223:192];
                c_q <= state_i[191:160];
                d_q <= state_i[159:128];
                e_q <= state_i[127:96];
                f_q <= state_i[95:64];
                g_q <= state_i[63:32];
                h_q <= state_i[31:0];
                round_q <= 6'd0;
                busy_o <= 1'b1;
            end else if (busy_o) begin
                for (index = 0; index < 14; index = index + 1)
                    schedule_q[index] <= schedule_q[index + 2];
                schedule_q[14] <= schedule_next0;
                schedule_q[15] <= schedule_next1;
                a_q <= a_r2;
                b_q <= b_r2;
                c_q <= c_r2;
                d_q <= d_r2;
                e_q <= e_r2;
                f_q <= f_r2;
                g_q <= g_r2;
                h_q <= h_r2;
                if (round_q == 6'd62) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    round_q <= round_q + 6'd2;
                end
            end
        end
    end

    // PRIVATE owner contract: the enclosing page bank holds state_i from
    // an accepted START through the DONE-consumption edge. This is not the
    // reusable compressor's arbitrary-changing-input contract.
    generate if (REGISTER_RESULT != 0) begin : g_registered_result
        logic [255:0] result_q;
        assign state_o = result_q;
        always_ff @(posedge clk_i or negedge reset_n_i) begin
            if (!reset_n_i) result_q <= 256'd0;
            else if (busy_o && round_q == 6'd62) begin
                    result_q <= {
                        state_i[255:224] + a_r2,
                        state_i[223:192] + b_r2,
                        state_i[191:160] + c_r2,
                        state_i[159:128] + d_r2,
                        state_i[127:96] + e_r2,
                        state_i[95:64] + f_r2,
                        state_i[63:32] + g_r2,
                        state_i[31:0] + h_r2
                    };
            end
        end
    end else begin : g_bank_captures_result
        // On DONE the working registers already hold round 63's completed
        // a..h. The bank captures these eight sums at its unchanged edge.
        // Outside DONE this private bus is unspecified, not a valid digest.
        assign state_o = {
            state_i[255:224] + a_q, state_i[223:192] + b_q,
            state_i[191:160] + c_q, state_i[159:128] + d_q,
            state_i[127:96] + e_q, state_i[95:64] + f_q,
            state_i[63:32] + g_q, state_i[31:0] + h_q
        };
    end endgenerate

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (!(busy_o && done_o));
            if (busy_o) begin
                assert (round_q <= 6'd62);
                assert (round_q[0] == 1'b0);
            end
        end
    end
`endif
endmodule

module board1_verified_ddr_page_service #(
    parameter integer BANKS=8,
    parameter integer ADDR_W=25,
    parameter integer IMAGE_WORDS=227062,
    parameter integer WEIGHT_WORDS=211800,
    parameter integer MAX_OUTSTANDING=32,
    parameter integer DDR_WATCHDOG_CYCLES=50000000,
    parameter DIGEST_HEX="digests32.memh",
    parameter integer LOCAL_METADATA=1,
    parameter METADATA_HEX="metadata192.memh"
) (
    input wire clk,reset_n,cancel_i,model_locked_i,
    input wire request_valid_i,
    output wire request_ready_o,
    input wire [ADDR_W-1:0] request_word_i,
    output wire response_valid_o,
    input wire response_ready_i,
    output wire [255:0] response_data_o,
    output wire ddr_request_valid_o,
    input wire ddr_request_ready_i,
    output wire [ADDR_W-1:0] ddr_request_word_o,
    input wire ddr_response_valid_i,
    input wire [255:0] ddr_response_data_i,
    input wire ddr_response_error_i,
    output wire fault_o
);
    localparam integer BANK_W=$clog2(BANKS);
    localparam integer PAGES=(IMAGE_WORDS+127)/128;
    localparam integer WEIGHT_PAGES=(WEIGHT_WORDS+127)/128;
    localparam integer WATCH_W=$clog2(DDR_WATCHDOG_CYCLES+1);
    localparam [2:0] IDLE=0,ROM_READ=1,ROM_CAPTURE=2,ALLOCATE=3,FILL=4,SCAN=5;
    logic [2:0] dma_state_q;
    logic fault_q,locked_seen_q;
    wire [BANKS-1:0] bank_begin_ready,bank_fill_ready,bank_read_ready;
    wire [BANKS-1:0] bank_assigned,bank_verified,bank_fault,bank_response_valid;
    logic [BANKS-1:0] bank_begin_valid,bank_fill_valid,bank_read_valid,bank_response_ready;
    wire [10:0] bank_page [0:BANKS-1];
    wire [255:0] bank_response_data [0:BANKS-1];
    wire enabled=model_locked_i && !fault_o;
    assign fault_o=fault_q || (|bank_fault);

    // Payload is resetless; only pointers/counts are reset or cancelled.
    (* ram_style="distributed" *) logic [17:0] request_fifo [0:63];
    logic [5:0] request_write_q,request_read_q;
    logic [6:0] request_count_q;
    logic [17:0] head_word;
    logic head_valid_q;
    // Explicit registered FIFO head breaks the async RAM -> selected bank
    // ready -> pop/pointer feedback timing path. It permits one consumed word
    // every two clocks; measure the end-to-end trade-off against routed MHz.
    wire head_load=enabled && !cancel_i && !head_valid_q && request_count_q!=0;
    wire [10:0] head_page=head_word[17:7];
    wire [BANK_W-1:0] head_bank=head_page[BANK_W-1:0];
    logic [BANK_W:0] response_fifo [0:31];
    logic [4:0] response_write_q,response_read_q;
    logic [5:0] response_count_q;
    wire [BANK_W:0] response_source=response_fifo[response_read_q];
    wire [BANK_W-1:0] response_bank=response_source[BANK_W-1:0];
    wire metadata_head=LOCAL_METADATA!=0 && head_word>=18'd211920 && head_word<18'd214248;
    wire metadata_ready,metadata_valid;
    wire [255:0] metadata_data;
    wire metadata_read=enabled && !cancel_i && head_valid_q && response_count_q<6'd32 &&
        metadata_head && metadata_ready;
    wire metadata_response_ready=enabled && !cancel_i && response_count_q!=0 &&
        response_source[BANK_W] && response_ready_i;
    wire request_fire=request_valid_i && request_ready_o;
    wire response_fire=response_valid_o && response_ready_i;
    wire read_fire=(| (bank_read_valid & bank_read_ready)) || metadata_read;
    assign request_ready_o=enabled && !cancel_i && request_count_q<7'd64;
    assign response_valid_o=enabled && !cancel_i && response_count_q!=0 &&
        (response_source[BANK_W] ? metadata_valid : bank_response_valid[response_bank]);
    assign response_data_o=response_valid_o ?
        (response_source[BANK_W] ? metadata_data : bank_response_data[response_bank]) : 256'd0;

    // The fixed projection row scales/exponents are only 55,872 useful bytes.
    // Keep them in immutable on-chip ROM instead of evicting streaming pages
    // and rehashing a metadata page at each group boundary. No new parameters
    // or model-changing command are exposed to a user.
    generate if(LOCAL_METADATA!=0) begin: g_metadata
        (* rom_style="block" *) logic [191:0] memory [0:2327];
        logic [191:0] data_q;
        logic valid_q;
        wire [11:0] address=12'(head_word-18'd211920);
        assign metadata_valid=valid_q;
        assign metadata_ready=!valid_q || metadata_response_ready;
        for(genvar m=0;m<8;m=m+1) begin: g_expand
            assign metadata_data[m*32 +: 32]={8'd0,data_q[m*24 +: 24]};
        end
        always_ff @(posedge clk) begin
            if(metadata_read) data_q<=memory[address];
        end
        always_ff @(posedge clk or negedge reset_n) begin
            if(!reset_n) valid_q<=0;
            else if(cancel_i || fault_o) valid_q<=0;
            else if(metadata_ready) valid_q<=metadata_read;
        end
        initial $readmemh(METADATA_HEX,memory);
    end else begin: g_external_metadata
        assign metadata_valid=0;
        assign metadata_ready=0;
        assign metadata_data=0;
    end endgenerate

    logic [10:0] fill_page_q;
    wire [BANK_W-1:0] fill_bank=fill_page_q[BANK_W-1:0];
    logic [7:0] issued_q,received_q,page_words_q;
    wire [8:0] outstanding={1'b0,issued_q}-{1'b0,received_q};
    logic [WATCH_W-1:0] ddr_watchdog_q;
    wire ddr_request_fire=ddr_request_valid_o && ddr_request_ready_i;
    wire ddr_response_legal=dma_state_q==FILL && outstanding!=0 &&
        bank_fill_ready[fill_bank] && !ddr_response_error_i;
    wire ddr_response_fire=ddr_response_valid_i && ddr_response_legal && enabled;
    assign ddr_request_valid_o=enabled && dma_state_q==FILL &&
        issued_q<page_words_q && outstanding<9'(MAX_OUTSTANDING);
    assign ddr_request_word_o=ddr_request_valid_o ? ADDR_W'({fill_page_q,issued_q[6:0]}) : {ADDR_W{1'b0}};

    // Narrow synchronous ROM is never writable. The evidence generator pins
    // the exact model image, zero-tail convention, table bytes and source hash.
    (* rom_style="block" *) logic [31:0] digest_rom [0:PAGES*8-1];
    logic [2:0] digest_word_q;
    logic [31:0] digest_data_q;
    logic [255:0] expected_digest_q;
    always_ff @(posedge clk) begin
        if(dma_state_q==ROM_READ)
            digest_data_q<=digest_rom[{fill_page_q,digest_word_q}];
        if(dma_state_q==ROM_CAPTURE)
            expected_digest_q<={expected_digest_q[223:0],digest_data_q};
        if(request_fire) request_fifo[request_write_q]<=request_word_i[17:0];
        if(head_load) head_word<=request_fifo[request_read_q];
        if(read_fire) response_fifo[response_write_q]<={metadata_read,head_bank};
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) head_valid_q<=0;
        else if(cancel_i || fault_o || read_fire) head_valid_q<=0;
        else if(head_load) head_valid_q<=1;
    end

    // Private weight frontier survives temporary consumer request gaps.
    // No public input selects it; a foreground non-weight page revokes it.
    logic remembered_weight_valid_q;
    logic [10:0] remembered_weight_page_q;
    wire foreground_scan=head_valid_q && !metadata_head;
    wire remembered_scan=remembered_weight_valid_q && (!head_valid_q || metadata_head);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            remembered_weight_valid_q<=0;remembered_weight_page_q<=0;
        end else if(cancel_i || fault_o) remembered_weight_valid_q<=0;
        else if(enabled && head_valid_q && !metadata_head) begin
            remembered_weight_valid_q<=head_word<18'(WEIGHT_WORDS);
            remembered_weight_page_q<=head_page;
        end
    end

    // Registered look-ahead scanner: one bank candidate per cycle. It removes
    // the async FIFO -> BANKS-way priority scan -> DMA control timing chain.
    // The next fixed-model fill can be chosen while previous banks hash.
    // A stale scan may waste a harmless prefetch; ALLOCATE rechecks ownership.
    logic [10:0] scan_base_q;
    logic [BANK_W-1:0] scan_offset_q;
    wire [11:0] probe_page={1'b0,scan_base_q}+12'(scan_offset_q);
    wire candidate_valid=probe_page<12'(PAGES) &&
        (scan_offset_q==0 || ({1'b0,scan_base_q}<12'(WEIGHT_PAGES) && probe_page<12'(WEIGHT_PAGES))) &&
        !(bank_assigned[probe_page[BANK_W-1:0]] &&
            bank_page[probe_page[BANK_W-1:0]]==probe_page[10:0]) &&
        bank_begin_ready[probe_page[BANK_W-1:0]];

    always_comb begin
        bank_begin_valid=0;bank_fill_valid=0;bank_read_valid=0;bank_response_ready=0;
        if(enabled) begin
            if(dma_state_q==ALLOCATE) bank_begin_valid[fill_bank]=1;
            if(ddr_response_fire) bank_fill_valid[fill_bank]=1;
            if(!cancel_i) begin
                if(head_valid_q && response_count_q<6'd32 && !metadata_head &&
                    bank_verified[head_bank] && bank_page[head_bank]==head_page)
                    bank_read_valid[head_bank]=1;
                if(response_count_q!=0 && !response_source[BANK_W])
                    bank_response_ready[response_bank]=response_ready_i;
            end
        end
    end

    genvar b;
    generate for(b=0;b<BANKS;b=b+1) begin: g_bank
        board1_verified_page_bank #(.IMAGE_WORDS(IMAGE_WORDS)) u_bank (
            .clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i),
            .begin_valid_i(bank_begin_valid[b]),.begin_ready_o(bank_begin_ready[b]),
            .begin_page_i(fill_page_q),.expected_digest_i(expected_digest_q),
            .fill_valid_i(bank_fill_valid[b]),.fill_ready_o(bank_fill_ready[b]),
            .fill_data_i(ddr_response_data_i),.fill_last_i(received_q==page_words_q-8'd1),
            .read_valid_i(bank_read_valid[b]),.read_ready_o(bank_read_ready[b]),
            .read_word_i(head_word[6:0]),.response_valid_o(bank_response_valid[b]),
            .response_ready_i(bank_response_ready[b]),.response_data_o(bank_response_data[b]),
            .assigned_o(bank_assigned[b]),.verified_o(bank_verified[b]),
            .page_o(bank_page[b]),.fault_o(bank_fault[b]));
    end endgenerate

    wire protocol_error=(request_fire && request_word_i>=ADDR_W'(IMAGE_WORDS)) ||
        (ddr_response_valid_i && !ddr_response_legal) ||
        (locked_seen_q && !model_locked_i) ||
        (dma_state_q==FILL && ddr_watchdog_q==WATCH_W'(DDR_WATCHDOG_CYCLES-1));
`ifndef SYNTHESIS
    logic x_error;
    always_comb begin
        x_error=$isunknown(cancel_i) || $isunknown(model_locked_i) ||
            $isunknown(request_valid_i) || $isunknown(ddr_response_valid_i);
        if(request_valid_i) x_error=x_error || $isunknown(request_word_i);
        if(response_valid_o) x_error=x_error || $isunknown(response_ready_i);
        if(ddr_request_valid_o) x_error=x_error || $isunknown(ddr_request_ready_i);
        if(ddr_response_valid_i) x_error=x_error || $isunknown(ddr_response_data_i) ||
            $isunknown(ddr_response_error_i);
    end
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            fault_q<=0;locked_seen_q<=0;dma_state_q<=IDLE;
            request_write_q<=0;request_read_q<=0;request_count_q<=0;
            response_write_q<=0;response_read_q<=0;response_count_q<=0;
            fill_page_q<=0;page_words_q<=0;issued_q<=0;received_q<=0;
            digest_word_q<=0;ddr_watchdog_q<=0;scan_base_q<=0;scan_offset_q<=0;
        end else if(fault_o || protocol_error
`ifndef SYNTHESIS
            || x_error
`endif
        ) begin
            fault_q<=1;request_count_q<=0;response_count_q<=0;
        end else begin
            if(model_locked_i) locked_seen_q<=1;
            if(cancel_i) begin
                request_write_q<=0;request_read_q<=0;request_count_q<=0;
                response_write_q<=0;response_read_q<=0;response_count_q<=0;
            end else begin
                if(request_fire) request_write_q<=request_write_q+6'd1;
                if(read_fire) request_read_q<=request_read_q+6'd1;
                case({request_fire,read_fire})
                    2'b10:request_count_q<=request_count_q+7'd1;
                    2'b01:request_count_q<=request_count_q-7'd1;
                    default: ;
                endcase
                if(read_fire) response_write_q<=response_write_q+5'd1;
                if(response_fire) response_read_q<=response_read_q+5'd1;
                case({read_fire,response_fire})
                    2'b10:response_count_q<=response_count_q+6'd1;
                    2'b01:response_count_q<=response_count_q-6'd1;
                    default: ;
                endcase
            end
            if(dma_state_q!=FILL || ddr_request_fire || ddr_response_fire) ddr_watchdog_q<=0;
            else ddr_watchdog_q<=ddr_watchdog_q+1'b1;
            // CLEAR intentionally does not cancel raw reads or SHA. This
            // permits all old raw responses to drain without an epoch alias.
            if(enabled) case(dma_state_q)
                IDLE: if(!cancel_i && (foreground_scan || remembered_scan)) begin
                    scan_base_q<=foreground_scan ? head_page : remembered_weight_page_q;
                    scan_offset_q<=0;dma_state_q<=SCAN;
                end
                SCAN: begin
                    if(cancel_i) dma_state_q<=IDLE;
                    else if(candidate_valid) begin
                        fill_page_q<=probe_page[10:0];
                        page_words_q<=probe_page==12'(PAGES-1) ? 8'(IMAGE_WORDS-(PAGES-1)*128) : 8'd128;
                        digest_word_q<=0;dma_state_q<=ROM_READ;
                    end else if(scan_offset_q==BANK_W'(BANKS-1)) dma_state_q<=IDLE;
                    else scan_offset_q<=scan_offset_q+1'b1;
                end
                ROM_READ: dma_state_q<=ROM_CAPTURE;
                ROM_CAPTURE: begin
                    digest_word_q<=digest_word_q+3'd1;
                    dma_state_q<=digest_word_q==3'd7 ? ALLOCATE : ROM_READ;
                end
                ALLOCATE: if(bank_begin_ready[fill_bank]) begin
                    issued_q<=0;received_q<=0;dma_state_q<=FILL;
                end
                FILL: begin
                    if(ddr_request_fire) issued_q<=issued_q+8'd1;
                    if(ddr_response_fire) begin
                        received_q<=received_q+8'd1;
                        if(received_q==page_words_q-8'd1) dma_state_q<=IDLE;
                    end
                end
                default: fault_q<=1;
            endcase
        end
    end
    initial begin
        if(BANKS<2 || BANKS>16 || (BANKS&(BANKS-1))!=0 || ADDR_W<18 ||
            IMAGE_WORDS<1 || PAGES>2048 || WEIGHT_WORDS<1 || WEIGHT_WORDS>IMAGE_WORDS ||
            MAX_OUTSTANDING<1 || MAX_OUTSTANDING>128 || DDR_WATCHDOG_CYCLES<2 || DIGEST_HEX=="" ||
            (LOCAL_METADATA!=0 && (IMAGE_WORDS!=227062 || METADATA_HEX=="")))
            $fatal(1,"unsupported fixed verified-page service geometry");
        $readmemh(DIGEST_HEX,digest_rom);
    end
endmodule
