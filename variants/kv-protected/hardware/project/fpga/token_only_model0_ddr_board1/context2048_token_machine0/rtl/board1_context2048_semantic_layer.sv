`timescale 1ns/1ps
`default_nettype none

// Private six-layer SimpleStories-V2-5M semantic service.  A product top may
// connect only the fixed token-derived hidden stream and the authenticated DDR
// fabric to this module; none of its internal stage signals leave this file.
module board1_context2048_semantic_layer #(
    parameter integer ADDR_W = 25
) (
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    clear_i,
    input  wire                    model_lock_i,
    input  wire                    upstream_fault_i,

    // Fixed tied-head client of the semantic datapath's sole projection
    // array.  This is an integration-private seam and is absent from the
    // token-machine public wrapper.
    input  wire                    private_head_start_valid_i,
    output logic                   private_head_start_ready_o,
    input  wire signed [7:0]       private_head_activation_exponent_i,
    input  wire                    private_head_activation_valid_i,
    output logic                   private_head_activation_ready_o,
    input  wire [7:0]              private_head_activation_index_i,
    input  wire signed [15:0]      private_head_activation_mantissa_i,
    input  wire                    private_head_activation_last_i,
    output logic                   private_head_result_valid_o,
    input  wire                    private_head_result_ready_i,
    output logic [12:0]            private_head_result_row_index_o,
    output logic signed [49:0]     private_head_result_scaled_raw_o,
    output logic signed [7:0]      private_head_result_source_exponent_o,
    output logic                   private_head_result_last_o,
    output logic                   private_head_done_valid_o,
    input  wire                    private_head_done_ready_i,

    input  wire                    start_valid_i,
    output logic                   start_ready_o,
    input  wire [10:0]             fixed_position_i,
    input  wire signed [7:0]       input_exponent_i,

    input  wire                    input_valid_i,
    output logic                   input_ready_o,
    input  wire [7:0]              input_index_i,
    input  wire signed [15:0]      input_mantissa_i,
    input  wire                    input_last_i,

    output logic                   result_valid_o,
    input  wire                    result_ready_i,
    output logic [7:0]             result_index_o,
    output logic signed [15:0]     result_mantissa_o,
    output logic signed [7:0]      result_exponent_o,
    output logic                   result_last_o,
    output logic                   done_valid_o,
    input  wire                    done_ready_i,

    // Integration-private authenticated DDR read seam.  No write signal is
    // present and every address is derived below the fixed semantic schedule.
    output logic                   private_word_req_valid_o,
    input  wire                    private_word_req_ready_i,
    output logic [ADDR_W-1:0]      private_word_req_index_o,
    input  wire                    private_word_rsp_valid_i,
    output logic                   private_word_rsp_ready_o,
    input  wire [255:0]            private_word_rsp_data_i,
    input  wire                    private_word_rsp_fault_i,

    output logic                   kv_write_req_valid_o,
    input  wire                    kv_write_req_ready_i,
    output logic [2:0]             kv_write_req_layer_o,
    output logic [11:0]            kv_write_req_position_o,
    output logic [1:0]             kv_write_req_head_o,
    output logic [3:0]             kv_write_req_row_word_o,
    output logic [18:0]            kv_write_req_shadow_address_o,
    output logic [255:0]           kv_write_req_data_o,
    input  wire                    kv_write_cpl_valid_i,
    output logic                   kv_write_cpl_ready_o,
    input  wire                    kv_write_cpl_fault_i,
    output logic                   kv_read_req_valid_o,
    input  wire                    kv_read_req_ready_i,
    output logic [2:0]             kv_read_req_layer_o,
    output logic [11:0]            kv_read_req_position_o,
    output logic [1:0]             kv_read_req_head_o,
    output logic [3:0]             kv_read_req_row_word_o,
    output logic [18:0]            kv_read_req_shadow_address_o,
    input  wire                    kv_read_rsp_valid_i,
    output logic                   kv_read_rsp_ready_o,
    input  wire [255:0]            kv_read_rsp_data_i,
    input  wire                    kv_read_rsp_fault_i,
    input  wire                    kv_endpoint_fault_i,

    output logic [71:0]            committed_prefixes_o,
    output logic                   busy_o,
    output logic                   range_fault_o
);
    logic ingress_write;
    logic stage_valid;
    logic stage_ready;
    logic [4:0] stage;
    logic [2:0] layer;
    logic [10:0] position;
    logic signed [7:0] initial_exponent;
    logic stage_done;
    logic stage_fault;
    logic [7:0] private_result_index;
    logic signed [15:0] private_result_mantissa;
    logic signed [7:0] private_result_exponent;
    logic sequence_busy;
    logic sequence_fault;
    logic sequence_start_ready;
    logic datapath_busy;
    logic datapath_fault;
    logic datapath_head_start_ready;
    logic [71:0] committed_prefixes;
    logic service_start_collision_q;
    wire service_start_collision = start_valid_i &&
        private_head_start_valid_i && !clear_i;

    // The two fixed controller phases are structurally disjoint.  If that
    // invariant is ever violated, suppress both accepts combinationally and
    // latch the terminal evidence without creating a child-fault/valid loop.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            service_start_collision_q <= 1'b0;
        else if (service_start_collision)
            service_start_collision_q <= 1'b1;
    end

    board1_context2048_semantic_sequence u_sequence (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || datapath_fault ||
                          service_start_collision_q),
        // A CLEAR-aborted DDR read retains private ownership until its late
        // response drains.  Do not admit a new semantic transaction until
        // the complete datapath, including that ownership, is quiescent.
        .start_valid_i(start_valid_i && !datapath_busy &&
                       !private_head_start_valid_i),
        .start_ready_o(sequence_start_ready),
        .fixed_position_i(fixed_position_i),
        .input_exponent_i(input_exponent_i),
        .input_valid_i(input_valid_i), .input_ready_o(input_ready_o),
        .input_index_i(input_index_i),
        .input_mantissa_i(input_mantissa_i), .input_last_i(input_last_i),
        .private_ingress_write_o(ingress_write),
        .private_stage_valid_o(stage_valid),
        .private_stage_ready_i(stage_ready), .private_stage_o(stage),
        .private_layer_o(layer), .private_position_o(position),
        .private_input_exponent_o(initial_exponent),
        .private_stage_done_i(stage_done),
        .private_stage_fault_i(stage_fault),
        .private_result_index_o(private_result_index),
        .private_result_mantissa_i(private_result_mantissa),
        .private_result_exponent_i(private_result_exponent),
        .result_valid_o(result_valid_o), .result_ready_i(result_ready_i),
        .result_index_o(result_index_o),
        .result_mantissa_o(result_mantissa_o),
        .result_exponent_o(result_exponent_o),
        .result_last_o(result_last_o),
        .done_valid_o(done_valid_o), .done_ready_i(done_ready_i),
        .committed_prefixes_i(committed_prefixes),
        .busy_o(sequence_busy), .range_fault_o(sequence_fault)
    );

    board1_context2048_semantic_datapath #(.ADDR_W(ADDR_W)) u_datapath (
        .clk(clk), .rst_n(rst_n), .clear_i(clear_i),
        .model_lock_i(model_lock_i),
        .upstream_fault_i(upstream_fault_i || sequence_fault ||
                          service_start_collision_q),
        .private_head_start_valid_i(private_head_start_valid_i &&
                                    !sequence_busy && !start_valid_i),
        .private_head_start_ready_o(datapath_head_start_ready),
        .private_head_activation_exponent_i(
            private_head_activation_exponent_i),
        .private_head_activation_valid_i(private_head_activation_valid_i),
        .private_head_activation_ready_o(private_head_activation_ready_o),
        .private_head_activation_index_i(private_head_activation_index_i),
        .private_head_activation_mantissa_i(
            private_head_activation_mantissa_i),
        .private_head_activation_last_i(private_head_activation_last_i),
        .private_head_result_valid_o(private_head_result_valid_o),
        .private_head_result_ready_i(private_head_result_ready_i),
        .private_head_result_row_index_o(private_head_result_row_index_o),
        .private_head_result_scaled_raw_o(
            private_head_result_scaled_raw_o),
        .private_head_result_source_exponent_o(
            private_head_result_source_exponent_o),
        .private_head_result_last_o(private_head_result_last_o),
        .private_head_done_valid_o(private_head_done_valid_o),
        .private_head_done_ready_i(private_head_done_ready_i),
        .private_ingress_write_i(ingress_write),
        .private_ingress_index_i(input_index_i),
        .private_ingress_mantissa_i(input_mantissa_i),
        .private_stage_valid_i(stage_valid),
        .private_stage_ready_o(stage_ready), .private_stage_i(stage),
        .private_layer_i(layer), .private_position_i(position),
        .private_initial_exponent_i(initial_exponent),
        .private_stage_done_o(stage_done),
        .private_stage_fault_o(stage_fault),
        .private_result_index_i(private_result_index),
        .private_result_mantissa_o(private_result_mantissa),
        .private_result_exponent_o(private_result_exponent),
        .private_word_req_valid_o(private_word_req_valid_o),
        .private_word_req_ready_i(private_word_req_ready_i),
        .private_word_req_index_o(private_word_req_index_o),
        .private_word_rsp_valid_i(private_word_rsp_valid_i),
        .private_word_rsp_ready_o(private_word_rsp_ready_o),
        .private_word_rsp_data_i(private_word_rsp_data_i),
        .private_word_rsp_fault_i(private_word_rsp_fault_i),
        .kv_write_req_valid_o(kv_write_req_valid_o),
        .kv_write_req_ready_i(kv_write_req_ready_i),
        .kv_write_req_layer_o(kv_write_req_layer_o),
        .kv_write_req_position_o(kv_write_req_position_o),
        .kv_write_req_head_o(kv_write_req_head_o),
        .kv_write_req_row_word_o(kv_write_req_row_word_o),
        .kv_write_req_shadow_address_o(
            kv_write_req_shadow_address_o),
        .kv_write_req_data_o(kv_write_req_data_o),
        .kv_write_cpl_valid_i(kv_write_cpl_valid_i),
        .kv_write_cpl_ready_o(kv_write_cpl_ready_o),
        .kv_write_cpl_fault_i(kv_write_cpl_fault_i),
        .kv_read_req_valid_o(kv_read_req_valid_o),
        .kv_read_req_ready_i(kv_read_req_ready_i),
        .kv_read_req_layer_o(kv_read_req_layer_o),
        .kv_read_req_position_o(kv_read_req_position_o),
        .kv_read_req_head_o(kv_read_req_head_o),
        .kv_read_req_row_word_o(kv_read_req_row_word_o),
        .kv_read_req_shadow_address_o(kv_read_req_shadow_address_o),
        .kv_read_rsp_valid_i(kv_read_rsp_valid_i),
        .kv_read_rsp_ready_o(kv_read_rsp_ready_o),
        .kv_read_rsp_data_i(kv_read_rsp_data_i),
        .kv_read_rsp_fault_i(kv_read_rsp_fault_i),
        .kv_endpoint_fault_i(kv_endpoint_fault_i),
        .committed_prefixes_o(committed_prefixes),
        .busy_o(datapath_busy), .range_fault_o(datapath_fault)
    );

    always @* begin
        start_ready_o = sequence_start_ready && !datapath_busy &&
                        !private_head_start_valid_i &&
                        !service_start_collision;
        private_head_start_ready_o = datapath_head_start_ready &&
                                     !sequence_busy && !start_valid_i &&
                                     !service_start_collision;
        committed_prefixes_o = committed_prefixes;
        busy_o = sequence_busy || datapath_busy;
        range_fault_o = sequence_fault || datapath_fault || upstream_fault_i ||
                        service_start_collision_q;
    end

`ifdef FORMAL
    logic formal_past_valid;
    always_ff @(posedge clk) begin
        formal_past_valid <= 1'b1;
        if (rst_n) begin
            assert (!(start_valid_i && start_ready_o &&
                      private_head_start_valid_i &&
                      private_head_start_ready_o));
            if (service_start_collision) begin
                assert (!start_ready_o);
                assert (!private_head_start_ready_o);
            end
            if (start_valid_i && start_ready_o)
                assert (!private_head_start_valid_i && !datapath_busy);
            if (private_head_start_valid_i &&
                private_head_start_ready_o)
                assert (!start_valid_i && !sequence_busy);
            if (service_start_collision_q)
                assert (range_fault_o);
            assert (busy_o == (sequence_busy || datapath_busy));
            if (formal_past_valid &&
                $past(rst_n && service_start_collision))
                assert (service_start_collision_q);
            if (formal_past_valid &&
                $past(rst_n && service_start_collision_q))
                assert (service_start_collision_q);
        end
    end
`endif
endmodule

`default_nettype wire
