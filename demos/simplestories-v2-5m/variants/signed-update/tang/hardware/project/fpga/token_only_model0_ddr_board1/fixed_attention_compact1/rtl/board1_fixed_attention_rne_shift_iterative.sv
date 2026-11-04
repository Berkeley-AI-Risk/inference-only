`timescale 1ns/1ps
`default_nettype none

// Four-cycle registered-group signed64 shift with the oracle's exact RNE rule.
// Negative shift counts mean left shift.  Counts below -62 fault and counts
// above 62 produce zero, matching the fixed-attention oracle helper.  A left
// result which cannot be represented in signed 64 bits also faults instead of
// silently wrapping; all legal attention-engine requests are proven to remain
// in range.  Only one private request can be in flight and CLEAR cancels it
// deterministically.
module board1_fixed_attention_rne_shift_iterative (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    request_valid_i,
    output logic                   request_ready_o,
    input  wire signed [63:0]      request_value_i,
    input  wire signed [8:0]       request_shift_i,
    output logic                   response_valid_o,
    input  wire                    response_ready_i,
    output logic signed [63:0]     response_result_o,
    output logic                   response_fault_o
);
    logic busy_q, left_q, negative_q;
    logic [1:0] phase_q;
    logic [5:0] amount_q;
    logic [63:0] work_q;
    // [66]=cumulative left overflow, [65]=guard, [64]=sticky.
    logic [66:0] stage1_q, stage2_q, stage3_q;

    // Fixed distances, not a cascaded full-width variable barrel path.
    function automatic [66:0] shift_group0(
        input [63:0] value, input guard, sticky, left,
        input [1:0] select_i
    );
        reg [63:0] shifted;
        reg next_guard, next_sticky, overflow;
        begin
            shifted=value; next_guard=guard; next_sticky=sticky; overflow=0;
            case(select_i)
                2'd1: begin
                    if(left)begin
                        shifted=value << 1;
                        overflow=(value[63:62] != {2{value[63]}});
                    end else begin
                        shifted=value >> 1;
                        next_guard=value[0];
                        next_sticky=sticky || guard || 1'b0;
                    end
                end
                2'd2: begin
                    if(left)begin
                        shifted=value << 2;
                        overflow=(value[63:61] != {3{value[63]}});
                    end else begin
                        shifted=value >> 2;
                        next_guard=value[1];
                        next_sticky=sticky || guard || (|value[0:0]);
                    end
                end
                2'd3: begin
                    if(left)begin
                        shifted=value << 3;
                        overflow=(value[63:60] != {4{value[63]}});
                    end else begin
                        shifted=value >> 3;
                        next_guard=value[2];
                        next_sticky=sticky || guard || (|value[1:0]);
                    end
                end
                default: begin end
            endcase
            shift_group0={overflow,next_guard,next_sticky,shifted};
        end
    endfunction
    // Fixed distances, not a cascaded full-width variable barrel path.
    function automatic [66:0] shift_group1(
        input [63:0] value, input guard, sticky, left,
        input [1:0] select_i
    );
        reg [63:0] shifted;
        reg next_guard, next_sticky, overflow;
        begin
            shifted=value; next_guard=guard; next_sticky=sticky; overflow=0;
            case(select_i)
                2'd1: begin
                    if(left)begin
                        shifted=value << 4;
                        overflow=(value[63:59] != {5{value[63]}});
                    end else begin
                        shifted=value >> 4;
                        next_guard=value[3];
                        next_sticky=sticky || guard || (|value[2:0]);
                    end
                end
                2'd2: begin
                    if(left)begin
                        shifted=value << 8;
                        overflow=(value[63:55] != {9{value[63]}});
                    end else begin
                        shifted=value >> 8;
                        next_guard=value[7];
                        next_sticky=sticky || guard || (|value[6:0]);
                    end
                end
                2'd3: begin
                    if(left)begin
                        shifted=value << 12;
                        overflow=(value[63:51] != {13{value[63]}});
                    end else begin
                        shifted=value >> 12;
                        next_guard=value[11];
                        next_sticky=sticky || guard || (|value[10:0]);
                    end
                end
                default: begin end
            endcase
            shift_group1={overflow,next_guard,next_sticky,shifted};
        end
    endfunction
    // Fixed distances, not a cascaded full-width variable barrel path.
    function automatic [66:0] shift_group2(
        input [63:0] value, input guard, sticky, left,
        input [1:0] select_i
    );
        reg [63:0] shifted;
        reg next_guard, next_sticky, overflow;
        begin
            shifted=value; next_guard=guard; next_sticky=sticky; overflow=0;
            case(select_i)
                2'd1: begin
                    if(left)begin
                        shifted=value << 16;
                        overflow=(value[63:47] != {17{value[63]}});
                    end else begin
                        shifted=value >> 16;
                        next_guard=value[15];
                        next_sticky=sticky || guard || (|value[14:0]);
                    end
                end
                2'd2: begin
                    if(left)begin
                        shifted=value << 32;
                        overflow=(value[63:31] != {33{value[63]}});
                    end else begin
                        shifted=value >> 32;
                        next_guard=value[31];
                        next_sticky=sticky || guard || (|value[30:0]);
                    end
                end
                2'd3: begin
                    if(left)begin
                        shifted=value << 48;
                        overflow=(value[63:15] != {49{value[63]}});
                    end else begin
                        shifted=value >> 48;
                        next_guard=value[47];
                        next_sticky=sticky || guard || (|value[46:0]);
                    end
                end
                default: begin end
            endcase
            shift_group2={overflow,next_guard,next_sticky,shifted};
        end
    endfunction

    wire [66:0] group0_result=shift_group0(work_q,1'b0,1'b0,left_q,amount_q[1:0]);
    wire [66:0] group1_result=shift_group1(stage1_q[63:0],stage1_q[65],stage1_q[64],left_q,amount_q[3:2]);
    wire [66:0] group2_result=shift_group2(stage2_q[63:0],stage2_q[65],stage2_q[64],left_q,amount_q[5:4]);
    wire round_up=stage3_q[65] && (stage3_q[64] || stage3_q[0]);
    wire [63:0] rounded=stage3_q[63:0]+{{63{1'b0}},round_up};
    // Standalone prototype: stages1/2 are unnecessary for counts1..3.
    wire small_round_up=stage1_q[65] && (stage1_q[64] || stage1_q[0]);
    wire [63:0] small_rounded=stage1_q[63:0]+{{63{1'b0}},small_round_up};
    always_comb request_ready_o=rst_n && !clear_i && !busy_q && !response_valid_o;

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            busy_q<=0;left_q<=0;negative_q<=0;phase_q<=0;amount_q<=0;work_q<=0;
            stage1_q<=0;stage2_q<=0;stage3_q<=0;
            response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else if(clear_i)begin
            busy_q<=0;left_q<=0;negative_q<=0;phase_q<=0;amount_q<=0;work_q<=0;
            stage1_q<=0;stage2_q<=0;stage3_q<=0;
            response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
        end else begin
            if(response_valid_o && response_ready_i)begin
                response_valid_o<=0;response_result_o<=0;response_fault_o<=0;
            end
            if(request_valid_i && request_ready_o)begin
                response_result_o<=0;response_fault_o<=0;
                phase_q<=0;
                if(request_shift_i==0)begin
                    busy_q<=0;response_valid_o<=1;response_result_o<=request_value_i;
                end else if(request_shift_i < -9'sd62)begin
                    busy_q<=0;response_valid_o<=1;response_fault_o<=1;
                end else if(request_shift_i > 9'sd62 || request_value_i==0)begin
                    busy_q<=0;response_valid_o<=1;
                end else begin
                    busy_q<=1;
                    left_q<=request_shift_i<0;
                    negative_q<=request_value_i[63];
                    amount_q<=request_shift_i<0 ? $unsigned(-request_shift_i) : $unsigned(request_shift_i);
                    work_q<=request_shift_i<0 ? $unsigned(request_value_i) :
                        (request_value_i[63] ? $unsigned(-request_value_i) : $unsigned(request_value_i));
                end
            end else if(busy_q)begin
                case(phase_q)
                    0: begin stage1_q<=group0_result;phase_q<=1;end
                    1: begin
                        if(amount_q[5:2]==0)begin
                            busy_q<=0;response_valid_o<=1;
                            response_fault_o<=left_q && stage1_q[66];
                            response_result_o<=left_q ? (stage1_q[66] ? 64'sd0 : $signed(stage1_q[63:0])) :
                                (negative_q ? $signed(~small_rounded+64'd1) : $signed(small_rounded));
                        end else begin
                            stage2_q<={stage1_q[66] || group1_result[66],group1_result[65:0]};phase_q<=2;
                        end
                    end
                    2: begin stage3_q<={stage2_q[66] || group2_result[66],group2_result[65:0]};phase_q<=3;end
                    3: begin
                        busy_q<=0;response_valid_o<=1;
                        response_fault_o<=left_q && stage3_q[66];
                        response_result_o<=left_q ? (stage3_q[66] ? 64'sd0 : $signed(stage3_q[63:0])) :
                            (negative_q ? $signed(~rounded+64'd1) : $signed(rounded));
                    end
                endcase
            end
        end
    end
endmodule
`default_nettype wire
