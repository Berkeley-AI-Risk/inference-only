// PRIVATE fixed-model page transport over eight HBM AXI3 read ports.
// 64 KiB logical pages are striped in 32-byte pieces over eight channels, rotating each page among four channel groups.
// Address on lane L: {page[1:0], 3'(L), page[17:2], burst[3:0], 9'b0}.
// Each page uses sixteen INCR bursts of sixteen 32-byte beats per lane.
// Same-ID responses are ordered within a lane; lanes may complete independently.
//
// This module runs in the HBM AXI clock domain. A qualified CDC boundary,
// HBM IP/monitor hookup, provisioning writer and AWS shell remain external.
// rst_n may be asserted only with a coordinated reset/drain of the AXI fabric;
// use abort, NOT rst_n, for application CLEAR or numerical-core cancellation.
// Abort never retracts an already asserted ARVALID: pending addresses are
// accepted and all requested responses drained before quiescent becomes true.
// RRESP errors drain and recover with abort. ID/framing/unsolicited-response
// errors fail closed until a coordinated fabric reset: drainage is then unknown.
module qwen_model_hbm_reader #(
    parameter integer FIFO_DEPTH=64
) (
    input wire clk,input wire rst_n,input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire [17:0] request_page,
    output wire data_valid,input wire data_ready,output wire [2047:0] data,output wire data_last,
    output wire [8*34-1:0] axi_araddr,output wire [8*6-1:0] axi_arid,
    output wire [8*4-1:0] axi_arlen,output wire [8*3-1:0] axi_arsize,
    output wire [8*2-1:0] axi_arburst,output wire [7:0] axi_arvalid,input wire [7:0] axi_arready,
    input wire [8*256-1:0] axi_rdata,input wire [8*6-1:0] axi_rid,
    input wire [8*2-1:0] axi_rresp,input wire [7:0] axi_rlast,input wire [7:0] axi_rvalid,
    output wire [7:0] axi_rready
);
    localparam integer INDEX_BITS=$clog2(FIFO_DEPTH);
    localparam [8:0] CREDIT_LIMIT=9'(FIFO_DEPTH-16);
    reg busy,cancelling,failed,protocol_failed;
    reg [17:0] page;
    reg [8:0] loaded;
    reg output_valid,output_last;
    wire [2047:0] output_data;
    wire [7:0] empty,pending,response_fault,protocol_fault;
    wire all_drained=!(|pending) && !(|axi_rvalid);
    wire running=rst_n && busy && !core_abort && !cancelling && !failed && !protocol_failed;
    wire load_output=running && !(|empty) && (!output_valid || data_ready);
    wire take_output=data_valid && data_ready;
    assign error=rst_n && (failed || protocol_failed);
    (* keep="true" *) wire quiet_owner=rst_n && !protocol_failed && !(|pending) && (!busy || cancelling || core_abort || failed);
    assign quiescent=quiet_owner && !(|axi_rvalid);
    assign request_ready=rst_n && !core_abort && !busy && !failed && !protocol_failed && all_drained;
    wire request_fire=request_valid && request_ready;
    assign data_valid=running && output_valid;
    assign data=data_valid ? output_data : 2048'b0;
    assign data_last=data_valid && output_last;

    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1)begin:lanes
        localparam [2:0] CHANNEL=3'(lane);
        reg [8:0] issued,received;
        reg address_valid;
        reg [33:0] address;
        (* ram_style="block" *) reg [255:0] fifo [0:FIFO_DEPTH-1];
        reg [255:0] output_q;
        wire address_fire=address_valid && axi_arready[lane] && rst_n;
        wire response_fire=axi_rvalid[lane] && axi_rready[lane];
        wire ordered_id=axi_rid[lane*6+:6]==6'd0;
        wire proper_last=axi_rlast[lane]==(received[3:0]==4'd15);
        wire unsolicited=axi_rvalid[lane] && received==issued && !address_valid;
        assign pending[lane]=address_valid || received!=issued;
        assign empty[lane]=received==loaded;
        assign axi_arvalid[lane]=rst_n && address_valid;
        assign axi_araddr[lane*34+:34]=address;
        assign axi_arid[lane*6+:6]=6'd0;
        assign axi_arlen[lane*4+:4]=4'd15;
        assign axi_arsize[lane*3+:3]=3'd5;
        assign axi_arburst[lane*2+:2]=2'b01;
        assign axi_rready[lane]=rst_n && !protocol_failed && received<issued;
        assign response_fault[lane]=response_fire && axi_rresp[lane*2+:2]!=2'b00;
        assign protocol_fault[lane]=rst_n && (unsolicited || (response_fire && (!ordered_id || !proper_last)));
        assign output_data[lane*256+:256]=output_q;
        // No data-RAM reset or combinational read port.
        always @(posedge clk)begin
            if(response_fire && running)fifo[received[INDEX_BITS-1:0]]<=axi_rdata[lane*256+:256];
            // PRIVATE_MODEL_FIFO_READ119: held valid payload is retained.
            // Extra private reads never advance loaded or assert output_valid.
            if(!output_valid || data_ready)output_q<=fifo[loaded[INDEX_BITS-1:0]];
        end
        always @(posedge clk)begin
            if(!rst_n)begin issued<=0;received<=0;address_valid<=0;address<=0;end
            else if(request_fire)begin issued<=0;received<=0;address_valid<=0;end
            else begin
                if(address_fire)begin issued<=issued+9'd16;address_valid<=0;end
                if(response_fire)received<=received+9'd1;
                // Reserve enough FIFO space for a whole burst, including
                // responses not yet received. Do not depend on RREADY for
                // downstream cancellation or discard an outstanding request.
                if(running && !address_valid && issued<9'd256 && issued-loaded<=CREDIT_LIMIT)begin
                    address<={page[1:0],CHANNEL,page[17:2],issued[7:4],9'b0};address_valid<=1;
                end
            end
        end
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            busy<=0;cancelling<=0;failed<=0;protocol_failed<=0;page<=0;
            loaded<=0;output_valid<=0;output_last<=0;
        end else begin
            if(request_fire)begin
                page<=request_page;loaded<=0;output_valid<=0;output_last<=0;cancelling<=0;
                if(request_page<18'd134705)busy<=1;
                else begin failed<=1;busy<=0;end
            end
            if(take_output)begin output_valid<=0;if(output_last)busy<=0;end
            if(load_output)begin loaded<=loaded+9'd1;output_valid<=1;output_last<=loaded==9'd255;end
            if(core_abort || failed || (|response_fault) || (|protocol_fault))begin
                cancelling<=1;output_valid<=0;
                if(all_drained)begin busy<=0;if(core_abort)begin failed<=0;cancelling<=0;end end
            end
            if(|response_fault)failed<=1;
            if(|protocol_fault)begin failed<=1;protocol_failed<=1;end
        end
    end
endmodule
