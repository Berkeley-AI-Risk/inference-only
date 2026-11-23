`timescale 1ns/1ps
`default_nettype none
// Modeled two-entry private test vault; public fixture keys, real inherited engines.
module combined_kv_cipher_shared (
    input wire model_slot_i,
    input wire clk,reset_n,clear_i,model_locked_i,upstream_fault_i,
    input wire [63:0] epoch_i,
    input wire s_wr_valid,
    output wire s_wr_ready,
    input wire [2:0] s_wr_layer,
    input wire [11:0] s_wr_position,
    input wire [1:0] s_wr_head,
    input wire [3:0] s_wr_word,
    input wire [18:0] s_wr_shadow,
    input wire [255:0] s_wr_data,
    output wire s_wr_cpl_valid,
    input wire s_wr_cpl_ready,
    output wire s_wr_cpl_fault,
    input wire s_rd_valid,
    output wire s_rd_ready,
    input wire [2:0] s_rd_layer,
    input wire [11:0] s_rd_position,
    input wire [1:0] s_rd_head,
    input wire [3:0] s_rd_word,
    input wire [18:0] s_rd_shadow,
    output wire s_rd_rsp_valid,
    input wire s_rd_rsp_ready,
    output wire [255:0] s_rd_rsp_data,
    output wire s_rd_rsp_fault,
    output wire m_wr_valid,
    input wire m_wr_ready,
    output wire [2:0] m_wr_layer,
    output wire [11:0] m_wr_position,
    output wire [1:0] m_wr_head,
    output wire [3:0] m_wr_word,
    output wire [18:0] m_wr_shadow,
    output wire [255:0] m_wr_data,
    input wire m_wr_cpl_valid,
    output wire m_wr_cpl_ready,
    input wire m_wr_cpl_fault,
    output wire m_rd_valid,
    input wire m_rd_ready,
    output wire [2:0] m_rd_layer,
    output wire [11:0] m_rd_position,
    output wire [1:0] m_rd_head,
    output wire [3:0] m_rd_word,
    output wire [18:0] m_rd_shadow,
    input wire m_rd_rsp_valid,
    output wire m_rd_rsp_ready,
    input wire [255:0] m_rd_rsp_data,
    input wire m_rd_rsp_fault,
    output wire busy_o,fault_o
);
    // The existing lease guard holds reset low until the admitted model and
    // authorization context are bound. Keep that model until reset. A bad
    // live selector change uses the bridge's original fail-closed drain path.
    logic slot_owned_q,model_slot_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            slot_owned_q<=0;
            model_slot_q<=0;
        end else if(!slot_owned_q) begin
            slot_owned_q<=1;
            model_slot_q<=model_slot_i;
        end
    end
    wire selected_model=slot_owned_q ? model_slot_q : model_slot_i;
    wire slot_violation=slot_owned_q && model_slot_i!=model_slot_q;
    tang_private_kv_siv_bridge_two_model #(.KEY_IS_PROVISIONED(1'b1),
        .MAC_KEY0(256'h404142434445464748494a4b4c4d4e4f505152535455565758595a5b5c5d5e5f), .CTR_KEY0(256'h606162636465666768696a6b6c6d6e6f707172737475767778797a7b7c7d7e7f), .MODEL_ID0(256'hcad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0),
        .MAC_KEY1(256'he80f51d830cff0f7d20fee03eda4834e0545139d7bce81ecc25576fecb5002fb), .CTR_KEY1(256'h4736aa8a32105d2b32d9f0539dac49f9c691a736ae0264482bd06fede6baebac), .MODEL_ID1(256'h1ada1d7dfbbae137f8747945a7144a84428f2d1d6135afa13c071ab67e7f05ce)) u_shared (
        .model_slot_i(selected_model),
        .clk(clk),
        .reset_n(reset_n),
        .clear_i(clear_i),
        .model_locked_i(model_locked_i),
        .upstream_fault_i(upstream_fault_i || slot_violation),
        .epoch_i(epoch_i),
        .s_wr_valid(s_wr_valid),
        .s_wr_ready(s_wr_ready),
        .s_wr_layer(s_wr_layer),
        .s_wr_position(s_wr_position),
        .s_wr_head(s_wr_head),
        .s_wr_word(s_wr_word),
        .s_wr_shadow(s_wr_shadow),
        .s_wr_data(s_wr_data),
        .s_wr_cpl_valid(s_wr_cpl_valid),
        .s_wr_cpl_ready(s_wr_cpl_ready),
        .s_wr_cpl_fault(s_wr_cpl_fault),
        .s_rd_valid(s_rd_valid),
        .s_rd_ready(s_rd_ready),
        .s_rd_layer(s_rd_layer),
        .s_rd_position(s_rd_position),
        .s_rd_head(s_rd_head),
        .s_rd_word(s_rd_word),
        .s_rd_shadow(s_rd_shadow),
        .s_rd_rsp_valid(s_rd_rsp_valid),
        .s_rd_rsp_ready(s_rd_rsp_ready),
        .s_rd_rsp_data(s_rd_rsp_data),
        .s_rd_rsp_fault(s_rd_rsp_fault),
        .m_wr_valid(m_wr_valid),
        .m_wr_ready(m_wr_ready),
        .m_wr_layer(m_wr_layer),
        .m_wr_position(m_wr_position),
        .m_wr_head(m_wr_head),
        .m_wr_word(m_wr_word),
        .m_wr_shadow(m_wr_shadow),
        .m_wr_data(m_wr_data),
        .m_wr_cpl_valid(m_wr_cpl_valid),
        .m_wr_cpl_ready(m_wr_cpl_ready),
        .m_wr_cpl_fault(m_wr_cpl_fault),
        .m_rd_valid(m_rd_valid),
        .m_rd_ready(m_rd_ready),
        .m_rd_layer(m_rd_layer),
        .m_rd_position(m_rd_position),
        .m_rd_head(m_rd_head),
        .m_rd_word(m_rd_word),
        .m_rd_shadow(m_rd_shadow),
        .m_rd_rsp_valid(m_rd_rsp_valid),
        .m_rd_rsp_ready(m_rd_rsp_ready),
        .m_rd_rsp_data(m_rd_rsp_data),
        .m_rd_rsp_fault(m_rd_rsp_fault),
        .busy_o(busy_o),
        .fault_o(fault_o)
    );
endmodule
`default_nettype wire
