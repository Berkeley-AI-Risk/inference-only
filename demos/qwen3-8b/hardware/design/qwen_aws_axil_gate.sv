// Shell-clock AXI-Lite lifecycle guard. The PRIVATE target is the restricted
// token endpoint, never a raw-memory or clock-control endpoint. 'online' is a
// trusted hardware lifecycle signal, not a host-selectable bypass mode.
//
// Offline requests finish with zero/error without touching the target. AW/W
// are collected independently before either is sent onward. Accepted host
// responses survive target shutdown and remain stable under backpressure.
// IMPORTANT: every falling online edge must assert the PRIVATE target's reset
// at the same time, cancelling its in-flight AXI transactions coherently. The
// shell side remains alive. Ordinary application CLEAR must not change online.
// This guard supplies no downstream watchdog; the lifecycle owner must take
// a failed/stalled target offline. Whole-shell reset may discard host requests.
// Tie online=0 and OFFLINE_RESPONSE=3 for an always-disabled SDA endpoint.
module qwen_aws_axil_gate #(
    parameter [1:0] OFFLINE_RESPONSE=2'b10
) (
    input wire clk,input wire rst_n,input wire online,
    input wire [31:0] s_awaddr,input wire s_awvalid,output wire s_awready,
    input wire [31:0] s_wdata,input wire [3:0] s_wstrb,input wire s_wvalid,output wire s_wready,
    output reg [1:0] s_bresp,output reg s_bvalid,input wire s_bready,
    input wire [31:0] s_araddr,input wire s_arvalid,output wire s_arready,
    output reg [31:0] s_rdata,output reg [1:0] s_rresp,output reg s_rvalid,input wire s_rready,
    output wire [31:0] m_awaddr,output wire m_awvalid,input wire m_awready,
    output wire [31:0] m_wdata,output wire [3:0] m_wstrb,output wire m_wvalid,input wire m_wready,
    input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
    output wire [31:0] m_araddr,output wire m_arvalid,input wire m_arready,
    input wire [31:0] m_rdata,input wire [1:0] m_rresp,input wire m_rvalid,output wire m_rready
);
    reg aw_full,w_full,write_issued,write_reject,aw_sent,w_sent;
    reg ar_full,read_reject,ar_sent;
    reg [31:0] aw_buffer,w_buffer,ar_buffer;
    reg [3:0] strb_buffer;
    assign s_awready=rst_n && !aw_full && !s_bvalid;
    assign s_wready=rst_n && !w_full && !s_bvalid;
    assign s_arready=rst_n && !ar_full && !s_rvalid;
    assign m_awaddr=aw_buffer;
    assign m_wdata=w_buffer;
    assign m_wstrb=strb_buffer;
    assign m_araddr=ar_buffer;
    assign m_awvalid=rst_n && online && write_issued && !write_reject && !s_bvalid && !aw_sent;
    assign m_wvalid=rst_n && online && write_issued && !write_reject && !s_bvalid && !w_sent;
    assign m_bready=rst_n && online && write_issued && !write_reject && aw_sent && w_sent && !s_bvalid;
    assign m_arvalid=rst_n && online && ar_full && !read_reject && !ar_sent && !s_rvalid;
    assign m_rready=rst_n && online && ar_full && !read_reject && ar_sent && !s_rvalid;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            aw_full<=0;w_full<=0;write_issued<=0;write_reject<=0;aw_sent<=0;w_sent<=0;
            ar_full<=0;read_reject<=0;ar_sent<=0;
            s_bresp<=0;s_bvalid<=0;s_rdata<=0;s_rresp<=0;s_rvalid<=0;
            aw_buffer<=0;w_buffer<=0;strb_buffer<=0;ar_buffer<=0;
        end else begin
            if(s_awvalid && s_awready) begin
                aw_full<=1;aw_buffer<=s_awaddr;if(!online)write_reject<=1;
            end
            if(s_wvalid && s_wready) begin
                w_full<=1;w_buffer<=s_wdata;strb_buffer<=s_wstrb;if(!online)write_reject<=1;
            end
            // Latch shutdown even if it occurs between the two host channels.
            if(!online && (aw_full || w_full))write_reject<=1;
            if(m_awvalid && m_awready)aw_sent<=1;
            if(m_wvalid && m_wready)w_sent<=1;
            if(aw_full && w_full && !s_bvalid) begin
                if(write_reject || !online) begin
                    write_issued<=1;s_bvalid<=1;s_bresp<=OFFLINE_RESPONSE;
                end else if(!write_issued)write_issued<=1;
                else if(m_bvalid && m_bready)begin s_bvalid<=1;s_bresp<=m_bresp;end
            end
            if(s_bvalid && s_bready) begin
                s_bvalid<=0;aw_full<=0;w_full<=0;write_issued<=0;write_reject<=0;aw_sent<=0;w_sent<=0;
            end
            if(s_arvalid && s_arready)begin
                ar_full<=1;ar_buffer<=s_araddr;read_reject<=!online;
            end
            if(!online && ar_full)read_reject<=1;
            if(m_arvalid && m_arready)ar_sent<=1;
            if(ar_full && !s_rvalid)begin
                if(read_reject || !online)begin s_rvalid<=1;s_rdata<=0;s_rresp<=OFFLINE_RESPONSE;end
                else if(m_rvalid && m_rready)begin s_rvalid<=1;s_rdata<=m_rdata;s_rresp<=m_rresp;end
            end
            if(s_rvalid && s_rready)begin s_rvalid<=0;ar_full<=0;read_reject<=0;ar_sent<=0;end
        end
    end
endmodule
