// PRIVATE fixed 128-coordinate Q/K score engine with shared arithmetic.
// Capture one complete private vector pair, then serialize eight ordered
// 16-coordinate chunks. No user-selected operation, operand or address.
// Same FP32 adjacent-pair reduction and BF16 scaling as the wide engine.
// Minimum steady input interval is eight cycles; latency is not equivalent.
module qwen_qk_dot128 (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire [2047:0] query,input wire [2047:0] key,
    output wire out_valid,input wire out_ready,
    output wire [15:0] score,output wire out_error
);
    reg held;
    reg [2:0] group_index;
    reg [2047:0] held_query,held_key;
    wire alive=rst_n && !clear;
    wire beat_ready,beat_payload_ready;
    wire beat_valid=held && alive;
    wire beat_take=beat_valid && beat_ready;
    assign in_ready=alive && (!held || (group_index==3'd7 && beat_ready));
    wire input_take=in_valid && in_ready;
    always @(posedge clk)begin
        if(!rst_n || clear)begin held<=0;group_index<=0;end
        else begin
            if(beat_take)group_index<=group_index+1'b1;
            if(in_ready)held<=in_valid;
        end
    end
    always @(posedge clk)begin
        // QK_CAPTURE076: refresh only a free private payload slot.
        // If a live vector is not retiring, preserve both operands exactly.
        // held/input_take still determine validity; invalid payload is unused.
        if(!held || (group_index==3'd7 && beat_payload_ready))begin held_query<=query;held_key<=key;end
    end
    // QK_FIFO081: private score buffering; never expose arithmetic to the host.
    // A full queue refuses a push even if a pop happens on this edge. This
    // breaks the combinational downstream-ready path; the next edge frees it.
    reg [1:0] score_count;
    reg score_read,score_write;
    reg [16:0] score_queue [0:1];
    wire score_room=score_count!=2'd2;
    wire raw_valid,raw_error;
    wire [15:0] raw_score;
    wire score_push=raw_valid && score_room;
    wire score_pop=out_valid && out_ready;
    assign out_valid=(score_count!=0) && alive;
    assign score=score_queue[score_read][15:0];
    assign out_error=score_queue[score_read][16];
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            score_count<=0;score_read<=0;score_write<=0;
        end else begin
            case({score_push,score_pop})
                2'b10:score_count<=score_count+1'b1;
                2'b01:score_count<=score_count-1'b1;
                default:score_count<=score_count;
            endcase
            if(score_push)score_write<=!score_write;
            if(score_pop)score_read<=!score_read;
        end
    end
    always @(posedge clk) begin
        if(score_push)score_queue[score_write]<={raw_error,raw_score};
    end
    qwen_qk_serial16_internal arithmetic(
        .clk(clk),.rst_n(rst_n),.clear(clear),
        .in_valid(beat_valid),.in_ready(beat_ready),.payload_ready(beat_payload_ready),
        .query(held_query[group_index*256+:256]),
        .key(held_key[group_index*256+:256]),
        .out_valid(raw_valid),.out_ready(score_room),
        .score(raw_score),.out_error(raw_error));
endmodule

// PRIVATE fixed Q/K score engine: eight consecutive 16-coordinate beats per
// head. The fixed controller owns query/key chunks and their implicit order.
// Computes exactly the same FP32 tree and BF16 scaling as qwen_qk_dot128,
// but shares 16 multipliers and 15 local adders across the eight chunks.
// A 7-adder final tree reduces eight stored chunk sums; heads may overlap.
// Output backpressure freezes every stage. CLEAR discards even a partial head.
module qwen_qk_serial16_internal (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    output wire in_ready,
    output wire payload_ready,
    input wire [255:0] query,
    input wire [255:0] key,
    output wire out_valid,
    input wire out_ready,
    output reg [15:0] score,
    output reg out_error
);
    reg [2:0] input_group;
    reg [10:0] partial_valid;
    reg [9:0] head_valid;
    reg [2:0] group_pipe [0:10];
    reg head_committed;
    // Payload may advance during cancellation; reset/CLEAR clears validity.
    // out_ready here is a private registered-occupancy condition, not the host.
    assign payload_ready=!head_valid[9] || out_ready;
    wire advance=payload_ready && rst_n && !clear;
    assign in_ready=advance;
    assign out_valid=head_valid[9] && rst_n && !clear;
    wire [32:0] local_tree [1:31];
    wire local_error [1:31];
    genvar lane,node;
    generate for(lane=0;lane<16;lane=lane+1) begin:products
        wire [15:0] q=query[16*lane +: 16],k=key[16*lane +: 16];
        wire [32:0] qr,kr;
        fNToRecFN #(8,24) decode_q(.in({q,16'b0}),.out(qr));
        fNToRecFN #(8,24) decode_k(.in({k,16'b0}),.out(kr));
        // PRIVATE_QK_OPERAND_STAGE: keep chunk selection and recoding
        // outside the multiplier's first arithmetic clock interval.
        reg [32:0] query_rec_q,key_rec_q;
        reg operand_error_q;
        always @(posedge clk)if(payload_ready)begin
            query_rec_q<=qr;key_rec_q<=kr;
            operand_error_q<=(&q[14:7]) || (&k[14:7]);
        end
        qwen_fp32_mul_stage multiply(.clk(clk),.advance(payload_ready),.a(query_rec_q),.b(key_rec_q),
            .in_error(operand_error_q),
            .result(local_tree[16+lane]),.out_error(local_error[16+lane]));
    end
    for(node=1;node<16;node=node+1) begin:local_reduction
        qwen_fp32_add_stage add(.clk(clk),.advance(payload_ready),
            .a(local_tree[2*node]),.b(local_tree[2*node+1]),
            .in_error(local_error[2*node] || local_error[2*node+1]),
            .result(local_tree[node]),.out_error(local_error[node]));
    end endgenerate
    reg [32:0] partial [0:7];
    reg [7:0] partial_error;
    wire [32:0] final_tree [1:15];
    wire final_error [1:15];
    generate for(lane=0;lane<8;lane=lane+1) begin:partials
        assign final_tree[8+lane]=partial[lane];
        assign final_error[8+lane]=partial_error[lane];
    end
    for(node=1;node<8;node=node+1) begin:final_reduction
        qwen_fp32_add_stage add(.clk(clk),.advance(payload_ready),
            .a(final_tree[2*node]),.b(final_tree[2*node+1]),
            .in_error(final_error[2*node] || final_error[2*node+1]),
            .result(final_tree[node]),.out_error(final_error[node]));
    end endgenerate
    wire [16:0] dot_bf_rec,score_rec;
    wire [15:0] dot_bits,score_bits;
    wire [4:0] dot_flags,score_flags;
    reg [15:0] dot_reg;
    reg dot_error;
    recFNToRecFN #(8,24,8,8) dot_narrow(.control(1'b1),.in(final_tree[1]),
        .roundingMode(3'b000),.out(dot_bf_rec),.exceptionFlags(dot_flags));
    recFNToFN #(8,8) dot_encode(.in(dot_bf_rec),.out(dot_bits));
    wire [32:0] dot_wide,scale_rec,scaled;
    wire scale_error;
    fNToRecFN #(8,24) dot_decode(.in({dot_reg,16'b0}),.out(dot_wide));
    fNToRecFN #(8,24) scale_decode(.in(32'h3db504f3),.out(scale_rec));
    qwen_fp32_mul_stage scale(.clk(clk),.advance(payload_ready),.a(dot_wide),
        .b(scale_rec),.in_error(dot_error),.result(scaled),.out_error(scale_error));
    recFNToRecFN #(8,24,8,8) score_narrow(.control(1'b1),.in(scaled),
        .roundingMode(3'b000),.out(score_rec),.exceptionFlags(score_flags));
    recFNToFN #(8,8) score_encode(.in(score_rec),.out(score_bits));
    integer i;
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            input_group<=0;partial_valid<=0;head_valid<=0;head_committed<=0;
            score<=0;out_error<=0;
        end else if(advance) begin
            if(in_valid)input_group<=input_group+1'b1;
            partial_valid<={partial_valid[9:0],in_valid};
            group_pipe[0]<=input_group;
            for(i=1;i<11;i=i+1)group_pipe[i]<=group_pipe[i-1];
            if(partial_valid[10]) begin
                partial[group_pipe[10]]<=local_tree[1];
                partial_error[group_pipe[10]]<=local_error[1];
            end
            // The final tree samples the completed bank on the next edge,
            // before chunk zero of the next head can replace its old value.
            head_committed<=partial_valid[10] && group_pipe[10]==3'd7;
            head_valid<={head_valid[8:0],head_committed};
            dot_reg<=dot_bits;
            dot_error<=final_error[1] || |dot_flags[4:2] || (&dot_bits[14:7]);
            score<=score_bits;
            out_error<=scale_error || |score_flags[4:2] || (&score_bits[14:7]);
        end
    end
    wire unused_flags=^{dot_flags[1:0],score_flags[1:0]};
endmodule
