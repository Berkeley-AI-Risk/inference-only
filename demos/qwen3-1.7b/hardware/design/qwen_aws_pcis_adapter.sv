// Full-width AWS PCIS IDs around the existing ordered six-bit ingress ABI.
// Both AW/B and AR/R queues retain all 16 ID bits; IDs are not silently truncated.
// This adapter is specific to the ordered receiver, NOT an arbitrary AXI fabric.
// Invalid write burst/lock attributes poison the aperture address, causing the
// fixed receiver to drain/reject the write and latch its normal startup error.
// No data, address, credit or boot-permission bypass is introduced.
module qwen_aws_pcis_adapter #(
    // Only for a directly connected guard whose ARREADY clears
    // asynchronously on this same reset. Not a general AXI mode.
    parameter bit GUARDED_AR_READY=1'b0,
    // Only with the paired asynchronously reset read guard.
    parameter bit GUARDED_READ_VALID=1'b0
) (
    input wire clk,input wire rst_n,
    input wire [1:0] s_awburst,input wire s_awlock,
    input wire [63:0] s_awaddr,
    input wire [15:0] s_awid,
    input wire [7:0] s_awlen,
    input wire [2:0] s_awsize,
    input wire s_awvalid,
    output wire s_awready,
    input wire [511:0] s_wdata,
    input wire [63:0] s_wstrb,
    input wire s_wlast,
    input wire s_wvalid,
    output wire s_wready,
    output wire [15:0] s_bid,
    output wire [1:0] s_bresp,
    output wire s_bvalid,
    input wire s_bready,
    input wire [63:0] s_araddr,
    input wire [15:0] s_arid,
    input wire [7:0] s_arlen,
    input wire [2:0] s_arsize,
    input wire s_arvalid,
    output wire s_arready,
    output wire [511:0] s_rdata,
    output wire [15:0] s_rid,
    output wire [1:0] s_rresp,
    output wire s_rlast,
    output wire s_rvalid,
    input wire s_rready,
    output wire [63:0] m_awaddr,
    output wire [5:0] m_awid,
    output wire [7:0] m_awlen,
    output wire [2:0] m_awsize,
    output wire m_awvalid,
    input wire m_awready,
    output wire [511:0] m_wdata,
    output wire [63:0] m_wstrb,
    output wire m_wlast,
    output wire m_wvalid,
    input wire m_wready,
    input wire [5:0] m_bid,
    input wire [1:0] m_bresp,
    input wire m_bvalid,
    output wire m_bready,
    output wire [63:0] m_araddr,
    output wire [5:0] m_arid,
    output wire [7:0] m_arlen,
    output wire [2:0] m_arsize,
    output wire m_arvalid,
    input wire m_arready,
    input wire [511:0] m_rdata,
    input wire [5:0] m_rid,
    input wire [1:0] m_rresp,
    input wire m_rlast,
    input wire m_rvalid,
    output wire m_rready
);
    (* ram_style="distributed" *) reg [15:0] write_ids [0:31];
    (* ram_style="distributed" *) reg [15:0] read_ids [0:31];
    reg [4:0] write_push,write_pop,read_push,read_pop;
    reg [5:0] write_count,read_count;
    wire aw_take=s_awvalid && s_awready;
    wire b_take=s_bvalid && s_bready;
    wire ar_take=s_arvalid && s_arready;
    wire r_finish=s_rvalid && s_rready && s_rlast;
    assign m_awaddr=(s_awburst==2'b01 && !s_awlock) ? s_awaddr : (s_awaddr | 64'h8000000000000000);
    assign m_awid=s_awid[5:0];
    assign m_awlen=s_awlen;
    assign m_awsize=s_awsize;
    assign m_awvalid=rst_n && write_count<32 && s_awvalid;
    assign s_awready=rst_n && write_count<32 && m_awready;
    assign m_wdata=s_wdata;
    assign m_wstrb=s_wstrb;
    assign m_wlast=s_wlast;
    assign m_wvalid=rst_n && s_wvalid;
    assign s_wready=rst_n && m_wready;
    assign s_bid=s_bvalid ? write_ids[write_pop] : 16'b0;
    assign s_bresp=m_bresp;
    assign s_bvalid=rst_n && write_count!=0 && m_bvalid;
    assign m_bready=rst_n && write_count!=0 && s_bready;
    assign m_araddr=s_araddr;
    assign m_arid=s_arid[5:0];
    assign m_arlen=s_arlen;
    assign m_arsize=s_arsize;
    assign m_arvalid=rst_n && read_count<32 && s_arvalid;
    assign s_arready=(GUARDED_AR_READY || rst_n) && read_count<32 && m_arready;
    assign s_rdata=m_rdata;
    assign s_rid=s_rvalid ? read_ids[read_pop] : 16'b0;
    assign s_rresp=m_rresp;
    assign s_rlast=m_rlast;
    assign s_rvalid=(GUARDED_READ_VALID || rst_n) && read_count!=0 && m_rvalid;
    assign m_rready=rst_n && read_count!=0 && s_rready;
    always @(posedge clk) begin
        if(!rst_n) begin
            write_push<=0;write_pop<=0;read_push<=0;read_pop<=0;write_count<=0;read_count<=0;
        end else begin
            write_count<=write_count+6'(aw_take)-6'(b_take);
            read_count<=read_count+6'(ar_take)-6'(r_finish);
            if(aw_take)begin write_ids[write_push]<=s_awid;write_push<=write_push+1'b1;end
            if(b_take)write_pop<=write_pop+1'b1;
            if(ar_take)begin read_ids[read_push]<=s_arid;read_push<=read_push+1'b1;end
            if(r_finish)read_pop<=read_pop+1'b1;
        end
    end
    // The inner receiver returns both streams in acceptance order. These
    // simulation checks make that dependency explicit; they add no host ports.
    // synthesis translate_off
    always @(posedge clk)if(rst_n)begin
        if(m_bvalid && (write_count==0 || m_bid!=write_ids[write_pop][5:0]))
            $fatal(1,"Inner PCIS B response violated ordered adapter contract");
        if(m_rvalid && (read_count==0 || m_rid!=read_ids[read_pop][5:0]))
            $fatal(1,"Inner PCIS R response violated ordered adapter contract");
    end
    // synthesis translate_on
endmodule
