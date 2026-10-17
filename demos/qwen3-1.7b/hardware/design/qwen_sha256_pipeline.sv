// PRIVATE SHA-256 compression pipeline for the model/KV integrity machinery.
// Equations/constants: RFC 6234 sections 5.1 and 6.2. This is compression only:
// the private controller owns message framing, padding and chaining states.
// None of the ports is an application interface or a host hash service.
//
// 64 spatial round stages plus a registered private result FIFO. One independent
// block may be accepted per clock. A single message still has a chaining
// dependency; a page scheduler must interleave independent chunks/messages.
// Carry-save reduction leaves one carry-propagating add for each round result.
//
// The credit limit bounds ALL accepted-but-unconsumed jobs, including pipeline,
// FIFO and output register. The rounds never depend on downstream ready, so a
// stalled consumer cannot create a chip-wide combinational clock-enable path.
// Reset/CLEAR invalidate control state, not bulk register/RAM contents.
module qwen_sha256_pipeline #(
    parameter integer TAG_BITS=16
) (
    input wire clk,input wire rst_n,input wire clear,
    input wire in_valid,output wire in_ready,
    input wire [511:0] block_data, // first message byte is [511:504]
    input wire [255:0] initial_state, // H0 is [255:224]
    input wire [TAG_BITS-1:0] in_tag,
    output wire out_valid,input wire out_ready,
    output wire [255:0] final_state,
    output wire [TAG_BITS-1:0] out_tag,
    output wire busy
);
    localparam integer FIFO_DEPTH=128;
    localparam [2047:0] K={
        32'h428a2f98,32'h71374491,32'hb5c0fbcf,32'he9b5dba5,
        32'h3956c25b,32'h59f111f1,32'h923f82a4,32'hab1c5ed5,
        32'hd807aa98,32'h12835b01,32'h243185be,32'h550c7dc3,
        32'h72be5d74,32'h80deb1fe,32'h9bdc06a7,32'hc19bf174,
        32'he49b69c1,32'hefbe4786,32'h0fc19dc6,32'h240ca1cc,
        32'h2de92c6f,32'h4a7484aa,32'h5cb0a9dc,32'h76f988da,
        32'h983e5152,32'ha831c66d,32'hb00327c8,32'hbf597fc7,
        32'hc6e00bf3,32'hd5a79147,32'h06ca6351,32'h14292967,
        32'h27b70a85,32'h2e1b2138,32'h4d2c6dfc,32'h53380d13,
        32'h650a7354,32'h766a0abb,32'h81c2c92e,32'h92722c85,
        32'ha2bfe8a1,32'ha81a664b,32'hc24b8b70,32'hc76c51a3,
        32'hd192e819,32'hd6990624,32'hf40e3585,32'h106aa070,
        32'h19a4c116,32'h1e376c08,32'h2748774c,32'h34b0bcb5,
        32'h391c0cb3,32'h4ed8aa4a,32'h5b9cca4f,32'h682e6ff3,
        32'h748f82ee,32'h78a5636f,32'h84c87814,32'h8cc70208,
        32'h90befffa,32'ha4506ceb,32'hbef9a3f7,32'hc67178f2};
    function automatic [31:0] rotate(input [31:0] x,input integer n);
        rotate=(x>>n)|(x<<(32-n));
    endfunction
    function automatic [31:0] sum3(input [31:0] a,b,c);
        sum3=a^b^c;
    endfunction
    function automatic [31:0] carry3(input [31:0] a,b,c);
        carry3=((a&b)|(a&c)|(b&c))<<1;
    endfunction

    reg [63:0] valid;
    reg [7:0] outstanding,fifo_count;
    reg [6:0] read_pointer,write_pointer;
    reg output_valid,ram_valid,buffer_valid;
    reg [255+TAG_BITS:0] output_word;
    reg [255+TAG_BITS:0] ram_word,buffer_word;
    wire alive=rst_n && !clear;
    wire output_take=out_valid && out_ready;
    assign in_ready=alive && (outstanding<8'd128 || output_take);
    wire input_take=in_valid && in_ready;
    assign out_valid=alive && output_valid;
    assign final_state=output_word[255:0];
    assign out_tag=output_word[255+TAG_BITS:256];
    assign busy=alive && outstanding!=0;
    wire [255:0] working [0:63],origin [0:63];
    wire [511:0] words [0:63];
    wire [TAG_BITS-1:0] tags [0:63];

    initial if(TAG_BITS<1 || TAG_BITS>64) $fatal(1,"Invalid private SHA tag width");
    genvar round,word_index;
    generate for(round=0;round<64;round=round+1) begin:rounds
        wire [255:0] before_state,original;
        wire [511:0] schedule;
        wire [TAG_BITS-1:0] tag;
        wire take;
        if(round==0) begin:first
            assign before_state=initial_state;assign original=initial_state;
            assign schedule=block_data;assign tag=in_tag;
            // PRIVATE_SHA_FIRST_CAPTURE112: refresh invalid payload freely.
            // valid[0] still records input_take, including reset/CLEAR/credit checks.
            // The next round consumes this payload only when that bit is valid.
            assign take=1'b1;
        end else begin:later
            assign before_state=working[round-1];assign original=origin[round-1];
            assign schedule=words[round-1];assign tag=tags[round-1];assign take=valid[round-1];
        end
        wire [31:0] a=before_state[255:224],b=before_state[223:192],c=before_state[191:160],d=before_state[159:128];
        wire [31:0] e=before_state[127:96],f=before_state[95:64],g=before_state[63:32],h=before_state[31:0];
        wire [31:0] s1=rotate(e,6)^rotate(e,11)^rotate(e,25);
        wire [31:0] s0=rotate(a,2)^rotate(a,13)^rotate(a,22);
        wire [31:0] choose=(e&f)^(~e&g),majority=(a&b)^(a&c)^(b&c);
        wire [31:0] constant_word=K[2047-round*32 -:32];
        wire [31:0] message_word=schedule[511:480];
        // Common T1 sum reduced to two words, modulo 2^32.
        wire [31:0] t0s=sum3(h,s1,choose),t0c=carry3(h,s1,choose);
        wire [31:0] t1s=sum3(t0s,t0c,constant_word),t1c=carry3(t0s,t0c,constant_word);
        wire [31:0] t2s=sum3(t1s,t1c,message_word),t2c=carry3(t1s,t1c,message_word);
        wire [31:0] as0=sum3(t2s,t2c,s0),ac0=carry3(t2s,t2c,s0);
        wire [31:0] next_a=sum3(as0,ac0,majority)+carry3(as0,ac0,majority);
        wire [31:0] next_e=sum3(t2s,t2c,d)+carry3(t2s,t2c,d);
        wire [31:0] future_word;
        if(round<48) begin:extend
            wire [31:0] w0=schedule[511:480],w1=schedule[479:448],w9=schedule[223:192],w14=schedule[63:32];
            wire [31:0] small0=rotate(w1,7)^rotate(w1,18)^(w1>>3);
            wire [31:0] small1=rotate(w14,17)^rotate(w14,19)^(w14>>10);
            wire [31:0] ws=sum3(small1,w9,small0),wc=carry3(small1,w9,small0);
            assign future_word=sum3(ws,wc,w0)+carry3(ws,wc,w0);
        end else begin:no_unused_schedule
            assign future_word=0;
        end
        reg [255:0] state_reg,origin_reg;
        reg [511:0] schedule_reg;
        reg [TAG_BITS-1:0] tag_reg;
        always @(posedge clk) if(take) begin
            state_reg<={next_a,a,b,c,next_e,e,f,g};origin_reg<=original;
            schedule_reg<={schedule[479:0],future_word};tag_reg<=tag;
        end
        assign working[round]=state_reg;assign origin[round]=origin_reg;
        assign words[round]=schedule_reg;assign tags[round]=tag_reg;
    end endgenerate
    wire [255:0] digest;
    generate for(word_index=0;word_index<8;word_index=word_index+1) begin:feedforward
        assign digest[255-word_index*32 -:32]=working[63][255-word_index*32 -:32]+origin[63][255-word_index*32 -:32];
    end endgenerate
    (* ram_style="block" *) reg [255+TAG_BITS:0] fifo [0:FIFO_DEPTH-1];
    wire produce=alive && valid[63];
    wire advance_output=alive && (!output_valid || out_ready);
    // The synchronous RAM read and consumer register are separate
    // elastic slots. Both hold under backpressure; credits still count
    // every accepted job until its externally observed consumption.
    // Three elastic slots: synchronous RAM read, optional RAM output
    // register, and the intended independently placeable consumer FFs.
    // The native map, not this source comment, establishes realization.
    wire advance_buffer=alive && (!buffer_valid || advance_output);
    wire advance_ram=alive && (!ram_valid || advance_buffer);
    wire fetch=advance_ram && fifo_count!=0;
    always @(posedge clk) if(alive) begin
        if(produce) fifo[write_pointer]<={tags[63],digest};
        if(fetch) ram_word<=fifo[read_pointer];
        if(advance_buffer && ram_valid) buffer_word<=ram_word;
        if(advance_output && buffer_valid) output_word<=buffer_word;
    end
    always @(posedge clk) begin
        if(!rst_n || clear) begin
            valid<=0;outstanding<=0;fifo_count<=0;read_pointer<=0;write_pointer<=0;output_valid<=0;ram_valid<=0;buffer_valid<=0;
        end else begin
            valid<={valid[62:0],input_take};
            case({input_take,output_take})
                2'b10:outstanding<=outstanding+1'b1;
                2'b01:outstanding<=outstanding-1'b1;
                default:begin end
            endcase
            case({produce,fetch})
                2'b10:fifo_count<=fifo_count+1'b1;
                2'b01:fifo_count<=fifo_count-1'b1;
                default:begin end
            endcase
            if(produce) write_pointer<=write_pointer+1'b1;
            if(fetch) read_pointer<=read_pointer+1'b1;
            if(advance_ram) ram_valid<=fetch;
            if(advance_buffer) buffer_valid<=ram_valid;
            if(advance_output) output_valid<=buffer_valid;
        end
    end
endmodule
