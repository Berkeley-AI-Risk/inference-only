    // Only read-only exported observer state is used below. No observer
    // signal feeds any native controller, FIFO or adapter decision.
    wire [1:0] f_queue_count = f_observe_queue[43:42];
    wire f_queue_write_ptr = f_observe_queue[41];
    wire f_queue_read_ptr = f_observe_queue[40];
    wire [18:0] f_head_address = f_queue_read_ptr ? f_observe_queue[39:21] : f_observe_queue[19:1];
    wire [18:0] f_tail_address = f_queue_read_ptr ? f_observe_queue[19:1] : f_observe_queue[39:21];
    wire f_head_write = f_queue_read_ptr ? f_observe_queue[20] : f_observe_queue[0];
    wire f_tail_write = f_queue_read_ptr ? f_observe_queue[0] : f_observe_queue[20];
    wire f_head_model_write = f_head_write && f_head_address < 19'd227062;
    wire f_tail_model_write = f_tail_write && f_tail_address < 19'd227062;
    wire f_head_scratch = f_head_address >= 19'd227072 && f_head_address < 19'd448256;
    wire f_tail_scratch = f_tail_address >= 19'd227072 && f_tail_address < 19'd448256;
    logic f_boundary_read_seen_q;
    always_ff @(posedge app_clk_i or negedge app_reset_n_i) begin
        if (!app_reset_n_i) f_boundary_read_seen_q <= 0;
        else if (app_cmd_en_o && app_cmd_o == 1) f_boundary_read_seen_q <= 1;
    end
    always_comb if (app_reset_n_i) begin
        assert(f_queue_count <= 2);
        assert((f_queue_count == 1) == (f_queue_write_ptr != f_queue_read_ptr));
        if (f_queue_count != 0) assert(!f_head_write || f_head_model_write || f_head_scratch);
        if (f_queue_count == 2) assert(!f_tail_write || f_tail_model_write || f_tail_scratch);
        if (f_observe_reads == 0) begin
            if (f_queue_count != 0) assert(f_head_model_write);
            if (f_queue_count == 2) assert(f_tail_model_write);
        end
        if (f_observe_reads == 1) begin
            if (f_queue_count == 1) assert(!f_head_model_write);
            if (f_queue_count == 2) assert(!f_tail_model_write);
        end
        if (f_observe_reads >= 2) begin
            if (f_queue_count != 0) assert(!f_head_model_write);
            if (f_queue_count == 2) assert(!f_tail_model_write);
        end
        if (f_boundary_read_seen_q) begin
            assert(f_observe_reads != 0);
            if (f_queue_count != 0) assert(!f_head_model_write);
            if (f_queue_count == 2) assert(!f_tail_model_write);
        end
        // The adapter may speculatively count a command suppressed by a
        // simultaneous malformed return. Its sticky fault then owns that
        // state; an error-free owned return still needs an actual read.
        if (f_observe_adapter_owned && !adapter_protocol_fault)
            assert(f_boundary_read_seen_q);
        if (f_observe_final_return) assert(f_boundary_read_seen_q);
        if (app_cmd_en_o) begin
            assert(f_queue_count != 0);
            assert(app_cmd_o == (f_head_write ? 3'd0 : 3'd1));
            assert(app_addr_o == {7'd0,f_head_address,3'd0});
        end
        // Main ordering obligation, at the real boundary's output.
        if (f_boundary_read_seen_q && app_cmd_en_o && app_cmd_o == 0)
            assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd448256);
        if (model_locked_o) begin
            assert(f_boundary_read_seen_q);
            assert(f_observe_reads == 19'd227062);
            if (f_queue_count != 0) assert(!f_head_model_write);
            if (f_queue_count == 2) assert(!f_tail_model_write);
            if (app_cmd_en_o && app_cmd_o == 0)
                assert(app_addr_o[21:3] >= 19'd227072 && app_addr_o[21:3] < 19'd448256);
        end
        if (fail_closed_o) assert(!app_cmd_en_o && !app_wr_data_en_o);
        cover(app_cmd_en_o && app_cmd_o == 0 && app_wr_data_en_o);
    end
