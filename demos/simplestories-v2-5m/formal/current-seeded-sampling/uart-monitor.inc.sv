    // Independent admitted-byte history. Actual CPB217 RX/TX are retained;
    // serial data, ready/results and settings feedback remain arbitrary.
    function automatic [7:0] f_crc_history(input [151:0] history, input [4:0] length);
        integer octet, bit_index;
        reg [7:0] remainder;
        reg feedback;
        begin
            remainder = 0;
            for (octet = 18; octet >= 0; octet = octet - 1)
                if (octet < length)
                    for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                        feedback = remainder[7] ^ history[octet*8+bit_index];
                        remainder = {remainder[6:0],1'b0};
                        if (feedback) remainder = remainder ^ 8'h07;
                    end
            f_crc_history = remainder;
        end
    endfunction
    function automatic [7:0] f_crc_octet(input [7:0] previous, input [7:0] octet);
        integer bit_index;
        reg [7:0] remainder;
        reg feedback;
        begin
            remainder = previous;
            for (bit_index = 7; bit_index >= 0; bit_index = bit_index - 1) begin
                feedback = remainder[7] ^ octet[bit_index];
                remainder = {remainder[6:0],1'b0};
                if (feedback) remainder = remainder ^ 8'h07;
            end
            f_crc_octet = remainder;
        end
    endfunction
    reg [151:0] f_history;
    reg [4:0] f_count, f_history_length;
    reg [7:0] f_opcode, f_low, f_high;
    reg [7:0] f_crc;
    reg [127:0] f_seed;
    reg [TIMEOUT_W-1:0] f_gap_count;
    wire f_owns_settings = f_opcode == 3 && f_count >= 2;
    wire f_admitted = rx_valid && (state_q == BRIDGE_IDLE ||
        (state_q == BRIDGE_WAIT_RESULT && !clear_pending_q && !out_valid_i) || f_owns_settings);
    wire f_timeout = f_owns_settings && !rx_valid &&
                     f_gap_count == TIMEOUT_W'(SETTINGS_TIMEOUT-1);
    wire f_legacy_complete = f_admitted && f_opcode != 3 && f_count == 4;
    wire f_settings_complete = f_admitted && f_opcode == 3 && f_count == 19;
    wire [7:0] f_checksum = f_crc;
    wire [11:0] f_operand = {f_high[3:0],f_low};
    wire f_malformed = rx_byte != f_checksum || f_high[7:4] != 0 || f_opcode > 2;
    wire f_bad_operand = f_opcode == 0 ? ({1'b0,f_operand} >= 13'd4019) : f_operand != 0;
    wire f_canonical = f_legacy_complete && !f_malformed && !f_bad_operand;
    wire f_new_command = state_q == BRIDGE_IDLE && f_canonical;
    wire f_new_clear = f_canonical && f_opcode == 2;
    wire f_new_settings = state_q == BRIDGE_IDLE && f_settings_complete &&
                          rx_byte == f_checksum && f_low <= 3;

    reg f_command_credit, f_clear_credit, f_step_owner, f_settings_credit;
    reg [1:0] f_command;
    reg [11:0] f_command_token;
    reg [2:0] f_settings_temperature;
    reg [127:0] f_settings_seed;
    reg f_reply_live;
    reg [7:0] f_reply_kind;
    reg [11:0] f_reply_token;
    reg [2:0] f_reply_index;
    reg f_reply_event;
    reg [7:0] f_new_reply_kind;
    reg [11:0] f_new_reply_token;
    wire [1:0] f_offered_command = recovery_clear_q ? 2'd2 : f_command;
    wire [31:0] f_reply_word = {8'h5a,f_reply_kind,f_reply_token[7:0],4'b0,f_reply_token[11:8]};
    wire [7:0] f_reply_checksum = f_crc_history({120'd0,f_reply_word},5'd4);
    wire [7:0] f_reply_byte = f_reply_index == 0 ? 8'h5a :
        f_reply_index == 1 ? f_reply_kind : f_reply_index == 2 ? f_reply_token[7:0] :
        f_reply_index == 3 ? {4'b0,f_reply_token[11:8]} : f_reply_checksum;

    always_comb begin
        f_reply_event = 0; f_new_reply_kind = 0; f_new_reply_token = 0;
        if (state_q == BRIDGE_IDLE && f_legacy_complete && !f_canonical) begin
            f_reply_event = 1;
            f_new_reply_kind = f_malformed ? 8'hcf : 8'hc0 | f_opcode;
        end
        if (state_q == BRIDGE_IDLE && f_settings_complete && !f_new_settings) begin
            f_reply_event = 1;
            f_new_reply_kind = rx_byte != f_checksum ? 8'hcf : 8'hc3;
        end
        if (state_q == BRIDGE_IDLE && f_timeout) begin
            f_reply_event = 1; f_new_reply_kind = 8'hcf;
        end
        if (state_q == BRIDGE_OFFER) begin
            if (cmd_ready_i && f_offered_command != 1) begin
                f_reply_event = 1; f_new_reply_kind = 8'h80 | {6'b0,f_offered_command};
            end else if (!cmd_ready_i && !recovery_clear_q) begin
                f_reply_event = 1; f_new_reply_kind = 8'hc0 | {6'b0,f_offered_command};
            end
        end
        if (state_q == BRIDGE_WAIT_RESULT) begin
            if (clear_pending_q && cmd_ready_i) begin
                f_reply_event = 1; f_new_reply_kind = 8'h82;
            end else if (out_valid_i) begin
                f_reply_event = 1; f_new_reply_kind = 8'h81; f_new_reply_token = out_token_i;
            end
        end
        if (state_q == BRIDGE_SETTINGS_OFFER && !settings_ready_i) begin
            f_reply_event = 1; f_new_reply_kind = 8'hc3;
        end
        if (state_q == BRIDGE_SETTINGS_WAIT) begin
            if (settings_accepted_i && !settings_rejected_i) begin
                f_reply_event = 1; f_new_reply_kind = 8'h83;
                f_new_reply_token = {9'd0,f_settings_temperature};
            end else if (settings_rejected_i || settings_wait_q) begin
                f_reply_event = 1; f_new_reply_kind = 8'hc3;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            f_history <= 0; f_count <= 0; f_history_length <= 0;
            f_opcode <= 0; f_low <= 0; f_high <= 0; f_seed <= 0; f_gap_count <= 0;
            f_crc <= 0;
            f_command_credit <= 0; f_command <= 0; f_command_token <= 0;
            f_clear_credit <= 0; f_step_owner <= 0; f_settings_credit <= 0;
            f_settings_temperature <= 0; f_settings_seed <= 0;
            f_reply_live <= 0; f_reply_kind <= 0; f_reply_token <= 0; f_reply_index <= 0;
        end else begin
            if (!f_owns_settings || rx_valid) f_gap_count <= 0;
            else if (f_gap_count < TIMEOUT_W'(SETTINGS_TIMEOUT-1)) f_gap_count <= f_gap_count + 1'b1;
            if (f_admitted) begin
                if (f_count == 0) begin
                    if (rx_byte == 8'ha5) begin
                        f_history <= 152'ha5; f_history_length <= 1; f_count <= 1;
                        f_crc <= f_crc_octet(0,rx_byte);
                    end
                end else if (f_legacy_complete || f_settings_complete) f_count <= 0;
                else begin
                    f_history <= {f_history[143:0],rx_byte};
                    f_crc <= f_crc_octet(f_crc,rx_byte);
                    f_history_length <= f_count + 1'b1;
                    f_count <= f_count + 1'b1;
                    if (f_count == 1) f_opcode <= rx_byte;
                    if (f_count == 2) f_low <= rx_byte;
                    if (f_count == 3 && f_opcode != 3) f_high <= rx_byte;
                    if (f_count >= 3 && f_opcode == 3)
                        f_seed[(f_count-3)*8+:8] <= rx_byte;
                end
            end
            if (f_timeout) begin f_count <= 0; f_gap_count <= 0; end
            if (f_new_command) begin
                f_command_credit <= 1; f_command <= f_opcode[1:0]; f_command_token <= f_operand;
            end
            if (state_q == BRIDGE_OFFER && !recovery_clear_q) f_command_credit <= 0;
            if (f_new_clear) f_clear_credit <= 1;
            if ((state_q == BRIDGE_OFFER && command_q == 2 && (cmd_ready_i || !recovery_clear_q)) ||
                (state_q == BRIDGE_WAIT_RESULT && clear_pending_q && cmd_ready_i)) f_clear_credit <= 0;
            if (cmd_valid_o && cmd_ready_i && cmd_o == 1) f_step_owner <= 1;
            if (state_q == BRIDGE_WAIT_RESULT && (out_valid_i || (clear_pending_q && cmd_ready_i))) f_step_owner <= 0;
            if (f_new_settings) begin
                f_settings_credit <= 1;
                f_settings_temperature <= f_low[2:0]; f_settings_seed <= f_seed;
            end
            if ((state_q == BRIDGE_SETTINGS_OFFER && !settings_ready_i) ||
                (state_q == BRIDGE_SETTINGS_WAIT && f_reply_event)) f_settings_credit <= 0;
            if (f_reply_event) begin
                f_reply_live <= 1; f_reply_kind <= f_new_reply_kind;
                f_reply_token <= f_new_reply_token; f_reply_index <= 0;
            end
            if (tx_valid && tx_ready) begin
                if (f_reply_index == 4) f_reply_live <= 0;
                else f_reply_index <= f_reply_index + 1'b1;
            end
        end
    end

    always_comb if (rst_n) begin
        assert(state_q <= BRIDGE_SETTINGS_WAIT);
        assert(request_index_q == f_count);
        assert(f_count <= 19);
        assert(f_history_length <= 19);
        assert(request_crc_q == f_checksum);
        assert(request_opcode_q == f_opcode);
        assert(request_token_low_q == f_low);
        assert(request_token_high_q == f_high);
        assert(request_seed_q == f_seed);
        assert(settings_timeout_q == f_gap_count);
        assert(settings_timed_out == f_timeout);
        assert(owns_settings_frame == f_owns_settings);
        if (f_count > 4) assert(f_opcode == 3);
        if (f_count != 0) assert(f_history_length == f_count);
        assert(response_index_q <= 4);
        assert(command_q <= 2 && cmd_o <= 2);
        if (state_q == BRIDGE_WAIT_RESULT) assert(command_q == 1);
        if (recovery_clear_q) assert(state_q == BRIDGE_OFFER && command_q == 2);
        if (clear_pending_q) assert(state_q != BRIDGE_IDLE);
        assert(clear_command_o == (cmd_valid_o && cmd_o == 2));
        if (cmd_valid_o) begin
            if (cmd_o == 0) assert({1'b0,in_token_o} < 4019);
            else assert(in_token_o == 0);
        end
        assert(f_command_credit == (state_q == BRIDGE_OFFER && !recovery_clear_q));
        if (f_command_credit) begin
            assert(command_q == f_command); assert(command_token_q == f_command_token);
        end
        assert(f_clear_credit == ((state_q == BRIDGE_OFFER && command_q == 2) || clear_pending_q));
        if (cmd_valid_o) assert((cmd_o == 2 && f_clear_credit) ||
            (f_command_credit && cmd_o == f_command && in_token_o == f_command_token));
        if (clear_command_o) assert(f_clear_credit);
        assert(f_step_owner == (state_q == BRIDGE_WAIT_RESULT));
        if (out_ready_o) assert(f_step_owner);
        assert(f_settings_credit == (state_q == BRIDGE_SETTINGS_OFFER || state_q == BRIDGE_SETTINGS_WAIT));
        assert(settings_valid_o == (state_q == BRIDGE_SETTINGS_OFFER));
        if (f_settings_credit) begin
            assert(settings_temperature_o == f_settings_temperature);
            assert(settings_seed_o == f_settings_seed);
            assert(settings_temperature_o <= 3);
        end
        if (settings_valid_o) assert(!cmd_valid_o && !clear_command_o);
        assert(f_reply_live == tx_valid);
        assert(f_reply_index <= 4);
        assert(!f_reply_event || !f_reply_live);
        if (f_reply_live) begin
            assert(f_reply_index == response_index_q);
            assert(f_reply_kind == response_kind_q);
            assert(f_reply_token == response_token_q);
            assert(tx_byte == f_reply_byte);
            if (f_reply_index != 0) assert(response_crc_q == f_reply_checksum);
            assert(f_reply_kind == 8'h80 || f_reply_kind == 8'h81 || f_reply_kind == 8'h82 ||
                   f_reply_kind == 8'h83 || f_reply_kind == 8'hc0 || f_reply_kind == 8'hc1 ||
                   f_reply_kind == 8'hc2 || f_reply_kind == 8'hc3 || f_reply_kind == 8'hcf);
            if (f_reply_kind != 8'h81 && f_reply_kind != 8'h83) assert(f_reply_token == 0);
            if (f_reply_kind == 8'h83) assert(f_reply_token <= 3);
        end
    end
