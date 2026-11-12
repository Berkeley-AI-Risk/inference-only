// Passive observer for the frozen TLM26 decoder. Every DUT connection is input-only.
`timescale 1ns/1ps
module moe_dispatch_observer #(
    parameter logic [8:0] EXPERT_START = 0,
    parameter logic [8:0] MAT_START = 0,
    parameter logic [8:0] EXPERT_W1_RETURN = 0,
    parameter logic [8:0] WEIGHT_WAIT = 0
) (
    input wire clk, rst_n, clear_i,
    input wire [8:0] state, back_MAT, pos, tok,
    input wire rank,
    input wire [2:0] layer, top0, top1,
    input wire [20:0] expertbase, lbase, mbase, wi, waddr,
    input wire [9:0] rows, cols, r, j,
    input wire wreq, wvalid, wfail
);
    integer history = -1;
    reg clear_previous = 0;
    reg check_launch = 0;
    reg awaiting_weight = 0;
    reg [20:0] saved_base;
    reg [8:0] saved_pos, saved_tok;
    reg [2:0] saved_layer, saved_expert;
    reg saved_rank;
    wire [2:0] selected = rank ? top1 : top0;

    always @(posedge clk) begin
        if (!rst_n) begin
            history <= -1;
            clear_previous <= 0;
            check_launch <= 0;
            awaiting_weight <= 0;
        end else begin
            clear_previous <= clear_i;
            if (clear_i) begin
                if (!clear_previous) begin
                    history <= history + 1;
                    $display("MOE_CLEAR %0d", history + 1);
                end
                check_launch <= 0;
                awaiting_weight <= 0;
            end else begin
                if (check_launch) begin
                    if (state != MAT_START || back_MAT != EXPERT_W1_RETURN ||
                        mbase != saved_base || rows != 192 || cols != 64)
                        $fatal(1, "Expert launch did not enter its W1 matrix");
                    $display("MOE_START %0d %0d %0d %0d %0d %0d %0d",
                        history, saved_pos, saved_tok, saved_layer,
                        saved_rank, saved_expert, saved_base);
                    check_launch <= 0;
                end
                if (state == EXPERT_START) begin
                    if (history < 0 || check_launch || awaiting_weight ||
                        expertbase != lbase + 12928 + selected * 36864)
                        $fatal(1, "Invalid or overlapping expert start");
                    saved_base <= expertbase;
                    saved_pos <= pos;
                    saved_tok <= tok;
                    saved_layer <= layer;
                    saved_rank <= rank;
                    saved_expert <= selected;
                    check_launch <= 1;
                    awaiting_weight <= 1;
                end
                if (state == WEIGHT_WAIT && back_MAT == EXPERT_W1_RETURN &&
                    r == 0 && j == 0 && wreq && wvalid && !wfail) begin
                    if (!awaiting_weight || waddr != saved_base ||
                        wi != saved_base || mbase != saved_base ||
                        pos != saved_pos || tok != saved_tok ||
                        layer != saved_layer || rank != saved_rank)
                        $fatal(1, "Expert's first accepted weight lost its launch identity");
                    $display("MOE_WEIGHT %0d %0d %0d %0d %0d %0d %0d",
                        history, pos, tok, layer, rank, saved_expert, waddr);
                    awaiting_weight <= 0;
                end
            end
        end
    end
endmodule

bind tlm_decoder moe_dispatch_observer #(
    .EXPERT_START(EXPERT_1), .MAT_START(MAT),
    .EXPERT_W1_RETURN(EXPERT_2), .WEIGHT_WAIT(MAT_MAC_1_WAIT)
) dispatch_observer (
    .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
    .state(state), .back_MAT(back_MAT), .pos(pos), .tok(tok),
    .rank(rank), .layer(layer), .top0(top0), .top1(top1),
    .expertbase(expertbase), .lbase(lbase), .mbase(mbase), .wi(wi),
    .waddr(waddr), .rows(rows), .cols(cols), .r(r), .j(j),
    .wreq(wreq), .wvalid(wvalid), .wfail(wfail)
);
