    // Healthy around trajectory over the production UART, with the original
    // protected core, model loader, auth/decrypt, and ordered DDR fixture.
    localparam int UART_CLKS = 217;
    wire different_model = 1'b0;
    int uart_commands = 0;
    int wire_frames = 0;
    int wire_byte_index = 0;
    logic [7:0] wire_frame [0:4];

    always @(posedge core_clk_i) begin
        if (reset_n_i) begin
            if (u_uart.cmd_valid && u_uart.cmd_ready) begin
                uart_commands <= uart_commands + 1;
                $display("UART_CMD %0d %0d %0d %0d", core_cycle_q,
                         uart_commands + 1, u_uart.cmd, u_uart.command_token);
            end
            if (u_uart.clear)
                $display("UART_CLEAR_CORE %0d %0d", core_cycle_q, uart_commands + 1);
            if (token_valid_o && token_ready_i)
                $display("UART_TOKEN %0d %0d %0d", core_cycle_q, uart_commands, token_o);
            if (u_uart.result_valid && u_uart.result_ready)
                $display("UART_RESULT %0d %0d %0d", core_cycle_q, uart_commands, u_uart.result_token);
            if (u_uart.u_fixed_uart.tx_valid && u_uart.u_fixed_uart.tx_ready) begin
                if (u_uart.u_fixed_uart.response_index_q == 0)
                    $display("UART_TX_COMMIT %0d %0d %0d %0d", core_cycle_q, uart_commands,
                             u_uart.u_fixed_uart.response_kind_q, u_uart.u_fixed_uart.response_token_q);
                $display("UART_TX_BYTE %0d %0d %0d %0d", core_cycle_q, uart_commands,
                         u_uart.u_fixed_uart.response_index_q, u_uart.u_fixed_uart.tx_byte);
            end
        end
    end

    // A passive 8N1 mid-bit sampler of the external pin. It uses neither
    // the production receiver nor the transmit-byte bus to recover bytes.
    always begin : sample_uart_pin
        logic [7:0] sampled;
        @(negedge uart_tx);
        if (reset_n_i) begin
            sampled = '0;
            repeat (UART_CLKS/2) @(negedge core_clk_i);
            for (int symbol=0; symbol<10; symbol++) begin
                if (symbol != 0)
                    repeat (UART_CLKS) @(negedge core_clk_i);
                $display("UART_PIN %0d %0d %0d %0d %0d", core_cycle_q,
                         wire_frames + 1, wire_byte_index, symbol, uart_tx);
                if (symbol >= 1 && symbol <= 8)
                    sampled[symbol-1] = uart_tx;
                if ((symbol == 0 && uart_tx !== 1'b0) ||
                    (symbol == 9 && uart_tx !== 1'b1))
                    $fatal(1,"Wire sampler found bad UART framing");
            end
            wire_frame[wire_byte_index] = sampled;
            if (wire_byte_index == 4) begin
                wire_frames = wire_frames + 1;
                wire_byte_index = 0;
            end else begin
                wire_byte_index = wire_byte_index + 1;
            end
        end
    end

    function automatic logic [7:0] uart_crc(input logic [7:0] crc, input logic [7:0] byte_value);
        logic [7:0] c;
        c = crc ^ byte_value;
        repeat (8) c = {c[6:0], 1'b0} ^ (c[7] ? 8'h07 : 8'h00);
        return c;
    endfunction

    task automatic uart_send_byte(input logic [7:0] data);
        uart_rx = 0;
        repeat (UART_CLKS) @(negedge core_clk_i);
        for (int i=0; i<8; i++) begin
            uart_rx = data[i];
            repeat (UART_CLKS) @(negedge core_clk_i);
        end
        uart_rx = 1;
        repeat (UART_CLKS) @(negedge core_clk_i);
    endtask

    task automatic uart_exchange(input logic [7:0] op, input logic [11:0] command_token,
                                 input logic [11:0] expected_payload);
        int old_frames, old_commands;
        logic [7:0] lo, hi, crc;
        old_frames = wire_frames;
        old_commands = uart_commands;
        lo = command_token[7:0];
        hi = {4'd0, command_token[11:8]};
        crc = uart_crc(uart_crc(uart_crc(uart_crc(0, 8'ha5), op), lo), hi);
        @(negedge core_clk_i);
        uart_send_byte(8'ha5);
        uart_send_byte(op);
        uart_send_byte(lo);
        uart_send_byte(hi);
        uart_send_byte(crc);
        while (wire_frames == old_frames && !fail_closed_o) @(posedge core_clk_i);
        if (fail_closed_o || uart_commands != old_commands + 1 || wire_frames != old_frames + 1 ||
                wire_frame[0] !== 8'h5a || wire_frame[1] !== (8'h80 | op) ||
                {wire_frame[3], wire_frame[2]} !== {4'd0, expected_payload})
            $fatal(1,"Missing or mismatched ordinary UART response");
        repeat (2*UART_CLKS) @(negedge core_clk_i);
    endtask

    initial begin : preserved_around
        if (AUTH_BANKS != 4 || !$test$plusargs("ZERO_STALL"))
            $fatal(1,"Use the four-bank historical zero-stall fixture");
        zero_stall = 1;
        if (!$value$plusargs("IMAGE_MEMH=%s", image_memh_path) ||
            !$value$plusargs("CIPHER_MEMH=%s", cipher_memh_path))
            $fatal(1,"Missing fixed model inputs");
        $readmemh(image_memh_path,semantic_image);
        $readmemh(cipher_memh_path,ciphertext_image);
        repeat (8) @(posedge app_clk_i);
        @(negedge app_clk_i); reset_n_i = 1;
        repeat (8) @(negedge core_clk_i);
        if (append_ready_o || step_ready_o || token_valid_o || model_locked_o || fail_closed_o)
            $fatal(1,"Public machine opened before boot");
        while (!model_locked_o && !fail_closed_o) @(negedge core_clk_i);
        if (fail_closed_o || !u_memory.u_boot.digest_success_app || u_memory.u_handoff.pending_q!=0 ||
            loader_words_q!=IMAGE_WORDS || boot_writes_q!=IMAGE_WORDS ||
            boot_reads_q!=IMAGE_WORDS || boot_returns_q!=IMAGE_WORDS)
            $fatal(1,"Original full-image readback and drained authentication did not complete");
        $display("BOOT_AUTHENTICATED words=%0d core_cycles=%0d app_cycles=%0d real_sha=1 handoff_drained=1",
                 boot_returns_q,core_cycle_q,app_cycle_q);
        uart_exchange(0, 12'd378, 0);
        uart_exchange(1, 0, 12'd200);
        uart_exchange(1, 0, 12'd15);
        uart_exchange(1, 0, 12'd103);
        uart_exchange(1, 0, 12'd157);
        uart_exchange(2, 0, 0);
        while (!append_ready_o && !fail_closed_o) @(negedge core_clk_i);
        if (fail_closed_o || u_uart.u_machine.u_machine.u_token_shell.tape_count_q!=0 ||
            u_uart.u_machine.u_machine.layer_committed_prefixes!=0)
            $fatal(1,"CLEAR did not revoke all tape and cache ownership");
        $display("UART_CLEAR_READY %0d %0d", core_cycle_q, uart_commands);
        uart_exchange(0, 12'd378, 0);
        uart_exchange(1, 0, 12'd200);
        uart_exchange(1, 0, 12'd15);
        while (thin_accepted!=thin_issued || u_transport.reserved_q!=0 || raw_count_q!=0 ||
               u_uart.u_machine.u_model_cdc.reserved_q!=0 || u_uart.u_machine.u_shared.busy_o ||
               u_uart.u_machine.u_auth.dma_state_q!=0)
            @(negedge core_clk_i);
        check_kv_oracle_done();
        if (wire_frames!=9 || uart_commands!=9 || wire_byte_index!=0 || fail_closed_o ||
            model_requests_q!=model_responses_q || raw_requests_q!=raw_returns_q || expected_count_q!=0 ||
            u_uart.u_machine.u_machine.u_token_shell.tape_count_q!=3 ||
            u_uart.u_machine.u_machine.layer_committed_prefixes!=={6{12'd2}})
            $fatal(1,"Incomplete ordinary UART campaign or incomplete retirement");
        $display("PASS_C070_UART boot_words=%0d frames=%0d primary_tokens=4 replay_tokens=2",
                 boot_returns_q, wire_frames);
        $finish;
    end
