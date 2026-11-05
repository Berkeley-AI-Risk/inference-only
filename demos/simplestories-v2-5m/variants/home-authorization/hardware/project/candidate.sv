`timescale 1ns/1ps
`default_nettype none

// PRIVATE exact BFP-v5 helper. Same value/fault contract as the bit-serial
// predecessor; three clocks after acceptance produce one held response.
// The surrounding fixed model, not a host, supplies values and shift counts.
// A split 128-bit barrel serves both directions: bit reversal converts a
// checked signed left shift into a right shift with an overflow witness.
module board1_fixed_vector_rne_shift_pipeline1 (
    input wire clk,rst_n,clear_i,request_valid_i,
    output wire request_ready_o,
    input wire signed [63:0] request_value_i,
    input wire signed [8:0] request_shift_i,
    output logic response_valid_o,
    input wire response_ready_i,
    output logic signed [63:0] response_result_o,
    output logic response_fault_o
);
    localparam [2:0] IDLE=0,LOW=1,HIGH=2,ROUND=3,HOLD=5;
    logic [2:0] state_q;
    wire busy_q=state_q!=IDLE && state_q!=HOLD;
    assign request_ready_o=rst_n && !clear_i && !busy_q && !response_valid_o;
    wire request_fire=request_valid_i && request_ready_o;

    // Reset/cancellation revokes state and output validity; private payload
    // registers are unread until a fresh accepted request initializes them.
    logic [127:0] source_q,low_q,shifted_q;
    logic [5:0] amount_q;
    logic left_q,negative_q,force_zero_q,bad_count_q;
    function automatic [127:0] reverse_bits(input [127:0] value);
        for(integer bit_index=0;bit_index<128;bit_index=bit_index+1)
            reverse_bits[bit_index]=value[127-bit_index];
    endfunction
    wire [63:0] magnitude=request_value_i[63] ? $unsigned(-request_value_i) : $unsigned(request_value_i);
    wire [127:0] left_result=reverse_bits(shifted_q);
    wire left_overflow=left_result[127:64]!={64{left_result[63]}};
    wire right_round_up=shifted_q[63] && ((|shifted_q[62:0]) || shifted_q[64]);
    // Merge sign and RNE increment into one modular two's-complement adder.
    wire [63:0] signed_right = (shifted_q[127:64] ^ {64{negative_q}}) +
        {63'd0, (right_round_up ^ negative_q)};
    wire result_fault = bad_count_q || (left_q && left_overflow);
    always_ff @(posedge clk) begin
        if(request_fire) begin
            source_q<=request_shift_i[8] ? reverse_bits({{64{request_value_i[63]}},request_value_i}) :
                {magnitude,64'd0};
            amount_q<=request_shift_i[8] ? -request_shift_i[5:0] : request_shift_i[5:0];
            left_q<=request_shift_i[8];negative_q<=request_value_i[63];
            // Preserve the predecessor's specified tails, even for zero:
            // count < -62 faults; count > +62 returns zero without fault.
            bad_count_q<=request_shift_i < -9'sd62;
            force_zero_q<=request_shift_i > 9'sd62;
        end
        if(state_q==LOW) low_q<=source_q>>amount_q[2:0];
        if(state_q==HIGH) shifted_q<=low_q>>{amount_q[5:3],3'b000};
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else if(clear_i) begin
            state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else case(state_q)
            IDLE: if(request_fire) state_q<=LOW;
            LOW: state_q<=HIGH;
            HIGH: state_q<=ROUND;
            ROUND: begin
                state_q<=HOLD;response_valid_o<=1;response_fault_o<=result_fault;
                response_result_o<=(result_fault || force_zero_q) ? 64'sd0 :
                    (left_q ? $signed(left_result[63:0]) : $signed(signed_right));
            end
            HOLD: if(response_ready_i) begin
                state_q<=IDLE;response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
            end
            default: begin
                state_q<=HOLD;response_valid_o<=1;response_result_o<=0;response_fault_o<=1;
            end
        endcase
    end
endmodule
`default_nettype wire
