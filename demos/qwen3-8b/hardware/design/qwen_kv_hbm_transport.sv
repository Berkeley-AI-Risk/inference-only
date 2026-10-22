// PRIVATE same-clock bridge for the protected K/V store's two internal buses.
// One transaction owns the physical ports at a time. Updates have priority;
// cancellation affects the current owner, never an unrelated idle interface.
// An attention abort cannot cancel a writer. A writer cannot preempt an
// accepted read without draining it. There is no host raw-memory access here.
// Fixed 8B baseline: REGION=1 owns the entire private K/V interval.
// AXI master ports 8..15 address all pseudochannels through the switch.
// The legacy second master group is never selected; REGION=2 rejects.
// Address range checks below and in each child enforce K/V/model separation.
// No CDC, vendor HBM, shell, or physical timing qualification is included.
module qwen_kv_hbm_transport (
    input wire clk,input wire rst_n,
    input wire update_request_valid,output wire update_request_ready,input wire update_request_write,
    input wire [33:0] update_address,input wire [16:0] update_bytes,
    output wire update_read_valid,input wire update_read_ready,output wire [2047:0] update_read_data,
    output wire update_read_last,output wire update_read_error,
    input wire update_write_valid,output wire update_write_ready,input wire [2047:0] update_write_data,
    input wire update_write_last,output wire update_done_valid,input wire update_done_ready,output wire update_done_error,
    output wire update_error,input wire update_abort,output wire update_quiescent,
    input wire read_request_valid,output wire read_request_ready,input wire [33:0] read_address,input wire [12:0] read_bytes,
    output wire read_data_valid,input wire read_data_ready,output wire [2047:0] read_data,
    output wire read_last,output wire read_data_error,output wire read_error,input wire read_abort,output wire read_quiescent,
    output wire [16*34-1:0] axi_araddr,output wire [16*6-1:0] axi_arid,
    output wire [16*4-1:0] axi_arlen,output wire [16*3-1:0] axi_arsize,
    output wire [16*2-1:0] axi_arburst,output wire [15:0] axi_arvalid,input wire [15:0] axi_arready,
    input wire [4095:0] axi_rdata,input wire [16*6-1:0] axi_rid,
    input wire [16*2-1:0] axi_rresp,input wire [15:0] axi_rlast,input wire [15:0] axi_rvalid,output wire [15:0] axi_rready,
    output wire [16*34-1:0] axi_awaddr,output wire [16*6-1:0] axi_awid,
    output wire [16*4-1:0] axi_awlen,output wire [16*3-1:0] axi_awsize,
    output wire [16*2-1:0] axi_awburst,output wire [15:0] axi_awvalid,input wire [15:0] axi_awready,
    output wire [4095:0] axi_wdata,output wire [511:0] axi_wstrb,
    output wire [15:0] axi_wlast,output wire [15:0] axi_wvalid,input wire [15:0] axi_wready,
    input wire [16*6-1:0] axi_bid,input wire [16*2-1:0] axi_bresp,input wire [15:0] axi_bvalid,output wire [15:0] axi_bready
);
    localparam [2:0] IDLE=0,ISSUE=1,ACTIVE=2,DRAIN=3,CANCEL=4;
    reg [2:0] state;
    reg owner_update,writing,region_select,failed;
    reg [33:0] address;
    reg [16:0] bytes;
    wire [1:0] rq,wq,re,we,rr,wr,rv,rl,wready,wcomplete;
    wire [4095:0] rd;
    wire all_quiet=(&rq) && (&wq);
    wire fault=failed || (|re) || (|we);
    wire owner_abort=owner_update ? update_abort : read_abort;
    wire abort_bus=state==CANCEL || (state!=IDLE && owner_abort)
        || (state==IDLE && (update_abort || read_abort));
    wire idle=rst_n && state==IDLE && all_quiet && !fault;
    wire active=rst_n && state==ACTIVE && !owner_abort && !fault;
    wire update_take=update_request_valid && update_request_ready;
    wire read_take=read_request_valid && read_request_ready;
    wire result_take=(update_read_valid && update_read_ready && update_read_last)
        || (read_data_valid && read_data_ready && read_last)
        || (update_done_valid && update_done_ready);
    assign update_request_ready=idle && !update_abort;
    assign read_request_ready=idle && !read_abort && !(update_request_valid && !update_abort);
    assign update_quiescent=rst_n && state==IDLE && all_quiet;
    assign read_quiescent=update_quiescent;
    assign update_error=rst_n && fault;
    assign read_error=update_error;
    assign update_read_error=1'b0;
    assign read_data_error=1'b0;
    assign update_done_error=1'b0;
    assign update_read_valid=active && owner_update && !writing && rv[region_select];
    assign read_data_valid=active && !owner_update && rv[region_select];
    // KV_REGION083: local private copies of the existing descriptor bit.
    // These replicas have exactly the original reset, capture and hold rule.
    (* DONT_TOUCH = "yes" *) reg [63:0] read_region_q;
    always @(posedge clk)begin
        if(!rst_n)read_region_q<=0;
        else if(state==IDLE)
            read_region_q<=64'b0;
    end
    genvar stripe;
    generate for(stripe=0;stripe<64;stripe=stripe+1)begin:read_stripes
        wire [31:0] selected_data=read_region_q[stripe] ?
            rd[2048+stripe*32+:32] : rd[stripe*32+:32];
        assign update_read_data[stripe*32+:32]=selected_data;
        assign read_data[stripe*32+:32]=selected_data;
    end endgenerate
    assign update_read_last=update_read_valid && rl[region_select];
    assign read_last=read_data_valid && rl[region_select];
    assign update_write_ready=active && writing && wready[region_select];
    assign update_done_valid=active && writing && wcomplete[region_select];
    genvar r;
    generate for(r=0;r<2;r=r+1)begin:regions
        wire selected=region_select==1'(r);
        wire issue=rst_n && state==ISSUE && selected && !owner_abort && !fault;
        wire read_ready=active && selected && !writing && (owner_update ? update_read_ready : read_data_ready);
        qwen_hbm_read_transport #(.REGION(r+1)) reader(
            .clk(clk),.rst_n(rst_n),.core_abort(abort_bus),.quiescent(rq[r]),.error(re[r]),
            .request_valid(issue && !writing),.request_ready(rr[r]),.request_address(address),.request_bytes(bytes),
            .data_valid(rv[r]),.data_ready(read_ready),.data(rd[r*2048+:2048]),.data_last(rl[r]),
            .axi_araddr(axi_araddr[r*272+:272]),
            .axi_arid(axi_arid[r*48+:48]),
            .axi_arlen(axi_arlen[r*32+:32]),
            .axi_arsize(axi_arsize[r*24+:24]),
            .axi_arburst(axi_arburst[r*16+:16]),
            .axi_arvalid(axi_arvalid[r*8+:8]),
            .axi_arready(axi_arready[r*8+:8]),
            .axi_rdata(axi_rdata[r*2048+:2048]),
            .axi_rid(axi_rid[r*48+:48]),
            .axi_rresp(axi_rresp[r*16+:16]),
            .axi_rlast(axi_rlast[r*8+:8]),
            .axi_rvalid(axi_rvalid[r*8+:8]),
            .axi_rready(axi_rready[r*8+:8]));
        qwen_hbm_write_transport #(.REGION(r+1)) writer(
            .clk(clk),.rst_n(rst_n),.core_abort(abort_bus),.quiescent(wq[r]),.error(we[r]),
            .request_valid(issue && writing),.request_ready(wr[r]),.request_address(address),.request_bytes(bytes),
            .write_valid(active && selected && writing && update_write_valid),.write_ready(wready[r]),
            .write_data(update_write_data),.write_last(update_write_last),
            .done_valid(wcomplete[r]),.done_ready(active && selected && writing && update_done_ready),
            .axi_awaddr(axi_awaddr[r*272+:272]),
            .axi_awid(axi_awid[r*48+:48]),
            .axi_awlen(axi_awlen[r*32+:32]),
            .axi_awsize(axi_awsize[r*24+:24]),
            .axi_awburst(axi_awburst[r*16+:16]),
            .axi_awvalid(axi_awvalid[r*8+:8]),
            .axi_awready(axi_awready[r*8+:8]),
            .axi_wdata(axi_wdata[r*2048+:2048]),
            .axi_wstrb(axi_wstrb[r*256+:256]),
            .axi_wlast(axi_wlast[r*8+:8]),
            .axi_wvalid(axi_wvalid[r*8+:8]),
            .axi_wready(axi_wready[r*8+:8]),
            .axi_bid(axi_bid[r*48+:48]),
            .axi_bresp(axi_bresp[r*16+:16]),
            .axi_bvalid(axi_bvalid[r*8+:8]),
            .axi_bready(axi_bready[r*8+:8]));
    end endgenerate
    // Descriptor bits are private and inactive throughout IDLE. Preparing
    // them does not accept a request: the unchanged state/admission logic
    // alone enables ISSUE. Accepted updates retain their original priority.
    wire descriptor_update=update_request_valid && !update_abort;
    always @(posedge clk)begin
        if(!rst_n)begin owner_update<=0;writing<=0;region_select<=0;address<=0;bytes<=0;end
        else if(state==IDLE)begin
            owner_update<=descriptor_update;
            writing<=descriptor_update && update_request_write;
            address<=descriptor_update ? update_address : read_address;
            bytes<=descriptor_update ? update_bytes : {4'b0,read_bytes};
            region_select<=1'b0;
        end
    end
    always @(posedge clk)begin
        if(!rst_n)begin
            state<=IDLE;failed<=0;
        end else begin
            case(state)
                IDLE:if(update_take || read_take)begin
                    if((update_take && update_address>=34'd8828026880 && update_address<34'd13659865088)
                        || (read_take && read_address>=34'd8828026880 && read_address<34'd13659865088))state<=ISSUE;
                    else begin failed<=1;state<=ACTIVE;end
                end
                ISSUE:if(owner_abort)state<=CANCEL;
                    else if(!fault && (writing ? wr[region_select] : rr[region_select]))state<=ACTIVE;
                ACTIVE:if(owner_abort)state<=CANCEL;
                    else if(result_take)state<=DRAIN;
                DRAIN:if(owner_abort)state<=CANCEL;
                    else if(all_quiet && !fault)state<=IDLE;
                CANCEL:if(all_quiet)begin failed<=0;state<=IDLE;end
                default:begin failed<=1;state<=CANCEL;end
            endcase
        end
    end
endmodule

