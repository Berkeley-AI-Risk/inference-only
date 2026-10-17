// Fixed private tensor scratchpad. No application/debug/host access port.
// One read per bank and one write per bank; operations that use both operands
// read DIFFERENT fixed banks. A/B must not request different rows of one bank.
// Contents are not reset: fixed operation sequencing and abort invalidation
// determine validity, rather than clearing thousands of RAM cells.
module qwen_private_tensors (
    input wire clk,
    input wire enable,
    input wire read_enable,
    input wire [3:0] read_a_tensor, read_b_tensor,
    input wire [12:0] read_index,
    output wire [15:0] read_a, read_b,
    input wire write_enable,
    input wire [3:0] write_tensor,
    input wire [12:0] write_index,
    input wire [15:0] write_data
);
    // X=0, Z=1, Q=2, K=3, V=4, A=5, T=6, G=7, U=8.
    wire [15:0] samples [0:8];
    reg [3:0] sample_a_tensor, sample_b_tensor;
    always @(posedge clk) if(enable && read_enable) begin
        sample_a_tensor <= read_a_tensor;
        sample_b_tensor <= read_b_tensor;
    end
    assign read_a = sample_a_tensor < 9 ? samples[sample_a_tensor] : 16'b0;
    assign read_b = sample_b_tensor < 9 ? samples[sample_b_tensor] : 16'b0;
    genvar bank;
    generate for(bank=0; bank<9; bank=bank+1) begin:banks
        localparam integer DEPTH = (bank==3 || bank==4) ? 1024 : (bank>=7 ? 6144 : 2048);
        localparam integer ADDR_BITS = (bank==3 || bank==4) ? 10 : (bank>=7 ? 13 : 11);
        (* ram_style="block" *) reg [15:0] memory [0:DEPTH-1];
        reg [15:0] sample;
        always @(posedge clk) if(enable) begin
            if(write_enable && write_tensor==4'(bank)) memory[write_index[ADDR_BITS-1:0]] <= write_data;
            if(read_enable && (read_a_tensor==4'(bank) || read_b_tensor==4'(bank)))
                sample <= memory[read_index[ADDR_BITS-1:0]];
        end
        assign samples[bank] = sample;
    end endgenerate
endmodule
