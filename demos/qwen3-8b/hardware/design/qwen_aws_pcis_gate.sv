// PRIVATE-target lifecycle guard between the full-ID adapter and model ingress.
// 32 AW/B records and 64 independent W beats preserve the existing ingress
// concurrency. Host AW acceptance uses local capacity, independently of
// lifecycle/downstream readiness. Remember the admission state at that edge.
// Issue live addresses in order; do not forward their W until the downstream
// AW handshake has reserved ingress credit. B retirement waits for both local
// address retirement and all declared W beats, preventing early slot reuse.
// Reads are always zero/DECERR here; no read request reaches the private target.
//
// 'online' is shell-synchronous trusted lifecycle state, not a host register.
// Its falling edge MUST coherently reset the private target and its memory
// fabric. Host-facing queues survive; outstanding writes finish as errors once
// their remaining W beats arrive. Already captured B/R responses remain stable.
// Once an online target shuts down, restart requires whole-interface reset.
// W beats supplied before startup cannot become accepted model data afterward:
// if their AW is live, zero strobes force the real restricted ingress to reject.
// CLEAR must not reset this guard or change online. No downstream watchdog is
// implemented here; lifecycle shutdown must handle a failed private target.
module qwen_aws_pcis_gate #(parameter bit REGISTER_AR_READY=1'b0,
    // read_count has the existing asynchronous reset below.
    parameter bit ASYNC_READ_COUNT_VALID=1'b0) (
    input wire clk,input wire rst_n,input wire online,
    output reg error,output wire fault_request,
    input wire [63:0] s_awaddr,input wire [5:0] s_awid,
    input wire [7:0] s_awlen,input wire [2:0] s_awsize,
    input wire s_awvalid,output wire s_awready,
    input wire [511:0] s_wdata,input wire [63:0] s_wstrb,
    input wire s_wlast,input wire s_wvalid,output wire s_wready,
    output reg [5:0] s_bid,output reg [1:0] s_bresp,output reg s_bvalid,input wire s_bready,
    input wire [63:0] s_araddr,input wire [5:0] s_arid,
    input wire [7:0] s_arlen,input wire [2:0] s_arsize,
    input wire s_arvalid,output wire s_arready,
    output wire [511:0] s_rdata,output wire [5:0] s_rid,
    output wire [1:0] s_rresp,output wire s_rlast,output wire s_rvalid,input wire s_rready,
    output wire [63:0] m_awaddr,output wire [5:0] m_awid,
    output wire [7:0] m_awlen,output wire [2:0] m_awsize,
    output wire m_awvalid,input wire m_awready,
    output wire [511:0] m_wdata,output wire [63:0] m_wstrb,
    output wire m_wlast,output wire m_wvalid,input wire m_wready,
    input wire [5:0] m_bid,input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
    output wire [63:0] m_araddr,output wire [5:0] m_arid,
    output wire [7:0] m_arlen,output wire [2:0] m_arsize,
    output wire m_arvalid,input wire m_arready,
    input wire [511:0] m_rdata,input wire [5:0] m_rid,
    input wire [1:0] m_rresp,input wire m_rlast,input wire m_rvalid,output wire m_rready
);
    reg online_seen,dead,protocol_error;
    wire active=online && !dead;
    assign fault_request=dead || protocol_error;
    (* ram_style="distributed" *) reg [14:0] writes [0:31]; // live, id, len
    (* ram_style="distributed" *) reg [13:0] reads [0:31];
    (* ram_style="distributed" *) reg [66:0] addresses [0:31]; // size, address
    reg [31:0] write_data_done,write_address_done;
    reg [4:0] address_record;
    reg [5:0] awaiting_address;
    reg [4:0] aw_push,w_record,b_record,ar_push,ar_pop;
    reg [5:0] w_push,w_pop;
    reg [5:0] outstanding,awaiting_data,read_count;
    reg [6:0] data_count;
    reg [7:0] write_beat,read_beat;
    wire [14:0] write_head=writes[w_record],response_head=writes[b_record];
    wire [577:0] data_head;
    wire [13:0] read_head=reads[ar_pop];
    reg [14:0] address_head;
    reg [66:0] address_payload;
    reg address_head_valid;
    wire capture_address_head=rst_n && !address_head_valid && awaiting_address!=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)address_head_valid<=0;
        else if(address_retire)address_head_valid<=0;
        else if(capture_address_head)address_head_valid<=1;
    end
    // The unowned head may refresh, but a published address holds until
    // retirement. Queue ownership still ends only at address_retire/B.
    always @(posedge clk)begin
        if(!address_head_valid)begin
            address_head<=writes[address_record];
            address_payload<=addresses[address_record];
        end
    end
    assign m_awaddr=address_payload[63:0];
    assign m_awid=address_head[13:8];
    assign m_awlen=address_head[7:0];
    assign m_awsize=address_payload[66:64];
    assign m_awvalid=rst_n && active && address_head_valid && awaiting_address!=0 && address_head[14];
    assign s_awready=rst_n && outstanding<32;
    wire address_retire=rst_n && address_head_valid && awaiting_address!=0 &&
        (!active || !address_head[14] || m_awready);
    assign s_wready=rst_n && data_count<64;
    wire forward_data=active && write_head[14];
    assign m_wvalid=rst_n && awaiting_data!=0 && committed_data && forward_data && write_address_done[w_record];
    assign m_wdata=data_head[511:0];
    assign m_wstrb=data_head[577] ? data_head[575:512] : 64'b0;
    assign m_wlast=data_head[576];
    wire aw_take=s_awvalid && s_awready;
    wire w_take=s_wvalid && s_wready;
    // Accepted beats occupy capacity immediately, but become readable only
    // after their RAM write on the next edge. The online bit is captured at
    // acceptance, never recomputed when that delayed write is committed.
    (* keep="true" *) reg w_stage_valid;
    reg [577:0] w_stage_word;
    reg [5:0] w_stage_address;
    wire committed_data=data_count>7'(w_stage_valid);
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)w_stage_valid<=0;
        else w_stage_valid<=w_take;
    end
    always @(posedge clk)begin
        w_stage_word<={active,s_wlast,s_wstrb,s_wdata};
        w_stage_address<=w_push;
    end
    for(genvar w_lane=0;w_lane<17;w_lane=w_lane+1)begin:write_lanes
        (* keep="true" *) reg commit_q;
        (* ram_style="distributed" *) reg [33:0] words [0:63];
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)commit_q<=0;
            else commit_q<=w_take;
        end
        always @(posedge clk)begin
            if(commit_q)words[w_stage_address]<=w_stage_word[w_lane*34+:34];
        end
        assign data_head[w_lane*34+:34]=words[w_pop];
    end
    wire b_take=s_bvalid && s_bready;
    wire data_pop=rst_n && awaiting_data!=0 && committed_data &&
        (!forward_data || (write_address_done[w_record] && m_wready));
    wire data_finish=data_pop && write_beat==write_head[7:0];
    wire reject_response=!active || !response_head[14];
    wire response_pending=rst_n && outstanding!=0 && write_data_done[b_record] &&
        write_address_done[b_record] && !s_bvalid;
    assign m_bready=response_pending && !reject_response;
    wire capture_b=response_pending && (reject_response || m_bvalid);
    wire wrong_id=capture_b && !reject_response && m_bid!=response_head[13:8];

    // Read capacity is selected below; reads still never reach the target.
    assign s_rvalid=(ASYNC_READ_COUNT_VALID || rst_n) && read_count!=0;
    assign s_rdata=0;
    assign s_rid=s_rvalid ? read_head[13:8] : 6'b0;
    assign s_rresp=2'b11;
    assign s_rlast=s_rvalid && read_beat==read_head[7:0];
    wire ar_take=s_arvalid && s_arready;
    wire r_take=s_rvalid && s_rready;
    wire read_finish=r_take && s_rlast;
    // PRIVATE_READ_CREDIT_STAGE: only capacity for zero/DECERR reads.
    // Predict the post-edge count. Both reset assertion and the disabled
    // mode retain their original fail-closed behavior; release takes one edge.
    generate if(REGISTER_AR_READY)begin:read_credit_stage
        (* keep="true" *) reg ready_q;
        always @(posedge clk or negedge rst_n)begin
            if(!rst_n)ready_q<=0;
            else case({ar_take,read_finish})
                2'b10:ready_q<=read_count<6'd31;
                2'b01:ready_q<=1'b1;
                default:ready_q<=read_count<6'd32;
            endcase
        end
        assign s_arready=ready_q;
    end else begin:combinational_read_credit
        assign s_arready=rst_n && read_count<32;
    end endgenerate
    assign m_araddr=0;
    assign m_arid=0;
    assign m_arlen=0;
    assign m_arsize=0;
    assign m_arvalid=0;
    assign m_rready=0;
    always @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin
            online_seen<=0;dead<=0;protocol_error<=0;error<=0;
            write_address_done<=0;address_record<=0;awaiting_address<=0;
            write_data_done<=0;aw_push<=0;w_record<=0;b_record<=0;ar_push<=0;ar_pop<=0;
            w_push<=0;w_pop<=0;outstanding<=0;awaiting_data<=0;read_count<=0;data_count<=0;
            write_beat<=0;read_beat<=0;s_bid<=0;s_bresp<=0;s_bvalid<=0;
        end else begin
            if(online)online_seen<=1;
            if(online_seen && !online)begin dead<=1;error<=1;end
            outstanding<=outstanding+6'(aw_take)-6'(b_take);
            awaiting_address<=awaiting_address+6'(aw_take)-6'(address_retire);
            if(address_retire)begin
                write_address_done[address_record]<=1;
                address_record<=address_record+1'b1;
            end
            awaiting_data<=awaiting_data+6'(aw_take)-6'(data_finish);
            data_count<=data_count+7'(w_take)-7'(data_pop);
            read_count<=read_count+6'(ar_take)-6'(read_finish);
            if(aw_take)begin
                write_address_done[aw_push]<=0;
                write_data_done[aw_push]<=0;aw_push<=aw_push+1'b1;
                if(!active)error<=1;
            end
            if(w_take)begin
                w_push<=w_push+1'b1;
                if(!active)error<=1;
            end
            if(data_pop)begin
                w_pop<=w_pop+1'b1;
                if(data_finish)begin write_beat<=0;write_data_done[w_record]<=1;w_record<=w_record+1'b1;end
                else write_beat<=write_beat+1'b1;
            end
            if(capture_b)begin
                s_bvalid<=1;s_bid<=response_head[13:8];
                s_bresp<=(reject_response || wrong_id) ? 2'b10 : m_bresp;
                if(reject_response || wrong_id || m_bresp!=0)error<=1;
            end
            if(wrong_id)protocol_error<=1;
            if(b_take)begin s_bvalid<=0;b_record<=b_record+1'b1;end
            if(ar_take)ar_push<=ar_push+1'b1;
            if(r_take)begin
                if(read_finish)begin read_beat<=0;ar_pop<=ar_pop+1'b1;end
                else read_beat<=read_beat+1'b1;
            end
        end
    end
    // These payload arrays have no reset in either implementation. Each
    // take signal includes rst_n, preserving the original write qualification.
    // Keep them outside the asynchronous control-reset process for RAM inference.
    always @(posedge clk)begin
        if(aw_take)begin
            writes[aw_push]<={active,s_awid,s_awlen};
            addresses[aw_push]<={s_awsize,s_awaddr};
        end
        if(ar_take)reads[ar_push]<={s_arid,s_arlen};
    end
endmodule
