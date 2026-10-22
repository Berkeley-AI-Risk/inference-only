// PRIVATE 32-row tile: 32 independent eight-product lanes, 256 W8*A16
// multiplications per accepted beat, followed by shared FP32/BF16 scaling.
// Activation data is broadcast; weights are packed as 32 little-endian groups
// of eight signed bytes. All rows use the same private activation scale.
// Fixed GROUPS is 256 for 2048 columns, or 768 for 6144 columns in Qwen3-1.7B.
// This component alone has no authenticated-memory or application boundary.
module qwen_projection_tile32 #(
    parameter integer GROUPS=256
) (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire start,
    input wire [1023:0] row_scales,
    input wire [31:0] vector_scale,
    input wire in_valid,
    output wire in_ready,
    input wire [127:0] activations,
    input wire [2047:0] weights,
    output wire out_valid,
    input wire out_ready,
    output wire [4:0] out_row,
    output wire [15:0] result,
    output wire out_error,
    output wire busy
);
    localparam [1:0] IDLE=0, DOT=1, SCALE=2, DRAIN=3;
    reg [1:0] state;
    reg [4:0] issue_row, receive_row;
    reg [1023:0] scales;
    reg [31:0] activation_scale;
    wire [31:0] ready_lanes, valid_lanes, busy_lanes;
    wire signed [39:0] sums [0:31];
    wire lane_start = state == IDLE && start && rst_n && !clear;
    // PRIVATE_INPUT_BUFFER: acceptance of authenticated weights ends at
    // this local queue. The arithmetic consumes registered words and a local
    // valid bit, not the upstream authentication/control cone. Capture the
    // corresponding activation word at the SAME acceptance position.
    localparam integer INPUT_COUNT_WIDTH = $clog2(GROUPS+1);
    reg lane_kick;
    reg [2175:0] input_buffer [0:1];
    reg input_read, input_write;
    reg [1:0] input_count;
    reg [INPUT_COUNT_WIDTH-1:0] input_remaining;
    wire [2175:0] input_word = input_buffer[input_read];
    wire [127:0] input_activations = input_word[2175:2048];
    wire [2047:0] input_weights = input_word[2047:0];
    assign in_ready = state == DOT && input_remaining != 0
        && input_count < 2 && rst_n && !clear;
    wire input_push = in_valid && in_ready;
    wire beat = state == DOT && input_count != 0 && &ready_lanes
        && rst_n && !clear;
    // Free slots are unpublished. Local capacity controls payload capture;
    // only input_push commits a word. Extra captures cannot alter a live slot.
    always @(posedge clk) begin
        if (input_count < 2)
            input_buffer[input_write] <= {activations, weights};
    end
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            lane_kick <= 0;
            input_read <= 0;
            input_write <= 0;
            input_count <= 0;
            input_remaining <= 0;
        end else begin
            lane_kick <= lane_start;
            if (lane_start) begin
                input_read <= 0;
                input_write <= 0;
                input_count <= 0;
                input_remaining <= INPUT_COUNT_WIDTH'(GROUPS);
            end else begin
                if (input_push) begin
                    input_write <= !input_write;
                    input_remaining <= input_remaining - 1'b1;
                end
                if (beat)
                    input_read <= !input_read;
                case ({input_push, beat})
                    2'b10: input_count <= input_count + 1'b1;
                    2'b01: input_count <= input_count - 1'b1;
                    default: ;
                endcase
            end
        end
    end
    wire scale_ready;
    wire scale_valid = state == SCALE && &valid_lanes;
    wire scale_accept = scale_valid && scale_ready;
    wire release_lanes = scale_accept && issue_row == 31;
    genvar row;
    generate for (row=0; row<32; row=row+1) begin: rows
        private_dot8_accumulator #(.GROUPS(GROUPS)) dot(
            .clk(clk), .rst_n(rst_n), .clear(clear), .start(lane_kick),
            .in_valid(beat), .in_ready(ready_lanes[row]), .activations(input_activations),
            .weights(input_weights[row*64 +: 64]), .out_valid(valid_lanes[row]),
            .out_ready(release_lanes), .result(sums[row]), .busy(busy_lanes[row])
        );
    end endgenerate
    // PRIVATE_RESULT_BUFFER_BEGIN
    // No combinational downstream-ready path back to the rescaler/32 lanes.
    // Payload is private and unreset; count/pointers establish its validity.
    wire scaled_valid, scaled_ready, scaled_error;
    wire [15:0] scaled_result;
    reg [16:0] result_buffer [0:1];
    reg result_read, result_write;
    reg [1:0] result_count;
    assign scaled_ready = result_count < 2 && rst_n && !clear;
    assign out_valid = result_count != 0 && rst_n && !clear;
    assign {out_error, result} = result_buffer[result_read];
    wire result_push = scaled_valid && scaled_ready;
    wire result_pop = out_valid && out_ready;
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            result_read <= 0;
            result_write <= 0;
            result_count <= 0;
        end else begin
            if (result_push) begin
                result_buffer[result_write] <= {scaled_error, scaled_result};
                result_write <= !result_write;
            end
            if (result_pop)
                result_read <= !result_read;
            case ({result_push, result_pop})
                2'b10: result_count <= result_count + 1'b1;
                2'b01: result_count <= result_count - 1'b1;
                default: result_count <= result_count;
            endcase
        end
    end
    // PRIVATE_RESULT_BUFFER_END
    qwen_projection_scale rescale(
        .clk(clk), .rst_n(rst_n), .clear(clear), .in_valid(scale_valid),
        .in_ready(scale_ready), .integer_sum(sums[issue_row]),
        .row_scale(scales[issue_row*32 +: 32]), .vector_scale(activation_scale),
        .out_valid(scaled_valid), .out_ready(scaled_ready), .result(scaled_result), .out_error(scaled_error)
    );
    assign out_row = receive_row;
    assign busy = state != IDLE;
    // PRIVATE scale payload: every accepted start is in IDLE. Capture
    // locally in IDLE and hold through DOT/SCALE/DRAIN. Extra idle samples
    // are not consumed; keep lane_start and all publication gates unchanged.
    always @(posedge clk) begin
        if (state == IDLE) begin
            scales <= row_scales;
            activation_scale <= vector_scale;
        end
    end
    always @(posedge clk) begin
        if (!rst_n || clear) begin
            state <= IDLE;
            issue_row <= 0;
            receive_row <= 0;
        end else begin
            if (lane_start) begin
                issue_row <= 0;
                receive_row <= 0;
                state <= DOT;
            end
            if (state == DOT && &valid_lanes)
                state <= SCALE;
            if (scale_accept) begin
                if (issue_row == 31)
                    state <= DRAIN;
                else
                    issue_row <= issue_row+1'b1;
            end
            if (out_valid && out_ready) begin
                if (receive_row == 31)
                    state <= IDLE;
                else
                    receive_row <= receive_row+1'b1;
            end
        end
    end
    wire unused_busy = ^busy_lanes;
endmodule
