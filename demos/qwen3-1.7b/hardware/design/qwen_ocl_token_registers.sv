// Bounded token-only AXI-Lite register endpoint. All ports use the shell clock.
// AW and W are captured independently. No bus transaction waits for inference.
// Unavailable command credit produces a readable BUSY outcome, not a long stall.
// The host cannot choose the private IDs, tensor addresses or arithmetic modes.
//
// Writes (full WSTRB only): 0x100 APPEND(token), 0x104 STEP(0), 0x108 CLEAR(0).
// Reads: 0x000 ID, 004 ABI, 008 status, 00c last write outcome, 010 last command
// ID, 014 last response ID, 018 ingress credits, 01c ingress accepted bytes,
// 020 packed result (read-to-consume), 024 fixed image size. All other accesses
// are rejected. Only status inputs are readable; there is no HBM read window.
//
// Result: bit31 valid, bits21:18 status, bits17:0 token; other bits zero.
// Result capture/pop linearizes at AR handshake. An already captured AXI R
// response remains stable even if CLEAR arrives later. A simultaneous CLEAR
// command acceptance wins over an as-yet uncaptured old result.
module qwen_ocl_token_registers (
    input wire clk,input wire rst_n,
    input wire [31:0] ocl_awaddr,input wire ocl_awvalid,output wire ocl_awready,
    input wire [31:0] ocl_wdata,input wire [3:0] ocl_wstrb,input wire ocl_wvalid,output wire ocl_wready,
    output wire [1:0] ocl_bresp,output wire ocl_bvalid,input wire ocl_bready,
    input wire [31:0] ocl_araddr,input wire ocl_arvalid,output wire ocl_arready,
    output wire [31:0] ocl_rdata,output wire [1:0] ocl_rresp,output wire ocl_rvalid,input wire ocl_rready,
    output wire command_valid,input wire command_ready,
    output wire [31:0] command_id,output wire [7:0] command_opcode,output wire [31:0] command_token,
    input wire result_valid,output wire result_ready,
    input wire [31:0] result_id,input wire [3:0] result_status,input wire [31:0] result_token,
    input wire model_ready,input wire model_loading,input wire model_error,
    input wire ingress_error,input wire [15:0] ingress_credit_blocks,input wire [31:0] ingress_received_bytes
);
    localparam [31:0] DESIGN_ID=32'h51494f31,ABI_VERSION=32'd1,IMAGE_BYTES=32'd2354380800;
    localparam [3:0] ACCEPTED=0,BAD_ADDRESS=1,BAD_STROBES=2,BAD_PAYLOAD=3,COMMAND_BUSY=4;
    reg aw_pending,w_pending,b_pending,r_pending;
    reg [31:0] aw_address,w_data,read_data;
    reg [3:0] w_strobes,last_write_outcome;
    reg [1:0] write_response,read_response;
    reg outstanding,clear_outstanding,reply_pending;
    reg [31:0] next_id,latest_id,waiting_id,reply_id;
    reg [7:0] waiting_opcode;
    reg [3:0] reply_status;
    reg [17:0] reply_token;
    // Retire a held B response before executing another buffered write.
    // This prevents lifecycle-gated BREADY from feeding the command FIFO's
    // write enable or the simultaneous CLEAR/status selection in this cycle.
    // BVALID/data stability, address/data buffering and CLEAR priority remain.
    wire write_execute=rst_n && aw_pending && w_pending && !b_pending;
    wire address_ok=aw_address==32'h100 || aw_address==32'h104 || aw_address==32'h108;
    wire append=aw_address==32'h100,clear=aw_address==32'h108;
    wire payload_ok=append ? w_data<32'd151936 : w_data==0;
    wire ordinary_credit=!outstanding && !reply_pending && !clear_outstanding && command_ready;
    wire clear_credit=!clear_outstanding && command_ready;
    wire allowed=address_ok && w_strobes==4'hf && payload_ok && (clear ? clear_credit : ordinary_credit);
    wire accepted=write_execute && allowed;
    wire clear_accept=accepted && clear;
    wire read_take=ocl_arvalid && ocl_arready;
    wire pop_reply=read_take && ocl_araddr==32'h020;
    wire matched_result=result_valid && result_ready && outstanding && result_id==waiting_id;
    wire good_result_status=result_status<=4'd6;
    wire generated_result=waiting_opcode==8'd2 && result_status==0;
    wire good_result_token=!generated_result || result_token<32'd151936;

    assign ocl_awready=rst_n && !aw_pending;
    assign ocl_wready=rst_n && !w_pending;
    assign ocl_bvalid=rst_n && b_pending;
    assign ocl_bresp=write_response;
    assign ocl_arready=rst_n && (!r_pending || ocl_rready);
    assign ocl_rvalid=rst_n && r_pending;
    assign ocl_rdata=read_data;
    assign ocl_rresp=read_response;
    // Offer only when FIFO credit is present; rejection is recorded locally.
    assign command_valid=accepted;
    assign command_id=next_id;
    assign command_opcode=append ? 8'd1 : clear ? 8'd3 : 8'd2;
    assign command_token=append ? w_data : 32'b0;
    assign result_ready=rst_n;

    always @(posedge clk)begin
        if(!rst_n)begin
            aw_pending<=0;w_pending<=0;b_pending<=0;r_pending<=0;
            aw_address<=0;w_data<=0;w_strobes<=0;read_data<=0;
            last_write_outcome<=ACCEPTED;write_response<=0;read_response<=0;
            outstanding<=0;clear_outstanding<=0;reply_pending<=0;
            next_id<=1;latest_id<=0;waiting_id<=0;reply_id<=0;waiting_opcode<=0;reply_status<=0;reply_token<=0;
        end else begin
            if(ocl_awvalid && ocl_awready)begin aw_pending<=1;aw_address<=ocl_awaddr;end
            if(ocl_wvalid && ocl_wready)begin w_pending<=1;w_data<=ocl_wdata;w_strobes<=ocl_wstrb;end
            if(ocl_bvalid && ocl_bready)b_pending<=0;
            if(ocl_rvalid && ocl_rready)r_pending<=0;
            if(pop_reply)reply_pending<=0;
            if(matched_result)begin
                outstanding<=0;clear_outstanding<=0;reply_pending<=1;reply_id<=result_id;
                reply_status<=good_result_status && good_result_token ? result_status : 4'd6;
                reply_token<=good_result_status && good_result_token && generated_result ? result_token[17:0] : 18'b0;
            end
            if(write_execute)begin
                aw_pending<=0;w_pending<=0;b_pending<=1;
                write_response<=accepted ? 2'b00 : address_ok ? 2'b10 : 2'b11;
                if(!address_ok)last_write_outcome<=BAD_ADDRESS;
                else if(w_strobes!=4'hf)last_write_outcome<=BAD_STROBES;
                else if(!payload_ok)last_write_outcome<=BAD_PAYLOAD;
                else if(!allowed)last_write_outcome<=COMMAND_BUSY;
                else last_write_outcome<=ACCEPTED;
            end
            if(accepted)begin
                latest_id<=next_id;waiting_id<=next_id;next_id<=next_id+32'd1;
                waiting_opcode<=command_opcode;outstanding<=1;clear_outstanding<=clear;
                if(clear)reply_pending<=0;
            end
            if(read_take)begin
                r_pending<=1;read_response<=2'b00;
                case(ocl_araddr)
                    32'h000:read_data<=DESIGN_ID;
                    32'h004:read_data<=ABI_VERSION;
                    32'h008:read_data<={24'b0,ingress_error,model_error,model_loading,model_ready,
                        reply_pending && !clear_accept,outstanding,clear_credit,ordinary_credit};
                    32'h00c:read_data<={28'b0,last_write_outcome};
                    32'h010:read_data<=latest_id;
                    32'h014:read_data<=reply_id;
                    32'h018:read_data<={16'b0,ingress_credit_blocks};
                    32'h01c:read_data<=ingress_received_bytes;
                    32'h020:read_data<=reply_pending && !clear_accept ? {1'b1,9'b0,reply_status,reply_token} : 32'b0;
                    32'h024:read_data<=IMAGE_BYTES;
                    default:begin read_data<=0;read_response<=2'b11;end
                endcase
            end
        end
    end
endmodule
