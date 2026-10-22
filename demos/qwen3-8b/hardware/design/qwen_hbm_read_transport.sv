// 8B candidate: fixed global page interleave shared with the model reader.
// PRIVATE bounded read transport for plain K/V (REGION=1) only.
// Logical 256-byte beats are striped over eight 32-byte HBM pseudochannels.
// Requests are aligned/bounded inside one compile-time memory region. This is
// not a public memory interface; the fixed K/V writer/reader owns the requests.
//
// Independent lanes have 64-word FIFOs. Credits reserve space for outstanding
// responses, not just received bytes. Bursts are <=16 words and never cross a
// physical 4 KiB boundary, even for a request not aligned to an AXI burst.
// Normal abort retains presented ARVALID and drains all accepted requests.
// Bad ID/LAST/unsolicited R is fatal until coordinated adapter/fabric reset;
// ordinary response errors drain and recover with core_abort.
// Same clock only: a qualified CDC and vendor HBM remain external.
module qwen_hbm_read_transport #(
    parameter integer REGION=1,
    parameter integer FIFO_DEPTH=64
) (
    input wire clk,input wire rst_n,input wire core_abort,output wire quiescent,output wire error,
    input wire request_valid,output wire request_ready,input wire [33:0] request_address,input wire [16:0] request_bytes,
    output wire data_valid,input wire data_ready,output wire [2047:0] data,output wire data_last,
    output wire [8*34-1:0] axi_araddr,output wire [8*6-1:0] axi_arid,
    output wire [8*4-1:0] axi_arlen,output wire [8*3-1:0] axi_arsize,
    output wire [8*2-1:0] axi_arburst,output wire [7:0] axi_arvalid,input wire [7:0] axi_arready,
    input wire [2047:0] axi_rdata,input wire [8*6-1:0] axi_rid,
    input wire [8*2-1:0] axi_rresp,input wire [7:0] axi_rlast,input wire [7:0] axi_rvalid,output wire [7:0] axi_rready
);
    localparam integer INDEX_BITS=$clog2(FIFO_DEPTH);
    localparam [8:0] CREDIT_LIMIT=9'(FIFO_DEPTH-16);
    localparam [33:0] LIMIT=34'd13659865088;
    localparam [25:0] FIRST=26'(34'd8828026880>>8);
    reg busy,cancelling,failed,protocol_failed;
    reg [25:0] offset_words;
    reg [8:0] total,loaded;
    reg output_valid,output_last,ram_valid,ram_last,delivery_valid,delivery_last;
    wire [2047:0] output_data;
    wire [7:0] empty,pending,response_fault,protocol_fault;
    wire all_drained=!(|pending) && !(|axi_rvalid);
    wire running=rst_n && busy && !core_abort && !cancelling && !failed && !protocol_failed;
    // HBM_OUTPUT180: RAM read, BRAM output register, then fabric delivery.
    wire advance_delivery=running && delivery_valid && (!output_valid || data_ready);
    wire advance_output=running && ram_valid && (!delivery_valid || advance_delivery);
    wire load_output=running && !(|empty) && (!ram_valid || advance_output);
    wire take_output=data_valid && data_ready;
    // HBM_READ_BOUNDS202: equivalent bounds for the four fixed lengths.
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
    wire header_ok=(REGION==1) && request_address[33:8]>=FIRST
        && request_address[7:0]==0 && bounded_length;
    assign error=rst_n && (failed || protocol_failed);
    (* keep="true" *) wire quiet_owner=rst_n && !protocol_failed && !(|pending) && (!busy || cancelling || core_abort || failed);
    assign quiescent=quiet_owner && !(|axi_rvalid);
    assign request_ready=rst_n && !core_abort && !busy && !failed && !protocol_failed && all_drained;
    wire request_fire=request_valid && request_ready;
    assign data_valid=running && output_valid;
    assign data=output_data;
    assign data_last=data_valid && output_last;

    function automatic [4:0] choose_burst(input [8:0] words,input [25:0] offset);
        reg [8:0] count,boundary;
        begin
            boundary=9'd128-{2'b0,offset[6:0]};
            count=words<9'd16 ? words : 9'd16;
            if(boundary<count)count=boundary;
            choose_burst=count[4:0];
        end
    endfunction
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1)begin:lanes
        localparam [2:0] CHANNEL=3'(lane);
        reg [8:0] issued,received,response_burst_end;
        reg address_valid;
        reg [33:0] address;
        reg [4:0] address_words;
        (* ram_style="block" *) reg [255:0] fifo [0:FIFO_DEPTH-1];
        reg [255:0] output_q,delivery_q,fabric_q;
        wire [25:0] next_address_offset=offset_words+{17'b0,issued};
        wire [8:0] next_response_start=received+9'd1;
        wire [25:0] next_response_offset=offset_words+{17'b0,next_response_start};
        wire [4:0] next_response_words=choose_burst(total-next_response_start,next_response_offset);
        wire address_fire=address_valid && axi_arready[lane] && rst_n;
        wire response_fire=axi_rvalid[lane] && axi_rready[lane];
        wire ordered_id=axi_rid[lane*6+:6]==6'd0;
        wire expected_last=received+9'd1==response_burst_end;
        wire proper_last=axi_rlast[lane]==expected_last;
        wire unsolicited=axi_rvalid[lane] && received==issued && !address_valid;
        assign pending[lane]=address_valid || received!=issued;
        assign empty[lane]=received==loaded;
        assign axi_arvalid[lane]=rst_n && address_valid;
        assign axi_araddr[lane*34+:34]=address;
        assign axi_arid[lane*6+:6]=6'd0;
        assign axi_arlen[lane*4+:4]=address_words[3:0]-4'd1;
        assign axi_arsize[lane*3+:3]=3'd5;
        assign axi_arburst[lane*2+:2]=2'b01;
        assign axi_rready[lane]=rst_n && !protocol_failed && received<issued;
        assign response_fault[lane]=response_fire && axi_rresp[lane*2+:2]!=2'b00;
        assign protocol_fault[lane]=rst_n && (unsolicited || (response_fire && (!ordered_id || !proper_last)));
        assign output_data[lane*256+:256]=fabric_q;
        always @(posedge clk)begin
            if(response_fire && running)fifo[received[INDEX_BITS-1:0]]<=axi_rdata[lane*256+:256];
            if(load_output)output_q<=fifo[loaded[INDEX_BITS-1:0]];
            if(advance_output)delivery_q<=output_q;
            if(advance_delivery)fabric_q<=delivery_q;
        end
        always @(posedge clk)begin
            if(!rst_n)begin
                issued<=0;received<=0;response_burst_end<=0;address_valid<=0;address<=0;address_words<=0;
            end else if(request_fire)begin
                issued<=0;received<=0;response_burst_end<={4'b0,choose_burst(request_bytes[16:8],request_address[33:8])};address_valid<=0;
            end else begin
                if(address_fire)begin issued<=issued+{4'b0,address_words};address_valid<=0;end
                if(response_fire)begin
                    received<=received+9'd1;
                    if(expected_last)response_burst_end<=next_response_start+{4'b0,next_response_words};
                end
                if(running && !address_valid && issued<total && issued-loaded<=CREDIT_LIMIT)begin
                    address<={next_address_offset[9:8],CHANNEL,next_address_offset[25:10],next_address_offset[7:0],5'b0};
                    address_words<=choose_burst(total-issued,next_address_offset);address_valid<=1;
                end
            end
        end
    end endgenerate
    always @(posedge clk)begin
        if(!rst_n)begin
            busy<=0;cancelling<=0;failed<=0;protocol_failed<=0;offset_words<=0;total<=0;
            loaded<=0;output_valid<=0;output_last<=0;ram_valid<=0;ram_last<=0;delivery_valid<=0;delivery_last<=0;
        end else begin
            if(request_fire)begin
                offset_words<=request_address[33:8];total<=request_bytes[16:8];
                loaded<=0;output_valid<=0;output_last<=0;ram_valid<=0;ram_last<=0;delivery_valid<=0;delivery_last<=0;cancelling<=0;
                if(header_ok)busy<=1;else begin failed<=1;busy<=0;end
            end
            if(take_output)begin output_valid<=0;if(output_last)busy<=0;end
            if(advance_delivery)begin delivery_valid<=0;output_valid<=1;output_last<=delivery_last;end
            if(advance_output)begin ram_valid<=0;delivery_valid<=1;delivery_last<=ram_last;end
            if(load_output)begin loaded<=loaded+9'd1;ram_valid<=1;ram_last<=loaded+9'd1==total;end
            if(core_abort || failed || (|response_fault) || (|protocol_fault))begin
                cancelling<=1;output_valid<=0;ram_valid<=0;delivery_valid<=0;
                if(all_drained)begin busy<=0;if(core_abort)begin failed<=0;cancelling<=0;end end
            end
            if(|response_fault)failed<=1;
            if(|protocol_fault)begin failed<=1;protocol_failed<=1;end
        end
    end
endmodule
