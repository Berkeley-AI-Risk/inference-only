// PRIVATE fixed K/V external-memory layout, in one place. Pure combinational
// constants derived from internal coordinates; no software supplies any input.
// The two bases select the AWS HBM regions decoded by the released transport:
// bit 32 = payload (REGION 1), bit 33 = digest lists (REGION 2).
//
// A larger model or an ASIC memory map changes these parameters and this module,
// not the owner, reader or writer control logic.
module qwen_kvp_address #(
    parameter [33:0] PAYLOAD_BASE=34'd4294967296,
    parameter [33:0] DIGEST_BASE=34'd8589934592
) (
    input wire [4:0] layer,input wire [10:0] group,input wire [3:0] node,
    output wire [33:0] page_address,output wire [33:0] leaf_address,output wire [33:0] digest_address
);
    wire [15:0] page_index={layer,group};
    assign page_address=PAYLOAD_BASE+{2'b0,page_index,16'b0};
    assign leaf_address=page_address+{18'b0,node,12'b0};
    assign digest_address=DIGEST_BASE+{9'b0,page_index,9'b0};
endmodule
