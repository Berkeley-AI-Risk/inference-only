// PRIVATE complete 128-element Q/K head rotation. Load 128 activations and
// 64 fixed cosine/sine pairs (independent streams), then return 64 pairs.
// Pair i writes destinations i and i+64 in the private result buffer.
// The outer controller owns the position and authenticates table data; no
// table-loader or coefficient/position selection is a host application port.
module qwen_rotary_head (
    input wire clk,input wire rst_n,input wire clear,input wire start,
    input wire in_valid,output wire in_ready,input wire [15:0] activation,
    input wire table_valid,output wire table_ready,
    input wire [15:0] cosine,input wire [15:0] sine,
    output wire out_valid,input wire out_ready,output wire [5:0] out_pair_index,
    output wire [15:0] low_result,output wire [15:0] high_result,
    output wire out_error,output wire busy
);
    localparam [2:0] IDLE=0,LOAD=1,FETCH=2,FEED=3,DRAIN=4;
    reg [2:0] state;
    reg [6:0] input_index;
    reg [5:0] table_index,feed_index,output_index;
    reg input_done,table_done;
    wire alive=rst_n && !clear;
    assign busy=state!=IDLE;
    assign in_ready=state==LOAD && !input_done && alive;
    assign table_ready=state==LOAD && !table_done && alive;
    wire input_accept=in_valid && in_ready,table_accept=table_valid && table_ready;
    (* ram_style="distributed" *) reg [15:0] low_values [0:63],high_values [0:63];
    (* ram_style="distributed" *) reg [31:0] coefficients [0:63];
    reg [15:0] low_sample,high_sample;
    reg [31:0] table_sample;
    wire pair_in_ready,pair_out_valid;
    wire pair_in_valid=state==FEED && alive;
    wire pair_accept=pair_in_valid && pair_in_ready;
    wire [5:0] read_index=pair_accept ? feed_index+1'b1 : feed_index;
    always @(posedge clk) if(rst_n) begin
        if(input_accept) begin
            if(input_index[6]) high_values[input_index[5:0]]<=activation;
            else low_values[input_index[5:0]]<=activation;
        end
        if(table_accept) coefficients[table_index]<={sine,cosine};
        low_sample<=low_values[read_index];high_sample<=high_values[read_index];
        table_sample<=coefficients[read_index];
    end
    qwen_rotary_pair pairs(
        .clk(clk),.rst_n(rst_n),.clear(clear),.in_valid(pair_in_valid),.in_ready(pair_in_ready),
        .low_value(low_sample),.high_value(high_sample),.cosine(table_sample[15:0]),.sine(table_sample[31:16]),
        .out_valid(pair_out_valid),.out_ready(out_ready && alive),
        .low_result(low_result),.high_result(high_result),.out_error(out_error)
    );
    assign out_valid=pair_out_valid && alive;
    assign out_pair_index=output_index;
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            state<=IDLE;input_index<=0;table_index<=0;feed_index<=0;output_index<=0;
            input_done<=0;table_done<=0;
        end else begin
            case(state)
                IDLE: if(start) begin
                    state<=LOAD;input_index<=0;table_index<=0;feed_index<=0;output_index<=0;
                    input_done<=0;table_done<=0;
                end
                LOAD: begin
                    if(input_accept) begin
                        if(input_index==127) input_done<=1;else input_index<=input_index+1'b1;
                    end
                    if(table_accept) begin
                        if(table_index==63) table_done<=1;else table_index<=table_index+1'b1;
                    end
                    if((input_done || (input_accept && input_index==127))
                        && (table_done || (table_accept && table_index==63))) state<=FETCH;
                end
                FETCH: state<=FEED;
                FEED: if(pair_accept) begin
                    if(feed_index==63) state<=DRAIN;else feed_index<=feed_index+1'b1;
                end
                DRAIN: begin end
                default: state<=IDLE;
            endcase
            if(out_valid && out_ready) begin
                if(output_index==63) state<=IDLE;else output_index<=output_index+1'b1;
            end
        end
    end
endmodule
