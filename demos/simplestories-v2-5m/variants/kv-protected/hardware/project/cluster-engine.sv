`timescale 1ns/1ps
`default_nettype none

// Drop-in PRIVATE group seam, not a product top. Same frozen W10/A16 model
// geometries, metadata, signed-50 outputs and ordering as shared scale0/1.
// Four local 16-lane tiles retain the existing 640-bit image layout. Exact
// multiply and accumulation have separate registers. Two additional DSPs
// postscale one row/cycle through a globally stalled four-stage output pipe.
// No architecture, weight, matrix shape or arithmetic operation is public.
module board1_clustered_projection_scale2 (
    input wire clk, reset_n, clear_i, model_locked_i, upstream_fail_closed_i,
    input wire start_valid_i,
    output wire start_ready_o,
    input wire [2:0] fixed_layer_i,
    input wire [3:0] fixed_job_i,
    input wire [5:0] fixed_group_i,
    input wire signed [7:0] activation_exponent_i,
    input wire metadata_valid_i,
    output wire metadata_ready_o,
    input wire signed [7:0] metadata_exponent_i,
    input wire [15:0] metadata_multiplier_i,
    input wire [12:0] metadata_row_index_i,
    input wire metadata_last_i,
    input wire weight_valid_i,
    output wire weight_ready_o,
    input wire signed [15:0] activation_i,
    input wire [639:0] weight_data_i,
    input wire weight_last_i,
    output wire result_valid_o,
    input wire result_ready_i,
    output wire [12:0] result_row_index_o,
    output wire signed [49:0] result_scaled_raw_o,
    output wire signed [7:0] result_source_exponent_o,
    output wire result_last_o,
    output wire done_valid_o,
    input wire done_ready_i,
    output wire busy_o, fail_closed_o
);
    localparam [2:0] IDLE=0, META=1, WEIGHTS=2, DRAIN=3, EMIT=4, DONE=5, FAIL=7;
    logic [2:0] state_q;
    // Private sixteen-way sharing: four multipliers serve64 fixed rows.
    logic [3:0] weight_pause_q;
    logic fail_q;
    logic [5:0] group_q;
    logic [6:0] valid_lanes_q, metadata_count_q, issue_count_q;
    logic [9:0] columns_q, column_q;
    logic signed [7:0] activation_exponent_q;
    logic [6:0] descriptor_groups, descriptor_lanes;
    logic [9:0] descriptor_columns;
    // always_comb also evaluates the fixed job-0/group-0 descriptor at time
    // zero; it must not depend on those initially-zero inputs changing first.
    always_comb begin
        descriptor_groups = 0;
        case (fixed_job_i)
            0,3,6: descriptor_groups = 4;
            1,2: descriptor_groups = 2;
            4,5: descriptor_groups = 11;
            7: descriptor_groups = 63;
            default: descriptor_groups = 0;
        endcase
        descriptor_columns = (fixed_job_i == 6) ? 10'd682 : 10'd256;
        descriptor_lanes = 64;
        if ({1'b0,fixed_group_i} == descriptor_groups-7'd1) begin
            if (fixed_job_i == 4 || fixed_job_i == 5) descriptor_lanes = 42;
            if (fixed_job_i == 7) descriptor_lanes = 51;
        end
    end
    wire descriptor_ok = descriptor_groups != 0 &&
        {1'b0,fixed_group_i} < descriptor_groups &&
        ((fixed_job_i == 7 && fixed_layer_i == 7) ||
         (fixed_job_i < 7 && fixed_layer_i < 6));
    wire [12:0] row_base = {1'b0,group_q,6'b0};
    wire signed [10:0] exponent_sum =
        $signed({{3{activation_exponent_q[7]}},activation_exponent_q}) +
        $signed({{3{metadata_exponent_i[7]}},metadata_exponent_i}) - 11'sd15;
    wire metadata_error =
        metadata_row_index_i != row_base + {6'b0,metadata_count_q} ||
        metadata_last_i != (metadata_count_q == valid_lanes_q-7'd1) ||
        metadata_multiplier_i == 0 || metadata_multiplier_i[15] ||
        exponent_sum < -11'sd128 || exponent_sum > 11'sd127;
    wire [3:0] tile_fault, tile_done;
    wire live = model_locked_i && !clear_i && !upstream_fail_closed_i &&
                !fail_q && !(|tile_fault);
    assign start_ready_o = state_q == IDLE && live;
    assign metadata_ready_o = state_q == META && live;
    assign weight_ready_o = state_q == WEIGHTS && live && weight_pause_q == 4'd0;
    assign busy_o = state_q != IDLE && state_q != FAIL;
    assign fail_closed_o = fail_q || upstream_fail_closed_i || (|tile_fault);
    wire start_fire = start_valid_i && start_ready_o;
    wire metadata_fire = metadata_valid_i && metadata_ready_o;
    wire weight_fire = weight_valid_i && weight_ready_o;
    wire kill = clear_i || fail_q || upstream_fail_closed_i || !model_locked_i;

    // Hold each captured weight beat for sixteen private row slices.
    // Keep the original combinational live/fault/CLEAR gates on ready.
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) weight_pause_q <= 0;
        else if (kill || start_fire) weight_pause_q <= 0;
        else if (weight_fire) weight_pause_q <= 4'd15;
        else if (weight_pause_q != 0) weight_pause_q <= weight_pause_q-4'd1;
    end

    wire signed [34:0] tile_dot [0:3];
    wire [15:0] tile_multiplier [0:3];
    wire signed [7:0] tile_exponent [0:3];
    logic [3:0] scale_valid_q;
    logic [1:0] selected_tile_q;
    logic [5:0] row_pipe_q [0:3];
    logic signed [7:0] exponent_pipe_q [1:3];
    logic signed [26:0] low_operand_q, high_operand_q;
    logic signed [17:0] scale_operand_q;
    wire signed [47:0] low_product, high_product;
    logic signed [47:0] low_product_q, high_product_q;
    logic signed [49:0] result_q;
    wire advance = !scale_valid_q[3] || result_ready_i;
    wire issue = state_q == EMIT && issue_count_q < valid_lanes_q && advance && live;

    genvar tile;
    generate for (tile=0; tile<4; tile=tile+1) begin : g_tile
        wire [4:0] tile_lanes = (descriptor_lanes >= (tile+1)*16) ? 5'd16 :
            (descriptor_lanes <= tile*16) ? 5'd0 : 5'(descriptor_lanes-tile*16);
        board1_projection_tile16 u_tile (
            .clk(clk), .reset_n(reset_n), .kill_i(kill),
            .begin_i(start_fire && descriptor_ok), .valid_lanes_i(tile_lanes),
            .accept_i(weight_fire), .first_i(column_q == 0),
            .last_i(column_q == columns_q-10'd1), .activation_i(activation_i),
            .weights_i(weight_data_i[tile*160 +: 160]),
            .metadata_write_i(metadata_fire && !metadata_error && metadata_count_q[5:4] == tile),
            .metadata_lane_i(metadata_count_q[3:0]),
            .metadata_multiplier_i(metadata_multiplier_i),
            .metadata_exponent_i(exponent_sum[7:0]),
            .read_i(issue), .read_lane_i(issue_count_q[3:0]),
            .dot_o(tile_dot[tile]), .multiplier_o(tile_multiplier[tile]),
            .exponent_o(tile_exponent[tile]), .done_o(tile_done[tile]),
            .fault_o(tile_fault[tile]));
    end endgenerate

    board1_projection_postscale_mul u_scale_low (
        .a_i(low_operand_q), .b_i(scale_operand_q), .product_o(low_product));
    board1_projection_postscale_mul u_scale_high (
        .a_i(high_operand_q), .b_i(scale_operand_q), .product_o(high_product));

    // Read tiles -> select/register operands -> multiply/register -> add.
    // One global advance freezes all data and tags together on backpressure.
    // No payload reset: each valid tag is created only by its matching write.
    always_ff @(posedge clk) begin
        if (advance) begin
            if (issue) begin
                selected_tile_q <= issue_count_q[5:4];
                row_pipe_q[0] <= issue_count_q[5:0];
            end
            if (scale_valid_q[0]) begin
                low_operand_q <= {2'b00,tile_dot[selected_tile_q][24:0]};
                high_operand_q <= {{17{tile_dot[selected_tile_q][34]}},tile_dot[selected_tile_q][34:25]};
                scale_operand_q <= {2'b00,tile_multiplier[selected_tile_q]};
                row_pipe_q[1] <= row_pipe_q[0];
                exponent_pipe_q[1] <= tile_exponent[selected_tile_q];
            end
            if (scale_valid_q[1]) begin
                low_product_q <= low_product;
                high_product_q <= high_product;
                row_pipe_q[2] <= row_pipe_q[1];
                exponent_pipe_q[2] <= exponent_pipe_q[1];
            end
            if (scale_valid_q[2]) begin
                result_q <= $signed({2'b00,low_product_q}) +
                    ($signed({{2{high_product_q[47]}},high_product_q}) <<< 25);
                row_pipe_q[3] <= row_pipe_q[2];
                exponent_pipe_q[3] <= exponent_pipe_q[2];
            end
        end
    end
    assign result_valid_o = state_q == EMIT && scale_valid_q[3] && live;
    // Private metadata is meaningful only with result_valid_o.
    // Keep the fault/CLEAR gates on VALID and every accepted transfer.
    assign result_row_index_o = row_base + {7'b0,row_pipe_q[3]};
    assign result_scaled_raw_o = result_valid_o ? result_q : 50'sd0;
    assign result_source_exponent_o = result_valid_o ? exponent_pipe_q[3] : 8'sd0;
    assign result_last_o = {1'b0,row_pipe_q[3]} == valid_lanes_q-7'd1;
    assign done_valid_o = state_q == DONE && live;

    wire control_error = upstream_fail_closed_i || (|tile_fault) ||
        ((state_q != IDLE && state_q != FAIL) && !model_locked_i) ||
        (start_valid_i && !start_ready_o) ||
        (metadata_valid_i && state_q != META) ||
        (weight_valid_i && state_q != WEIGHTS) ||
        ((|tile_done) && !(&tile_done));
`ifndef SYNTHESIS
    logic x_error;
    always @* begin
        // Individual operands avoid an Icarus $isunknown(concatenation)
        // temporary-value bug; the checked bits are unchanged.
        x_error = $isunknown(clear_i) || $isunknown(model_locked_i) ||
            $isunknown(upstream_fail_closed_i) || $isunknown(start_valid_i) ||
            $isunknown(metadata_valid_i) || $isunknown(weight_valid_i);
        if (start_valid_i) x_error = x_error || $isunknown(fixed_layer_i) ||
            $isunknown(fixed_job_i) || $isunknown(fixed_group_i) || $isunknown(activation_exponent_i);
        if (metadata_valid_i) x_error = x_error || $isunknown(metadata_exponent_i) ||
            $isunknown(metadata_multiplier_i) || $isunknown(metadata_row_index_i) || $isunknown(metadata_last_i);
        if (weight_valid_i) x_error = x_error || $isunknown(activation_i) ||
            $isunknown(weight_data_i) || $isunknown(weight_last_i);
        if (result_valid_o) x_error = x_error || $isunknown(result_ready_i);
        if (done_valid_o) x_error = x_error || $isunknown(done_ready_i);
    end
`endif
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            state_q <= IDLE; fail_q <= 0; group_q <= 0;
            valid_lanes_q <= 0; metadata_count_q <= 0; issue_count_q <= 0;
            columns_q <= 0; column_q <= 0; activation_exponent_q <= 0;
            scale_valid_q <= 0;
        end else if (clear_i === 1'b1) begin
            state_q <= IDLE; fail_q <= 0;
            metadata_count_q <= 0; issue_count_q <= 0; column_q <= 0;
            scale_valid_q <= 0;
        end else if (control_error
`ifndef SYNTHESIS
            || x_error
`endif
        ) begin
            state_q <= FAIL; fail_q <= 1; scale_valid_q <= 0;
        end else begin
            if (advance) scale_valid_q <= {scale_valid_q[2:0],issue};
            case (state_q)
                IDLE: if (start_fire) begin
                    if (!descriptor_ok) begin state_q <= FAIL; fail_q <= 1; end
                    else begin
                        group_q <= fixed_group_i; columns_q <= descriptor_columns;
                        valid_lanes_q <= descriptor_lanes;
                        activation_exponent_q <= activation_exponent_i;
                        metadata_count_q <= 0; column_q <= 0; issue_count_q <= 0;
                        scale_valid_q <= 0; state_q <= META;
                    end
                end
                META: if (metadata_fire) begin
                    if (metadata_error) begin state_q <= FAIL; fail_q <= 1; end
                    else if (metadata_count_q == valid_lanes_q-7'd1) state_q <= WEIGHTS;
                    else metadata_count_q <= metadata_count_q+7'd1;
                end
                WEIGHTS: if (weight_fire) begin
                    if (weight_last_i != (column_q == columns_q-10'd1)) begin
                        state_q <= FAIL; fail_q <= 1;
                    end else if (column_q == columns_q-10'd1) state_q <= DRAIN;
                    else column_q <= column_q+10'd1;
                end
                DRAIN: if (&tile_done) state_q <= EMIT;
                EMIT: begin
                    if (issue) issue_count_q <= issue_count_q+7'd1;
                    if (result_valid_o && result_ready_i && result_last_o) state_q <= DONE;
                end
                DONE: if (done_ready_i) state_q <= IDLE;
                default: begin state_q <= FAIL; fail_q <= 1; scale_valid_q <= 0; end
            endcase
        end
    end
endmodule
`default_nettype wire
