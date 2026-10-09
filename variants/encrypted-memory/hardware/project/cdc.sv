`timescale 1ns/1ps
`default_nettype none

// Private pipelined read-only model transport. All three Gray-pointer FIFOs
// use the existing preserved FIFO implementation, not a new CDC primitive.
// Parent resets assert together and release synchronously in each domain;
// the physical adapter and its outstanding epoch reset with the app side.
// CLEAR does NOT reset this transport: accepted page fills must still drain.
//
// Before an app request is accepted, reserve one of 32 return credits.
// Only core delivery returns a credit, through a third FIFO. Thus stopping
// either clock cannot overrun the 64-entry response FIFO. The credit reaches
// app later than that response FIFO's synchronized read pointer (same core
// delivery edge, two synchronizers plus credit-output prefetch). This also
// covers conservative FIFO-full indications after wrap, without assuming a
// particular core/app frequency ratio. Physical Gray-bus skew constraints
// and reset-release checks remain required in the final routed wrapper.
module board1_private_model_ddr_cdc (
    input wire core_clk_i, core_reset_n_i, core_upstream_fault_i,
    input wire core_req_valid_i,
    output wire core_req_ready_o,
    input wire [18:0] core_req_word_i,
    output wire core_rsp_valid_o,
    output wire [255:0] core_rsp_data_o,
    output wire core_rsp_error_o,
    output wire core_fault_o,
    input wire app_clk_i, app_reset_n_i, app_upstream_fault_i,
    output wire app_req_valid_o,
    input wire app_req_ready_i,
    output wire [18:0] app_req_word_o,
    input wire app_rsp_valid_i,
    input wire [255:0] app_rsp_data_i,
    input wire app_rsp_error_i,
    output wire app_fault_o
);
    wire req_s_ready,req_m_valid,req_m_ready,req_s_fault,req_m_fault;
    wire rsp_s_ready,rsp_m_valid,rsp_m_ready,rsp_s_fault,rsp_m_fault;
    wire credit_s_ready,credit_m_valid,credit_m_ready,credit_s_fault,credit_m_fault;
    wire [256:0] response_payload;
    logic core_fault_q,app_fault_q;
    (* async_reg="true",syn_preserve=1 *) logic app_fault_meta_q,app_fault_sync_q;
    (* async_reg="true",syn_preserve=1 *) logic core_fault_meta_q,core_fault_sync_q;
    logic [5:0] reserved_q,inflight_q;
    wire core_dead=core_fault_q || app_fault_sync_q || core_upstream_fault_i;
    wire app_dead=app_fault_q || core_fault_sync_q || app_upstream_fault_i;
    wire request_fire=app_req_valid_o && app_req_ready_i;
    wire credit_fire=credit_m_valid && credit_m_ready;
    wire legal_return=app_rsp_valid_i && inflight_q!=0 && !app_dead;
    wire core_delivery=rsp_m_valid && rsp_m_ready;

    assign core_req_ready_o=req_s_ready && !core_dead;
    assign app_req_valid_o=req_m_valid && reserved_q<32 && !app_dead;
    assign req_m_ready=app_req_ready_i && reserved_q<32 && !app_dead;
    assign rsp_m_ready=credit_s_ready && !core_dead;
    assign core_rsp_valid_o=core_delivery;
    assign core_rsp_data_o=response_payload[255:0];
    assign core_rsp_error_o=response_payload[256];
    assign credit_m_ready=reserved_q!=0 && !app_dead;
    assign core_fault_o=core_dead;
    assign app_fault_o=app_dead;

    // Reserve/return credits and all fault gates are unchanged. The request
    // pointer selects its owned row from registered state; downstream readiness
    // no longer selects a different distributed-memory address in this cycle.
    // A consumed request leaves one app-cycle bubble, never an extra owner slot.
    board1_async_fifo_gray #(.WIDTH(19),.ADDR_BITS(6),
        .DESTINATION_LOOKAHEAD(0)) u_requests (
        .s_clk_i(core_clk_i),.s_reset_n_i(core_reset_n_i),
        .s_valid_i(core_req_valid_i && !core_dead),.s_ready_o(req_s_ready),.s_data_i(core_req_word_i),
        .s_abort_i(core_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(req_s_fault),
        .m_clk_i(app_clk_i),.m_reset_n_i(app_reset_n_i),.m_valid_o(req_m_valid),
        .m_ready_i(req_m_ready),.m_data_o(app_req_word_o),.m_empty_o(),.m_protocol_fault_o(req_m_fault));
    board1_async_fifo_gray_block #(.WIDTH(257),.ADDR_BITS(6),.RAM_STYLE("block")) u_responses (
        .s_clk_i(app_clk_i),.s_reset_n_i(app_reset_n_i),
        .s_valid_i(legal_return),.s_ready_o(rsp_s_ready),.s_data_i({app_rsp_error_i,app_rsp_data_i}),
        .s_abort_i(app_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(rsp_s_fault),
        .m_clk_i(core_clk_i),.m_reset_n_i(core_reset_n_i),.m_valid_o(rsp_m_valid),
        .m_ready_i(rsp_m_ready),.m_data_o(response_payload),.m_empty_o(),.m_protocol_fault_o(rsp_m_fault));
    board1_async_fifo_gray #(.WIDTH(1),.ADDR_BITS(6)) u_credits (
        .s_clk_i(core_clk_i),.s_reset_n_i(core_reset_n_i),
        .s_valid_i(core_delivery),.s_ready_o(credit_s_ready),.s_data_i(1'b1),
        .s_abort_i(core_dead),.s_full_o(),.s_empty_o(),.s_protocol_fault_o(credit_s_fault),
        .m_clk_i(app_clk_i),.m_reset_n_i(app_reset_n_i),.m_valid_o(credit_m_valid),
        .m_ready_i(credit_m_ready),.m_data_o(),.m_empty_o(),.m_protocol_fault_o(credit_m_fault));

    always_ff @(posedge core_clk_i or negedge core_reset_n_i) begin
        if(!core_reset_n_i) begin
            app_fault_meta_q<=0;app_fault_sync_q<=0;core_fault_q<=0;
        end else begin
            app_fault_meta_q<=app_fault_o;app_fault_sync_q<=app_fault_meta_q;
            if(core_upstream_fault_i || app_fault_sync_q || req_s_fault || rsp_m_fault || credit_s_fault)
                core_fault_q<=1;
        end
    end
    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if(!app_reset_n_i) begin
            core_fault_meta_q<=0;core_fault_sync_q<=0;app_fault_q<=0;reserved_q<=0;inflight_q<=0;
        end else begin
            core_fault_meta_q<=core_fault_o;core_fault_sync_q<=core_fault_meta_q;
            if(app_upstream_fault_i || core_fault_sync_q || req_m_fault || rsp_s_fault || credit_m_fault ||
               (app_rsp_valid_i && (inflight_q==0 || !rsp_s_ready || app_rsp_error_i)) ||
               (credit_m_valid && reserved_q==0)) app_fault_q<=1;
            if(!app_dead) case({request_fire,credit_fire})
                2'b10:reserved_q<=reserved_q+6'd1;
                2'b01:reserved_q<=reserved_q-6'd1;
                default: ;
            endcase
            if(!app_dead) case({request_fire,legal_return})
                2'b10:inflight_q<=inflight_q+6'd1;
                2'b01:inflight_q<=inflight_q-6'd1;
                default: ;
            endcase
        end
    end
`ifdef FORMAL
    always_ff @(posedge app_clk_i) if(app_reset_n_i) begin
        assert(reserved_q<=32);
        assert(inflight_q<=reserved_q);
        if(legal_return) assert(rsp_s_ready);
        if(app_fault_o) assert(!app_req_valid_o);
    end
    always_ff @(posedge core_clk_i) if(core_reset_n_i && core_fault_o)
        assert(!core_req_ready_o && !core_rsp_valid_o);
`endif
endmodule
`default_nettype wire
