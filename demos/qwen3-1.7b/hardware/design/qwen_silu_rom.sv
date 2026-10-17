// PRIVATE fixed SiLU lookup. This ROM has no runtime write port. Its exact
// initialized bytes are part of the fixed numerical model, not host data.
module qwen_silu_rom #(
    parameter ROM_FILE="silu-bf16.hex"
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire in_valid,
    output wire in_ready,
    input wire [15:0] activation,
    output wire out_valid,
    input wire out_ready,
    output wire [15:0] result,
    output wire out_error
);
    (* rom_style="block" *) reg [15:0] table_values [0:65535];
    initial $readmemh(ROM_FILE,table_values);
    // SILU_RESULT181: ROM sampling is independent of caller/fault control.
    // Only an accepted input creates a pending result, and pending work has
    // a reserved queue slot. Arbitrary unaccepted samples remain private.
    reg [15:0] lookup_q;
    always @(posedge clk) lookup_q<=table_values[activation];
    reg pending,pending_error,head,tail;
    reg [1:0] count;
    reg [15:0] results [0:1];
    reg [1:0] errors;
    wire alive=rst_n && !clear;
    wire output_take=out_valid && out_ready;
    wire [2:0] reserved={1'b0,count}+{2'b0,pending};
    assign in_ready=alive && (reserved<3'd2 || output_take);
    wire input_take=in_valid && in_ready;
    assign out_valid=alive && count!=0;
    assign result=results[head];
    assign out_error=count!=0 ? errors[head] : 1'b0;
    // A write coincident with cancellation is harmless: count and pending
    // are revoked, and every subsequently published slot is overwritten.
    always @(posedge clk) if(pending) begin
        results[tail]<=lookup_q;
        errors[tail]<=pending_error;
    end
    always @(posedge clk) begin
        if(!rst_n || clear)begin
            pending<=0;pending_error<=0;head<=0;tail<=0;count<=0;
        end else begin
            pending<=input_take;
            if(input_take)pending_error<=&activation[14:7];
            if(pending)tail<=!tail;
            if(output_take)head<=!head;
            case({pending,output_take})
                2'b10:count<=count+1'b1;
                2'b01:count<=count-1'b1;
                default:begin end
            endcase
        end
    end
endmodule
