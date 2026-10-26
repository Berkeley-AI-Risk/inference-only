`define SYNTHESIS 1
`timescale 1ns/1ps
`default_nettype none

// PRIVATE logical-nine-word / encrypted-ten-word K/V transport.
// Upstream is the unchanged plaintext SHA guard, never a host memory port.
// Words 0..7 are acknowledged only into private staging; word 8 completes
// only after both encrypted role records have completed all physical writes.
// The parent publishes a position only after both heads and trusted tags.
// Reads consume exactly one guard role scan (0..3,8 or 4..7,8). Codec HOLD
// supplies authenticated plaintext; its result is never exposed before SIV.
// CLEAR cancels unissued work but drains the one accepted DDR transaction.
module tang_private_kv_siv_bridge #(
    parameter bit KEY_IS_PROVISIONED=0,
    parameter [255:0] MAC_KEY=256'd0,
    parameter [255:0] CTR_KEY=256'd0,
    parameter integer DDR_TIMEOUT_CYCLES=50000000
) (
    input wire clk,reset_n,clear_i,model_locked_i,upstream_fault_i,
    input wire [63:0] epoch_i,
    input wire s_wr_valid,
    output wire s_wr_ready,
    input wire [2:0] s_wr_layer,
    input wire [11:0] s_wr_position,
    input wire [1:0] s_wr_head,
    input wire [3:0] s_wr_word,
    input wire [18:0] s_wr_shadow,
    input wire [255:0] s_wr_data,
    output wire s_wr_cpl_valid,
    input wire s_wr_cpl_ready,
    output wire s_wr_cpl_fault,
    input wire s_rd_valid,
    output wire s_rd_ready,
    input wire [2:0] s_rd_layer,
    input wire [11:0] s_rd_position,
    input wire [1:0] s_rd_head,
    input wire [3:0] s_rd_word,
    input wire [18:0] s_rd_shadow,
    output wire s_rd_rsp_valid,
    input wire s_rd_rsp_ready,
    output wire [255:0] s_rd_rsp_data,
    output wire s_rd_rsp_fault,
    output wire m_wr_valid,
    input wire m_wr_ready,
    output wire [2:0] m_wr_layer,
    output wire [11:0] m_wr_position,
    output wire [1:0] m_wr_head,
    output wire [3:0] m_wr_word,
    output wire [18:0] m_wr_shadow,
    output wire [255:0] m_wr_data,
    input wire m_wr_cpl_valid,
    output wire m_wr_cpl_ready,
    input wire m_wr_cpl_fault,
    output wire m_rd_valid,
    input wire m_rd_ready,
    output wire [2:0] m_rd_layer,
    output wire [11:0] m_rd_position,
    output wire [1:0] m_rd_head,
    output wire [3:0] m_rd_word,
    output wire [18:0] m_rd_shadow,
    input wire m_rd_rsp_valid,
    output wire m_rd_rsp_ready,
    input wire [255:0] m_rd_rsp_data,
    input wire m_rd_rsp_fault,
    output wire busy_o,fault_o
);
    localparam [4:0] IDLE=0,WSTORE=1,WACK=2,CSTART=3,FREAD=4,
        FCAP=5,FSEND=6,CWISSUE=7,CWWAIT=8,RISSUE=9,RWAIT=10,
        RLOAD=11,RRESP=12,RNEXT=13,CANCELW=14,CANCELR=15;
    localparam [1:0] NONE=0,WRITE=1,READ=2;
    localparam integer WATCH_W=$clog2(DDR_TIMEOUT_CYCLES+1);
    logic [4:0] state_q;
    logic [1:0] owner_q;
    logic fault_q,lock_seen_q,aborted_q,row_active_q,open_q,role_q;
    logic [2:0] layer_q,slot_q,chunk_q;
    logic [11:0] position_q;
    logic [1:0] head_q;
    logic [3:0] row_word_q,next_word_q;
    logic [63:0] epoch_q;
    wire epoch_match;
    tang_private_epoch_match64 u_epoch_match (
        .a_i(epoch_i),.b_i(epoch_q),.equal_o(epoch_match));
    logic [255:0] word_q,assembly_q;
    logic [WATCH_W-1:0] watchdog_q;
    (* ram_style="block" *) logic [31:0] row_memory[0:71];
    logic [31:0] row_data_q;

    function automatic [18:0] logical_address(input [2:0] layer,
        input [11:0] position,input [1:0] head,input [3:0] word_index);
        reg [14:0] row;
        begin
            row={layer,position[10:0],1'b0}+{13'd0,head};
            logical_address=19'd227072+{1'b0,row,3'd0}+{4'd0,row}+{15'd0,word_index};
        end
    endfunction
    function automatic [18:0] cipher_address(input [2:0] layer,
        input [11:0] position,input [1:0] head,input [3:0] word_index);
        reg [14:0] row;
        begin
            row={layer,position[10:0],1'b0}+{13'd0,head};
            cipher_address=19'd227072+{1'b0,row,3'd0}+{3'd0,row,1'b0}+{15'd0,word_index};
        end
    endfunction
    wire [3:0] cipher_word=role_q ? 4'd5+{1'b0,slot_q} : {1'b0,slot_q};
    wire [3:0] expected_read_word=slot_q==4 ? 4'd8 : {1'b0,role_q,slot_q[1:0]};
    wire wr_legal=s_wr_layer<6 && s_wr_position<2048 && s_wr_head<2 && s_wr_word<9 &&
        s_wr_shadow==logical_address(s_wr_layer,s_wr_position,s_wr_head,s_wr_word) &&
        (s_wr_word!=8 || s_wr_data[255:16]==0) &&
        (row_active_q ? (s_wr_layer==layer_q && s_wr_position==position_q &&
             s_wr_head==head_q && s_wr_word==next_word_q && epoch_match) : s_wr_word==0);
    wire rd_shape=s_rd_layer<6 && s_rd_position<2048 && s_rd_head<2 &&
        s_rd_shadow==logical_address(s_rd_layer,s_rd_position,s_rd_head,s_rd_word);
    wire rd_legal=rd_shape && (state_q==IDLE ? (s_rd_word==0 || s_rd_word==4) :
        (s_rd_layer==layer_q && s_rd_position==position_q && s_rd_head==head_q &&
         s_rd_word==expected_read_word && epoch_match));
    wire codec_request_ready,codec_input_ready,codec_output_valid,codec_busy,codec_fault;
    wire [255:0] codec_output_data;
    wire down_write_wait=state_q==CWWAIT;
    wire down_read_wait=state_q==RWAIT;
    wire unexpected=(m_wr_cpl_valid && !down_write_wait) || (m_rd_rsp_valid && !down_read_wait);
    wire timeout_now=(down_write_wait || down_read_wait) && watchdog_q==WATCH_W'(DDR_TIMEOUT_CYCLES-1);
    // Check every bit; latch an epoch violation at the original clock edge.
    // Shared guard/CLEAR contract is required for the control-equivalence proof.
    wire epoch_violation=((row_active_q || state_q!=IDLE) && !clear_i && !aborted_q && !epoch_match);
    wire fault_event=upstream_fault_i || codec_fault || (lock_seen_q && !model_locked_i) ||
        unexpected || timeout_now ||
        (m_wr_cpl_valid && m_wr_cpl_fault && !clear_i && !aborted_q) ||
        (m_rd_rsp_valid && m_rd_rsp_fault && !clear_i && !aborted_q);
    wire terminal_now=fault_q || fault_event;
    wire live=reset_n && model_locked_i && !clear_i && !aborted_q && !terminal_now;
    assign fault_o=reset_n && terminal_now;
    assign busy_o=reset_n && (state_q!=IDLE || row_active_q);
    assign s_wr_ready=live && state_q==IDLE && !s_rd_valid;
    assign s_rd_ready=live && (state_q==IDLE || state_q==RNEXT) && !row_active_q && !s_wr_valid;
    wire write_fire=s_wr_valid && s_wr_ready;
    wire read_fire=s_rd_valid && s_rd_ready;
    assign s_wr_cpl_valid=reset_n && owner_q==WRITE && (state_q==WACK || state_q==CANCELW);
    assign s_wr_cpl_fault=s_wr_cpl_valid && terminal_now;
    assign s_rd_rsp_valid=reset_n && owner_q==READ &&
        (state_q==CANCELR || (live && state_q==RRESP && codec_output_valid));
    assign s_rd_rsp_fault=s_rd_rsp_valid && terminal_now;
    assign s_rd_rsp_data=s_rd_rsp_valid && live && state_q==RRESP ? codec_output_data : 256'd0;
    assign m_wr_valid=live && state_q==CWISSUE && codec_output_valid;
    assign m_wr_layer=layer_q;
    assign m_wr_position=position_q;
    assign m_wr_head=head_q;
    assign m_wr_word=cipher_word;
    assign m_wr_shadow=cipher_address(layer_q,position_q,head_q,cipher_word);
    assign m_wr_data=m_wr_valid ? codec_output_data : 256'd0;
    assign m_wr_cpl_ready=reset_n && down_write_wait;
    assign m_rd_valid=live && state_q==RISSUE;
    assign m_rd_layer=layer_q;
    assign m_rd_position=position_q;
    assign m_rd_head=head_q;
    assign m_rd_word=cipher_word;
    assign m_rd_shadow=cipher_address(layer_q,position_q,head_q,cipher_word);
    assign m_rd_rsp_ready=reset_n && down_read_wait;

    wire [3:0] feed_word=slot_q==4 ? 4'd8 : {1'b0,role_q,slot_q[1:0]};
    wire [6:0] row_address=state_q==WSTORE ? {row_word_q,chunk_q} : {feed_word,chunk_q};
    always_ff @(posedge clk) begin
        if(live && state_q==WSTORE) row_memory[row_address]<=word_q[chunk_q*32 +:32];
        if(live && state_q==FREAD) row_data_q<=row_memory[row_address];
        if(live && state_q==FCAP) assembly_q[chunk_q*32 +:32]<=row_data_q;
        if(write_fire) word_q<=s_wr_data;
        if(live && down_read_wait && m_rd_rsp_valid) word_q<=m_rd_rsp_data;
    end
    tang_private_kv_siv_role #(.KEY_IS_PROVISIONED(KEY_IS_PROVISIONED),.MAC_KEY(MAC_KEY),.CTR_KEY(CTR_KEY)) u_codec (
        .clk(clk),.reset_n(reset_n),.abort_i(clear_i || aborted_q || fault_q),
        .model_locked_i(model_locked_i),.upstream_fault_i(upstream_fault_i || fault_q),
        .request_valid_i(live && state_q==CSTART),.request_ready_o(codec_request_ready),
        .open_i(open_q),.epoch_i(epoch_q),.layer_i(layer_q),.position_i(position_q),
        .head_i(head_q),.role_i({1'b0,role_q}),
        .input_valid_i(live && (state_q==FSEND || state_q==RLOAD)),.input_ready_o(codec_input_ready),
        .input_data_i(open_q ? word_q : assembly_q),
        .output_valid_o(codec_output_valid),.output_data_o(codec_output_data),
        .output_ready_i(live && ((state_q==CWISSUE && m_wr_ready) ||
            (state_q==RRESP && owner_q==READ && s_rd_rsp_ready))),
        .busy_o(codec_busy),.fault_o(codec_fault));
`ifndef SYNTHESIS
    wire unknown_control=$isunknown({reset_n,clear_i,model_locked_i,upstream_fault_i,s_wr_valid,s_rd_valid,
        m_wr_cpl_valid,m_rd_rsp_valid}) ||
        (write_fire && $isunknown({s_wr_layer,s_wr_position,s_wr_head,s_wr_word,s_wr_shadow,s_wr_data,epoch_i})) ||
        (read_fire && $isunknown({s_rd_layer,s_rd_position,s_rd_head,s_rd_word,s_rd_shadow,epoch_i})) ||
        (m_wr_valid && $isunknown(m_wr_ready)) || (m_rd_valid && $isunknown(m_rd_ready)) ||
        (m_wr_cpl_valid && $isunknown(m_wr_cpl_fault)) ||
        (m_rd_rsp_valid && $isunknown({m_rd_rsp_data,m_rd_rsp_fault})) ||
        (s_wr_cpl_valid && $isunknown(s_wr_cpl_ready)) ||
        (s_rd_rsp_valid && $isunknown(s_rd_rsp_ready));
`else
    wire unknown_control=1'b0;
`endif
    // Request violations latch at the edge to avoid parent valid/fault loops.
    wire request_violation=unknown_control || (s_wr_valid && s_rd_valid) ||
        (state_q==RNEXT && s_wr_valid) || (row_active_q && s_rd_valid);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;owner_q<=NONE;fault_q<=0;lock_seen_q<=0;aborted_q<=0;row_active_q<=0;
            open_q<=0;role_q<=0;layer_q<=0;position_q<=0;head_q<=0;slot_q<=0;chunk_q<=0;
            row_word_q<=0;next_word_q<=0;epoch_q<=0;watchdog_q<=0;
        end else begin
            if(model_locked_i) lock_seen_q<=1;
            if(fault_event || request_violation || epoch_violation) fault_q<=1;
            if(!down_write_wait && !down_read_wait) watchdog_q<=0;
            else if(!timeout_now) watchdog_q<=watchdog_q+1'b1;
            if(clear_i || terminal_now) begin
                row_active_q<=0;next_word_q<=0;
                if(owner_q!=NONE || state_q!=IDLE) aborted_q<=1;
            end
            if(clear_i || aborted_q || terminal_now) begin
                if((down_write_wait && !m_wr_cpl_valid) || (down_read_wait && !m_rd_rsp_valid)) begin
                    // Ownership is retained even after timeout; no invented response.
                end else if(owner_q==WRITE) begin
                    if((state_q==WACK || state_q==CANCELW) && s_wr_cpl_ready) begin
                        owner_q<=NONE;state_q<=IDLE;aborted_q<=0;
                    end else state_q<=CANCELW;
                end else if(owner_q==READ) begin
                    if(state_q==CANCELR && s_rd_rsp_ready) begin
                        owner_q<=NONE;state_q<=IDLE;aborted_q<=0;
                    end else state_q<=CANCELR;
                end else begin state_q<=IDLE;aborted_q<=0;end
            end else case(state_q)
                IDLE: begin
                    if(write_fire) begin
                        owner_q<=WRITE;row_word_q<=s_wr_word;
                        if(!wr_legal) begin fault_q<=1;state_q<=CANCELW;end
                        else begin
                            if(!row_active_q) begin
                                layer_q<=s_wr_layer;position_q<=s_wr_position;head_q<=s_wr_head;
                                epoch_q<=epoch_i;row_active_q<=1;
                            end
                            chunk_q<=0;state_q<=WSTORE;
                        end
                    end else if(read_fire) begin
                        owner_q<=READ;
                        if(!rd_legal) begin fault_q<=1;state_q<=CANCELR;end
                        else begin
                            layer_q<=s_rd_layer;position_q<=s_rd_position;head_q<=s_rd_head;epoch_q<=epoch_i;
                            role_q<=s_rd_word[2];open_q<=1;slot_q<=0;state_q<=CSTART;
                        end
                    end
                end
                WSTORE: if(chunk_q==7) begin
                    chunk_q<=0;
                    if(row_word_q==8) begin role_q<=0;open_q<=0;slot_q<=0;state_q<=CSTART;end
                    else state_q<=WACK;
                end else chunk_q<=chunk_q+1'b1;
                WACK: if(s_wr_cpl_ready) begin
                    owner_q<=NONE;state_q<=IDLE;
                    if(row_word_q==8) begin row_active_q<=0;next_word_q<=0;end
                    else next_word_q<=row_word_q+1'b1;
                end
                CSTART: if(codec_request_ready) begin
                    slot_q<=0;chunk_q<=0;state_q<=open_q ? RISSUE : FREAD;
                end
                FREAD: state_q<=FCAP;
                FCAP: if(chunk_q==7) begin chunk_q<=0;state_q<=FSEND;end
                    else begin chunk_q<=chunk_q+1'b1;state_q<=FREAD;end
                FSEND: if(codec_input_ready) begin
                    if(slot_q==4) begin slot_q<=0;state_q<=CWISSUE;end
                    else begin slot_q<=slot_q+1'b1;chunk_q<=0;state_q<=FREAD;end
                end
                CWISSUE: if(codec_output_valid && m_wr_ready) state_q<=CWWAIT;
                CWWAIT: if(m_wr_cpl_valid) begin
                    if(slot_q==4) begin
                        slot_q<=0;
                        if(!role_q) begin role_q<=1;state_q<=CSTART;end
                        else state_q<=WACK;
                    end else begin slot_q<=slot_q+1'b1;state_q<=CWISSUE;end
                end
                RISSUE: if(m_rd_ready) state_q<=RWAIT;
                RWAIT: if(m_rd_rsp_valid) state_q<=RLOAD;
                RLOAD: if(codec_input_ready) begin
                    if(slot_q==4) begin slot_q<=0;state_q<=RRESP;end
                    else begin slot_q<=slot_q+1'b1;state_q<=RISSUE;end
                end
                RRESP: if(codec_output_valid && s_rd_rsp_ready) begin
                    owner_q<=NONE;
                    if(slot_q==4) state_q<=IDLE;
                    else begin slot_q<=slot_q+1'b1;state_q<=RNEXT;end
                end
                RNEXT: if(read_fire) begin
                    owner_q<=READ;
                    if(!rd_legal) begin fault_q<=1;state_q<=CANCELR;end
                    else state_q<=RRESP;
                end
                default: begin fault_q<=1;state_q<=IDLE;end
            endcase
        end
    end
    wire _unused_codec_busy=codec_busy;
endmodule
`default_nettype wire

`default_nettype none
// Alternative implementation of the same full-width combinational equality.
// Pairwise bitwise comparisons each have four input signals. Retained small
// reduction boundaries aim to avoid arithmetic carry mapping. Native mapping
// and physical delay must still be measured; no fault/check latency is added.
module tang_private_epoch_match64 (
    input wire [63:0] a_i,
    input wire [63:0] b_i,
    output wire equal_o
);
    (* keep = "true", syn_keep = 1 *) wire [31:0] pair_equal;
    (* keep = "true", syn_keep = 1 *) wire [7:0] group_equal;
    (* keep = "true", syn_keep = 1 *) wire [1:0] half_equal;
    generate for (genvar part=0; part<32; part=part+1) begin: g_pair
        assign pair_equal[part] = ~(a_i[part*2] ^ b_i[part*2]) &
                                  ~(a_i[part*2+1] ^ b_i[part*2+1]);
    end
    for (genvar group=0; group<8; group=group+1) begin: g_group
        assign group_equal[group] = &pair_equal[group*4 +: 4];
    end
    for (genvar half=0; half<2; half=half+1) begin: g_half
        assign half_equal[half] = &group_equal[half*4 +: 4];
    end endgenerate
    assign equal_o = &half_equal;
endmodule
`default_nettype wire
