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

// Serial column AES: private request identity remains latched until completion/abort.
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

    function automatic [64-1:0] column_key_lut(input integer output_bit);
        integer r,c;
        begin
            column_key_lut='0;
            for(r=0;r<15;r=r+1) for(c=0;c<4;c=c+1) begin
                column_key_lut[r*4+c]=ROUND_KEYS[1792-r*128+(3-c)*32+output_bit];
            end
        end
    endfunction

    localparam [1:0] CAP_FIRST=0,COMMIT_COLUMN=1,LOAD_FIRST=2;
    logic [127:0] state_q,result_q;
    logic [95:0] prefix_q;
    logic [15:0] first_pair_q;
    logic [3:0] round_q;
    logic [1:0] column_q,phase_q;
    wire accepted_start=start_i && ready_o;
    wire [127:0] initial_state=block_i ^ ROUND_KEYS[1919-:128];
    wire lookup_live=KEY_IS_PROVISIONED && reset_n && !abort_i && (accepted_start || busy_o);
    wire [127:0] lookup_state=accepted_start ? initial_state : state_q;
    wire [1:0] lookup_column=accepted_start ? 2'd0 :
        (phase_q==COMMIT_COLUMN && column_q!=3 ? column_q+2'd1 : column_q);
    wire second_pair=!accepted_start && phase_q==CAP_FIRST;
    function automatic [7:0] shifted_byte(input [127:0] value,input [1:0] col,input [1:0] row);
        reg [1:0] source_col;
        reg [3:0] index;
        begin
            source_col=col+row;index={source_col,row};
            shifted_byte=value[127-int'(index)*8-:8];
        end
    endfunction
    wire [7:0] address_a=lookup_live ? shifted_byte(lookup_state,lookup_column,second_pair ? 2'd2 : 2'd0) : 8'd0;
    wire [7:0] address_b=lookup_live ? shifted_byte(lookup_state,lookup_column,second_pair ? 2'd3 : 2'd1) : 8'd0;
    wire [7:0] sb_a,sb_b;
    tang_private_aes_sbox_rom2 u_sbox_rom(.clk(clk),.address_a_i(address_a),.address_b_i(address_b),.value_a_o(sb_a),.value_b_o(sb_b));
    wire [31:0] substituted_column={first_pair_q,sb_a,sb_b};
    wire [127:0] mixed_expanded=mix({substituted_column,96'd0});
    wire [31:0] selected_key;
    for(genvar bit_index=0;bit_index<32;bit_index=bit_index+1) begin:g_key
        localparam [64-1:0] BITS=column_key_lut(bit_index);
        assign selected_key[bit_index]=BITS[{round_q,column_q}];
    end
    wire [31:0] next_column=(round_q==14 ? substituted_column : mixed_expanded[127:96]) ^ selected_key;
    wire [127:0] next_state={prefix_q,next_column};
    assign ready_o=KEY_IS_PROVISIONED && reset_n && !abort_i && !busy_o;
    assign block_o=done_o && reset_n && !abort_i ? result_q : 128'd0;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            state_q<=0;result_q<=0;prefix_q<=0;first_pair_q<=0;round_q<=0;column_q<=0;phase_q<=LOAD_FIRST;busy_o<=0;done_o<=0;
        end else if(abort_i || !KEY_IS_PROVISIONED) begin
            state_q<=0;result_q<=0;prefix_q<=0;first_pair_q<=0;round_q<=0;column_q<=0;phase_q<=LOAD_FIRST;busy_o<=0;done_o<=0;
        end else begin
            done_o<=0;
            if(accepted_start) begin
                state_q<=initial_state;result_q<=0;prefix_q<=0;first_pair_q<=0;
                round_q<=1;column_q<=0;phase_q<=CAP_FIRST;busy_o<=1;
            end else if(busy_o) begin
                case(phase_q)
                    LOAD_FIRST:phase_q<=CAP_FIRST;
                    CAP_FIRST:begin first_pair_q<={sb_a,sb_b};phase_q<=COMMIT_COLUMN;end
                    COMMIT_COLUMN:begin
                        if(column_q!=3) begin prefix_q<={prefix_q[63:0],next_column};column_q<=column_q+2'd1;phase_q<=CAP_FIRST;end
                        else begin
                            state_q<=next_state;column_q<=0;prefix_q<=0;phase_q<=LOAD_FIRST;
                            if(round_q==14) begin result_q<=next_state;round_q<=0;busy_o<=0;done_o<=1;end
                            else round_q<=round_q+1'b1;
                        end
                    end
                    default:begin state_q<=0;result_q<=0;busy_o<=0;done_o<=0;end
                endcase
            end
        end
    end
endmodule
`default_nettype wire

