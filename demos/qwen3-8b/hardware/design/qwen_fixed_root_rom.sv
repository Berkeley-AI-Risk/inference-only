// PRIVATE build-time immutable root ROM. No write, model selector or host port.
// Explicit 4096-entry banks avoid rounding the full 134705-entry table up to
// 262144 entries. The data is valid for page_index from the preceding clock,
// matching the existing shared root address/read pipeline (two rising edges).
// The owning verifier, not this ROM, validates the accepted page and controls
// consumption. Out-of-range reads return zero and never authorize a page.
(* keep_hierarchy="yes" *)
module qwen_fixed_root_rom #(
    parameter integer PAGES=134705,
    parameter integer PAGE_BITS=18,
    parameter ROOT_PREFIX="model-page-roots-bank"
) (
    input wire clk,
    input wire [PAGE_BITS-1:0] page_index,
    output wire [255:0] root_data
);
    localparam integer BANK_BITS=12;
    localparam integer BANKS=(PAGES+4095)/4096;
    localparam integer SELECT_BITS=PAGE_BITS-BANK_BITS;
    reg [PAGE_BITS-1:0] address_q;
    reg [SELECT_BITS-1:0] selected_bank;
    reg address_valid;
    wire [BANKS*256-1:0] bank_data;
    initial if(PAGES<1 || PAGE_BITS<13 || PAGES>(1<<PAGE_BITS))
        $fatal(1,"Unsupported fixed root ROM geometry");
    always @(posedge clk)begin
        address_q<=page_index;
        selected_bank<=address_q[PAGE_BITS-1:BANK_BITS];
        address_valid<={1'b0,address_q}<(PAGE_BITS+1)'(PAGES);
    end
    assign root_data=address_valid ? bank_data[selected_bank*256+:256] : 256'b0;
    genvar bank;
    generate for(bank=0;bank<BANKS;bank=bank+1)begin:banks
        localparam integer ENTRIES=PAGES-bank*4096<4096 ? PAGES-bank*4096 : 4096;
        (* keep_hierarchy="yes" *) qwen_fixed_root_rom_bank #(
            .ENTRIES(ENTRIES),.FILE($sformatf("%s-%0d.hex",ROOT_PREFIX,bank))) storage(
            .clk(clk),.address(address_q[11:0]),.data(bank_data[bank*256+:256]));
    end endgenerate
endmodule

(* keep_hierarchy="yes" *)
module qwen_fixed_root_rom_bank #(
    parameter integer ENTRIES=4096,
    parameter FILE="model-page-roots-bank-0.hex"
) (
    input wire clk,input wire [11:0] address,output reg [255:0] data
);
    (* ram_style="block" *) reg [255:0] roots [0:ENTRIES-1];
    initial $readmemh(FILE,roots);
    // Invalid bits are private and ignored by the parent address-valid guard.
    always @(posedge clk)data<=roots[address];
endmodule
