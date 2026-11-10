// SHA-256 compression function (FIPS 180-4), one round per clock.
// start loads state_in and one 512-bit block (W0 = block[511:480]); 64 round cycles follow,
// then one cycle adds the input state. done pulses for one cycle with state_out valid; state_out
// holds until the next start or clear. Digest convention: {H0,...,H7}, so digest byte 0 is
// state_out[255:248].
`default_nettype none

module moe_sha256_core (
  input  wire          clk,
  input  wire          rst_n,
  input  wire          clear,      // zeroize all state
  input  wire          start,      // ignored while busy
  input  wire  [255:0] state_in,
  input  wire  [511:0] block,
  output logic         busy,
  output logic         done,
  output logic [255:0] state_out,
  output logic         nz          // any internal state nonzero (probe support)
);
  function automatic logic [31:0] kc(input logic [5:0] i);
    case (i)
      6'd0:  kc = 32'h428a2f98; 6'd1:  kc = 32'h71374491; 6'd2:  kc = 32'hb5c0fbcf; 6'd3:  kc = 32'he9b5dba5;
      6'd4:  kc = 32'h3956c25b; 6'd5:  kc = 32'h59f111f1; 6'd6:  kc = 32'h923f82a4; 6'd7:  kc = 32'hab1c5ed5;
      6'd8:  kc = 32'hd807aa98; 6'd9:  kc = 32'h12835b01; 6'd10: kc = 32'h243185be; 6'd11: kc = 32'h550c7dc3;
      6'd12: kc = 32'h72be5d74; 6'd13: kc = 32'h80deb1fe; 6'd14: kc = 32'h9bdc06a7; 6'd15: kc = 32'hc19bf174;
      6'd16: kc = 32'he49b69c1; 6'd17: kc = 32'hefbe4786; 6'd18: kc = 32'h0fc19dc6; 6'd19: kc = 32'h240ca1cc;
      6'd20: kc = 32'h2de92c6f; 6'd21: kc = 32'h4a7484aa; 6'd22: kc = 32'h5cb0a9dc; 6'd23: kc = 32'h76f988da;
      6'd24: kc = 32'h983e5152; 6'd25: kc = 32'ha831c66d; 6'd26: kc = 32'hb00327c8; 6'd27: kc = 32'hbf597fc7;
      6'd28: kc = 32'hc6e00bf3; 6'd29: kc = 32'hd5a79147; 6'd30: kc = 32'h06ca6351; 6'd31: kc = 32'h14292967;
      6'd32: kc = 32'h27b70a85; 6'd33: kc = 32'h2e1b2138; 6'd34: kc = 32'h4d2c6dfc; 6'd35: kc = 32'h53380d13;
      6'd36: kc = 32'h650a7354; 6'd37: kc = 32'h766a0abb; 6'd38: kc = 32'h81c2c92e; 6'd39: kc = 32'h92722c85;
      6'd40: kc = 32'ha2bfe8a1; 6'd41: kc = 32'ha81a664b; 6'd42: kc = 32'hc24b8b70; 6'd43: kc = 32'hc76c51a3;
      6'd44: kc = 32'hd192e819; 6'd45: kc = 32'hd6990624; 6'd46: kc = 32'hf40e3585; 6'd47: kc = 32'h106aa070;
      6'd48: kc = 32'h19a4c116; 6'd49: kc = 32'h1e376c08; 6'd50: kc = 32'h2748774c; 6'd51: kc = 32'h34b0bcb5;
      6'd52: kc = 32'h391c0cb3; 6'd53: kc = 32'h4ed8aa4a; 6'd54: kc = 32'h5b9cca4f; 6'd55: kc = 32'h682e6ff3;
      6'd56: kc = 32'h748f82ee; 6'd57: kc = 32'h78a5636f; 6'd58: kc = 32'h84c87814; 6'd59: kc = 32'h8cc70208;
      6'd60: kc = 32'h90befffa; 6'd61: kc = 32'ha4506ceb; 6'd62: kc = 32'hbef9a3f7; default: kc = 32'hc67178f2;
    endcase
  endfunction

  function automatic logic [31:0] rotr(input logic [31:0] x, input integer n);
    rotr = (x >> n) | (x << (32 - n));
  endfunction

  logic [31:0] a, b, c, d, e, f, g, h;
  logic [255:0] hin;
  logic [511:0] wv;          // W[t..t+15], W[t] in the top word
  logic [6:0]  rnd;

  logic [31:0] wt, big_s1, ch, t1, big_s0, maj, t2, w1, w14, sm0, sm1, wnew;
  always_comb nz = |{a, b, c, d, e, f, g, h, hin, wv, rnd, state_out};
  always_comb begin
    wt     = wv[511:480];
    big_s1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
    ch     = (e & f) ^ (~e & g);
    t1     = h + big_s1 + ch + kc(rnd[5:0]) + wt;
    big_s0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
    maj    = (a & b) ^ (a & c) ^ (b & c);
    t2     = big_s0 + maj;
    w1     = wv[479:448];
    w14    = wv[63:32];
    sm0    = rotr(w1, 7) ^ rotr(w1, 18) ^ (w1 >> 3);
    sm1    = rotr(w14, 17) ^ rotr(w14, 19) ^ (w14 >> 10);
    wnew   = sm1 + wv[223:192] + sm0 + wt;          // W[t+16] = s1(W[t+14]) + W[t+9] + s0(W[t+1]) + W[t]
  end

  always_ff @(posedge clk) begin                     // synchronous reset and zeroize
    if (!rst_n || clear) begin
      {a, b, c, d, e, f, g, h} <= '0;
      hin <= '0; wv <= '0; rnd <= '0; busy <= 1'b0; done <= 1'b0; state_out <= '0;
    end else begin
      done <= 1'b0;
      if (!busy) begin
        if (start) begin
          {a, b, c, d, e, f, g, h} <= state_in;
          hin  <= state_in;
          wv   <= block;
          rnd  <= '0;
          busy <= 1'b1;
        end
      end else if (rnd != 7'd64) begin
        h <= g; g <= f; f <= e; e <= d + t1;
        d <= c; c <= b; b <= a; a <= t1 + t2;
        wv  <= {wv[479:0], wnew};
        rnd <= rnd + 7'd1;
      end else begin
        state_out <= {a + hin[255:224], b + hin[223:192], c + hin[191:160], d + hin[159:128],
                      e + hin[127:96],  f + hin[95:64],   g + hin[63:32],   h + hin[31:0]};
        busy <= 1'b0;
        done <= 1'b1;
      end
    end
  end
endmodule

`default_nettype wire
