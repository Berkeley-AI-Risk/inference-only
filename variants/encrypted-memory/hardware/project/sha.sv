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
module board1_sha256_owner_held_boot_compress (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] state_i,
    output logic        busy_o,
    output logic        done_o,
    output wire  [255:0] state_o
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

    wire [31:0] schedule_next =
        small_sigma1(schedule_q[14]) + schedule_q[9] +
        small_sigma0(schedule_q[1]) + schedule_q[0];
    wire [31:0] temp1 = h_q + big_sigma1(e_q) +
                        choose(e_q, f_q, g_q) +
                        round_constant(round_q) + schedule_q[0];
    wire [31:0] temp2 = big_sigma0(a_q) + majority(a_q, b_q, c_q);
    wire [31:0] next_a = temp1 + temp2;
    wire [31:0] next_e = d_q + temp1;

    // PRIVATE owner-held state contract: state_i is stable until DONE.
    // The stream consumes state_o only with DONE. All working bits are loaded
    // before BUSY, and BUSY/DONE reset independently of these payload registers.
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            if (start_i && !busy_o) begin
                for (index=0;index<16;index=index+1)
                    schedule_q[index] <= block_i[511-index*32 -: 32];
                {a_q,b_q,c_q,d_q,e_q,f_q,g_q,h_q} <= state_i;
            end else if (busy_o) begin
                for (index=0;index<15;index=index+1)
                    schedule_q[index] <= schedule_q[index+1];
                schedule_q[15] <= schedule_next;
                a_q<=next_a; b_q<=a_q; c_q<=b_q; d_q<=c_q;
                e_q<=next_e; f_q<=e_q; g_q<=f_q; h_q<=g_q;
            end
        end
    end
    assign state_o = {
        state_i[255:224]+a_q, state_i[223:192]+b_q,
        state_i[191:160]+c_q, state_i[159:128]+d_q,
        state_i[127:96]+e_q, state_i[95:64]+f_q,
        state_i[63:32]+g_q, state_i[31:0]+h_q
    };
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            busy_o<=0; done_o<=0; round_q<=0;
        end else begin
            done_o<=0;
            if (start_i && !busy_o) begin
                round_q<=0; busy_o<=1;
            end else if (busy_o) begin
                if (round_q==6'd63) begin busy_o<=0; done_o<=1; end
                else round_q<=round_q+1'b1;
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
    // The delayed compression START consumes this complete64-byte block.
    // No bytes are accepted while the stream waits for compression.
    logic [511:0] block_buffer_q;
    logic [255:0] hash_state_q;
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

    board1_sha256_owner_held_boot_compress u_compress (
        .clk_i(clk_i),
        .reset_n_i(reset_n_i),
        .start_i(compress_start_q),
        .block_i(block_buffer_q),
        .state_i(compress_state_q),
        .busy_o(compress_busy),
        .done_o(compress_done),
        .state_o(compress_result)
    );

    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            state_q <= ST_IDLE;
            byte_index_q <= 6'd0;
            block_buffer_q <= 512'd0;
            hash_state_q <= INITIAL_HASH;
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
                    block_buffer_q <= 512'd0;
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
                                    {block_buffer_q[503:0], byte_data_i};
                                if (byte_last_i &&
                                    byte_index_q != 6'd63) begin
                                    fault_o <= 1'b1;
                                    state_q <= ST_DONE;
                                end else if (byte_index_q == 6'd63) begin
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

// Two complete rounds per clock; all64 SHA-256 rounds remain.
// Round indices are0,2,...,62. The fixed-tap schedule advances by two words.
// This private owner-held-state contract and external DONE handshake remain.
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

    // Precompute only state already known before each pair of rounds.
    // Busy START pulses are ignored, just as in the original compressor.
    wire lookahead_start = start_i && !busy_o;
    wire [31:0] lookahead_h = lookahead_start ? state_i[31:0] : f_q;
    wire [31:0] lookahead_g = lookahead_start ? state_i[63:32] : e_q;
    wire [31:0] lookahead_word0 = lookahead_start ? block_i[511:480] : schedule_q[2];
    wire [31:0] lookahead_word1 = lookahead_start ? block_i[479:448] : schedule_q[3];
    wire [5:0] lookahead_round0 = lookahead_start ? 6'd0 : round_q + 6'd2;
    wire [5:0] lookahead_round1 = lookahead_start ? 6'd1 : round_q + 6'd3;
    wire [31:0] lookahead_hk, lookahead_gk, lookahead_hkw, lookahead_gkw;
    logic [31:0] hkw_q, gkw_q;
    tang_sha_dsp_add32 u_lookahead_hk(.a_i(lookahead_h), .b_i(round_constant(lookahead_round0)), .sum_o(lookahead_hk));
    tang_sha_dsp_add32 u_lookahead_gk(.a_i(lookahead_g), .b_i(round_constant(lookahead_round1)), .sum_o(lookahead_gk));
    tang_sha_dsp_add32 u_lookahead_hkw(.a_i(lookahead_hk), .b_i(lookahead_word0), .sum_o(lookahead_hkw));
    tang_sha_dsp_add32 u_lookahead_gkw(.a_i(lookahead_gk), .b_i(lookahead_word1), .sum_o(lookahead_gkw));
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            hkw_q <= 32'd0;
            gkw_q <= 32'd0;
        end else if (lookahead_start || busy_o) begin
            hkw_q <= lookahead_hkw;
            gkw_q <= lookahead_gkw;
        end
    end

    // Balanced modulo-2^32 sums in fixed DSP adders.
    wire [31:0] schedule_first_lo;
    tang_sha_dsp_add32 u_schedule_first_lo(.a_i(small_sigma1(schedule_q[14])), .b_i(schedule_q[9]), .sum_o(schedule_first_lo));
    wire [31:0] schedule_first_hi;
    tang_sha_dsp_add32 u_schedule_first_hi(.a_i(small_sigma0(schedule_q[1])), .b_i(schedule_q[0]), .sum_o(schedule_first_hi));
    wire [31:0] schedule_next;
    tang_sha_dsp_add32 u_schedule_next(.a_i(schedule_first_lo), .b_i(schedule_first_hi), .sum_o(schedule_next));
    wire [31:0] sum_first_3;
    tang_sha_csa3_add32 u_sum_first_3 (
        .x_i(big_sigma1(e_q)), .y_i(choose(e_q, f_q, g_q)),
        .z_i(hkw_q), .sum_o(sum_first_3));
    wire [31:0] sum_first_4;
    tang_sha_dsp_add32 u_sum_first_4(.a_i(big_sigma0(a_q)), .b_i(majority(a_q, b_q, c_q)), .sum_o(sum_first_4));
    wire [31:0] next_a;
    tang_sha_dsp_add32 u_next_a(.a_i(sum_first_3), .b_i(sum_first_4), .sum_o(next_a));
    wire [31:0] next_e;
    tang_sha_dsp_add32 u_next_e(.a_i(d_q), .b_i(sum_first_3), .sum_o(next_e));
    wire [31:0] schedule_second_lo;
    tang_sha_dsp_add32 u_schedule_second_lo(.a_i(small_sigma1(schedule_q[15])), .b_i(schedule_q[10]), .sum_o(schedule_second_lo));
    wire [31:0] schedule_second_hi;
    tang_sha_dsp_add32 u_schedule_second_hi(.a_i(small_sigma0(schedule_q[2])), .b_i(schedule_q[1]), .sum_o(schedule_second_hi));
    wire [31:0] schedule_next1;
    tang_sha_dsp_add32 u_schedule_next1(.a_i(schedule_second_lo), .b_i(schedule_second_hi), .sum_o(schedule_next1));
    wire [31:0] sum_second_3;
    tang_sha_csa3_add32 u_sum_second_3 (
        .x_i(big_sigma1(next_e)), .y_i(choose(next_e, e_q, f_q)),
        .z_i(gkw_q), .sum_o(sum_second_3));
    wire [31:0] sum_second_4;
    tang_sha_dsp_add32 u_sum_second_4(.a_i(big_sigma0(next_a)), .b_i(majority(next_a, a_q, b_q)), .sum_o(sum_second_4));
    wire [31:0] second_a;
    tang_sha_dsp_add32 u_second_a(.a_i(sum_second_3), .b_i(sum_second_4), .sum_o(second_a));
    wire [31:0] second_e;
    tang_sha_dsp_add32 u_second_e(.a_i(c_q), .b_i(sum_second_3), .sum_o(second_e));

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
                for (index = 0; index < 14; index = index + 1)
                    schedule_q[index] <= schedule_q[index + 2];
                schedule_q[14] <= schedule_next;
                schedule_q[15] <= schedule_next1;
                a_q <= second_a;
                b_q <= next_a;
                c_q <= a_q;
                d_q <= b_q;
                e_q <= second_e;
                f_q <= next_e;
                g_q <= e_q;
                h_q <= f_q;
                if (round_q == 6'd62) begin
                    busy_o <= 1'b0;
                    done_o <= 1'b1;
                end else begin
                    round_q <= round_q + 6'd2;
                end
            end
        end
    end

    // PRIVATE owner contract: the enclosing page bank holds state_i from
    // an accepted START through the DONE-consumption edge. This is not the
    // reusable compressor's arbitrary-changing-input contract.
    generate if (REGISTER_RESULT != 0) begin : g_registered_result
        logic [255:0] result_q;
        wire [255:0] final_sum;
    tang_sha_dsp_add32 u_registered_sum0(.a_i(state_i[255:224]), .b_i(second_a), .sum_o(final_sum[255:224]));
    tang_sha_dsp_add32 u_registered_sum1(.a_i(state_i[223:192]), .b_i(next_a), .sum_o(final_sum[223:192]));
    tang_sha_dsp_add32 u_registered_sum2(.a_i(state_i[191:160]), .b_i(a_q), .sum_o(final_sum[191:160]));
    tang_sha_dsp_add32 u_registered_sum3(.a_i(state_i[159:128]), .b_i(b_q), .sum_o(final_sum[159:128]));
    tang_sha_dsp_add32 u_registered_sum4(.a_i(state_i[127:96]), .b_i(second_e), .sum_o(final_sum[127:96]));
    tang_sha_dsp_add32 u_registered_sum5(.a_i(state_i[95:64]), .b_i(next_e), .sum_o(final_sum[95:64]));
    tang_sha_dsp_add32 u_registered_sum6(.a_i(state_i[63:32]), .b_i(e_q), .sum_o(final_sum[63:32]));
    tang_sha_dsp_add32 u_registered_sum7(.a_i(state_i[31:0]), .b_i(f_q), .sum_o(final_sum[31:0]));
        assign state_o = result_q;
        always_ff @(posedge clk_i or negedge reset_n_i) begin
            if (!reset_n_i) result_q <= 256'd0;
            else if (busy_o && round_q == 6'd62) begin
                    result_q <= final_sum;
            end
        end
    end else begin : g_bank_captures_result
        // On DONE the working registers already hold round 63's completed
        // a..h. The bank captures these eight sums at its unchanged edge.
        // Outside DONE this private bus is unspecified, not a valid digest.
    tang_sha_dsp_add32 u_captured_sum0(.a_i(state_i[255:224]), .b_i(a_q), .sum_o(state_o[255:224]));
    tang_sha_dsp_add32 u_captured_sum1(.a_i(state_i[223:192]), .b_i(b_q), .sum_o(state_o[223:192]));
    tang_sha_dsp_add32 u_captured_sum2(.a_i(state_i[191:160]), .b_i(c_q), .sum_o(state_o[191:160]));
    tang_sha_dsp_add32 u_captured_sum3(.a_i(state_i[159:128]), .b_i(d_q), .sum_o(state_o[159:128]));
    tang_sha_dsp_add32 u_captured_sum4(.a_i(state_i[127:96]), .b_i(e_q), .sum_o(state_o[127:96]));
    tang_sha_dsp_add32 u_captured_sum5(.a_i(state_i[95:64]), .b_i(f_q), .sum_o(state_o[95:64]));
    tang_sha_dsp_add32 u_captured_sum6(.a_i(state_i[63:32]), .b_i(g_q), .sum_o(state_o[63:32]));
    tang_sha_dsp_add32 u_captured_sum7(.a_i(state_i[31:0]), .b_i(h_q), .sum_o(state_o[31:0]));
    end endgenerate

`ifdef FORMAL
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            assert (!(busy_o && done_o));
            if (busy_o) begin
                assert (round_q <= 6'd62);
                assert (!round_q[0]);
            end
        end
    end
`endif
endmodule

`default_nettype wire

// Full-model Verilator fixtures also define SYNTHESIS.
// Keep vendor selection for native builds, and portable arithmetic for that simulator.
`ifdef SYNTHESIS
`ifndef VERILATOR
`define TANG_SHA_DSP_ADDER
`endif
`endif
`timescale 1ns/1ps
// Private modulo-2^32 addition for the weight-page checker. This exposes no
// new public operation. The native multiplier's second operand is constant 1;
// feedback, cascade input, all dynamic controls and all registers are disabled.
// Split a_i to keep the signed native A input nonnegative. The small fabric
// correction restores its upper six bits, including the low-part carry.
module tang_sha_dsp_add32 (
    input wire [31:0] a_i,
    input wire [31:0] b_i,
    output wire [31:0] sum_o
);
    wire [47:0] low_sum;
`ifdef TANG_SHA_DSP_ADDER
    MULTALU27X18 #(
        .AREG_CLK("BYPASS"), .BREG_CLK("BYPASS"), .DREG_CLK("BYPASS"),
        .C_IREG_CLK("BYPASS"), .C_PREG_CLK("BYPASS"),
        .PREG_CLK("BYPASS"), .OREG_CLK("BYPASS"),
        .PSEL_IREG_CLK("BYPASS"), .PADDSUB_IREG_CLK("BYPASS"),
        .ADDSUB0_IREG_CLK("BYPASS"), .ADDSUB1_IREG_CLK("BYPASS"),
        .CSEL_IREG_CLK("BYPASS"), .CASISEL_IREG_CLK("BYPASS"),
        .ACCSEL_IREG_CLK("BYPASS"),
        .ADDSUB0_PREG_CLK("BYPASS"), .ADDSUB1_PREG_CLK("BYPASS"),
        .CSEL_PREG_CLK("BYPASS"), .CASISEL_PREG_CLK("BYPASS"),
        .ACCSEL_PREG_CLK("BYPASS"),
        .FB_PREG_EN("FALSE"), .SOA_PREG_EN("FALSE"),
        .MULT_RESET_MODE("SYNC"), .PRE_LOAD(48'd0),
        .DYN_P_SEL("FALSE"), .P_SEL(1'b0),
        .DYN_P_ADDSUB("FALSE"), .P_ADDSUB(1'b0),
        .DYN_A_SEL("FALSE"), .A_SEL(1'b0),
        .DYN_ADD_SUB_0("FALSE"), .ADD_SUB_0(1'b0),
        .DYN_ADD_SUB_1("FALSE"), .ADD_SUB_1(1'b0),
        .DYN_C_SEL("FALSE"), .C_SEL(1'b1),
        .DYN_CASI_SEL("FALSE"), .CASI_SEL(1'b0),
        .DYN_ACC_SEL("FALSE"), .ACC_SEL(1'b0),
        .MULT12X12_EN("FALSE")
    ) fixed_add (
        .DOUT(low_sum), .CASO(), .SOA(),
        .A({1'b0, a_i[25:0]}), .B(18'd1), .C({16'd0, b_i}),
        .D(26'd0), .SIA(27'd0), .CASI(48'd0),
        .PSEL(1'b0), .ASEL(1'b0), .CSEL(1'b1), .CASISEL(1'b0),
        .PADDSUB(1'b0), .ACCSEL(1'b0), .ADDSUB(2'b00),
        .CLK(2'b00), .CE(2'b00), .RESET(2'b00)
    );
`else
    // Portable arithmetic specification; not a replacement for checking the
    // actual vendor primitive or its native mapping and physical timing.
    assign low_sum = {22'd0, a_i[25:0]} + {16'd0, b_i};
`endif
    wire [5:0] corrected_high = low_sum[31:26] + a_i[31:26];
    assign sum_o = {corrected_high, low_sum[25:0]};
endmodule

`ifdef SYNTHESIS
`undef TANG_SHA_DSP_ADDER
`endif

`timescale 1ns/1ps
`default_nettype none
module board1_sha256_owner_held_kv_compress (
    input  wire         clk_i,
    input  wire         reset_n_i,
    input  wire         start_i,
    input  wire [511:0] block_i,
    input  wire [255:0] state_i,
    output logic        busy_o,
    output logic        done_o,
    output wire  [255:0] state_o
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

    wire [31:0] schedule_next =
        small_sigma1(schedule_q[14]) + schedule_q[9] +
        small_sigma0(schedule_q[1]) + schedule_q[0];
    wire [31:0] temp1 = h_q + big_sigma1(e_q) +
                        choose(e_q, f_q, g_q) +
                        round_constant(round_q) + schedule_q[0];
    wire [31:0] temp2 = big_sigma0(a_q) + majority(a_q, b_q, c_q);
    wire [31:0] next_a = temp1 + temp2;
    wire [31:0] next_e = d_q + temp1;

    // PRIVATE owner-held state contract: state_i is stable until DONE.
    // The stream consumes state_o only with DONE. All working bits are loaded
    // before BUSY, and BUSY/DONE reset independently of these payload registers.
    always_ff @(posedge clk_i) begin
        if (reset_n_i) begin
            if (start_i && !busy_o) begin
                for (index=0;index<16;index=index+1)
                    schedule_q[index] <= block_i[511-index*32 -: 32];
                {a_q,b_q,c_q,d_q,e_q,f_q,g_q,h_q} <= state_i;
            end else if (busy_o) begin
                for (index=0;index<15;index=index+1)
                    schedule_q[index] <= schedule_q[index+1];
                schedule_q[15] <= schedule_next;
                a_q<=next_a; b_q<=a_q; c_q<=b_q; d_q<=c_q;
                e_q<=next_e; f_q<=e_q; g_q<=f_q; h_q<=g_q;
            end
        end
    end
    assign state_o = {
        state_i[255:224]+a_q, state_i[223:192]+b_q,
        state_i[191:160]+c_q, state_i[159:128]+d_q,
        state_i[127:96]+e_q, state_i[95:64]+f_q,
        state_i[63:32]+g_q, state_i[31:0]+h_q
    };
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if (!reset_n_i) begin
            busy_o<=0; done_o<=0; round_q<=0;
        end else begin
            done_o<=0;
            if (start_i && !busy_o) begin
                round_q<=0; busy_o<=1;
            end else if (busy_o) begin
                if (round_q==6'd63) begin busy_o<=0; done_o<=1; end
                else round_q<=round_q+1'b1;
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
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none

// PRIVATE immutable-weight service, not a software-accessible hash interface.
// Even and odd banks have separate engines. Each engine fairly serves its
// own fixed group; two-bank builds have one engine per bank. Per-bank chaining
// values remain in the bank and accompany every block request. Ownership is
// fixed until the corresponding digest returns. No bank may have two blocks
// in flight. CLEAR is not an input: immutable-weight work drains across CLEAR.
// abort_i is a terminal global integrity fault, recoverable only by reset.
module tang_private_sha256_pool2 #(
    parameter integer BANKS=4
) (
    input wire clk,reset_n,abort_i,
    input wire [BANKS-1:0] request_valid_i,
    output logic [BANKS-1:0] request_ready_o,
    input wire [BANKS*512-1:0] request_block_i,
    input wire [BANKS*256-1:0] request_state_i,
    output wire [BANKS-1:0] pending_o,
    output logic [BANKS-1:0] response_valid_o,
    output logic [BANKS*256-1:0] response_state_o,
    output wire fault_o
);
    localparam integer GROUP_BANKS=BANKS/2;
    localparam integer SLOT_W=GROUP_BANKS>1 ? $clog2(GROUP_BANKS) : 1;
    localparam integer BANK_W=$clog2(BANKS);
    logic fault_q;
    logic [SLOT_W-1:0] rr_q [0:1];
    logic [1:0] owner_valid_q;
    logic [BANK_W-1:0] owner_q [0:1];
    logic [BANKS-1:0] pending_q;
    wire [1:0] engine_busy,engine_done;
    wire [255:0] engine_result [0:1];
    logic [1:0] grant_valid;
    logic [SLOT_W-1:0] grant_slot [0:1];
    logic [BANK_W-1:0] grant_bank [0:1];
    logic bad_return;
    wire enabled=reset_n && !abort_i && !fault_q;
    assign fault_o=fault_q;
    assign pending_o=pending_q & {BANKS{enabled}};

    integer engine,offset,slot,bank;
    always_comb begin
        request_ready_o=0;grant_valid=0;slot=0;bank=0;
        for(engine=0;engine<2;engine=engine+1) begin
            grant_slot[engine]=0;grant_bank[engine]=0;
            if(enabled && !engine_busy[engine] && !engine_done[engine]) begin
                for(offset=0;offset<GROUP_BANKS;offset=offset+1) begin
                    slot=(int'(rr_q[engine])+offset)&(GROUP_BANKS-1);
                    bank=slot*2+engine;
                    if(!grant_valid[engine] && request_valid_i[bank] && !pending_q[bank]) begin
                        grant_valid[engine]=1;grant_slot[engine]=SLOT_W'(slot);
                        grant_bank[engine]=BANK_W'(bank);request_ready_o[bank]=1;
                    end
                end
            end
        end
    end

    integer e;
    always_comb begin
        response_valid_o=0;response_state_o=0;bad_return=0;
        for(e=0;e<2;e=e+1) begin
            if(engine_done[e]) begin
                if(!owner_valid_q[e] || !pending_q[owner_q[e]] || owner_q[e][0]!=1'(e))
                    bad_return=1;
                else if(enabled) begin
                    response_valid_o[owner_q[e]]=1;
                    response_state_o[int'(owner_q[e])*256 +: 256]=engine_result[e];
                end
            end
        end
    end

    for(genvar g=0;g<2;g=g+1) begin: g_engine
        // The bank-owned compressor reads state_i through DONE. Keep
        // that bank selected, including the edge that captures its digest.
        wire [SLOT_W-1:0] active_slot=owner_valid_q[g] ?
            SLOT_W'(int'(owner_q[g])/2) : grant_slot[g];
        wire [GROUP_BANKS*512-1:0] blocks;
        wire [GROUP_BANKS*256-1:0] states;
        for(genvar b=0;b<GROUP_BANKS;b=b+1) begin: g_input
            assign blocks[b*512 +: 512]=request_block_i[(b*2+g)*512 +: 512];
            assign states[b*256 +: 256]=request_state_i[(b*2+g)*256 +: 256];
        end
        board1_sha256_bank_owned_compress #(.REGISTER_RESULT(0)) u_sha (
            .clk_i(clk),.reset_n_i(reset_n),.start_i(grant_valid[g]),
            .block_i(blocks[int'(active_slot)*512 +: 512]),
            .state_i(states[int'(active_slot)*256 +: 256]),
            .busy_o(engine_busy[g]),.done_o(engine_done[g]),.state_o(engine_result[g]));
    end

    wire protocol_error=bad_return || (|(request_valid_i & pending_q));
`ifndef SYNTHESIS
    logic x_error;
    integer x;
    always_comb begin
        x_error=$isunknown(abort_i) || $isunknown(request_valid_i);
        for(x=0;x<BANKS;x=x+1)
            if(request_valid_i[x]) x_error=x_error ||
                $isunknown(request_block_i[x*512 +: 512]) ||
                $isunknown(request_state_i[x*256 +: 256]);
    end
`endif
    integer k;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            fault_q<=0;owner_valid_q<=0;pending_q<=0;
            owner_q[0]<=0;owner_q[1]<=0;rr_q[0]<=0;rr_q[1]<=0;
        end else if(fault_q || abort_i || (enabled && protocol_error)
`ifndef SYNTHESIS
                    || (enabled && x_error)
`endif
        ) begin
            fault_q<=1;owner_valid_q<=0;pending_q<=0;
            owner_q[0]<=0;owner_q[1]<=0;rr_q[0]<=0;rr_q[1]<=0;
        end else begin
            for(k=0;k<2;k=k+1) begin
                if(engine_done[k] && owner_valid_q[k]) begin
                    pending_q[owner_q[k]]<=0;owner_valid_q[k]<=0;
                end
                if(grant_valid[k]) begin
                    pending_q[grant_bank[k]]<=1;owner_valid_q[k]<=1;
                    owner_q[k]<=grant_bank[k];rr_q[k]<=SLOT_W'(int'(grant_slot[k])+1);
                end
            end
        end
    end
    initial begin
        if(BANKS<2 || BANKS>16 || (BANKS&(BANKS-1))!=0)
            $fatal(1,"Unsupported private SHA pool geometry");
    end
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Private modulo-2^32 sum. Compress three inputs into two without propagating
// carry, then use the existing fixed-operation DSP adder. There is no state,
// new command, omitted SHA round, or change to the digest/acceptance boundary.
module tang_sha_csa3_add32 (
    input wire [31:0] x_i, y_i, z_i,
    output wire [31:0] sum_o
);
    wire [31:0] sum_bits = x_i ^ y_i ^ z_i;
    wire [31:0] carry_bits = ((x_i & y_i) | (x_i & z_i) | (y_i & z_i)) << 1;
    tang_sha_dsp_add32 u_final (
        .a_i(sum_bits), .b_i(carry_bits), .sum_o(sum_o));
endmodule
`default_nettype wire
