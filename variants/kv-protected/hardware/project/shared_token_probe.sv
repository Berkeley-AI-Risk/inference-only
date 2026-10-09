`timescale 1ns/1ps
`default_nettype none

// Connected context-2,048 logical product boundary.  The application-facing
// surface remains APPEND(token), STEP, and CLEAR.  The endpoint ports are a
// physical integration seam that must terminate inside the later sealed
// product wrapper; they are not host pins or commands.
module board1_context2048_shared_token_probe #(parameter integer AUTH_BANKS=8) (
    input  wire         core_clk_i,
    input  wire         app_clk_i,
    input  wire         reset_n_i,
    input  wire         clear_i,

    input  wire         append_valid_i,
    output wire         append_ready_o,
    input  wire [11:0]  append_token_i,
    input  wire         step_valid_i,
    output wire         step_ready_o,
    output wire         token_valid_o,
    input  wire         token_ready_i,
    output wire [11:0]  token_o,
    output wire         busy_o,
    output wire         model_locked_o,
    output wire         fail_closed_o,

    input  wire         private_model_locked_i,
    input  wire         private_endpoint_upstream_fault_i,
    output wire         private_endpoint_req_valid_o,
    input  wire         private_endpoint_req_ready_i,
    output wire [18:0]  private_endpoint_req_word_address_o,
    output wire         private_endpoint_req_write_o,
    output wire [255:0] private_endpoint_req_write_data_o,
    input  wire         private_endpoint_rsp_valid_i,
    output wire         private_endpoint_rsp_ready_o,
    input  wire [255:0] private_endpoint_rsp_data_i,
    input  wire         private_endpoint_rsp_error_i
);
    // Source-bound integration into the actual six-layer token machine.
    // These wires are PRIVATE, behind the APPEND/STEP/CLEAR shell.
    wire private_raw_req_valid_o,private_raw_req_ready_i;
    wire [18:0] private_raw_req_word_o;
    wire private_raw_rsp_valid_i,private_raw_rsp_error_i;
    wire [255:0] private_raw_rsp_data_i;
    wire model_app_req_valid,model_app_req_ready,model_app_rsp_valid,model_app_rsp_error;
    wire [18:0] model_app_req_word;
    wire [255:0] model_app_rsp_data;
    wire model_cdc_core_fault,model_cdc_app_fault,shared_app_fault;
    wire private_kv_req_valid_o,private_kv_req_ready_i,private_kv_req_write_o;
    wire [18:0] private_kv_req_word_address_o;
    wire [255:0] private_kv_req_write_data_o;
    wire private_kv_rsp_valid_i,private_kv_rsp_ready_o,private_kv_rsp_error_i;
    wire [255:0] private_kv_rsp_data_i;
    wire [24:0] shared_raw_word;
    wire shared_kv_req_ready,shared_kv_rsp_valid,shared_kv_rsp_ready;
    logic kv_write_pending_q;
    // reset_n_i is released synchronously to core_clk_i by the parent.
    // The app-side transport shares its asynchronous assertion but owns a
    // separate synchronized release. Neither domain resets on public CLEAR.
    (* async_reg="true",syn_preserve=1 *) logic [2:0] app_runtime_release_q;
    always_ff @(posedge app_clk_i or negedge reset_n_i) begin
        if(!reset_n_i) app_runtime_release_q<=0;
        else app_runtime_release_q<={app_runtime_release_q[1:0],1'b1};
    end
    wire app_runtime_reset_n=app_runtime_release_q[2];

    // The existing typed endpoint retires a WRITE on its request handshake
    // and expects response_valid only for READs. Capture a write into the
    // arbiter once, but do not acknowledge it to that endpoint until the
    // arbiter's completion certifies raw command+data acceptance. This state
    // does not reset on CLEAR, so already offered writes retain drain ownership.
    assign private_kv_req_ready_i=private_kv_req_write_o ?
        (kv_write_pending_q && shared_kv_rsp_valid) : shared_kv_req_ready;
    assign private_kv_rsp_valid_i=shared_kv_rsp_valid && !kv_write_pending_q;
    assign shared_kv_rsp_ready=kv_write_pending_q || private_kv_rsp_ready_o;
    always_ff @(posedge app_clk_i or negedge app_runtime_reset_n) begin
        if(!app_runtime_reset_n) kv_write_pending_q<=0;
        else if(kv_write_pending_q && shared_kv_rsp_valid) kv_write_pending_q<=0;
        else if(private_kv_req_valid_o && shared_kv_req_ready && private_kv_req_write_o)
            kv_write_pending_q<=1;
    end

    board1_private_model_ddr_cdc u_model_cdc (
        .core_clk_i(core_clk_i),.core_reset_n_i(reset_n_i),.core_upstream_fault_i(core_fault_to_boundary_q),
        .core_req_valid_i(private_raw_req_valid_o),.core_req_ready_o(private_raw_req_ready_i),
        .core_req_word_i(private_raw_req_word_o),.core_rsp_valid_o(private_raw_rsp_valid_i),
        .core_rsp_data_o(private_raw_rsp_data_i),.core_rsp_error_o(private_raw_rsp_error_i),
        .core_fault_o(model_cdc_core_fault),.app_clk_i(app_clk_i),.app_reset_n_i(app_runtime_reset_n),
        .app_upstream_fault_i(private_endpoint_upstream_fault_i || shared_app_fault),
        .app_req_valid_o(model_app_req_valid),.app_req_ready_i(model_app_req_ready),
        .app_req_word_o(model_app_req_word),.app_rsp_valid_i(model_app_rsp_valid),
        .app_rsp_data_i(model_app_rsp_data),.app_rsp_error_i(model_app_rsp_error),.app_fault_o(model_cdc_app_fault));
    board1_private_shared_ddr_transaction_boundary u_shared (
        .clk(app_clk_i),.reset_n(app_runtime_reset_n),.model_locked_i(private_model_locked_i),
        .upstream_fault_i(private_endpoint_upstream_fault_i || model_cdc_app_fault),
        .model_req_valid_i(model_app_req_valid),.model_req_ready_o(model_app_req_ready),
        .model_req_word_i(model_app_req_word),.model_rsp_valid_o(model_app_rsp_valid),
        .model_rsp_data_o(model_app_rsp_data),.model_rsp_error_o(model_app_rsp_error),
        .kv_req_valid_i(private_kv_req_valid_o && !kv_write_pending_q),.kv_req_ready_o(shared_kv_req_ready),
        .kv_req_word_i(private_kv_req_word_address_o),.kv_req_write_i(private_kv_req_write_o),
        .kv_req_data_i(private_kv_req_write_data_o),.kv_rsp_valid_o(shared_kv_rsp_valid),
        .kv_rsp_ready_i(shared_kv_rsp_ready),.kv_rsp_data_o(private_kv_rsp_data_i),
        .kv_rsp_error_o(private_kv_rsp_error_i),.raw_req_valid_o(private_endpoint_req_valid_o),
        .raw_req_ready_i(private_endpoint_req_ready_i),.raw_req_word_o(shared_raw_word),
        .raw_req_write_o(private_endpoint_req_write_o),.raw_req_data_o(private_endpoint_req_write_data_o),
        .raw_rsp_valid_i(private_endpoint_rsp_valid_i),.raw_rsp_data_i(private_endpoint_rsp_data_i),
        .raw_rsp_error_i(private_endpoint_rsp_error_i),.busy_o(),.fault_o(shared_app_fault));
    assign private_endpoint_req_word_address_o=shared_raw_word[18:0];
    // The raw adapter has no return backpressure; reservations guarantee room.
    assign private_endpoint_rsp_ready_o=1'b1;

    (* async_reg = "true", syn_preserve = 1 *)
    logic model_lock_core_meta_q;
    (* async_reg = "true", syn_preserve = 1 *)
    logic model_lock_core_sync_q;
    logic core_fault_to_boundary_q;

    wire model_req_valid;
    wire model_req_ready;
    wire [18:0] model_req_word;
    wire model_rsp_valid;
    wire model_rsp_ready;
    wire [255:0] model_rsp_data;
    wire model_rsp_fault;

    wire kv_write_req_valid;
    wire kv_write_req_ready;
    wire [2:0] kv_write_req_layer;
    wire [11:0] kv_write_req_position;
    wire [1:0] kv_write_req_head;
    wire [3:0] kv_write_req_row_word;
    wire [18:0] kv_write_req_shadow_address;
    wire [255:0] kv_write_req_data;
    wire kv_write_cpl_valid;
    wire kv_write_cpl_ready;
    wire kv_write_cpl_fault;

    wire kv_read_req_valid;
    wire kv_read_req_ready;
    wire [2:0] kv_read_req_layer;
    wire [11:0] kv_read_req_position;
    wire [1:0] kv_read_req_head;
    wire [3:0] kv_read_req_row_word;
    wire [18:0] kv_read_req_shadow_address;
    wire kv_read_rsp_valid;
    wire kv_read_rsp_ready;
    wire [255:0] kv_read_rsp_data;
    wire kv_read_rsp_fault;


    // Private integrity seam: parent semantic ownership stays unchanged.
    wire kv_integrity_fault;
    wire guard_wr_valid,guard_wr_ready,guard_wr_cpl_valid,guard_wr_cpl_ready,guard_wr_cpl_fault;
    wire guard_rd_valid,guard_rd_ready,guard_rd_rsp_valid,guard_rd_rsp_ready,guard_rd_rsp_fault;
    wire [2:0] guard_wr_layer,guard_rd_layer;
    wire [11:0] guard_wr_position,guard_rd_position;
    wire [1:0] guard_wr_head,guard_rd_head;
    wire [3:0] guard_wr_word,guard_rd_word;
    wire [18:0] guard_wr_shadow,guard_rd_shadow;
    wire [255:0] guard_wr_data,guard_rd_data;

    wire core_machine_busy;
    wire core_machine_locked;
    wire core_machine_fault;
    wire boundary_core_clear_pending;
    wire boundary_core_clear_drained;
    wire boundary_core_busy;
    wire boundary_core_fault;
    wire boundary_app_busy;
    wire boundary_app_fault;

    always_ff @(posedge core_clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            model_lock_core_meta_q <= 1'b0;
            model_lock_core_sync_q <= 1'b0;
            core_fault_to_boundary_q <= 1'b0;
        end else begin
            model_lock_core_meta_q <= private_model_locked_i;
            model_lock_core_sync_q <= model_lock_core_meta_q;
            if (core_machine_fault || auth_fault || model_cdc_core_fault || kv_integrity_fault)
                core_fault_to_boundary_q <= 1'b1;
        end
    end

    // Actual sealed-page service. Its raw reads now cross to the common
    // app-domain arbiter shared with the typed K/V boundary.
    wire auth_fault;
    board1_verified_ddr_page_service #(.BANKS(AUTH_BANKS),.ADDR_W(19)) u_auth (
        // Public CLEAR stops child work and revokes tape/KV validity.
        // Already accepted model reads remain owned by the fixed
        // arbiter and drain through its children; never erase their
        // queued responses here. Fixed verified weight copies may
        // survive CLEAR. Reset and all authentication faults retain
        // their original behavior. No new operation is exposed.
        .clk(core_clk_i),.reset_n(reset_n_i),.cancel_i(1'b0),
        .model_locked_i(model_lock_core_sync_q),
        .request_valid_i(model_req_valid),.request_ready_o(model_req_ready),
        .request_word_i(model_req_word),.response_valid_o(model_rsp_valid),
        .response_ready_i(model_rsp_ready),.response_data_o(model_rsp_data),
        .ddr_request_valid_o(private_raw_req_valid_o),
        .ddr_request_ready_i(private_raw_req_ready_i),
        .ddr_request_word_o(private_raw_req_word_o),
        .ddr_response_valid_i(private_raw_rsp_valid_i),
        .ddr_response_data_i(private_raw_rsp_data_i),
        .ddr_response_error_i(private_raw_rsp_error_i),.fault_o(auth_fault));
    assign model_rsp_fault=auth_fault;

    board1_context2048_token_machine_core #(
        .ADDR_W(19), .MODEL_WORDS(227062)
    ) u_machine (
        .clk(core_clk_i), .reset_n(reset_n_i), .clear_i(clear_i),
        .model_locked_i(model_lock_core_sync_q),
        .upstream_fail_closed_i(boundary_core_fault || auth_fault || model_cdc_core_fault || kv_integrity_fault),
        .append_valid_i(append_valid_i), .append_ready_o(append_ready_o),
        .append_token_i(append_token_i),
        .step_valid_i(step_valid_i), .step_ready_o(step_ready_o),
        .token_valid_o(token_valid_o), .token_ready_i(token_ready_i),
        .token_o(token_o),
        .private_runtime_req_valid_o(model_req_valid),
        .private_runtime_req_ready_i(model_req_ready),
        .private_runtime_req_word_index_o(model_req_word),
        .private_runtime_rsp_valid_i(model_rsp_valid),
        .private_runtime_rsp_ready_o(model_rsp_ready),
        .private_runtime_rsp_data_i(model_rsp_data),
        .private_runtime_rsp_fault_i(model_rsp_fault),
        .kv_write_req_valid_o(kv_write_req_valid),
        .kv_write_req_ready_i(kv_write_req_ready),
        .kv_write_req_layer_o(kv_write_req_layer),
        .kv_write_req_position_o(kv_write_req_position),
        .kv_write_req_head_o(kv_write_req_head),
        .kv_write_req_row_word_o(kv_write_req_row_word),
        .kv_write_req_shadow_address_o(kv_write_req_shadow_address),
        .kv_write_req_data_o(kv_write_req_data),
        .kv_write_cpl_valid_i(kv_write_cpl_valid),
        .kv_write_cpl_ready_o(kv_write_cpl_ready),
        .kv_write_cpl_fault_i(kv_write_cpl_fault),
        .kv_read_req_valid_o(kv_read_req_valid),
        .kv_read_req_ready_i(kv_read_req_ready),
        .kv_read_req_layer_o(kv_read_req_layer),
        .kv_read_req_position_o(kv_read_req_position),
        .kv_read_req_head_o(kv_read_req_head),
        .kv_read_req_row_word_o(kv_read_req_row_word),
        .kv_read_req_shadow_address_o(kv_read_req_shadow_address),
        .kv_read_rsp_valid_i(kv_read_rsp_valid),
        .kv_read_rsp_ready_o(kv_read_rsp_ready),
        .kv_read_rsp_data_i(kv_read_rsp_data),
        .kv_read_rsp_fault_i(kv_read_rsp_fault),
        .kv_endpoint_fault_i(boundary_core_fault || kv_integrity_fault),
        .busy_o(core_machine_busy),
        .model_locked_o(core_machine_locked),
        .fail_closed_o(core_machine_fault)
    );


    board1_kv_integrity_guard u_kv_integrity (
        .clk(core_clk_i),.reset_n(reset_n_i),.clear_i(clear_i),
        .model_locked_i(model_lock_core_sync_q),
        .upstream_fault_i(boundary_core_fault || core_fault_to_boundary_q),
        .s_wr_valid(kv_write_req_valid),.s_wr_ready(kv_write_req_ready),
        .s_wr_layer(kv_write_req_layer),.s_wr_position(kv_write_req_position),
        .s_wr_head(kv_write_req_head),.s_wr_word(kv_write_req_row_word),
        .s_wr_shadow(kv_write_req_shadow_address),.s_wr_data(kv_write_req_data),
        .s_wr_cpl_valid(kv_write_cpl_valid),.s_wr_cpl_ready(kv_write_cpl_ready),.s_wr_cpl_fault(kv_write_cpl_fault),
        .s_rd_valid(kv_read_req_valid),.s_rd_ready(kv_read_req_ready),
        .s_rd_layer(kv_read_req_layer),.s_rd_position(kv_read_req_position),
        .s_rd_head(kv_read_req_head),.s_rd_word(kv_read_req_row_word),.s_rd_shadow(kv_read_req_shadow_address),
        .s_rd_rsp_valid(kv_read_rsp_valid),.s_rd_rsp_ready(kv_read_rsp_ready),
        .s_rd_rsp_data(kv_read_rsp_data),.s_rd_rsp_fault(kv_read_rsp_fault),
        .m_wr_valid(guard_wr_valid),.m_wr_ready(guard_wr_ready),
        .m_wr_layer(guard_wr_layer),.m_wr_position(guard_wr_position),.m_wr_head(guard_wr_head),
        .m_wr_word(guard_wr_word),.m_wr_shadow(guard_wr_shadow),.m_wr_data(guard_wr_data),
        .m_wr_cpl_valid(guard_wr_cpl_valid),.m_wr_cpl_ready(guard_wr_cpl_ready),.m_wr_cpl_fault(guard_wr_cpl_fault),
        .m_rd_valid(guard_rd_valid),.m_rd_ready(guard_rd_ready),
        .m_rd_layer(guard_rd_layer),.m_rd_position(guard_rd_position),.m_rd_head(guard_rd_head),
        .m_rd_word(guard_rd_word),.m_rd_shadow(guard_rd_shadow),
        .m_rd_rsp_valid(guard_rd_rsp_valid),.m_rd_rsp_ready(guard_rd_rsp_ready),
        .m_rd_rsp_data(guard_rd_data),.m_rd_rsp_fault(guard_rd_rsp_fault),.fault_o(kv_integrity_fault));

    board1_context2048_typed_ddr_boundary #(.FIFO_ADDR_BITS(2)) u_boundary (
        .core_clk_i(core_clk_i), .core_reset_n_i(reset_n_i),
        .core_clear_i(clear_i),
        // Registering this feedback avoids a combinational fault loop while
        // still terminally closing the boundary one core clock later.
        .core_upstream_fault_i(core_fault_to_boundary_q),
        .model_req_valid_i(1'b0),
        .model_req_ready_o(),
        .model_req_word_i(19'd0),
        .model_rsp_valid_o(),
        .model_rsp_ready_i(1'b1),
        .model_rsp_data_o(),
        .model_rsp_fault_o(),
        .kv_write_req_valid_i(guard_wr_valid),
        .kv_write_req_ready_o(guard_wr_ready),
        .kv_write_req_layer_i(guard_wr_layer),
        .kv_write_req_position_i(guard_wr_position),
        .kv_write_req_head_i(guard_wr_head),
        .kv_write_req_row_word_i(guard_wr_word),
        .kv_write_req_shadow_address_i(guard_wr_shadow),
        .kv_write_req_data_i(guard_wr_data),
        .kv_write_cpl_valid_o(guard_wr_cpl_valid),
        .kv_write_cpl_ready_i(guard_wr_cpl_ready),
        .kv_write_cpl_fault_o(guard_wr_cpl_fault),
        .kv_read_req_valid_i(guard_rd_valid),
        .kv_read_req_ready_o(guard_rd_ready),
        .kv_read_req_layer_i(guard_rd_layer),
        .kv_read_req_position_i(guard_rd_position),
        .kv_read_req_head_i(guard_rd_head),
        .kv_read_req_row_word_i(guard_rd_word),
        .kv_read_req_shadow_address_i(guard_rd_shadow),
        .kv_read_rsp_valid_o(guard_rd_rsp_valid),
        .kv_read_rsp_ready_i(guard_rd_rsp_ready),
        .kv_read_rsp_data_o(guard_rd_data),
        .kv_read_rsp_fault_o(guard_rd_rsp_fault),
        .core_clear_pending_o(boundary_core_clear_pending),
        .core_clear_drained_o(boundary_core_clear_drained),
        .core_busy_o(boundary_core_busy),
        .core_fail_closed_o(boundary_core_fault),
        .app_clk_i(app_clk_i), .app_reset_n_i(app_runtime_reset_n),
        .app_model_locked_i(private_model_locked_i),
        .app_upstream_fault_i(private_endpoint_upstream_fault_i || shared_app_fault || model_cdc_app_fault),
        .endpoint_req_valid_o(private_kv_req_valid_o),
        .endpoint_req_ready_i(private_kv_req_ready_i),
        .endpoint_req_word_address_o(private_kv_req_word_address_o),
        .endpoint_req_write_o(private_kv_req_write_o),
        .endpoint_req_write_data_o(private_kv_req_write_data_o),
        .endpoint_rsp_valid_i(private_kv_rsp_valid_i),
        .endpoint_rsp_ready_o(private_kv_rsp_ready_o),
        .endpoint_rsp_data_i(private_kv_rsp_data_i),
        .endpoint_rsp_error_i(private_kv_rsp_error_i),
        .app_busy_o(boundary_app_busy),
        .app_fail_closed_o(boundary_app_fault)
    );

    // Every public status is expressed entirely in the core clock domain.
    // The boundary synchronizes app-side failures into boundary_core_fault;
    // sampling its app-domain status signals here would otherwise introduce
    // an unnecessary CDC path on the public interface.
    assign busy_o = core_machine_busy || boundary_core_busy ||
                    boundary_core_clear_pending;
    assign model_locked_o = core_machine_locked &&
                            model_lock_core_sync_q &&
                            !boundary_core_fault && !model_cdc_core_fault && !kv_integrity_fault;
    assign fail_closed_o = core_machine_fault || boundary_core_fault || model_cdc_core_fault || kv_integrity_fault;

`ifdef FORMAL
    always_ff @(posedge core_clk_i) begin
        if (reset_n_i) begin
            assert (!(append_ready_o && step_ready_o));
            if (!model_locked_o)
                assert (!append_ready_o && !step_ready_o && !token_valid_o);
            if (model_req_valid)
                assert (model_req_word < 19'd227062);
            if (kv_write_req_valid)
                assert (kv_write_req_shadow_address >= 19'd227072 &&
                        kv_write_req_shadow_address < 19'd448256);
            if (kv_read_req_valid)
                assert (kv_read_req_shadow_address >= 19'd227072 &&
                        kv_read_req_shadow_address < 19'd448256);
        end
    end
`endif

    wire _unused_boundary_status = boundary_core_clear_drained ^
                                   boundary_app_busy ^ boundary_app_fault;
endmodule

`default_nettype wire
