// 8B candidate: fixed global page interleave shared with the model reader.
// PRIVATE bounded write transport for fixed-image provisioning (REGION=0),
// Plain K/V (REGION=1) only. Other compile-time regions fail closed.
// Never map this interface to a public raw-memory/arithmetic API. A surrounding
// fixed loader/writer owns addresses and restricts when each instance is used.
// Logical 256-byte beats are striped over eight 32-byte HBM pseudochannels.
//
// A whole <=4 KiB burst is buffered BEFORE asserting any AXI AW/W signal.
// Thus cancellation can finish already presented writes without requesting
// further upstream data, withdrawing AWVALID/WVALID or inventing payload bytes.
// All eight B responses retire before completion or quiescent is reported.
// Per-lane AW and W handshakes are independent; WVALID does not wait for AWREADY.
//
// Runs in the HBM AXI clock domain. CDC, vendor HBM and the AWS shell remain
// external. rst_n requires coordinated fabric reset; core_abort drains normally.
module qwen_hbm_write_transport #(
    parameter integer REGION=1
) (
    input wire clk,input wire rst_n,input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire [33:0] request_address,input wire [16:0] request_bytes,
    input wire write_valid,output wire write_ready,input wire [2047:0] write_data,input wire write_last,
    output wire done_valid,input wire done_ready,
    output wire [8*34-1:0] axi_awaddr,output wire [8*6-1:0] axi_awid,
    output wire [8*4-1:0] axi_awlen,output wire [8*3-1:0] axi_awsize,
    output wire [8*2-1:0] axi_awburst,output wire [7:0] axi_awvalid,input wire [7:0] axi_awready,
    output wire [2047:0] axi_wdata,output wire [255:0] axi_wstrb,
    output wire [7:0] axi_wlast,output wire [7:0] axi_wvalid,input wire [7:0] axi_wready,
    input wire [8*6-1:0] axi_bid,input wire [8*2-1:0] axi_bresp,input wire [7:0] axi_bvalid,output wire [7:0] axi_bready
);
    localparam [2:0] IDLE=0,CAPTURE=1,SEND=2,DONE=3,DRAIN=4;
    localparam [33:0] LIMIT=REGION==0 ? 34'd8828026880 : 34'd13659865088;
    localparam [25:0] FIRST=REGION==0 ? 26'd0 : 26'(34'd8828026880>>8);
    reg [2:0] state;
    reg failed,protocol_failed,cancelled;
    reg [25:0] offset_words;
    reg [8:0] remaining;
    reg [4:0] burst_words,captured;
    wire [7:0] b_seen,response_fault,protocol_fault;
    wire request_fire=request_valid && request_ready;
    wire write_fire=write_valid && write_ready;
    // HBM_WRITE_BOUNDS148: equivalent bounds for the four fixed lengths.
    // LIMIT and admitted addresses are256-byte aligned. No runtime adder.
    localparam [25:0] LAST_256=26'((LIMIT-34'd256)>>8);
    localparam [25:0] LAST_512=26'((LIMIT-34'd512)>>8);
    localparam [25:0] LAST_4096=26'((LIMIT-34'd4096)>>8);
    localparam [25:0] LAST_65536=26'((LIMIT-34'd65536)>>8);
    wire bounded_length=
           (request_bytes==17'd256 && request_address[33:8]<=LAST_256)
        || (request_bytes==17'd512 && request_address[33:8]<=LAST_512)
        || (request_bytes==17'd4096 && request_address[33:8]<=LAST_4096)
        || (request_bytes==17'd65536 && request_address[33:8]<=LAST_65536);
    wire lower_bound_ok;
    generate if(REGION==0)begin:model_lower_bound
        assign lower_bound_ok=1'b1;
    end else begin:kv_lower_bound
        assign lower_bound_ok=request_address[33:8]>=FIRST;
    end endgenerate
    wire header_ok=(REGION==0 || REGION==1) && lower_bound_ok
        && request_address[7:0]==0 && bounded_length;
    wire bad_word=write_fire && write_last!=(remaining==9'd1);
    assign quiescent=rst_n && state==IDLE && !protocol_failed && !(|axi_bvalid);
    assign error=rst_n && (failed || protocol_failed);
    assign request_ready=quiescent && !core_abort && !failed;
    assign write_ready=rst_n && state==CAPTURE && !core_abort && !failed && !cancelled;
    assign done_valid=rst_n && state==DONE && !core_abort && !failed && !cancelled;

    function automatic [4:0] choose_burst(input [8:0] words,input [25:0] offset);
        reg [8:0] count,boundary;
        begin
            boundary=9'd128-{2'b0,offset[6:0]};
            count=words<9'd16 ? words : 9'd16;
            if(boundary<count)count=boundary;
            choose_burst=count[4:0];
        end
    endfunction
    wire [25:0] next_offset=offset_words+{21'b0,burst_words};
    wire burst_begin=state==CAPTURE && write_fire && !bad_word && captured+5'd1==burst_words;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1)begin:lanes
        localparam [2:0] CHANNEL=3'(lane);
        // Only 16 words: distributed RAM avoids wide/shallow block-RAM waste.
        // Payload is immutable while SEND is active, including under stalls.
        (* ram_style="distributed" *) reg [255:0] buffer [0:15];
        reg aw_sent,ack_seen;
        reg [4:0] sent;
        wire aw_fire=axi_awvalid[lane] && axi_awready[lane];
        wire w_fire=axi_wvalid[lane] && axi_wready[lane];
        wire b_fire=axi_bvalid[lane] && axi_bready[lane];
        assign b_seen[lane]=ack_seen;
        assign axi_awvalid[lane]=rst_n && state==SEND && !aw_sent;
        assign axi_awaddr[lane*34+:34]={offset_words[9:8],CHANNEL,offset_words[25:10],offset_words[7:0],5'b0};
        assign axi_awid[lane*6+:6]=6'd0;
        assign axi_awlen[lane*4+:4]=burst_words[3:0]-4'd1;
        assign axi_awsize[lane*3+:3]=3'd5;
        assign axi_awburst[lane*2+:2]=2'b01;
        assign axi_wvalid[lane]=rst_n && state==SEND && sent<burst_words;
        assign axi_wdata[lane*256+:256]=buffer[sent[3:0]];
        assign axi_wstrb[lane*32+:32]=32'hffffffff;
        assign axi_wlast[lane]=sent+5'd1==burst_words;
        assign axi_bready[lane]=rst_n && state==SEND && aw_sent && sent==burst_words && !ack_seen && !protocol_failed;
        assign response_fault[lane]=b_fire && axi_bresp[lane*2+:2]!=2'b00;
        assign protocol_fault[lane]=rst_n && ((b_fire && axi_bid[lane*6+:6]!=6'd0)
            || (axi_bvalid[lane] && (state!=SEND || ack_seen)));
        // HBM_WRITE_STAGE091: a separate local enable drives each lane's
        // small RAM. Invalid staged payload never publishes a buffer write.
        (* DONT_TOUCH="TRUE" *) reg buffer_write_valid_q;
        (* DONT_TOUCH="TRUE" *) reg [3:0] buffer_write_address_q;
        reg [255:0] buffer_write_data_q;
        always @(posedge clk)begin
            buffer_write_valid_q<=write_fire && !bad_word;
            buffer_write_address_q<=captured[3:0];
            buffer_write_data_q<=write_data[lane*256+:256];
            if(buffer_write_valid_q)buffer[buffer_write_address_q]<=buffer_write_data_q;
        end
        always @(posedge clk)begin
            if(!rst_n || burst_begin)begin aw_sent<=0;ack_seen<=0;sent<=0;end
            else begin
                if(aw_fire)aw_sent<=1;
                if(w_fire)sent<=sent+5'd1;
                if(b_fire)ack_seen<=1;
            end
        end
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;failed<=0;protocol_failed<=0;cancelled<=0;
            offset_words<=0;remaining<=0;burst_words<=0;captured<=0;
        end else begin
            if(core_abort)cancelled<=1;
            if(|response_fault)begin failed<=1;cancelled<=1;end
            if(|protocol_fault)begin failed<=1;protocol_failed<=1;cancelled<=1;end
            case(state)
                IDLE:begin
                    // HBM_WRITER_IDLE147: prepare inactive private payload.
                    // The unchanged request/header guard alone admits CAPTURE.
                    offset_words<=request_address[33:8];remaining<=request_bytes[16:8];
                    burst_words<=choose_burst(request_bytes[16:8],request_address[33:8]);
                    captured<=0;
                    if(core_abort)begin failed<=0;cancelled<=0;end
                    if(request_fire)begin
                        if(!header_ok)failed<=1;
                        else begin
                            cancelled<=0;state<=CAPTURE;
                        end
                    end
                end
                CAPTURE:begin
                    if(core_abort || cancelled || failed)state<=IDLE;
                    else if(bad_word)begin failed<=1;state<=IDLE;end
                    else if(write_fire)begin
                        remaining<=remaining-9'd1;captured<=captured+5'd1;
                        if(burst_begin)state<=DRAIN;
                    end
                end
                // The last accepted beat commits on this edge. No AXI
                // request/data is exposed until the following SEND cycle.
                DRAIN:begin
                    if(core_abort || cancelled || failed || protocol_failed || (|protocol_fault))state<=IDLE;
                    else state<=SEND;
                end
                SEND:if(&b_seen)begin
                    if(core_abort || cancelled || failed || protocol_failed)state<=IDLE;
                    else if(remaining==0)state<=DONE;
                    else begin
                        offset_words<=next_offset;burst_words<=choose_burst(remaining,next_offset);
                        captured<=0;state<=CAPTURE;
                    end
                end
                DONE:if(core_abort || cancelled || failed || done_ready)state<=IDLE;
                default:begin failed<=1;protocol_failed<=1;state<=IDLE;end
            endcase
        end
    end
endmodule
