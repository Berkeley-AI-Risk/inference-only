`timescale 1ns/1ps
`default_nettype none

// One-round-per-cycle SHA-256 compressor with a 16-word fixed-tap sliding
// schedule.  The live schedule always represents w[t]..w[t+15]: the current
// round consumes word 0 and the next word is
//   sigma1(w14) + w9 + sigma0(w1) + w0.
// This deliberately avoids a 64-word variable-indexed schedule mux.
module board1_sha256_compact_compress (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] state_i,
    output logic        busy_o,
    output logic        done_o,
    output logic [255:0] state_o
);
    logic [31:0] schedule_q [0:15];
    logic [31:0] a_q, b_q, c_q, d_q, e_q, f_q, g_q, h_q;
    logic [255:0] initial_state_q;
    logic [5:0] round_q;
    integer index;

    function automatic [31:0] ror(input [31:0] value,
                                  input integer amount);
        ror = (value >> amount) | (value << (32 - amount));
    endfunction

    function automatic [31:0] choose(input [31:0] x, input [31:0] y,
                                      input [31:0] z);
        choose = (x & y) ^ (~x & z);
    endfunction

    function automatic [31:0] majority(input [31:0] x, input [31:0] y,
                                        input [31:0] z);
        majority = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = ror(x, 2) ^ ror(x, 13) ^ ror(x, 22);
    endfunction

    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = ror(x, 6) ^ ror(x, 11) ^ ror(x, 25);
    endfunction

    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = ror(x, 7) ^ ror(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = ror(x, 17) ^ ror(x, 19) ^ (x >> 10);
    endfunction

    function automatic [31:0] round_constant(input [5:0] n);
        case (n)
            6'd0:  round_constant = 32'h428a2f98;
            6'd1:  round_constant = 32'h71374491;
            6'd2:  round_constant = 32'hb5c0fbcf;
            6'd3:  round_constant = 32'he9b5dba5;
            6'd4:  round_constant = 32'h3956c25b;
            6'd5:  round_constant = 32'h59f111f1;
            6'd6:  round_constant = 32'h923f82a4;
            6'd7:  round_constant = 32'hab1c5ed5;
            6'd8:  round_constant = 32'hd807aa98;
            6'd9:  round_constant = 32'h12835b01;
            6'd10: round_constant = 32'h243185be;
            6'd11: round_constant = 32'h550c7dc3;
            6'd12: round_constant = 32'h72be5d74;
            6'd13: round_constant = 32'h80deb1fe;
            6'd14: round_constant = 32'h9bdc06a7;
            6'd15: round_constant = 32'hc19bf174;
            6'd16: round_constant = 32'he49b69c1;
            6'd17: round_constant = 32'hefbe4786;
            6'd18: round_constant = 32'h0fc19dc6;
            6'd19: round_constant = 32'h240ca1cc;
            6'd20: round_constant = 32'h2de92c6f;
            6'd21: round_constant = 32'h4a7484aa;
            6'd22: round_constant = 32'h5cb0a9dc;
            6'd23: round_constant = 32'h76f988da;
            6'd24: round_constant = 32'h983e5152;
            6'd25: round_constant = 32'ha831c66d;
            6'd26: round_constant = 32'hb00327c8;
            6'd27: round_constant = 32'hbf597fc7;
            6'd28: round_constant = 32'hc6e00bf3;
            6'd29: round_constant = 32'hd5a79147;
            6'd30: round_constant = 32'h06ca6351;
            6'd31: round_constant = 32'h14292967;
            6'd32: round_constant = 32'h27b70a85;
            6'd33: round_constant = 32'h2e1b2138;
            6'd34: round_constant = 32'h4d2c6dfc;
            6'd35: round_constant = 32'h53380d13;
            6'd36: round_constant = 32'h650a7354;
            6'd37: round_constant = 32'h766a0abb;
            6'd38: round_constant = 32'h81c2c92e;
            6'd39: round_constant = 32'h92722c85;
            6'd40: round_constant = 32'ha2bfe8a1;
            6'd41: round_constant = 32'ha81a664b;
            6'd42: round_constant = 32'hc24b8b70;
            6'd43: round_constant = 32'hc76c51a3;
            6'd44: round_constant = 32'hd192e819;
            6'd45: round_constant = 32'hd6990624;
            6'd46: round_constant = 32'hf40e3585;
            6'd47: round_constant = 32'h106aa070;
            6'd48: round_constant = 32'h19a4c116;
            6'd49: round_constant = 32'h1e376c08;
            6'd50: round_constant = 32'h2748774c;
            6'd51: round_constant = 32'h34b0bcb5;
            6'd52: round_constant = 32'h391c0cb3;
            6'd53: round_constant = 32'h4ed8aa4a;
            6'd54: round_constant = 32'h5b9cca4f;
            6'd55: round_constant = 32'h682e6ff3;
            6'd56: round_constant = 32'h748f82ee;
            6'd57: round_constant = 32'h78a5636f;
            6'd58: round_constant = 32'h84c87814;
            6'd59: round_constant = 32'h8cc70208;
            6'd60: round_constant = 32'h90befffa;
            6'd61: round_constant = 32'ha4506ceb;
            6'd62: round_constant = 32'hbef9a3f7;
            default: round_constant = 32'hc67178f2;
        endcase
    endfunction

    wire [31:0] schedule_next =
        small_sigma1(schedule_q[14]) + schedule_q[9] +
        small_sigma0(schedule_q[1]) + schedule_q[0];
    wire [31:0] temp1 = h_q + big_sigma1(e_q) +
                        choose(e_q, f_q, g_q) +
                        round_constant(round_q) + schedule_q[0];
    wire [31:0] temp2 = big_sigma0(a_q) + majority(a_q, b_q, c_q);
    wire [31:0] next_a = temp1 + temp2;
    wire [31:0] next_e = d_q + temp1;

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            state_o <= 256'd0;
            initial_state_q <= 256'd0;
            a_q <= 32'd0;
            b_q <= 32'd0;
            c_q <= 32'd0;
            d_q <= 32'd0;
            e_q <= 32'd0;
            f_q <= 32'd0;
            g_q <= 32'd0;
            h_q <= 32'd0;
            round_q <= 6'd0;
            for (index = 0; index < 16; index = index + 1)
                schedule_q[index] <= 32'd0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_o) begin
                for (index = 0; index < 16; index = index + 1)
                    schedule_q[index] <=
                        block_i[511 - index * 32 -: 32];
                initial_state_q <= state_i;
                a_q <= state_i[255:224];
                b_q <= state_i[223:192];
                c_q <= state_i[191:160];
                d_q <= state_i[159:128];
                e_q <= state_i[127:96];
                f_q <= state_i[95:64];
                g_q <= state_i[63:32];
                h_q <= state_i[31:0];
                round_q <= 6'd0;
                busy_o <= 1'b1;
            end else if (busy_o) begin
                for (index = 0; index < 15; index = index + 1)
                    schedule_q[index] <= schedule_q[index + 1];
                schedule_q[15] <= schedule_next;
                a_q <= next_a;
                b_q <= a_q;
                c_q <= b_q;
                d_q <= c_q;
                e_q <= next_e;
                f_q <= e_q;
                g_q <= f_q;
                h_q <= g_q;
                if (round_q == 6'd63) begin
                    state_o <= {
                        initial_state_q[255:224] + next_a,
                        initial_state_q[223:192] + a_q,
                        initial_state_q[191:160] + b_q,
                        initial_state_q[159:128] + c_q,
                        initial_state_q[127:96]  + next_e,
                        initial_state_q[95:64]   + e_q,
                        initial_state_q[63:32]   + f_q,
                        initial_state_q[31:0]    + g_q
                    };
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    round_q <= round_q + 1'b1;
                end
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (!(busy_o && done_o));
            if (busy_o)
                assert (round_q <= 6'd63);
        end
    end
`endif
endmodule


// Consumes bytes that already include the exact SHA-256 padding.  byte_last_i
// is permitted only on byte 63 of the final block.  No digest, message length,
// or general hash command is exposed at the eventual public machine boundary.
module board1_sha256_compact_padded_stream (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         begin_i,
    input  wire         byte_valid_i,
    output wire         byte_ready_o,
    input  wire [7:0]   byte_data_i,
    input  wire         byte_last_i,
    output logic        digest_valid_o,
    output logic [255:0] digest_o,
    output logic        fault_o
);
    localparam logic [255:0] INITIAL_HASH = {
        32'h6a09e667, 32'hbb67ae85, 32'h3c6ef372, 32'ha54ff53a,
        32'h510e527f, 32'h9b05688c, 32'h1f83d9ab, 32'h5be0cd19
    };

    typedef enum logic [1:0] {
        ST_IDLE    = 2'd0,
        ST_COLLECT = 2'd1,
        ST_WAIT    = 2'd2,
        ST_DONE    = 2'd3
    } state_t;

    state_t state_q;
    logic [5:0] byte_index_q;
    // Only the preceding 63 bytes are retained; the 64th byte is concatenated
    // directly into compress_block_q on the acceptance edge.
    logic [503:0] block_buffer_q;
    logic [255:0] hash_state_q;
    logic [511:0] compress_block_q;
    logic [255:0] compress_state_q;
    logic compress_start_q;
    wire compress_busy;
    wire compress_done;
    wire [255:0] compress_result;
    logic pending_last_q;
    wire compressor_protocol_fault =
        (state_q == ST_WAIT) && !compress_start_q &&
        !compress_busy && !compress_done;

    assign byte_ready_o = state_q == ST_COLLECT && !fault_o;

    board1_sha256_compact_compress u_compress (
        .clk_i(clk_i),
        .reset_n_i(reset_n_i),
        .start_i(compress_start_q),
        .block_i(compress_block_q),
        .state_i(compress_state_q),
        .busy_o(compress_busy),
        .done_o(compress_done),
        .state_o(compress_result)
    );

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            state_q <= ST_IDLE;
            byte_index_q <= 6'd0;
            block_buffer_q <= 504'd0;
            hash_state_q <= INITIAL_HASH;
            compress_block_q <= 512'd0;
            compress_state_q <= INITIAL_HASH;
            compress_start_q <= 1'b0;
            pending_last_q <= 1'b0;
            digest_valid_o <= 1'b0;
            digest_o <= 256'd0;
            fault_o <= 1'b0;
        end else begin
            compress_start_q <= 1'b0;
            digest_valid_o <= 1'b0;
            if (compressor_protocol_fault) begin
                fault_o <= 1'b1;
                state_q <= ST_DONE;
            end else if (begin_i) begin
                if (state_q == ST_COLLECT || state_q == ST_WAIT) begin
                    fault_o <= 1'b1;
                    state_q <= ST_DONE;
                end else begin
                    state_q <= ST_COLLECT;
                    byte_index_q <= 6'd0;
                    block_buffer_q <= 504'd0;
                    hash_state_q <= INITIAL_HASH;
                    pending_last_q <= 1'b0;
                    fault_o <= 1'b0;
                end
            end else begin
                case (state_q)
                    ST_COLLECT: begin
                        if (byte_valid_i && byte_ready_o) begin
`ifndef SYNTHESIS
                            if ($isunknown(byte_data_i) ||
                                $isunknown(byte_last_i)) begin
                                fault_o <= 1'b1;
                                state_q <= ST_DONE;
                            end else begin
`endif
                                block_buffer_q <=
                                    {block_buffer_q[495:0], byte_data_i};
                                if (byte_last_i &&
                                    byte_index_q != 6'd63) begin
                                    fault_o <= 1'b1;
                                    state_q <= ST_DONE;
                                end else if (byte_index_q == 6'd63) begin
                                    compress_block_q <=
                                        {block_buffer_q, byte_data_i};
                                    compress_state_q <= hash_state_q;
                                    compress_start_q <= 1'b1;
                                    pending_last_q <= byte_last_i;
                                    byte_index_q <= 6'd0;
                                    state_q <= ST_WAIT;
                                end else begin
                                    byte_index_q <= byte_index_q + 1'b1;
                                end
`ifndef SYNTHESIS
                            end
`endif
                        end
                    end
                    ST_WAIT: begin
                        if (compress_done) begin
                            hash_state_q <= compress_result;
                            if (pending_last_q) begin
                                digest_o <= compress_result;
                                digest_valid_o <= 1'b1;
                                state_q <= ST_DONE;
                            end else begin
                                state_q <= ST_COLLECT;
                            end
                        end
                    end
                    default: state_q <= state_q;
                endcase
            end
        end
    end

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            if (digest_valid_o)
                assert (state_q == ST_DONE && !fault_o);
            if (state_q == ST_WAIT)
                assert (!byte_ready_o);
            if (fault_o)
                assert (!byte_ready_o);
        end
    end
`endif
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// Four complete rounds per clock; all64 SHA-256 rounds remain.
// Round indices are0,4,...,60. Schedule words16/17 feed18/19's sigma terms.
// Private owner-held-state and DONE-consumption contracts remain unchanged.
module board1_sha256_bank_owned_compress #(parameter integer REGISTER_RESULT=0) (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] state_i,
    output logic        busy_o,
    output logic        done_o,
    output wire [255:0] state_o
);
    logic [31:0] schedule_q [0:15];
    logic [31:0] a_q, b_q, c_q, d_q, e_q, f_q, g_q, h_q;
    logic [5:0] round_q;
    integer index;

    function automatic [31:0] ror(input [31:0] value,
                                  input integer amount);
        ror = (value >> amount) | (value << (32 - amount));
    endfunction

    function automatic [31:0] choose(input [31:0] x, input [31:0] y,
                                      input [31:0] z);
        choose = (x & y) ^ (~x & z);
    endfunction

    function automatic [31:0] majority(input [31:0] x, input [31:0] y,
                                        input [31:0] z);
        majority = (x & y) ^ (x & z) ^ (y & z);
    endfunction

    function automatic [31:0] big_sigma0(input [31:0] x);
        big_sigma0 = ror(x, 2) ^ ror(x, 13) ^ ror(x, 22);
    endfunction

    function automatic [31:0] big_sigma1(input [31:0] x);
        big_sigma1 = ror(x, 6) ^ ror(x, 11) ^ ror(x, 25);
    endfunction

    function automatic [31:0] small_sigma0(input [31:0] x);
        small_sigma0 = ror(x, 7) ^ ror(x, 18) ^ (x >> 3);
    endfunction

    function automatic [31:0] small_sigma1(input [31:0] x);
        small_sigma1 = ror(x, 17) ^ ror(x, 19) ^ (x >> 10);
    endfunction

    function automatic [31:0] round_constant(input [5:0] n);
        case (n)
            6'd0:  round_constant = 32'h428a2f98;
            6'd1:  round_constant = 32'h71374491;
            6'd2:  round_constant = 32'hb5c0fbcf;
            6'd3:  round_constant = 32'he9b5dba5;
            6'd4:  round_constant = 32'h3956c25b;
            6'd5:  round_constant = 32'h59f111f1;
            6'd6:  round_constant = 32'h923f82a4;
            6'd7:  round_constant = 32'hab1c5ed5;
            6'd8:  round_constant = 32'hd807aa98;
            6'd9:  round_constant = 32'h12835b01;
            6'd10: round_constant = 32'h243185be;
            6'd11: round_constant = 32'h550c7dc3;
            6'd12: round_constant = 32'h72be5d74;
            6'd13: round_constant = 32'h80deb1fe;
            6'd14: round_constant = 32'h9bdc06a7;
            6'd15: round_constant = 32'hc19bf174;
            6'd16: round_constant = 32'he49b69c1;
            6'd17: round_constant = 32'hefbe4786;
            6'd18: round_constant = 32'h0fc19dc6;
            6'd19: round_constant = 32'h240ca1cc;
            6'd20: round_constant = 32'h2de92c6f;
            6'd21: round_constant = 32'h4a7484aa;
            6'd22: round_constant = 32'h5cb0a9dc;
            6'd23: round_constant = 32'h76f988da;
            6'd24: round_constant = 32'h983e5152;
            6'd25: round_constant = 32'ha831c66d;
            6'd26: round_constant = 32'hb00327c8;
            6'd27: round_constant = 32'hbf597fc7;
            6'd28: round_constant = 32'hc6e00bf3;
            6'd29: round_constant = 32'hd5a79147;
            6'd30: round_constant = 32'h06ca6351;
            6'd31: round_constant = 32'h14292967;
            6'd32: round_constant = 32'h27b70a85;
            6'd33: round_constant = 32'h2e1b2138;
            6'd34: round_constant = 32'h4d2c6dfc;
            6'd35: round_constant = 32'h53380d13;
            6'd36: round_constant = 32'h650a7354;
            6'd37: round_constant = 32'h766a0abb;
            6'd38: round_constant = 32'h81c2c92e;
            6'd39: round_constant = 32'h92722c85;
            6'd40: round_constant = 32'ha2bfe8a1;
            6'd41: round_constant = 32'ha81a664b;
            6'd42: round_constant = 32'hc24b8b70;
            6'd43: round_constant = 32'hc76c51a3;
            6'd44: round_constant = 32'hd192e819;
            6'd45: round_constant = 32'hd6990624;
            6'd46: round_constant = 32'hf40e3585;
            6'd47: round_constant = 32'h106aa070;
            6'd48: round_constant = 32'h19a4c116;
            6'd49: round_constant = 32'h1e376c08;
            6'd50: round_constant = 32'h2748774c;
            6'd51: round_constant = 32'h34b0bcb5;
            6'd52: round_constant = 32'h391c0cb3;
            6'd53: round_constant = 32'h4ed8aa4a;
            6'd54: round_constant = 32'h5b9cca4f;
            6'd55: round_constant = 32'h682e6ff3;
            6'd56: round_constant = 32'h748f82ee;
            6'd57: round_constant = 32'h78a5636f;
            6'd58: round_constant = 32'h84c87814;
            6'd59: round_constant = 32'h8cc70208;
            6'd60: round_constant = 32'h90befffa;
            6'd61: round_constant = 32'ha4506ceb;
            6'd62: round_constant = 32'hbef9a3f7;
            default: round_constant = 32'hc67178f2;
        endcase
    endfunction

    wire [31:0] schedule_next0 = small_sigma1(schedule_q[14]) + schedule_q[9] + small_sigma0(schedule_q[1]) + schedule_q[0];
    wire [31:0] schedule_next1 = small_sigma1(schedule_q[15]) + schedule_q[10] + small_sigma0(schedule_q[2]) + schedule_q[1];
    wire [31:0] schedule_next2 = small_sigma1(schedule_next0) + schedule_q[11] + small_sigma0(schedule_q[3]) + schedule_q[2];
    wire [31:0] schedule_next3 = small_sigma1(schedule_next1) + schedule_q[12] + small_sigma0(schedule_q[4]) + schedule_q[3];
    wire [31:0] temp1_r1 = h_q + big_sigma1(e_q) + choose(e_q, f_q, g_q) +
        round_constant(round_q + 6'd0) + schedule_q[0];
    wire [31:0] temp2_r1 = big_sigma0(a_q) + majority(a_q, b_q, c_q);
    wire [31:0] a_r1 = temp1_r1 + temp2_r1;
    wire [31:0] b_r1 = a_q;
    wire [31:0] c_r1 = b_q;
    wire [31:0] d_r1 = c_q;
    wire [31:0] e_r1 = d_q + temp1_r1;
    wire [31:0] f_r1 = e_q;
    wire [31:0] g_r1 = f_q;
    wire [31:0] h_r1 = g_q;
    wire [31:0] temp1_r2 = h_r1 + big_sigma1(e_r1) + choose(e_r1, f_r1, g_r1) +
        round_constant(round_q + 6'd1) + schedule_q[1];
    wire [31:0] temp2_r2 = big_sigma0(a_r1) + majority(a_r1, b_r1, c_r1);
    wire [31:0] a_r2 = temp1_r2 + temp2_r2;
    wire [31:0] b_r2 = a_r1;
    wire [31:0] c_r2 = b_r1;
    wire [31:0] d_r2 = c_r1;
    wire [31:0] e_r2 = d_r1 + temp1_r2;
    wire [31:0] f_r2 = e_r1;
    wire [31:0] g_r2 = f_r1;
    wire [31:0] h_r2 = g_r1;
    wire [31:0] temp1_r3 = h_r2 + big_sigma1(e_r2) + choose(e_r2, f_r2, g_r2) +
        round_constant(round_q + 6'd2) + schedule_q[2];
    wire [31:0] temp2_r3 = big_sigma0(a_r2) + majority(a_r2, b_r2, c_r2);
    wire [31:0] a_r3 = temp1_r3 + temp2_r3;
    wire [31:0] b_r3 = a_r2;
    wire [31:0] c_r3 = b_r2;
    wire [31:0] d_r3 = c_r2;
    wire [31:0] e_r3 = d_r2 + temp1_r3;
    wire [31:0] f_r3 = e_r2;
    wire [31:0] g_r3 = f_r2;
    wire [31:0] h_r3 = g_r2;
    wire [31:0] temp1_r4 = h_r3 + big_sigma1(e_r3) + choose(e_r3, f_r3, g_r3) +
        round_constant(round_q + 6'd3) + schedule_q[3];
    wire [31:0] temp2_r4 = big_sigma0(a_r3) + majority(a_r3, b_r3, c_r3);
    wire [31:0] a_r4 = temp1_r4 + temp2_r4;
    wire [31:0] b_r4 = a_r3;
    wire [31:0] c_r4 = b_r3;
    wire [31:0] d_r4 = c_r3;
    wire [31:0] e_r4 = d_r3 + temp1_r4;
    wire [31:0] f_r4 = e_r3;
    wire [31:0] g_r4 = f_r3;
    wire [31:0] h_r4 = g_r3;

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            busy_o <= 1'b0;
            done_o <= 1'b0;
            a_q <= 32'd0;
            b_q <= 32'd0;
            c_q <= 32'd0;
            d_q <= 32'd0;
            e_q <= 32'd0;
            f_q <= 32'd0;
            g_q <= 32'd0;
            h_q <= 32'd0;
            round_q <= 6'd0;
            for (index = 0; index < 16; index = index + 1)
                schedule_q[index] <= 32'd0;
        end else begin
            done_o <= 1'b0;
            if (start_i && !busy_o) begin
                for (index = 0; index < 16; index = index + 1)
                    schedule_q[index] <=
                        block_i[511 - index * 32 -: 32];
                a_q <= state_i[255:224];
                b_q <= state_i[223:192];
                c_q <= state_i[191:160];
                d_q <= state_i[159:128];
                e_q <= state_i[127:96];
                f_q <= state_i[95:64];
                g_q <= state_i[63:32];
                h_q <= state_i[31:0];
                round_q <= 6'd0;
                busy_o <= 1'b1;
            end else if (busy_o) begin
                for (index = 0; index < 12; index = index + 1)
                    schedule_q[index] <= schedule_q[index + 4];
                schedule_q[12] <= schedule_next0;
                schedule_q[13] <= schedule_next1;
                schedule_q[14] <= schedule_next2;
                schedule_q[15] <= schedule_next3;
                a_q <= a_r4;
                b_q <= b_r4;
                c_q <= c_r4;
                d_q <= d_r4;
                e_q <= e_r4;
                f_q <= f_r4;
                g_q <= g_r4;
                h_q <= h_r4;
                if (round_q == 6'd60) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    round_q <= round_q + 6'd4;
                end
            end
        end
    end

    // PRIVATE owner contract: the enclosing page bank holds state_i from
    // an accepted START through the DONE-consumption edge. This is not the
    // reusable compressor's arbitrary-changing-input contract.
    generate if (REGISTER_RESULT != 0) begin : g_registered_result
        logic [255:0] result_q;
        assign state_o = result_q;
        always_ff @(posedge clk_i or negedge reset_n_i) begin
            if (!reset_n_i) result_q <= 256'd0;
            else if (busy_o && round_q == 6'd60) begin
                    result_q <= {
                        state_i[255:224] + a_r4,
                        state_i[223:192] + b_r4,
                        state_i[191:160] + c_r4,
                        state_i[159:128] + d_r4,
                        state_i[127:96] + e_r4,
                        state_i[95:64] + f_r4,
                        state_i[63:32] + g_r4,
                        state_i[31:0] + h_r4
                    };
            end
        end
    end else begin : g_bank_captures_result
        // On DONE the working registers already hold round 63's completed
        // a..h. The bank captures these eight sums at its unchanged edge.
        // Outside DONE this private bus is unspecified, not a valid digest.
        assign state_o = {
            state_i[255:224] + a_q, state_i[223:192] + b_q,
            state_i[191:160] + c_q, state_i[159:128] + d_q,
            state_i[127:96] + e_q, state_i[95:64] + f_q,
            state_i[63:32] + g_q, state_i[31:0] + h_q
        };
    end endgenerate

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (!(busy_o && done_o));
            if (busy_o) begin
                assert (round_q <= 6'd60);
                assert (round_q[1:0] == 2'b00);
            end
        end
    end
`endif
endmodule

`default_nettype wire
