`timescale 1ns/1ps
// Private component. All dimensions and IO are fixed for this model witness.
module rank_model (
    input logic clk, reset,
    input logic local_load, compute, first_beat, last_beat,
    input logic [9:0] base, valid_elements,
    input logic [3:0] row_slot,
    input logic signed [9:0] weight_i [16],
    input logic peer_config, peer_role, receive, tag_ok, sum_frame,
    input logic tx_start, tx_take,
    output logic tx_valid,
    output logic [63:0] tx_payload [16],
    output logic [63:0] tx_descriptor, tx_sequence, tx_count,
    input logic [63:0] rx_descriptor, expected_descriptor, rx_sequence,
    input logic [63:0] payload [16],
    output logic accepted, rejected,
    output logic [63:0] next_sequence, sum_writes, activation_writes,
    output logic signed [34:0] partial [16],
    output logic signed [35:0] reduced [16]
);
    logic signed [15:0] activation [682];
    logic signed [25:0] product [16];
    logic signed [34:0] running, beat_sum, full_sum;
    for (genvar lane=0; lane<16; lane++) begin: products
        wire signed [15:0] operand = (compute && lane < valid_elements)
            ? activation[int'(base)+lane] : 16'sd0;
        board1_unified_projection_head_mul_exact multiply (
            .mode_i(2'd0), .activation_i(operand), .direct_weight_i(weight_i[lane]),
            .coarse_weight0_i('0), .coarse_weight1_i('0),
            .residual_weight0_i('0), .residual_weight1_i('0),
            .product0_o(product[lane]), .product1_o()
        );
    end
    always_comb begin
        beat_sum = '0;
        for (int i=0; i<16; i++) beat_sum += {{9{product[i][25]}},product[i]};
        full_sum = (first_beat ? 35'sd0 : running) + beat_sum;
    end
    wire admissible = peer_config && (sum_frame != peer_role) && tag_ok && rx_descriptor == expected_descriptor &&
        rx_sequence == next_sequence && valid_elements != 0 &&
        (sum_frame ? (valid_elements <= 16) :
         (valid_elements <= 64 && int'(base)+int'(valid_elements) <= 682));
    always_ff @(posedge clk) begin
        accepted <= 0;
        rejected <= 0;
        if (reset) begin
            tx_valid <= 0;
            tx_count <= 0;
            tx_sequence <= 0;
            tx_descriptor <= 0;
            next_sequence <= 0;
            sum_writes <= 0;
            activation_writes <= 0;
            running <= 0;
            for (int i=0; i<16; i++) begin
                partial[i] <= 0;
                reduced[i] <= 0;
            end
        end else begin
            // Bounded sender slot. Role 1 publishes its actual arithmetic registers.
            // Role 0 publishes the activation chunk returned by the scalar operator.
            if (tx_valid && tx_take) begin
                tx_valid <= 0;
                tx_count <= tx_count + 1;
            end
            if (tx_start && !tx_valid && peer_config && sum_frame == peer_role) begin
                tx_descriptor <= expected_descriptor;
                tx_sequence <= tx_count;
                tx_valid <= 1;
                for (int i=0; i<16; i++)
                    tx_payload[i] <= sum_frame ? {{29{partial[i][34]}},partial[i]} : payload[i];
            end
            if (receive) begin
                accepted <= admissible;
                rejected <= !admissible;
                if (admissible) begin
                    next_sequence <= next_sequence + 1;
                    if (sum_frame) begin
                        for (int i=0; i<16; i++) begin
                            if (i < valid_elements)
                                reduced[i] <= $signed({partial[i][34],partial[i]}) +
                                              $signed(payload[i][35:0]);
                        end
                        sum_writes <= sum_writes + 64'(valid_elements);
                    end else activation_writes <= activation_writes + 64'(valid_elements);
                end
            end
            if (local_load || (receive && admissible && !sum_frame))
                for (int i=0; i<64; i++)
                    if (i < valid_elements)
                        activation[int'(base)+i] <= payload[i/4][(i%4)*16+:16];
            if (compute) begin
                running <= full_sum;
                if (last_beat) partial[row_slot] <= full_sum;
            end
        end
    end
endmodule
