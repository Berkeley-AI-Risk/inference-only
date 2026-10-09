`timescale 1ns/1ps
`default_nettype none

// PRIVATE typed K/V transport guard. No signal here is a public host port.
// Sixteen positions per head/role page, full SHA-256 tags in on-chip RAM.
// The unchanged parent owns semantic commit and on-chip pending-row bypass.
// Exactly one upstream word and one downstream word may be outstanding.
module board1_kv_integrity_guard #(
    parameter integer DDR_TIMEOUT_CYCLES=50000000
) (
    input wire clk,reset_n,clear_i,model_locked_i,upstream_fault_i,
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
    output wire fault_o
);
    localparam [4:0] IDLE=0,WREQ=1,WWAIT=2,WSTORE=3,WRETURN=4,
        RREQ=5,RWAIT=6,RSTORE=7,TREAD=8,TCAP=9,HBEGIN=10,
        HREAD=11,HCAP=12,HWORD=13,HDIGEST=14,TWRITE=15,
        OREAD=16,OCAP=17,RRETURN=18;
    localparam [1:0] NONE=0,WRITE_OWNER=1,READ_OWNER=2;
    localparam integer WATCH_W=$clog2(DDR_TIMEOUT_CYCLES+1);
    logic [4:0] state_q;
    logic [1:0] owner_q;
    logic fault_q,lock_seen_q,aborted_q,clear_seen_q;
    logic [63:0] epoch_q;
    logic [11:0] prefix_q[0:5];
    logic population_q;
    logic [2:0] population_layer_q;
    logic [11:0] population_position_q;
    logic next_head_q;
    logic [3:0] next_word_q;
    logic [2:0] layer_q;
    logic [11:0] position_q;
    logic head_q;
    logic [3:0] row_word_q;
    logic [6:0] page_q;
    logic [4:0] positions_q;
    logic group_head_q,role_q;
    logic [6:0] target_slot_q,scan_slot_q,hash_slot_q,total_slots_q;
    logic [3:0] scan_position_q,hash_position_q;
    logic [2:0] scan_group_word_q,hash_group_word_q;
    logic [2:0] chunk_q;
    logic hash_write_q;
    logic [255:0] word_q,assembly_q,expected_q,digest_q;
    logic cache_valid_q;
    logic [2:0] cache_layer_q;
    logic [4:0] cache_positions_q;
    logic [6:0] cache_page_q;
    logic cache_head_q,cache_role_q;
    logic [63:0] cache_epoch_q;
    logic [WATCH_W-1:0] watchdog_q;

    function automatic [18:0] address(input [2:0] layer,
        input [11:0] position,input [1:0] head,input [3:0] word_index);
        reg [14:0] row;
        begin
            row={layer,position[10:0],1'b0}+{13'd0,head};
            address=19'd227072+{1'b0,row,3'd0}+{4'd0,row}+{15'd0,word_index};
        end
    endfunction
    function automatic [8:0] partial_slot_for(input [3:0] position_mod,input head,input [3:0] word_index);
        partial_slot_for={1'b0,position_mod,4'd0}+{4'd0,position_mod,1'b0}+
             {5'd0,head,3'd0}+{8'd0,head}+{5'd0,word_index};
    endfunction
    function automatic [6:0] role_slot(input [3:0] position_mod,input [3:0] word_index);
        role_slot={1'b0,position_mod,2'd0}+{3'd0,position_mod}+
                  (word_index==8 ? 7'd4 : {5'd0,word_index[1:0]});
    endfunction
    function automatic [3:0] role_word(input role,input [2:0] index);
        role_word=index==4 ? 4'd8 : {1'b0,role,index[1:0]};
    endfunction
    function automatic [13:0] layer_base(input [2:0] layer);
        layer_base={layer,11'd0}+{3'd0,layer,8'd0};
    endfunction
    wire wr_shape=s_wr_layer<6 && s_wr_position<2048 && s_wr_head<2 && s_wr_word<9;
    wire wr_legal=wr_shape && s_wr_shadow==address(s_wr_layer,s_wr_position,s_wr_head,s_wr_word) &&
        (population_q ? (s_wr_layer==population_layer_q && s_wr_position==population_position_q &&
            s_wr_head=={1'b0,next_head_q} && s_wr_word==next_word_q) :
            (s_wr_head==0 && s_wr_word==0 && s_wr_position==prefix_q[s_wr_layer]));
    wire rd_legal=s_rd_layer<6 && s_rd_position<2048 && s_rd_head<2 && s_rd_word<9 &&
        s_rd_shadow==address(s_rd_layer,s_rd_position,s_rd_head,s_rd_word) &&
        !population_q && s_rd_position<prefix_q[s_rd_layer];
    wire [11:0] page_valid_remaining=prefix_q[s_rd_layer]-{s_rd_position[11:4],4'd0};
    wire [4:0] read_positions=page_valid_remaining>=16 ? 5'd16 : page_valid_remaining[4:0];
    wire cache_identity=cache_valid_q && cache_epoch_q==epoch_q && cache_layer_q==s_rd_layer &&
        cache_page_q==s_rd_position[10:4] && cache_positions_q==read_positions &&
        {1'b0,cache_head_q}==s_rd_head;
    // Shared tail word 8 can use either verified role for this exact identity.
    // A miss on word 8 alone deterministically selects the key role.
    wire read_role=s_rd_word==8 ? (cache_identity && cache_role_q) : s_rd_word[2];
    wire cache_hit=cache_identity && cache_role_q==read_role;

    wire hash_begin_ready,hash_word_ready,hash_digest_valid,hash_fault;
    wire [255:0] hash_digest;
    wire unexpected=(m_wr_cpl_valid && state_q!=WWAIT) || (m_rd_rsp_valid && state_q!=RWAIT);
    wire timeout_now=(state_q==WWAIT || state_q==RWAIT) && watchdog_q==WATCH_W'(DDR_TIMEOUT_CYCLES-1);
`ifndef SYNTHESIS
    wire unknown_control=$isunknown({reset_n,clear_i,model_locked_i,upstream_fault_i,s_wr_valid,s_rd_valid,
        m_wr_cpl_valid,m_rd_rsp_valid}) ||
        (state_q==IDLE && s_wr_valid && $isunknown({s_wr_layer,s_wr_position,s_wr_head,s_wr_word,s_wr_shadow,s_wr_data})) ||
        (state_q==IDLE && s_rd_valid && $isunknown({s_rd_layer,s_rd_position,s_rd_head,s_rd_word,s_rd_shadow})) ||
        (state_q==WREQ && $isunknown(m_wr_ready)) || (state_q==RREQ && $isunknown(m_rd_ready)) ||
        (m_wr_cpl_valid && $isunknown(m_wr_cpl_fault)) ||
        (m_rd_rsp_valid && $isunknown({m_rd_rsp_data,m_rd_rsp_fault})) ||
        (state_q==WRETURN && $isunknown(s_wr_cpl_ready)) || (state_q==RRETURN && $isunknown(s_rd_rsp_ready));
`else
    wire unknown_control=1'b0;
`endif
    // The parent masks its request-valid signals on fault_o. Request protocol
    // violations therefore latch a fault at the clock edge, not through a
    // combinational valid -> fault -> parent-valid feedback loop. Colliding
    // requests already see both ready outputs low. An accepted malformed/X
    // request cannot issue downstream before the latched fault closes it.
    wire request_violation=unknown_control || (state_q==IDLE && s_wr_valid && s_rd_valid);
    wire fault_event=upstream_fault_i || (lock_seen_q && !model_locked_i) || hash_fault ||
        unexpected || timeout_now ||
        (clear_i && !clear_seen_q && &epoch_q) ||
        (m_wr_cpl_valid && m_wr_cpl_fault && !aborted_q && !clear_i) ||
        (m_rd_rsp_valid && m_rd_rsp_fault && !aborted_q && !clear_i);
    wire terminal_now=fault_q || fault_event;
    wire live=reset_n && model_locked_i && !clear_i && !aborted_q && !terminal_now;
    assign fault_o=reset_n && terminal_now;
    assign s_wr_ready=live && state_q==IDLE && !s_rd_valid;
    assign s_rd_ready=live && state_q==IDLE && !s_wr_valid;
    wire write_fire=s_wr_valid && s_wr_ready;
    wire read_fire=s_rd_valid && s_rd_ready;
    assign s_wr_cpl_valid=reset_n && state_q==WRETURN && owner_q==WRITE_OWNER;
    assign s_wr_cpl_fault=s_wr_cpl_valid && terminal_now;
    assign s_rd_rsp_valid=reset_n && state_q==RRETURN && owner_q==READ_OWNER;
    assign s_rd_rsp_fault=s_rd_rsp_valid && terminal_now;
    assign s_rd_rsp_data=s_rd_rsp_valid && !terminal_now && !aborted_q && !clear_i ? assembly_q : 256'd0;

    assign m_wr_valid=live && state_q==WREQ;
    assign m_wr_layer=layer_q;
    assign m_wr_position=position_q;
    assign m_wr_head={1'b0,head_q};
    assign m_wr_word=row_word_q;
    assign m_wr_shadow=address(layer_q,position_q,{1'b0,head_q},row_word_q);
    assign m_wr_data=word_q;
    assign m_wr_cpl_ready=reset_n && state_q==WWAIT;
    assign m_rd_valid=live && state_q==RREQ;
    assign m_rd_layer=layer_q;
    assign m_rd_position={1'b0,page_q,scan_position_q};
    assign m_rd_head={1'b0,group_head_q};
    assign m_rd_word=role_word(role_q,scan_group_word_q);
    assign m_rd_shadow=address(m_rd_layer,m_rd_position,m_rd_head,m_rd_word);
    assign m_rd_rsp_ready=reset_n && state_q==RWAIT;

    // Memories have no reset. Current-generation prefixes and verified-cache
    // ownership are reset before any old bits can become observable.
    (* ram_style="block" *) logic [31:0] partial_memory[0:13823];
    (* ram_style="block" *) logic [31:0] stage_memory[0:639];
    logic [31:0] partial_data_q,stage_data_q;
    wire [8:0] partial_slot=state_q==WSTORE ?
        partial_slot_for(position_q[3:0],head_q,row_word_q) :
        partial_slot_for(hash_position_q,group_head_q,role_word(role_q,hash_group_word_q));
    wire [13:0] partial_address=layer_base(layer_q)+{2'd0,partial_slot,chunk_q};
    wire [6:0] stage_slot=state_q==RSTORE ? scan_slot_q :
        ((state_q==OREAD || state_q==OCAP) ? target_slot_q : hash_slot_q);
    wire [9:0] stage_address={stage_slot,chunk_q};
    wire tag_read=live && state_q==TREAD;
    wire tag_write=live && state_q==TWRITE;
    wire [11:0] tag_address={page_q,group_head_q,role_q,chunk_q};
    wire [31:0] tag_data[0:5];
    for(genvar bank=0;bank<6;bank=bank+1) begin:g_tags
        (* ram_style="block" *) logic [31:0] memory[0:4095];
        logic [31:0] read_q;
        always_ff @(posedge clk) begin
            if(tag_write && layer_q==bank) memory[tag_address]<=digest_q[chunk_q*32 +:32];
            if(tag_read) read_q<=memory[tag_address];
        end
        assign tag_data[bank]=read_q;
    end
    always_ff @(posedge clk) begin
        if(live && state_q==WSTORE) partial_memory[partial_address]<=word_q[chunk_q*32 +:32];
        if(live && state_q==RSTORE) stage_memory[stage_address]<=word_q[chunk_q*32 +:32];
        if(live && state_q==HREAD && hash_write_q) partial_data_q<=partial_memory[partial_address];
        if(live && ((state_q==HREAD && !hash_write_q) || state_q==OREAD)) stage_data_q<=stage_memory[stage_address];
        if(live && state_q==HCAP) assembly_q[chunk_q*32 +:32]<=hash_write_q ? partial_data_q : stage_data_q;
        if(live && state_q==OCAP) assembly_q[chunk_q*32 +:32]<=stage_data_q;
        if(live && state_q==TCAP) expected_q[chunk_q*32 +:32]<=tag_data[layer_q];
        if(write_fire) word_q<=s_wr_data;
        if(live && state_q==RWAIT && m_rd_rsp_valid) word_q<=m_rd_rsp_data;
        if(live && state_q==HDIGEST && hash_digest_valid) digest_q<=hash_digest;
    end
    kv_page_hash u_hash(.clk(clk),.reset_n(reset_n),.clear_i(clear_i || terminal_now),
        .begin_valid_i(live && state_q==HBEGIN),.begin_ready_o(hash_begin_ready),
        .epoch_i(epoch_q),.layer_i(layer_q),.page_i(page_q),
        .head_i(group_head_q),.role_i(role_q),.positions_i(positions_q),
        .word_valid_i(live && state_q==HWORD),.word_ready_o(hash_word_ready),.word_i(assembly_q),
        .digest_valid_o(hash_digest_valid),.digest_ready_i(live && state_q==HDIGEST),
        .digest_o(hash_digest),.fault_o(hash_fault));

    integer i;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=IDLE;owner_q<=NONE;fault_q<=0;lock_seen_q<=0;aborted_q<=0;clear_seen_q<=0;epoch_q<=0;
            for(i=0;i<6;i=i+1) prefix_q[i]<=0;
            population_q<=0;population_layer_q<=0;population_position_q<=0;next_head_q<=0;next_word_q<=0;
            layer_q<=0;position_q<=0;head_q<=0;row_word_q<=0;page_q<=0;positions_q<=0;
            target_slot_q<=0;scan_slot_q<=0;hash_slot_q<=0;total_slots_q<=0;
            scan_position_q<=0;scan_group_word_q<=0;chunk_q<=0;hash_write_q<=0;
            hash_position_q<=0;hash_group_word_q<=0;group_head_q<=0;role_q<=0;
            cache_head_q<=0;cache_role_q<=0;
            cache_valid_q<=0;cache_layer_q<=0;cache_positions_q<=0;cache_page_q<=0;cache_epoch_q<=0;
            watchdog_q<=0;
        end else begin
            clear_seen_q<=clear_i;
            if(model_locked_i) lock_seen_q<=1;
            if(fault_event || request_violation) fault_q<=1;
            if(state_q!=WWAIT && state_q!=RWAIT) watchdog_q<=0;
            else if(!timeout_now) watchdog_q<=watchdog_q+1'b1;
            if(clear_i) begin
                if(!clear_seen_q && !(&epoch_q)) epoch_q<=epoch_q+1'b1;
                for(i=0;i<6;i=i+1) prefix_q[i]<=0;
                cache_valid_q<=0;population_q<=0;next_head_q<=0;next_word_q<=0;
                if(owner_q!=NONE) aborted_q<=1;
            end
            if(terminal_now) cache_valid_q<=0;

            // CLEAR/fault must retire an accepted upstream word even if it
            // has not yet issued DDR. An issued DDR word is drained first.
            // A canceled, nonfaulting read returns zeros; the parent's own
            // CLEAR/aborted state discards it. No new request can interleave.
            if(clear_i || aborted_q || terminal_now) begin
                if((state_q==WWAIT && !m_wr_cpl_valid) || (state_q==RWAIT && !m_rd_rsp_valid)) begin
                    // Await the already-owned completion. Timeout latches a
                    // terminal fault; it never opens the channel for reuse.
                end else if(owner_q==WRITE_OWNER) begin
                    if(state_q==WRETURN && s_wr_cpl_ready) begin
                        owner_q<=NONE;state_q<=IDLE;aborted_q<=0;
                    end else state_q<=WRETURN;
                end else if(owner_q==READ_OWNER) begin
                    if(state_q==RRETURN && s_rd_rsp_ready) begin
                        owner_q<=NONE;state_q<=IDLE;aborted_q<=0;
                    end else state_q<=RRETURN;
                end else begin state_q<=IDLE;aborted_q<=0;end
            end else case(state_q)
                IDLE: begin
                    if(write_fire) begin
                        owner_q<=WRITE_OWNER;aborted_q<=0;cache_valid_q<=0;
                        if(!wr_legal) begin fault_q<=1;state_q<=WRETURN;end
                        else begin
                            layer_q<=s_wr_layer;position_q<=s_wr_position;head_q<=s_wr_head[0];row_word_q<=s_wr_word;
                            page_q<=s_wr_position[10:4];positions_q<={1'b0,s_wr_position[3:0]}+5'd1;
                            if(!population_q) begin
                                population_q<=1;population_layer_q<=s_wr_layer;population_position_q<=s_wr_position;
                            end
                            state_q<=WREQ;
                        end
                    end else if(read_fire) begin
                        owner_q<=READ_OWNER;aborted_q<=0;
                        if(!rd_legal) begin fault_q<=1;state_q<=RRETURN;end
                        else begin
                            layer_q<=s_rd_layer;page_q<=s_rd_position[10:4];positions_q<=read_positions;
                            group_head_q<=s_rd_head[0];role_q<=read_role;
                            target_slot_q<=role_slot(s_rd_position[3:0],s_rd_word);
                            total_slots_q<={read_positions,2'b0}+{2'd0,read_positions};
                            chunk_q<=0;
                            if(cache_hit) state_q<=OREAD;
                            else begin
                                cache_valid_q<=0;scan_slot_q<=0;scan_position_q<=0;scan_group_word_q<=0;
                                state_q<=RREQ;
                            end
                        end
                    end
                end
                WREQ: if(m_wr_ready) state_q<=WWAIT;
                WWAIT: if(m_wr_cpl_valid) begin chunk_q<=0;state_q<=WSTORE;end
                WSTORE: if(chunk_q==7) begin
                    chunk_q<=0;
                    if(head_q && row_word_q==8) begin
                        hash_write_q<=1;hash_slot_q<=0;hash_position_q<=0;hash_group_word_q<=0;
                        group_head_q<=0;role_q<=0;
                        total_slots_q<={positions_q,2'b0}+{2'd0,positions_q};state_q<=HBEGIN;
                    end else state_q<=WRETURN;
                end else chunk_q<=chunk_q+1'b1;
                WRETURN: if(s_wr_cpl_ready) begin
                    owner_q<=NONE;state_q<=IDLE;
                    if(row_word_q==8) begin
                        next_word_q<=0;next_head_q<=1;
                        if(head_q) begin population_q<=0;next_head_q<=0;end
                    end else next_word_q<=row_word_q+1'b1;
                end
                RREQ: if(m_rd_ready) state_q<=RWAIT;
                RWAIT: if(m_rd_rsp_valid) begin chunk_q<=0;state_q<=RSTORE;end
                RSTORE: if(chunk_q==7) begin
                    chunk_q<=0;
                    if(scan_slot_q==total_slots_q-1'b1) state_q<=TREAD;
                    else begin
                        scan_slot_q<=scan_slot_q+1'b1;
                        if(scan_group_word_q==4) begin
                            scan_group_word_q<=0;scan_position_q<=scan_position_q+1'b1;
                        end else scan_group_word_q<=scan_group_word_q+1'b1;
                        state_q<=RREQ;
                    end
                end else chunk_q<=chunk_q+1'b1;
                TREAD: state_q<=TCAP;
                TCAP: if(chunk_q==7) begin
                    chunk_q<=0;hash_write_q<=0;hash_slot_q<=0;
                    hash_position_q<=0;hash_group_word_q<=0;state_q<=HBEGIN;
                end else begin chunk_q<=chunk_q+1'b1;state_q<=TREAD;end
                HBEGIN: if(hash_begin_ready) begin chunk_q<=0;state_q<=HREAD;end
                HREAD: state_q<=HCAP;
                HCAP: if(chunk_q==7) begin chunk_q<=0;state_q<=HWORD;end
                    else begin chunk_q<=chunk_q+1'b1;state_q<=HREAD;end
                HWORD: if(hash_word_ready) begin
                    if(hash_slot_q==total_slots_q-1'b1) state_q<=HDIGEST;
                    else begin
                        hash_slot_q<=hash_slot_q+1'b1;chunk_q<=0;state_q<=HREAD;
                        if(hash_group_word_q==4) begin
                            hash_group_word_q<=0;hash_position_q<=hash_position_q+1'b1;
                        end else hash_group_word_q<=hash_group_word_q+1'b1;
                    end
                end
                HDIGEST: if(hash_digest_valid) begin
                    chunk_q<=0;
                    if(hash_write_q) state_q<=TWRITE;
                    else if(hash_digest==expected_q) begin
                        cache_valid_q<=1;cache_layer_q<=layer_q;cache_page_q<=page_q;
                        cache_positions_q<=positions_q;cache_epoch_q<=epoch_q;
                        cache_head_q<=group_head_q;cache_role_q<=role_q;state_q<=OREAD;
                    end else begin fault_q<=1;state_q<=RRETURN;end
                end
                TWRITE: if(chunk_q==7) begin
                    chunk_q<=0;
                    if(group_head_q && role_q) begin
                        // Publish the position only after all four trusted tags.
                        prefix_q[layer_q]<=prefix_q[layer_q]+1'b1;state_q<=WRETURN;
                    end else begin
                        if(role_q) begin group_head_q<=1;role_q<=0;end
                        else role_q<=1;
                        hash_slot_q<=0;hash_position_q<=0;hash_group_word_q<=0;state_q<=HBEGIN;
                    end
                end else chunk_q<=chunk_q+1'b1;
                OREAD: state_q<=OCAP;
                OCAP: if(chunk_q==7) begin chunk_q<=0;state_q<=RRETURN;end
                    else begin chunk_q<=chunk_q+1'b1;state_q<=OREAD;end
                RRETURN: if(s_rd_rsp_ready) begin owner_q<=NONE;state_q<=IDLE;end
                default: begin fault_q<=1;state_q<=IDLE;end
            endcase
        end
    end
endmodule
`default_nettype wire
