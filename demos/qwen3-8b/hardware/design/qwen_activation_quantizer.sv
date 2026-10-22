// Candidate replacement for qwen_activation_quantizer.sv. Compile ONE version.
// The vector scale still uses the existing exact HardFloat division. Element
// conversion uses an exact pipelined integer implementation, not a reciprocal
// approximation. Preserve the fixed numerical function and private interface.
module qwen_activation_quantizer #(
    parameter integer ELEMENTS=4096
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire start,
    input wire in_valid,
    output wire in_ready,
    input wire [15:0] activation,
    output wire out_valid,
    input wire out_ready,
    output wire [$clog2(ELEMENTS)-1:0] out_index,
    output wire signed [15:0] code,
    output reg [31:0] vector_scale,
    output wire out_error,
    output wire busy
);
    localparam integer AW=$clog2(ELEMENTS);
    localparam [AW-1:0] LAST=AW'(ELEMENTS-1);
    localparam [3:0] IDLE=0, LOAD=1, SCALE_LAUNCH=2, SCALE_WAIT=3,
        STREAM=4, ERROR=8, ZERO_OUTPUT=9;
    reg [3:0] state;
    reg [AW-1:0] input_index,output_index,read_index;
    reg [14:0] max_absolute;
    reg read_done,sample_valid;
    reg [15:0] sample;
    (* ram_style="block" *) reg [15:0] values [0:ELEMENTS-1];
    // PRIVATE_QUANTIZER_WRITE_CAPTURE: accepted payload and address stay
    // paired. This pending private write cannot publish an output after CLEAR.
    reg write_pending;
    reg [AW-1:0] write_address;
    reg [15:0] write_data;
    always @(posedge clk) begin
        if(!rst_n || clear) write_pending<=0;
        else write_pending<=load_accept;
        write_address<=input_index;
        write_data<=activation;
    end
    (* ram_style="distributed" *) reg [15:0] result_fifo [0:63];
    reg [5:0] write_pointer,read_pointer;
    reg [6:0] result_count,reserved;
    wire alive=rst_n && !clear;
    wire load_accept=in_valid && in_ready;
    wire stream_output=state==STREAM && result_count!=0;
    wire consume=stream_output && out_ready && alive;
    // Reservations cover synchronous RAM read, all pipeline stages and FIFO.
    // Thus a downstream stall cannot overwrite an in-flight or queued result.
    wire issue=state==STREAM && !read_done && reserved<7'd64 && alive;
    assign in_ready=state==LOAD && alive;
    assign out_valid=(stream_output || state==ERROR || state==ZERO_OUTPUT) && alive;
    assign out_error=state==ERROR;
    assign out_index=output_index;
    assign code=state==STREAM ? $signed(result_fifo[read_pointer]) : 16'sd0;
    assign busy=state!=IDLE;

    wire [32:0] rec_a,rec_b,rec_result;
    wire [31:0] float_result;
    wire div_ready,div_valid,unused_sqrt;
    wire [4:0] div_flags;
    fNToRecFN #(8,24) decode_a(.in({1'b0,max_absolute,16'b0}),.out(rec_a));
    fNToRecFN #(8,24) decode_b(.in(32'h46fffe00),.out(rec_b));
    divSqrtRecFN_small #(8,24,0) divide(
        .nReset(alive),.clock(clk),.control(1'b1),.inReady(div_ready),
        .inValid(state==SCALE_LAUNCH && alive),.sqrtOp(1'b0),.a(rec_a),.b(rec_b),
        .roundingMode(3'b000),.outValid(div_valid),.sqrtOpOut(unused_sqrt),
        .out(rec_result),.exceptionFlags(div_flags)
    );
    recFNToFN #(8,24) encode_float(.in(rec_result),.out(float_result));
    wire pipeline_valid;
    wire signed [15:0] pipeline_code;
    wire pipeline_clear=clear || state!=STREAM;
    qwen_exact_activation_pipeline pipeline(
        .clk(clk),.rst_n(rst_n),.clear(pipeline_clear),
        .in_valid(sample_valid && state==STREAM && alive),
        .activation(sample),.vector_scale(vector_scale),
        .out_valid(pipeline_valid),.code(pipeline_code)
    );
    wire enqueue=pipeline_valid && state==STREAM && alive;
    initial begin
        if(ELEMENTS!=4096 && ELEMENTS!=12288)
            $fatal(1,"Quantizer geometry must match a fixed Qwen projection");
    end
    always @(posedge clk) begin
        if(write_pending) values[write_address]<=write_data;
        if(issue) sample<=values[read_index];
        if(enqueue) result_fifo[write_pointer]<=pipeline_code;
    end
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            state<=IDLE; input_index<=0; output_index<=0; read_index<=0;
            max_absolute<=0; vector_scale<=32'h3f800000; read_done<=0;
            sample_valid<=0; write_pointer<=0; read_pointer<=0;
            result_count<=0; reserved<=0;
        end else begin
            sample_valid<=issue;
            case({issue,consume})
                2'b10: reserved<=reserved+1'b1;
                2'b01: reserved<=reserved-1'b1;
                default: begin end
            endcase
            case({enqueue,consume})
                2'b10: result_count<=result_count+1'b1;
                2'b01: result_count<=result_count-1'b1;
                default: begin end
            endcase
            if(enqueue) write_pointer<=write_pointer+1'b1;
            if(consume) read_pointer<=read_pointer+1'b1;
            if(issue) begin
                if(read_index==LAST) read_done<=1;
                else read_index<=read_index+1'b1;
            end
            case(state)
                IDLE: if(start) begin
                    input_index<=0; output_index<=0; max_absolute<=0;
                    read_index<=0; read_done<=0; result_count<=0; reserved<=0;
                    write_pointer<=0; read_pointer<=0; state<=LOAD;
                end
                LOAD: if(load_accept) begin
                    if(&activation[14:7]) state<=ERROR;
                    else begin
                        if(activation[14:0]>max_absolute) max_absolute<=activation[14:0];
                        if(input_index==LAST) begin
                            if(max_absolute==0 && activation[14:0]==0) begin
                                vector_scale<=32'h3f800000; state<=ZERO_OUTPUT;
                            end else state<=SCALE_LAUNCH;
                        end else input_index<=input_index+1'b1;
                    end
                end
                SCALE_LAUNCH: if(div_ready) state<=SCALE_WAIT;
                SCALE_WAIT: if(div_valid) begin
                    if(|div_flags[4:2] || float_result[31] || !(|float_result[30:0]) || &float_result[30:23])
                        state<=ERROR;
                    else begin vector_scale<=float_result; state<=STREAM; end
                end
                STREAM: if(consume) begin
                    if(output_index==LAST) state<=IDLE;
                    else output_index<=output_index+1'b1;
                end
                ZERO_OUTPUT: if(out_ready) begin
                    if(output_index==LAST) state<=IDLE;
                    else output_index<=output_index+1'b1;
                end
                ERROR: if(out_ready) state<=IDLE;
                default: state<=ERROR;
            endcase
        end
    end
    wire unused_flags=^{div_flags[1:0],unused_sqrt};
`ifdef VERILATOR
    always @(posedge clk) if(alive) begin
        if(reserved>64 || result_count>reserved || (enqueue && result_count==64 && !consume))
            $fatal(1,"Quantizer reservation/FIFO invariant");
        if(consume && output_index==LAST && reserved!=1)
            $fatal(1,"Quantizer completed with outstanding samples");
    end
`endif
endmodule
