// INTERNAL arithmetic component only. These ports are not a host interface.
// A future fixed-model sequencer must own start, operands, and result routing.
// Eight signed W8 x A16 products per beat, fixed number of beats per result.
module private_dot8_accumulator #(
    parameter integer GROUPS = 256,
    parameter integer ACC_WIDTH = 40
) (
    input  wire clk,
    input  wire rst_n,
    input  wire clear,
    input  wire start,
    input  wire in_valid,
    output wire in_ready,
    input  wire [127:0] activations,
    input  wire [63:0] weights,
    output reg out_valid,
    input  wire out_ready,
    output reg signed [ACC_WIDTH-1:0] result,
    output wire busy
);
    localparam integer COUNT_WIDTH = (GROUPS < 2) ? 1 : $clog2(GROUPS);
    localparam [COUNT_WIDTH-1:0] LAST_GROUP = COUNT_WIDTH'(GROUPS-1);
    localparam [1:0] IDLE=0, FEED=1, DRAIN=2, HOLD=3;
    reg [1:0] state;
    reg [COUNT_WIDTH-1:0] accepted_count;
    reg [3:0] valid_pipe, last_pipe;
    reg signed [23:0] products [0:7];
    reg signed [24:0] pairs [0:3];
    reg signed [25:0] halves [0:1];
    reg signed [26:0] group_sum;
    reg signed [ACC_WIDTH-1:0] accumulator;
    wire accept = in_valid && in_ready;
    wire last_accept = accept && (accepted_count == LAST_GROUP);
    wire signed [ACC_WIDTH-1:0] widened_sum = {{(ACC_WIDTH-27){group_sum[26]}}, group_sum};
    assign in_ready = (state == FEED) && !clear && rst_n;
    assign busy = (state != IDLE);
    integer i;

    initial begin
        if (GROUPS < 1 || ACC_WIDTH < 27 || ACC_WIDTH < 24+$clog2(8*GROUPS))
            $fatal(1, "Invalid fixed dot-product geometry");
    end

    // PRIVATE_DOT_PAYLOAD065: these intermediate bits have no independent
    // validity. The unchanged valid_pipe gates their consumption by the
    // accumulator; reset/CLEAR still revoke every pending valid bit.
    always @(posedge clk) begin
        for (i=0; i<8; i=i+1)
            products[i] <= $signed(activations[i*16 +: 16]) * $signed(weights[i*8 +: 8]);
        for (i=0; i<4; i=i+1)
            pairs[i] <= $signed(products[2*i]) + $signed(products[2*i+1]);
        halves[0] <= $signed(pairs[0]) + $signed(pairs[1]);
        halves[1] <= $signed(pairs[2]) + $signed(pairs[3]);
        group_sum <= $signed(halves[0]) + $signed(halves[1]);
    end

    always @(posedge clk) begin
        if (!rst_n || clear) begin
            state <= IDLE;
            accepted_count <= 0;
            valid_pipe <= 0;
            last_pipe <= 0;
            accumulator <= 0;
            result <= 0;
            out_valid <= 0;
        end else begin
            valid_pipe <= {valid_pipe[2:0], accept};
            last_pipe <= {last_pipe[2:0], last_accept};
            if (accept) begin
                if (last_accept)
                    state <= DRAIN;
                else
                    accepted_count <= accepted_count + 1'b1;
            end
            if (valid_pipe[3]) begin
                accumulator <= accumulator + widened_sum;
                if (last_pipe[3]) begin
                    result <= accumulator + widened_sum;
                    out_valid <= 1;
                    state <= HOLD;
                end
            end
            if (state == HOLD && out_ready) begin
                out_valid <= 0;
                state <= IDLE;
            end
            if (state == IDLE && start) begin
                accepted_count <= 0;
                accumulator <= 0;
                state <= FEED;
            end
        end
    end
endmodule
