`timescale 1ns/1ps
`default_nettype none

// PRIVATE fixed-key primitive; never expose these ports as a user API.
// The KEY parameter is part of the configuration and is NOT secret unless
// the complete configuration/provisioning boundary protects it. Test keys
// are public. No masking, fault-attack or side-channel certification claimed.
module tang_private_aes256 #(
    parameter bit KEY_IS_PROVISIONED=0,
    parameter [255:0] KEY=256'd0
) (
    input wire clk,reset_n,abort_i,start_i,
    input wire [127:0] block_i,
    output wire ready_o,
    output logic busy_o,done_o,
    output wire [127:0] block_o
);
    localparam [2047:0] SBOX={
        128'h637c777bf26b6fc53001672bfed7ab76,
        128'hca82c97dfa5947f0add4a2af9ca472c0,
        128'hb7fd9326363ff7cc34a5e5f171d83115,
        128'h04c723c31896059a071280e2eb27b275,
        128'h09832c1a1b6e5aa0523bd6b329e32f84,
        128'h53d100ed20fcb15b6acbbe394a4c58cf,
        128'hd0efaafb434d338545f9027f503c9fa8,
        128'h51a3408f929d38f5bcb6da2110fff3d2,
        128'hcd0c13ec5f974417c4a77e3d645d1973,
        128'h60814fdc222a908846eeb814de5e0bdb,
        128'he0323a0a4906245cc2d3ac629195e479,
        128'he7c8376d8dd54ea96c56f4ea657aae08,
        128'hba78252e1ca6b4c6e8dd741f4bbd8b8a,
        128'h703eb5664803f60e613557b986c11d9e,
        128'he1f8981169d98e949b1e87e9ce5528df,
        128'h8ca1890dbfe6426841992d0fb054bb16};
    function automatic [7:0] sb(input [7:0] x);
        case (x)
            8'h00: sb=8'h63;
            8'h01: sb=8'h7c;
            8'h02: sb=8'h77;
            8'h03: sb=8'h7b;
            8'h04: sb=8'hf2;
            8'h05: sb=8'h6b;
            8'h06: sb=8'h6f;
            8'h07: sb=8'hc5;
            8'h08: sb=8'h30;
            8'h09: sb=8'h01;
            8'h0a: sb=8'h67;
            8'h0b: sb=8'h2b;
            8'h0c: sb=8'hfe;
            8'h0d: sb=8'hd7;
            8'h0e: sb=8'hab;
            8'h0f: sb=8'h76;
            8'h10: sb=8'hca;
            8'h11: sb=8'h82;
            8'h12: sb=8'hc9;
            8'h13: sb=8'h7d;
            8'h14: sb=8'hfa;
            8'h15: sb=8'h59;
            8'h16: sb=8'h47;
            8'h17: sb=8'hf0;
            8'h18: sb=8'had;
            8'h19: sb=8'hd4;
            8'h1a: sb=8'ha2;
            8'h1b: sb=8'haf;
            8'h1c: sb=8'h9c;
            8'h1d: sb=8'ha4;
            8'h1e: sb=8'h72;
            8'h1f: sb=8'hc0;
            8'h20: sb=8'hb7;
            8'h21: sb=8'hfd;
            8'h22: sb=8'h93;
            8'h23: sb=8'h26;
            8'h24: sb=8'h36;
            8'h25: sb=8'h3f;
            8'h26: sb=8'hf7;
            8'h27: sb=8'hcc;
            8'h28: sb=8'h34;
            8'h29: sb=8'ha5;
            8'h2a: sb=8'he5;
            8'h2b: sb=8'hf1;
            8'h2c: sb=8'h71;
            8'h2d: sb=8'hd8;
            8'h2e: sb=8'h31;
            8'h2f: sb=8'h15;
            8'h30: sb=8'h04;
            8'h31: sb=8'hc7;
            8'h32: sb=8'h23;
            8'h33: sb=8'hc3;
            8'h34: sb=8'h18;
            8'h35: sb=8'h96;
            8'h36: sb=8'h05;
            8'h37: sb=8'h9a;
            8'h38: sb=8'h07;
            8'h39: sb=8'h12;
            8'h3a: sb=8'h80;
            8'h3b: sb=8'he2;
            8'h3c: sb=8'heb;
            8'h3d: sb=8'h27;
            8'h3e: sb=8'hb2;
            8'h3f: sb=8'h75;
            8'h40: sb=8'h09;
            8'h41: sb=8'h83;
            8'h42: sb=8'h2c;
            8'h43: sb=8'h1a;
            8'h44: sb=8'h1b;
            8'h45: sb=8'h6e;
            8'h46: sb=8'h5a;
            8'h47: sb=8'ha0;
            8'h48: sb=8'h52;
            8'h49: sb=8'h3b;
            8'h4a: sb=8'hd6;
            8'h4b: sb=8'hb3;
            8'h4c: sb=8'h29;
            8'h4d: sb=8'he3;
            8'h4e: sb=8'h2f;
            8'h4f: sb=8'h84;
            8'h50: sb=8'h53;
            8'h51: sb=8'hd1;
            8'h52: sb=8'h00;
            8'h53: sb=8'hed;
            8'h54: sb=8'h20;
            8'h55: sb=8'hfc;
            8'h56: sb=8'hb1;
            8'h57: sb=8'h5b;
            8'h58: sb=8'h6a;
            8'h59: sb=8'hcb;
            8'h5a: sb=8'hbe;
            8'h5b: sb=8'h39;
            8'h5c: sb=8'h4a;
            8'h5d: sb=8'h4c;
            8'h5e: sb=8'h58;
            8'h5f: sb=8'hcf;
            8'h60: sb=8'hd0;
            8'h61: sb=8'hef;
            8'h62: sb=8'haa;
            8'h63: sb=8'hfb;
            8'h64: sb=8'h43;
            8'h65: sb=8'h4d;
            8'h66: sb=8'h33;
            8'h67: sb=8'h85;
            8'h68: sb=8'h45;
            8'h69: sb=8'hf9;
            8'h6a: sb=8'h02;
            8'h6b: sb=8'h7f;
            8'h6c: sb=8'h50;
            8'h6d: sb=8'h3c;
            8'h6e: sb=8'h9f;
            8'h6f: sb=8'ha8;
            8'h70: sb=8'h51;
            8'h71: sb=8'ha3;
            8'h72: sb=8'h40;
            8'h73: sb=8'h8f;
            8'h74: sb=8'h92;
            8'h75: sb=8'h9d;
            8'h76: sb=8'h38;
            8'h77: sb=8'hf5;
            8'h78: sb=8'hbc;
            8'h79: sb=8'hb6;
            8'h7a: sb=8'hda;
            8'h7b: sb=8'h21;
            8'h7c: sb=8'h10;
            8'h7d: sb=8'hff;
            8'h7e: sb=8'hf3;
            8'h7f: sb=8'hd2;
            8'h80: sb=8'hcd;
            8'h81: sb=8'h0c;
            8'h82: sb=8'h13;
            8'h83: sb=8'hec;
            8'h84: sb=8'h5f;
            8'h85: sb=8'h97;
            8'h86: sb=8'h44;
            8'h87: sb=8'h17;
            8'h88: sb=8'hc4;
            8'h89: sb=8'ha7;
            8'h8a: sb=8'h7e;
            8'h8b: sb=8'h3d;
            8'h8c: sb=8'h64;
            8'h8d: sb=8'h5d;
            8'h8e: sb=8'h19;
            8'h8f: sb=8'h73;
            8'h90: sb=8'h60;
            8'h91: sb=8'h81;
            8'h92: sb=8'h4f;
            8'h93: sb=8'hdc;
            8'h94: sb=8'h22;
            8'h95: sb=8'h2a;
            8'h96: sb=8'h90;
            8'h97: sb=8'h88;
            8'h98: sb=8'h46;
            8'h99: sb=8'hee;
            8'h9a: sb=8'hb8;
            8'h9b: sb=8'h14;
            8'h9c: sb=8'hde;
            8'h9d: sb=8'h5e;
            8'h9e: sb=8'h0b;
            8'h9f: sb=8'hdb;
            8'ha0: sb=8'he0;
            8'ha1: sb=8'h32;
            8'ha2: sb=8'h3a;
            8'ha3: sb=8'h0a;
            8'ha4: sb=8'h49;
            8'ha5: sb=8'h06;
            8'ha6: sb=8'h24;
            8'ha7: sb=8'h5c;
            8'ha8: sb=8'hc2;
            8'ha9: sb=8'hd3;
            8'haa: sb=8'hac;
            8'hab: sb=8'h62;
            8'hac: sb=8'h91;
            8'had: sb=8'h95;
            8'hae: sb=8'he4;
            8'haf: sb=8'h79;
            8'hb0: sb=8'he7;
            8'hb1: sb=8'hc8;
            8'hb2: sb=8'h37;
            8'hb3: sb=8'h6d;
            8'hb4: sb=8'h8d;
            8'hb5: sb=8'hd5;
            8'hb6: sb=8'h4e;
            8'hb7: sb=8'ha9;
            8'hb8: sb=8'h6c;
            8'hb9: sb=8'h56;
            8'hba: sb=8'hf4;
            8'hbb: sb=8'hea;
            8'hbc: sb=8'h65;
            8'hbd: sb=8'h7a;
            8'hbe: sb=8'hae;
            8'hbf: sb=8'h08;
            8'hc0: sb=8'hba;
            8'hc1: sb=8'h78;
            8'hc2: sb=8'h25;
            8'hc3: sb=8'h2e;
            8'hc4: sb=8'h1c;
            8'hc5: sb=8'ha6;
            8'hc6: sb=8'hb4;
            8'hc7: sb=8'hc6;
            8'hc8: sb=8'he8;
            8'hc9: sb=8'hdd;
            8'hca: sb=8'h74;
            8'hcb: sb=8'h1f;
            8'hcc: sb=8'h4b;
            8'hcd: sb=8'hbd;
            8'hce: sb=8'h8b;
            8'hcf: sb=8'h8a;
            8'hd0: sb=8'h70;
            8'hd1: sb=8'h3e;
            8'hd2: sb=8'hb5;
            8'hd3: sb=8'h66;
            8'hd4: sb=8'h48;
            8'hd5: sb=8'h03;
            8'hd6: sb=8'hf6;
            8'hd7: sb=8'h0e;
            8'hd8: sb=8'h61;
            8'hd9: sb=8'h35;
            8'hda: sb=8'h57;
            8'hdb: sb=8'hb9;
            8'hdc: sb=8'h86;
            8'hdd: sb=8'hc1;
            8'hde: sb=8'h1d;
            8'hdf: sb=8'h9e;
            8'he0: sb=8'he1;
            8'he1: sb=8'hf8;
            8'he2: sb=8'h98;
            8'he3: sb=8'h11;
            8'he4: sb=8'h69;
            8'he5: sb=8'hd9;
            8'he6: sb=8'h8e;
            8'he7: sb=8'h94;
            8'he8: sb=8'h9b;
            8'he9: sb=8'h1e;
            8'hea: sb=8'h87;
            8'heb: sb=8'he9;
            8'hec: sb=8'hce;
            8'hed: sb=8'h55;
            8'hee: sb=8'h28;
            8'hef: sb=8'hdf;
            8'hf0: sb=8'h8c;
            8'hf1: sb=8'ha1;
            8'hf2: sb=8'h89;
            8'hf3: sb=8'h0d;
            8'hf4: sb=8'hbf;
            8'hf5: sb=8'he6;
            8'hf6: sb=8'h42;
            8'hf7: sb=8'h68;
            8'hf8: sb=8'h41;
            8'hf9: sb=8'h99;
            8'hfa: sb=8'h2d;
            8'hfb: sb=8'h0f;
            8'hfc: sb=8'hb0;
            8'hfd: sb=8'h54;
            8'hfe: sb=8'hbb;
            8'hff: sb=8'h16;
            default: sb=SBOX[2047-8*int'(x) -: 8];
        endcase
    endfunction
    function automatic [7:0] xt(input [7:0] x);
        xt={x[6:0],1'b0} ^ (x[7] ? 8'h1b : 8'd0);
    endfunction
    function automatic [31:0] subword(input [31:0] x);
        subword={sb(x[31:24]),sb(x[23:16]),sb(x[15:8]),sb(x[7:0])};
    endfunction
    function automatic [1919:0] expand(input [255:0] key);
        reg [31:0] w [0:59];
        reg [31:0] t;
        reg [7:0] rc;
        integer i;
        begin
            rc=8'h01;
            for(i=0;i<8;i=i+1) w[i]=key[255-i*32 -: 32];
            for(i=8;i<60;i=i+1) begin
                t=w[i-1];
                if(i%8==0) begin
                    t=subword({t[23:0],t[31:24]}) ^ {rc,24'd0};
                    rc=xt(rc);
                end else if(i%8==4) t=subword(t);
                w[i]=w[i-8] ^ t;
            end
            for(i=0;i<60;i=i+1) expand[1919-i*32 -: 32]=w[i];
        end
    endfunction
    localparam [1919:0] ROUND_KEYS=expand(KEY);
    function automatic [7:0] batch_key_lut(input integer output_bit,input integer offset);
        integer batch,r;
        begin
            batch_key_lut=8'b0;
            for(batch=0;batch<5;batch=batch+1) begin
                r=1+3*batch+offset;
                // The third key is unused in the final two-round batch.
                if(r>14)r=14;
                batch_key_lut[batch]=ROUND_KEYS[1792-r*128+output_bit];
            end
        end
    endfunction
    function automatic [127:0] mix(input [127:0] state);
        reg [7:0] a,b,c,d;
        integer col;
        begin
            for(col=0;col<4;col=col+1) begin
                {a,b,c,d}=state[127-col*32 -: 32];
                mix[127-col*32 -: 32]={xt(a)^xt(b)^b^c^d,
                    a^xt(b)^xt(c)^c^d,a^b^xt(c)^xt(d)^d,xt(a)^a^b^c^xt(d)};
            end
        end
    endfunction
    logic [127:0] result_q;
    // Private round-batch index, not an externally selectable AES round.
    logic [2:0] round_q;
    wire [127:0] shifted;
    wire accepted_start=start_i && ready_o;
/*
 * AES S-box Boolean circuit, adapted to one-bit SystemVerilog signals from
 * BearSSL br_aes_ct_bitslice_Sbox, src/symcipher/aes_ct.c at commit
 * 5f045c759957fdff8c85716e6af99e10901fdac0.
 * https://www.bearssl.org/gitweb/?p=BearSSL;a=blob;f=src/symcipher/aes_ct.c;hb=5f045c759957fdff8c85716e6af99e10901fdac0
 * The circuit is by Boyar and Peralta, "A new combinational logic
 * minimization technique with applications to cryptology" (2009/191).
 * Only the S-box is adapted; the fixed-key AES controller is unchanged.
 * This combinational hardware is not a power/EM side-channel countermeasure.
 *
 * Copyright (c) 2016 Thomas Pornin <pornin@bolet.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
function automatic [7:0] compact_sb(input [7:0] q);
    reg x0, x1, x2, x3, x4, x5, x6, x7;
    reg y1, y2, y3, y4, y5, y6, y7, y8, y9;
    reg y10, y11, y12, y13, y14, y15, y16, y17, y18, y19;
    reg y20, y21;
    reg z0, z1, z2, z3, z4, z5, z6, z7, z8, z9;
    reg z10, z11, z12, z13, z14, z15, z16, z17;
    reg t0, t1, t2, t3, t4, t5, t6, t7, t8, t9;
    reg t10, t11, t12, t13, t14, t15, t16, t17, t18, t19;
    reg t20, t21, t22, t23, t24, t25, t26, t27, t28, t29;
    reg t30, t31, t32, t33, t34, t35, t36, t37, t38, t39;
    reg t40, t41, t42, t43, t44, t45, t46, t47, t48, t49;
    reg t50, t51, t52, t53, t54, t55, t56, t57, t58, t59;
    reg t60, t61, t62, t63, t64, t65, t66, t67;
    reg s0, s1, s2, s3, s4, s5, s6, s7;
    begin
        // x0/s0 are the high bit; x7/s7 are the low bit.
        x0 = q[7]; x1 = q[6]; x2 = q[5]; x3 = q[4];
        x4 = q[3]; x5 = q[2]; x6 = q[1]; x7 = q[0];

        y14 = x3 ^ x5;
        y13 = x0 ^ x6;
        y9 = x0 ^ x3;
        y8 = x0 ^ x5;
        t0 = x1 ^ x2;
        y1 = t0 ^ x7;
        y4 = y1 ^ x3;
        y12 = y13 ^ y14;
        y2 = y1 ^ x0;
        y5 = y1 ^ x6;
        y3 = y5 ^ y8;
        t1 = x4 ^ y12;
        y15 = t1 ^ x5;
        y20 = t1 ^ x1;
        y6 = y15 ^ x7;
        y10 = y15 ^ t0;
        y11 = y20 ^ y9;
        y7 = x7 ^ y11;
        y17 = y10 ^ y11;
        y19 = y10 ^ y8;
        y16 = t0 ^ y11;
        y21 = y13 ^ y16;
        y18 = x0 ^ y16;

        t2 = y12 & y15;
        t3 = y3 & y6;
        t4 = t3 ^ t2;
        t5 = y4 & x7;
        t6 = t5 ^ t2;
        t7 = y13 & y16;
        t8 = y5 & y1;
        t9 = t8 ^ t7;
        t10 = y2 & y7;
        t11 = t10 ^ t7;
        t12 = y9 & y11;
        t13 = y14 & y17;
        t14 = t13 ^ t12;
        t15 = y8 & y10;
        t16 = t15 ^ t12;
        t17 = t4 ^ t14;
        t18 = t6 ^ t16;
        t19 = t9 ^ t14;
        t20 = t11 ^ t16;
        t21 = t17 ^ y20;
        t22 = t18 ^ y19;
        t23 = t19 ^ y21;
        t24 = t20 ^ y18;
        t25 = t21 ^ t22;
        t26 = t21 & t23;
        t27 = t24 ^ t26;
        t28 = t25 & t27;
        t29 = t28 ^ t22;
        t30 = t23 ^ t24;
        t31 = t22 ^ t26;
        t32 = t31 & t30;
        t33 = t32 ^ t24;
        t34 = t23 ^ t33;
        t35 = t27 ^ t33;
        t36 = t24 & t35;
        t37 = t36 ^ t34;
        t38 = t27 ^ t36;
        t39 = t29 & t38;
        t40 = t25 ^ t39;
        t41 = t40 ^ t37;
        t42 = t29 ^ t33;
        t43 = t29 ^ t40;
        t44 = t33 ^ t37;
        t45 = t42 ^ t41;
        z0 = t44 & y15;
        z1 = t37 & y6;
        z2 = t33 & x7;
        z3 = t43 & y16;
        z4 = t40 & y1;
        z5 = t29 & y7;
        z6 = t42 & y11;
        z7 = t45 & y17;
        z8 = t41 & y10;
        z9 = t44 & y12;
        z10 = t37 & y3;
        z11 = t33 & y4;
        z12 = t43 & y13;
        z13 = t40 & y5;
        z14 = t29 & y2;
        z15 = t42 & y9;
        z16 = t45 & y14;
        z17 = t41 & y8;

        t46 = z15 ^ z16;
        t47 = z10 ^ z11;
        t48 = z5 ^ z13;
        t49 = z9 ^ z10;
        t50 = z2 ^ z12;
        t51 = z2 ^ z5;
        t52 = z7 ^ z8;
        t53 = z0 ^ z3;
        t54 = z6 ^ z7;
        t55 = z16 ^ z17;
        t56 = z12 ^ t48;
        t57 = t50 ^ t53;
        t58 = z4 ^ t46;
        t59 = z3 ^ t54;
        t60 = t46 ^ t57;
        t61 = z14 ^ t57;
        t62 = t52 ^ t58;
        t63 = t49 ^ t58;
        t64 = z4 ^ t59;
        t65 = t61 ^ t62;
        t66 = z1 ^ t63;
        s0 = t59 ^ t63;
        s6 = t56 ^ ~t62;
        s7 = t48 ^ ~t60;
        t67 = t64 ^ t65;
        s3 = t53 ^ t66;
        s4 = t51 ^ t66;
        s5 = t47 ^ t65;
        s1 = t64 ^ ~s3;
        s2 = t55 ^ ~t67;
        compact_sb = {s0,s1,s2,s3,s4,s5,s6,s7};
    end
endfunction

    wire [127:0] selected_round_key;
    for(genvar key_bit=0;key_bit<128;key_bit=key_bit+1) begin: g_batch_key_0
        localparam [7:0] KEY_BITS=batch_key_lut(key_bit,0);
        assign selected_round_key[key_bit]=KEY_BITS[round_q];
    end
    wire [127:0] second_round_key;
    for(genvar key_bit=0;key_bit<128;key_bit=key_bit+1) begin: g_batch_key_1
        localparam [7:0] KEY_BITS=batch_key_lut(key_bit,1);
        assign second_round_key[key_bit]=KEY_BITS[round_q];
    end
    wire [127:0] third_round_key;
    for(genvar key_bit=0;key_bit<128;key_bit=key_bit+1) begin: g_batch_key_2
        localparam [7:0] KEY_BITS=batch_key_lut(key_bit,2);
        assign third_round_key[key_bit]=KEY_BITS[round_q];
    end
    // Batches0..4 start rounds1,4,7,10,13. Only round14 omits MixColumns.
    wire [127:0] first_round=mix(shifted) ^ selected_round_key;
    wire [127:0] second_shifted;
    for(genvar j=0;j<16;j=j+1) begin: g_second_sbox
        localparam integer S=4*(((j/4)+(j%4))%4)+(j%4);
        assign second_shifted[127-j*8 -:8]=compact_sb(first_round[127-S*8 -:8]);
    end
    wire [127:0] second_state=(round_q==3'd4 ? second_shifted : mix(second_shifted)) ^ second_round_key;
    wire [127:0] third_shifted;
    for(genvar j=0;j<16;j=j+1) begin: g_third_sbox
        localparam integer S=4*(((j/4)+(j%4))%4)+(j%4);
        assign third_shifted[127-j*8 -:8]=compact_sb(second_state[127-S*8 -:8]);
    end
    wire [127:0] next_state=round_q==3'd4 ? second_state : mix(third_shifted) ^ third_round_key;
    // The existing synchronous ROM output IS the round-state register.
    // On acceptance, capture SubBytes/ShiftRows of the initial add-key value.
    // Each following edge advances three AES rounds, or two for the final step. Busy input changes
    // cannot enter this feedback path because only accepted_start selects them.
    wire feedback_active=reset_n && !abort_i && KEY_IS_PROVISIONED && busy_o && round_q<3'd4;
    wire [127:0] lookup_state=accepted_start ? (block_i ^ ROUND_KEYS[1919 -: 128]) :
        feedback_active ? next_state : 128'd0;
    // No reset is attached to the read-only DPBs. An inactive/aborted edge
    // flushes their output registers to public SBOX[0]; those registers are
    // never exposed as a result. A new request always overwrites them first.
    for(genvar pair=0;pair<8;pair=pair+1) begin: g_sbox_rom
        localparam integer J0=2*pair,J1=2*pair+1;
        localparam integer S0=4*(((J0/4)+(J0%4))%4)+(J0%4);
        localparam integer S1=4*(((J1/4)+(J1%4))%4)+(J1%4);
        tang_private_aes_sbox_rom2 u_rom (
            .clk(clk),
            .address_a_i(lookup_state[127-S0*8 -: 8]),
            .address_b_i(lookup_state[127-S1*8 -: 8]),
            .value_a_o(shifted[127-J0*8 -: 8]),
            .value_b_o(shifted[127-J1*8 -: 8]));
    end
    assign ready_o=KEY_IS_PROVISIONED && reset_n && !abort_i && !busy_o;
    assign block_o=done_o && reset_n && !abort_i ? result_q : 128'd0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            result_q<=0;round_q<=0;busy_o<=0;done_o<=0;
        end else if(abort_i || !KEY_IS_PROVISIONED) begin
            result_q<=0;round_q<=0;busy_o<=0;done_o<=0;
        end else begin
            done_o<=0;
            if(accepted_start) begin
                
                round_q<=0;busy_o<=1;result_q<=0;
            end else if(busy_o) begin
                if(round_q==3'd4) begin
                    result_q<=next_state;round_q<=0;busy_o<=0;done_o<=1;
                end else round_q<=round_q+3'd1;
            end
        end
    end

endmodule
`default_nettype wire

// One actual dual-port BSRAM, permanently read-only; no extra pipeline.
module tang_private_aes_sbox_rom2 (
    input wire clk,
    input wire [7:0] address_a_i,address_b_i,
    output wire [7:0] value_a_o,value_b_o
);
    wire [15:0] data_a,data_b;
    assign value_a_o=data_a[7:0];
    assign value_b_o=data_b[7:0];
    DPB #(.READ_MODE0(1'b0),.READ_MODE1(1'b0),
        .BIT_WIDTH_0(8),.BIT_WIDTH_1(8),.BLK_SEL_0(3'd0),.BLK_SEL_1(3'd0),
        .INIT_RAM_00(256'hc072a49cafa2d4adf04759fa7dc982ca76abd7fe2b670130c56f6bf27b777c63),
        .INIT_RAM_01(256'h75b227ebe28012079a059618c323c7041531d871f1e5a534ccf73f362693fdb7),
        .INIT_RAM_02(256'hcf584c4a39becb6a5bb1fc20ed00d153842fe329b3d63b52a05a6e1b1a2c8309),
        .INIT_RAM_03(256'hd2f3ff1021dab6bcf5389d928f40a351a89f3c507f02f94585334d43fbaaefd0),
        .INIT_RAM_04(256'hdb0b5ede14b8ee4688902a22dc4f816073195d643d7ea7c41744975fec130ccd),
        .INIT_RAM_05(256'h08ae7a65eaf4566ca94ed58d6d37c8e779e4959162acd3c25c2406490a3a32e0),
        .INIT_RAM_06(256'h9e1dc186b95735610ef6034866b53e708a8bbd4b1f74dde8c6b4a61c2e2578ba),
        .INIT_RAM_07(256'h16bb54b00f2d99416842e6bf0d89a18cdf2855cee9871e9b948ed9691198f8e1)) u_table (
        .DOA(data_a),.DOB(data_b),.DIA(16'd0),.DIB(16'd0),
        .BLKSELA(3'd0),.BLKSELB(3'd0),
        .ADA({3'd0,address_a_i,3'd0}),.ADB({3'd0,address_b_i,3'd0}),
        .WREA(1'b0),.WREB(1'b0),.CLKA(clk),.CLKB(clk),
        .CEA(1'b1),.CEB(1'b1),.OCEA(1'b1),.OCEB(1'b1),
        .RESETA(1'b0),.RESETB(1'b0));
endmodule
