`timescale 1ns/1ps
`default_nettype none

// All memories in this milestone have one registered synchronous read port
// and one clocked write port.  Addresses are generated only by the enclosing
// fixed attention FSM; none is exposed at the product boundary.
module board1_context2048_attention_vector256x16 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [7:0]              read_address_i,
    output logic signed [15:0]     read_data_o,
    input  wire                    write_enable_i,
    input  wire [7:0]              write_address_i,
    input  wire signed [15:0]      write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic signed [15:0] payload_mem [0:255];

    always_ff @(posedge clk) begin
        if (write_enable_i)
            payload_mem[write_address_i] <= write_data_i;
        if (read_enable_i)
            read_data_o <= payload_mem[read_address_i];
    end
endmodule

// Eight independently written coordinate banks. A score beat reads adjacent
// coordinates in parallel; scalar query upload keeps its original interface.
module board1_context2048_attention_query8 (
    input wire clk, read_enable_i,
    input wire [4:0] read_address_i,
    output wire [127:0] read_data_o,
    input wire write_enable_i,
    input wire [7:0] write_address_i,
    input wire signed [15:0] write_data_i
);
    genvar lane;
    generate for (lane=0;lane<8;lane=lane+1) begin : g_bank
        (* ram_style="block", syn_ramstyle="block_ram" *)
        logic [15:0] payload_mem [0:31];
        logic [15:0] read_q;
        assign read_data_o[lane*16 +:16]=read_q;
        always_ff @(posedge clk) begin
            if (write_enable_i && write_address_i[2:0]==lane)
                payload_mem[write_address_i[7:3]]<=write_data_i;
            if (read_enable_i) read_q<=payload_mem[read_address_i];
        end
    end endgenerate
endmodule

// Exact prefix sufficient statistic for the original V exponent scan.
// This is a private observer of accepted staging/commit transactions. It has
// no memory-request capability. Pending data never change committed history.
module board1_attention_value_fit_prefix (
    input wire clk, rst_n, clear_i, model_lock_i, upstream_fault_i,
    input wire stage_begin_i, stage_value_valid_i,
    input wire [2:0] layer_i,
    input wire [10:0] position_i,
    input wire [6:0] coordinate_i,
    input wire signed [15:0] value_i,
    input wire signed [7:0] exponent_i,
    input wire pending_complete_i, read_i, commit_i,
    output wire read_valid_o,
    output wire signed [7:0] exponent0_o, exponent1_o,
    output logic fault_o
);
    logic [11:0] prefix_q [0:5];
    logic signed [7:0] maximum_q [0:5][0:1];
    logic nonzero_q [0:5][0:1];
    logic signed [7:0] pending_max_q [0:1];
    logic pending_nonzero_q [0:1];
    logic [2:0] pending_layer_q;
    logic [10:0] pending_position_q;
    logic signed [7:0] pending_exponent_q;
    logic [6:0] next_coordinate_q;
    logic staging_q, pending_valid_q, consumed_q, lock_seen_q;
    integer l,h;
    function automatic signed [7:0] first_fit(input signed [15:0] v,
                                             input signed [7:0] e);
        reg [15:0] magnitude; integer bits_needed,b,required;
        begin
            magnitude=v[15] ? $unsigned(-v) : $unsigned(v);
            bits_needed=0;
            for(b=0;b<15;b=b+1) if(magnitude[b])bits_needed=b+1;
            required=$signed(e)+bits_needed-15;
            if(v==0 || required < -32)first_fit=-8'sd32;
            else if(required>31)first_fit=8'sd31;
            else first_fit=required;
        end
    endfunction
    wire layer_legal=layer_i<6;
    wire tuple_matches=layer_legal && pending_layer_q==layer_i &&
        pending_position_q==position_i && prefix_q[layer_i]=={1'b0,position_i};
    wire pending_owned=pending_valid_q && tuple_matches && pending_complete_i;
    assign read_valid_o=rst_n && !clear_i && model_lock_i && !fault_o &&
        !upstream_fault_i && pending_owned && !consumed_q;
    wire signed [7:0] fit=first_fit(value_i,exponent_i);
    wire signed [7:0] combined0=(maximum_q[layer_i][0]>pending_max_q[0]) ?
        maximum_q[layer_i][0] : pending_max_q[0];
    wire signed [7:0] combined1=(maximum_q[layer_i][1]>pending_max_q[1]) ?
        maximum_q[layer_i][1] : pending_max_q[1];
    assign exponent0_o=(nonzero_q[layer_i][0] || pending_nonzero_q[0]) ? combined0 : 8'sd0;
    assign exponent1_o=(nonzero_q[layer_i][1] || pending_nonzero_q[1]) ? combined1 : 8'sd0;
    wire stage_bad=stage_begin_i && (!layer_legal || staging_q || pending_valid_q ||
        prefix_q[layer_i]!={1'b0,position_i} || exponent_i < -32 || exponent_i >31);
    wire value_bad=stage_value_valid_i && (!staging_q || !tuple_matches ||
        coordinate_i!=next_coordinate_q || exponent_i!=pending_exponent_q ||
        value_i==-16'sd32768);
    wire read_bad=read_i && !read_valid_o;
    wire commit_bad=commit_i && (!pending_owned || !consumed_q || staging_q);
    wire event_collision=(stage_begin_i && (stage_value_valid_i || read_i || commit_i)) ||
        (stage_value_valid_i && (read_i || commit_i)) || (read_i && commit_i);
    logic unknown_event;
    always_comb begin
        unknown_event=1'b0;
`ifndef SYNTHESIS
        if((^{stage_begin_i,stage_value_valid_i,read_i,commit_i,
               pending_complete_i,model_lock_i,upstream_fault_i})===1'bx)unknown_event=1'b1;
        if(stage_begin_i || stage_value_valid_i || read_i || commit_i)
            if((^{layer_i,position_i,coordinate_i,value_i,exponent_i})===1'bx)unknown_event=1'b1;
`endif
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n)begin
            fault_o<=0;lock_seen_q<=0;staging_q<=0;pending_valid_q<=0;consumed_q<=0;
            next_coordinate_q<=0;pending_layer_q<=0;pending_position_q<=0;pending_exponent_q<=0;
            for(l=0;l<6;l=l+1)begin
                prefix_q[l]<=0;
                for(h=0;h<2;h=h+1)begin maximum_q[l][h]<=-32;nonzero_q[l][h]<=0;end
            end
            for(h=0;h<2;h=h+1)begin pending_max_q[h]<=-32;pending_nonzero_q[h]<=0;end
        end else begin
            if(model_lock_i)lock_seen_q<=1;
            if(upstream_fault_i || (lock_seen_q && !model_lock_i) || unknown_event ||
               (!clear_i && (stage_bad || value_bad || read_bad || commit_bad || event_collision)))fault_o<=1;
            if(clear_i)begin
                staging_q<=0;pending_valid_q<=0;consumed_q<=0;next_coordinate_q<=0;
                for(l=0;l<6;l=l+1)begin
                    prefix_q[l]<=0;
                    for(h=0;h<2;h=h+1)begin maximum_q[l][h]<=-32;nonzero_q[l][h]<=0;end
                end
            end else if(!fault_o && !upstream_fault_i && model_lock_i && !unknown_event &&
                        !stage_bad && !value_bad && !read_bad && !commit_bad && !event_collision)begin
                if(stage_begin_i)begin
                    pending_layer_q<=layer_i;pending_position_q<=position_i;
                    pending_exponent_q<=exponent_i;next_coordinate_q<=0;staging_q<=1;consumed_q<=0;
                    for(h=0;h<2;h=h+1)begin pending_max_q[h]<=-32;pending_nonzero_q[h]<=0;end
                end
                if(stage_value_valid_i)begin
                    if(fit>pending_max_q[coordinate_i[6]])pending_max_q[coordinate_i[6]]<=fit;
                    if(value_i!=0)pending_nonzero_q[coordinate_i[6]]<=1;
                    if(coordinate_i==127)begin staging_q<=0;pending_valid_q<=1;end
                    else next_coordinate_q<=next_coordinate_q+1'b1;
                end
                if(read_i)consumed_q<=1;
                if(commit_i)begin
                    maximum_q[layer_i][0]<=combined0;maximum_q[layer_i][1]<=combined1;
                    nonzero_q[layer_i][0]<=nonzero_q[layer_i][0] || pending_nonzero_q[0];
                    nonzero_q[layer_i][1]<=nonzero_q[layer_i][1] || pending_nonzero_q[1];
                    prefix_q[layer_i]<=prefix_q[layer_i]+1'b1;
                    pending_valid_q<=0;consumed_q<=0;
                end
            end
        end
    end
endmodule

// The output store is deliberately 18 bits wide.  A head result first uses
// signed bits [16:0].  Global normalization later overwrites that same address
// with a sign-extended signed-16 result; no raw-output side array remains.
module board1_context2048_attention_vector256x18 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [7:0]              read_address_i,
    output logic signed [17:0]     read_data_o,
    input  wire                    write_enable_i,
    input  wire [7:0]              write_address_i,
    input  wire signed [17:0]      write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic signed [17:0] payload_mem [0:255];

    always_ff @(posedge clk) begin
        if (write_enable_i)
            payload_mem[write_address_i] <= write_data_i;
        if (read_enable_i)
            read_data_o <= payload_mem[read_address_i];
    end
endmodule

// Three physical 8192x18 banks hold four independent 45-bit score workspaces.
// The two high address bits select the query head; the low11 select context.  Every phase
// rewrites all banks together, which gives each bank exactly one syntactic
// write port.  Reads are registered.  The controller never asserts read and
// write together, so behavior does not depend on a device's read-during-write
// mode.
module board1_context2048_attention_workspace3x18 (
    input  wire                    clk,
    input  wire                    read_enable_i,
    input  wire [12:0]             read_address_i,
    output logic [17:0]            bank0_read_data_o,
    output logic [17:0]            bank1_read_data_o,
    output logic [17:0]            bank2_read_data_o,
    input  wire                    write_enable_i,
    input  wire [12:0]             write_address_i,
    input  wire [17:0]             bank0_write_data_i,
    input  wire [17:0]             bank1_write_data_i,
    input  wire [17:0]             bank2_write_data_i
);
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank0_mem [0:8191];
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank1_mem [0:8191];
    (* ram_style = "block", syn_ramstyle = "block_ram" *)
    logic [17:0] bank2_mem [0:8191];

    always_ff @(posedge clk) begin
        if (write_enable_i) begin
            bank0_mem[write_address_i] <= bank0_write_data_i;
            bank1_mem[write_address_i] <= bank1_write_data_i;
            bank2_mem[write_address_i] <= bank2_write_data_i;
        end
        if (read_enable_i) begin
            bank0_read_data_o <= bank0_mem[read_address_i];
            bank1_read_data_o <= bank1_mem[read_address_i];
            bank2_read_data_o <= bank2_mem[read_address_i];
        end
    end

`ifndef SYNTHESIS
    always_ff @(posedge clk) begin
        if (read_enable_i && write_enable_i)
            $fatal(1,
                "workspace BSRAM read/write overlap: implementation must not depend on read-during-write behavior");
    end
`endif
endmodule

`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Eight resetless payload banks, exactly one synchronous read and one write
// per bank. The parent supplies only a derived {query_head,coordinate_group}.
// Registered tags are control, never an asynchronous second payload port.
module board1_context2048_attention_accumulator8(
    input wire clk,rst_n,clear_i,
    input wire read_enable_i,
    input wire [4:0] read_address_i,
    output wire [303:0] read_data_o,
    output wire read_valid_o,
    output logic [4:0] read_tag_o,
    output logic fault_o,
    input wire write_enable_i,
    input wire [4:0] write_address_i,
    input wire [303:0] write_data_i
);
    wire collision=read_enable_i && write_enable_i && read_address_i==write_address_i;
    logic unknown_access;
    always_comb begin
        unknown_access=1'b0;
`ifndef SYNTHESIS
        if((^{read_enable_i,write_enable_i})===1'bx)unknown_access=1'b1;
        if(read_enable_i && (^read_address_i===1'bx))unknown_access=1'b1;
        if(write_enable_i && (^{write_address_i,write_data_i}===1'bx))unknown_access=1'b1;
`endif
    end
    wire do_read=rst_n && !clear_i && !fault_o && !collision && !unknown_access && read_enable_i;
    wire do_write=rst_n && !clear_i && !fault_o && !collision && !unknown_access && write_enable_i;
    logic read_valid_q;
    assign read_valid_o=rst_n && !clear_i && !fault_o && read_valid_q;
    genvar lane;
    generate for(lane=0;lane<8;lane=lane+1)begin:g_bank
        (* ram_style="block",syn_ramstyle="block_ram" *)
        logic [37:0] payload_mem [0:31];
        logic [37:0] read_q;
        assign read_data_o[lane*38 +:38]=read_q;
        always_ff @(posedge clk)begin
            if(do_write)payload_mem[write_address_i]<=write_data_i[lane*38 +:38];
            if(do_read)read_q<=payload_mem[read_address_i];
        end
    end endgenerate
    always_ff @(posedge clk or negedge rst_n)begin
        if(!rst_n)begin read_valid_q<=0;read_tag_o<=0;fault_o<=0;end
        else if(clear_i)read_valid_q<=0;
        else if(fault_o || collision || unknown_access)begin
            read_valid_q<=0;
            if(collision || unknown_access)fault_o<=1;
        end else if(do_read)begin read_valid_q<=1;read_tag_o<=read_address_i;end
        else if(do_write && read_valid_q && write_address_i==read_tag_o)read_valid_q<=0;
    end
endmodule
`default_nettype wire
