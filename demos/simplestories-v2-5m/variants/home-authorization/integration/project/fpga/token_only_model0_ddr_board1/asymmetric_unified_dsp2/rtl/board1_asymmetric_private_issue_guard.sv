`timescale 1ns/1ps
`default_nettype none

// Private fixed-stage authorization boundary for the asymmetric DSP array.
//
// Modes 0--2 may issue any subset of the 64 projection/head lanes.  Modes
// 3--4 are physically implemented only in lanes 0--15, so a request naming
// any upper lane is rejected as a whole.  Modes 5--7 are unreachable and are
// also rejected.  The only product-level caller is the immutable transformer
// stage controller; this is not a user-visible opcode or operand interface.
module board1_asymmetric_private_issue_guard (
    input  wire        request_valid_i,
    input  wire [2:0]  private_mode_i,
    input  wire [63:0] requested_lanes_i,
    output reg         issue_valid_o,
    output reg  [63:0] issued_lanes_o,
    output reg         illegal_request_o
);
    localparam [2:0] MODE_DIRECT   = 3'd0;
    localparam [2:0] MODE_COARSE   = 3'd1;
    localparam [2:0] MODE_RESIDUAL = 3'd2;
    localparam [2:0] MODE_DYNAMIC  = 3'd3;
    localparam [2:0] MODE_WIDE     = 3'd4;

    always @* begin
        issue_valid_o = 1'b0;
        issued_lanes_o = 64'd0;
        illegal_request_o = 1'b0;
        case (request_valid_i)
            1'b0: begin
                // Idle never reports an illegal transaction, regardless of
                // don't-care mode/operand wires behind the fixed controller.
            end
            1'b1: begin
                case (private_mode_i)
                    MODE_DIRECT,
                    MODE_COARSE,
                    MODE_RESIDUAL: begin
                        issue_valid_o = 1'b1;
                        issued_lanes_o = requested_lanes_i;
                    end
                    MODE_DYNAMIC,
                    MODE_WIDE: begin
                        // Procedural-if treats an X/Z comparison as false in
                        // four-state simulation, which fails this request
                        // closed rather than accidentally authorizing it.
                        if (requested_lanes_i[63:16] == 48'd0) begin
                            issue_valid_o = 1'b1;
                            issued_lanes_o = requested_lanes_i;
                        end else begin
                            illegal_request_o = 1'b1;
                        end
                    end
                    default: begin
                        illegal_request_o = 1'b1;
                    end
                endcase
            end
            default: begin
                // Unknown request validity is not an authorization.
                illegal_request_o = 1'b1;
            end
        endcase
    end
endmodule

`default_nettype wire
