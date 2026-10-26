`timescale 1ns/1ps
`default_nettype none

// PRIVATE two-engine allocator for immutable-weight page-bank counter blocks.
// Not a host API. Each bank may own at most one in-flight block. Requests
// remain asserted until granted; returns have fixed ownership and no stalls.
// CLEAR is deliberately not an input: valid fills/decrypts drain across CLEAR.
// Reset/global fault invalidate ownership; real DDR reset/drain is a parent duty.
module tang_private_aes256_pool2 #(
    parameter integer BANKS=4,
    parameter bit KEY_IS_PROVISIONED=0,
    parameter [255:0] KEY=256'd0
) (
    input wire clk,reset_n,abort_i,
    input wire [BANKS-1:0] request_valid_i,
    output logic [BANKS-1:0] request_ready_o,
    input wire [BANKS*128-1:0] request_block_i,
    output logic [BANKS-1:0] response_valid_o,
    output logic [BANKS*128-1:0] response_block_o,
    output wire fault_o
);
    localparam integer BANK_W=$clog2(BANKS);
    logic fault_q;
    logic [BANK_W-1:0] rr_q;
    logic [1:0] owner_valid_q;
    logic [BANK_W-1:0] owner_q [0:1];
    logic [BANKS-1:0] pending_q;
    wire [1:0] engine_ready,engine_busy,engine_done;
    wire [127:0] engine_result [0:1];
    logic [1:0] grant_valid;
    logic [BANK_W-1:0] grant_bank [0:1];
    logic [BANKS-1:0] selected;
    logic [BANK_W-1:0] rr_next;
    logic bad_return;
    integer engine,offset,candidate;
    assign fault_o=fault_q || !KEY_IS_PROVISIONED;
    wire enabled=reset_n && !abort_i && !fault_o;

    // Two grants are drawn in round-robin order without selecting one bank
    // twice. Advancing past the last accepted bank prevents starvation even
    // when another bank repeatedly submits work after every completion.
    always_comb begin
        grant_valid=0;request_ready_o=0;selected=0;rr_next=rr_q;
        candidate=0;
        for(engine=0;engine<2;engine=engine+1) begin
            grant_bank[engine]=0;
            if(enabled && engine_ready[engine]) begin
                for(offset=0;offset<BANKS;offset=offset+1) begin
                    candidate=(int'(rr_q)+offset)&(BANKS-1);
                    if(!grant_valid[engine] && request_valid_i[candidate] &&
                            !pending_q[candidate] && !selected[candidate]) begin
                        grant_valid[engine]=1;grant_bank[engine]=BANK_W'(candidate);
                        selected[candidate]=1;request_ready_o[candidate]=1;
                        rr_next=BANK_W'(candidate+1);
                    end
                end
            end
        end
    end

    integer e;
    always_comb begin
        response_valid_o=0;response_block_o=0;bad_return=0;
        for(e=0;e<2;e=e+1) begin
            if(engine_done[e]) begin
                if(!owner_valid_q[e] || !pending_q[owner_q[e]]) bad_return=1;
                else if(enabled) begin
                    if(response_valid_o[owner_q[e]]) bad_return=1;
                    response_valid_o[owner_q[e]]=1;
                    response_block_o[int'(owner_q[e])*128 +: 128]=engine_result[e];
                end
            end
        end
        if(owner_valid_q==2'b11 && owner_q[0]==owner_q[1]) bad_return=1;
    end

    for(genvar g=0;g<2;g=g+1) begin: g_engine
        tang_private_aes256 #(.KEY_IS_PROVISIONED(KEY_IS_PROVISIONED),.KEY(KEY)) u_aes (
            .clk(clk),.reset_n(reset_n),.abort_i(abort_i || fault_o),
            .start_i(grant_valid[g]),
            .block_i(request_block_i[int'(grant_bank[g])*128 +: 128]),
            .ready_o(engine_ready[g]),.busy_o(engine_busy[g]),
            .done_o(engine_done[g]),.block_o(engine_result[g]));
    end

    wire protocol_error=bad_return || (|(request_valid_i & pending_q));
`ifndef SYNTHESIS
    logic x_error;
    integer x;
    always_comb begin
        x_error=$isunknown(abort_i) || $isunknown(request_valid_i);
        for(x=0;x<BANKS;x=x+1)
            if(request_valid_i[x]) x_error=x_error || $isunknown(request_block_i[x*128 +: 128]);
    end
`endif
    integer k;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            fault_q<=0;rr_q<=0;owner_valid_q<=0;pending_q<=0;
            owner_q[0]<=0;owner_q[1]<=0;
        end else if(fault_o || (enabled && protocol_error)
`ifndef SYNTHESIS
                || (enabled && x_error)
`endif
        ) begin
            fault_q<=1;owner_valid_q<=0;pending_q<=0;
            owner_q[0]<=0;owner_q[1]<=0;rr_q<=0;
        end else if(abort_i) begin
            owner_valid_q<=0;pending_q<=0;owner_q[0]<=0;owner_q[1]<=0;rr_q<=0;
        end else begin
            rr_q<=rr_next;
            for(k=0;k<2;k=k+1) begin
                if(engine_done[k] && owner_valid_q[k]) begin
                    pending_q[owner_q[k]]<=0;owner_valid_q[k]<=0;
                end
                if(grant_valid[k]) begin
                    pending_q[grant_bank[k]]<=1;owner_valid_q[k]<=1;
                    owner_q[k]<=grant_bank[k];
                end
            end
        end
    end
    initial begin
        if(BANKS<2 || BANKS>16 || (BANKS&(BANKS-1))!=0)
            $fatal(1,"Unsupported private AES pool geometry");
    end
endmodule
`default_nettype wire
