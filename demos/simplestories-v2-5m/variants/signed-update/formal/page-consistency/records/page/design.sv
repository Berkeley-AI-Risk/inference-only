`timescale 1ns/1ps
`default_nettype none
// Check the sealed page table against the same ordered readback stream used
// by the whole-image checker. The final page has the runtime bank's zero tail.
// Expected digests are eight big-endian words from a synchronous private port.
module su_page_table_check #(
    parameter bit USE_SHARED_COMPRESSOR=1'b0,
    parameter integer IMAGE_BYTES=7265984,
    parameter integer PAGE_BYTES=4096
) (
    input wire clk,reset_n,start_i,
    input wire readback_valid_i,readback_last_i,
    input wire [7:0] readback_byte_i,
    output wire readback_ready_o,
    output wire digest_read_o,
    output wire [13:0] digest_address_o,
    input wire [31:0] digest_data_i,
    output wire verified_o,fault_o,
    output wire shared_request_o,
    output wire [511:0] shared_block_o,
    output wire [255:0] shared_state_o,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i
);
    localparam integer PAGES=(IMAGE_BYTES+PAGE_BYTES-1)/PAGE_BYTES;
    localparam integer TAIL_BYTES=IMAGE_BYTES-(PAGES-1)*PAGE_BYTES;
    localparam [3:0] IDLE=0,PAGE_START=1,EXPECT_READ=2,EXPECT_CAPTURE=3,
        PAYLOAD=4,ZERO_TAIL=5,WAIT_HASH=6,VERIFIED=7,FAILED=15;
    logic [3:0] state_q;
    logic [10:0] page_q;
    logic [12:0] page_byte_q;
    logic [2:0] digest_word_q;
    logic [255:0] expected_q;
    logic fault_q;
    wire sha_ready,sha_busy,sha_done,sha_fault;
    wire [31:0] sha_offset;
    wire [255:0] sha_digest;
    wire final_input=page_q==11'(PAGES-1) && page_byte_q==13'(TAIL_BYTES-1);
    wire input_fire=readback_valid_i && readback_ready_o;
    wire zero_fire=state_q==ZERO_TAIL && sha_ready && !fault_o;
    assign fault_o=fault_q || sha_fault;
    assign verified_o=state_q==VERIFIED && !fault_o;
    assign readback_ready_o=state_q==PAYLOAD && sha_ready && !fault_o;
    assign digest_read_o=state_q==EXPECT_READ && !fault_o;
    assign digest_address_o={page_q,digest_word_q};
    su_sha256 #(.MAX_BYTES(PAGE_BYTES),.USE_SHARED_COMPRESSOR(USE_SHARED_COMPRESSOR)) u_sha(
        .clk(clk),.reset_n(reset_n),.start_i(state_q==PAGE_START && !fault_o),
        .length_i(32'(PAGE_BYTES)),
        .byte_valid_i(!fault_o && ((state_q==PAYLOAD && readback_valid_i) || state_q==ZERO_TAIL)),
        .byte_ready_o(sha_ready),.byte_i(state_q==ZERO_TAIL ? 8'd0 : readback_byte_i),
        .byte_offset_o(sha_offset),.busy_o(sha_busy),.done_o(sha_done),.fault_o(sha_fault),.digest_o(sha_digest),
        .shared_request_o(shared_request_o),.shared_block_o(shared_block_o),.shared_state_o(shared_state_o),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;page_q<=0;page_byte_q<=0;digest_word_q<=0;expected_q<=0;fault_q<=0;
        end else if(fault_o || (start_i && state_q!=IDLE) ||
                    (sha_done && state_q!=WAIT_HASH) ||
                    (readback_valid_i && state_q==VERIFIED)) begin
            state_q<=FAILED;fault_q<=1;
        end else case(state_q)
            IDLE: if(start_i) state_q<=PAGE_START;
            PAGE_START: begin
                page_byte_q<=0;digest_word_q<=0;expected_q<=0;state_q<=EXPECT_READ;
            end
            EXPECT_READ: state_q<=EXPECT_CAPTURE;
            EXPECT_CAPTURE: begin
                expected_q<={expected_q[223:0],digest_data_i};
                if(digest_word_q==7) state_q<=PAYLOAD;
                else begin digest_word_q<=digest_word_q+1;state_q<=EXPECT_READ;end
            end
            PAYLOAD: if(input_fire) begin
                if(readback_last_i!=final_input) begin state_q<=FAILED;fault_q<=1;end
                else if(page_byte_q==13'(PAGE_BYTES-1)) state_q<=WAIT_HASH;
                else begin
                    page_byte_q<=page_byte_q+1;
                    if(final_input) state_q<=ZERO_TAIL;
                end
            end
            ZERO_TAIL: if(zero_fire) begin
                if(page_byte_q==13'(PAGE_BYTES-1)) state_q<=WAIT_HASH;
                else page_byte_q<=page_byte_q+1;
            end
            WAIT_HASH: if(sha_done) begin
                if(sha_digest!=expected_q) begin state_q<=FAILED;fault_q<=1;end
                else if(page_q==11'(PAGES-1)) state_q<=VERIFIED;
                else begin page_q<=page_q+1;state_q<=PAGE_START;end
            end
            VERIFIED: begin end
            FAILED: fault_q<=1;
            default: begin state_q<=FAILED;fault_q<=1;end
        endcase
    end
    initial begin
        if(IMAGE_BYTES<1 || PAGE_BYTES<1 || PAGE_BYTES>4096 || PAGES>2048)
            $fatal(1,"unsupported private page-check geometry");
    end
    // Controller proof: binary clocked state with an abstract SHA child that
    // completes only after a complete page. Hash value correctness is separate.
    logic spec_initial=1;
    always_ff @(posedge clk) spec_initial<=0;
    always_comb if(spec_initial) assume(!reset_n);
    logic [23:0] spec_inputs;
    logic [11:0] spec_pages;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin spec_inputs<=0;spec_pages<=0;end
        else if(!fault_o) begin
            if(input_fire) spec_inputs<=spec_inputs+1;
            if(state_q==WAIT_HASH && sha_done && sha_digest==expected_q)
                spec_pages<=spec_pages+1;
        end
    end
    always_comb if(reset_n) begin
        assert(state_q==IDLE || state_q==PAGE_START || state_q==EXPECT_READ ||
               state_q==EXPECT_CAPTURE || state_q==PAYLOAD || state_q==ZERO_TAIL ||
               state_q==WAIT_HASH || state_q==VERIFIED || state_q==FAILED);
        assert(page_q<PAGES);
        assert(page_byte_q<PAGE_BYTES);
        assert(spec_inputs<=IMAGE_BYTES);
        assert(spec_pages<=PAGES);
        if(fault_q) assert(state_q==FAILED);
        if(verified_o) begin
            assert(spec_inputs==IMAGE_BYTES);
            assert(spec_pages==PAGES);
            assert(page_q==PAGES-1);
            assert(!readback_ready_o && !digest_read_o);
        end
        if(state_q!=VERIFIED && state_q!=FAILED) assert(spec_pages=={1'b0,page_q});
        if(state_q==IDLE || state_q==PAGE_START || state_q==EXPECT_READ || state_q==EXPECT_CAPTURE)
            assert(spec_inputs==24'(page_q*PAGE_BYTES));
        if(state_q==EXPECT_READ || state_q==EXPECT_CAPTURE) assert(page_byte_q==0);
        if(state_q==PAYLOAD) begin
            assert(spec_inputs==24'(page_q*PAGE_BYTES)+24'(page_byte_q));
            if(page_q==PAGES-1) assert(page_byte_q<TAIL_BYTES);
        end
        if(state_q==ZERO_TAIL) begin
            assert(page_q==PAGES-1);
            assert(spec_inputs==IMAGE_BYTES);
            assert(page_byte_q>=TAIL_BYTES);
            assert(!readback_ready_o);
        end
        if(state_q==WAIT_HASH)
            assert(spec_inputs==24'(page_q*PAGE_BYTES)+24'(page_q==PAGES-1 ? TAIL_BYTES : PAGE_BYTES));
        if(digest_read_o) assert(digest_address_o<PAGES*8);
        if(readback_ready_o) assert(state_q==PAYLOAD && !fault_o);
    end
    logic spec_past_valid=0;
    always_ff @(posedge clk) begin
        spec_past_valid<=1;
        if(spec_past_valid && reset_n && $past(reset_n)) begin
            if($past(fault_o)) assert(fault_o);
            if($past(state_q==WAIT_HASH && sha_done && sha_digest!=expected_q))
                assert(fault_o && !verified_o);
            if($past(state_q==PAYLOAD && input_fire && readback_last_i!=final_input))
                assert(fault_o && !verified_o);
        end
    end

endmodule

// Three private hash streams share one compressor. A block and its chaining
// state are sampled together on acceptance; only that owner receives done.
module swic_boot_compressor_mux3(
    input wire clk,reset_n,
    input wire request0_i,request1_i,request2_i,
    input wire [511:0] block0_i,block1_i,block2_i,
    input wire [255:0] state0_i,state1_i,state2_i,
    output wire accept0_o,accept1_o,accept2_o,done0_o,done1_o,done2_o,
    output wire [255:0] digest_o,
    output wire fault_o
);
    logic occupied_q,fault_q;
    logic [1:0] owner_q,last_owner_q,choice;
    wire busy,done;
    wire available=!occupied_q && !busy && !done && !fault_q;
    always_comb begin
        choice=3;
        case(last_owner_q)
            0: begin
                if(request1_i) choice=1;
                else if(request2_i) choice=2;
                else if(request0_i) choice=0;
            end
            1: begin
                if(request2_i) choice=2;
                else if(request0_i) choice=0;
                else if(request1_i) choice=1;
            end
            default: begin
                if(request0_i) choice=0;
                else if(request1_i) choice=1;
                else if(request2_i) choice=2;
            end
        endcase
    end
    assign accept0_o=reset_n && available && choice==0;
    assign accept1_o=reset_n && available && choice==1;
    assign accept2_o=reset_n && available && choice==2;
    assign done0_o=reset_n && occupied_q && owner_q==0 && done && !fault_q;
    assign done1_o=reset_n && occupied_q && owner_q==1 && done && !fault_q;
    assign done2_o=reset_n && occupied_q && owner_q==2 && done && !fault_q;
    assign fault_o=fault_q;
    board1_sha256_compact_compress u_compress(
        .clk_i(clk),.reset_n_i(reset_n),.start_i(accept0_o || accept1_o || accept2_o),
        .block_i(choice==0 ? block0_i : (choice==1 ? block1_i : block2_i)),
        .state_i(choice==0 ? state0_i : (choice==1 ? state1_i : state2_i)),
        .busy_o(busy),.done_o(done),.state_o(digest_o));
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin occupied_q<=0;owner_q<=0;last_owner_q<=2;fault_q<=0;end
        else begin
            if((busy || done) && !occupied_q) fault_q<=1;
            if(accept0_o || accept1_o || accept2_o) begin
                occupied_q<=1;owner_q<=choice;last_owner_q<=choice;
            end
            if(done && occupied_q) occupied_q<=0;
        end
    end
endmodule
`default_nettype wire
