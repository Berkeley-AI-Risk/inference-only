// PRIVATE one Qwen rotary pair; each product and sum rounds to BF16.
// low'  = BF16(BF16(low*cos) + BF16((-high)*sin))
// high' = BF16(BF16(high*cos) + BF16(low*sin))
// Coefficients must come from the fixed, position-indexed table reader.
module qwen_rotary_pair (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire [15:0] low_value,input wire [15:0] high_value,
    input wire [15:0] cosine,input wire [15:0] sine,
    output wire out_valid,input wire out_ready,
    output wire [15:0] low_result,output wire [15:0] high_result,
    output wire out_error
);
    wire alive=rst_n && !clear;
    wire [3:0] mul_ready,mul_valid,mul_error;
    wire [1:0] add_ready,add_valid,add_error;
    wire [15:0] product [0:3];
    wire mul_input_valid=in_valid && (&mul_ready) && alive;
    wire mul_output_ready=(&mul_valid) && (&add_ready) && alive;
    wire add_input_valid=mul_output_ready;
    // ROTARY_BUFFER206: private non-fall-through result slot.
    // Do not reintroduce consumer out_ready into producer readiness.
    reg held_valid;
    reg [15:0] held_low,held_high;
    reg held_error;
    wire [15:0] low_sum,high_sum;
    wire add_output_ready=!held_valid && (&add_valid) && alive;
    assign in_ready=(&mul_ready) && alive;
    assign out_valid=held_valid && alive;
    qwen_bf16_elementwise mul0(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b1),
        .in_valid(mul_input_valid),.in_ready(mul_ready[0]),.a(low_value),.b(cosine),
        .out_valid(mul_valid[0]),.out_ready(mul_output_ready),.result(product[0]),.out_error(mul_error[0]));
    qwen_bf16_elementwise mul1(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b1),
        .in_valid(mul_input_valid),.in_ready(mul_ready[1]),.a(high_value^16'h8000),.b(sine),
        .out_valid(mul_valid[1]),.out_ready(mul_output_ready),.result(product[1]),.out_error(mul_error[1]));
    qwen_bf16_elementwise mul2(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b1),
        .in_valid(mul_input_valid),.in_ready(mul_ready[2]),.a(high_value),.b(cosine),
        .out_valid(mul_valid[2]),.out_ready(mul_output_ready),.result(product[2]),.out_error(mul_error[2]));
    qwen_bf16_elementwise mul3(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b1),
        .in_valid(mul_input_valid),.in_ready(mul_ready[3]),.a(low_value),.b(sine),
        .out_valid(mul_valid[3]),.out_ready(mul_output_ready),.result(product[3]),.out_error(mul_error[3]));
    qwen_bf16_elementwise add0(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b0),
        .in_valid(add_input_valid),.in_ready(add_ready[0]),.a(product[0]),.b(product[1]),
        .out_valid(add_valid[0]),.out_ready(add_output_ready),.result(low_sum),.out_error(add_error[0]));
    qwen_bf16_elementwise add1(.clk(clk),.rst_n(rst_n),.clear(clear),.multiply(1'b0),
        .in_valid(add_input_valid),.in_ready(add_ready[1]),.a(product[2]),.b(product[3]),
        .out_valid(add_valid[1]),.out_ready(add_output_ready),.result(high_sum),.out_error(add_error[1]));
    reg [3:0] fault_pipeline;
    always @(posedge clk) begin
        if(!rst_n || clear) fault_pipeline<=0;
        else if((&add_ready) && alive) fault_pipeline<={fault_pipeline[2:0],(|mul_error)};
    end
    assign low_result=held_low;
    assign high_result=held_high;
    assign out_error=held_error;
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            held_valid<=0;held_low<=0;held_high<=0;held_error<=0;
        end else begin
            if(held_valid && out_ready) held_valid<=0;
            if(add_output_ready) begin
                held_valid<=1;held_low<=low_sum;held_high<=high_sum;
                held_error<=(|add_error) || fault_pipeline[3];
            end
        end
    end
endmodule
