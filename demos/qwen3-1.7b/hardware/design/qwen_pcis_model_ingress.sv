// Restricted startup-only PCIS receiver, in the shell clock domain.
// The 4 KiB aperture is a rolling sequential stream, NOT an HBM address window.
// A host sends exactly IMAGE_BYTES, at offset received_bytes modulo 4096.
// Contiguous byte enables pack partial stores; no gaps, rewrites, or reordering.
// AW/W are independently buffered. AXI B acknowledges ingress, NOT model_ready.
// Every PCIS read returns zero/DECERR. No CLEAR, model selector, expected hash,
// host-selected memory address, or readback of accepted data exists here.
//
// Reserve worst-case complete-block capacity at AW acceptance. Writes without
// credits are promptly drained/rejected and latch error until fabric reset.
// The caller exposes credit_blocks/received_bytes/error through read-only OCL
// status: AWS does not propagate BRESP failures as PCIe errors to the host.
// rst_n must have synchronized release in clk; loader_* are shell-synchronous.
module qwen_pcis_model_ingress #(
    parameter [31:0] IMAGE_BYTES=32'd2354380800,
    parameter integer BLOCK_ADDRESS_BITS=8
) (
    input wire clk,input wire rst_n,
    input wire [63:0] pcis_awaddr,input wire [5:0] pcis_awid,
    input wire [7:0] pcis_awlen,input wire [2:0] pcis_awsize,
    input wire pcis_awvalid,output wire pcis_awready,
    input wire [511:0] pcis_wdata,input wire [63:0] pcis_wstrb,
    input wire pcis_wlast,input wire pcis_wvalid,output wire pcis_wready,
    output wire [5:0] pcis_bid,output wire [1:0] pcis_bresp,
    output wire pcis_bvalid,input wire pcis_bready,
    input wire [63:0] pcis_araddr,input wire [5:0] pcis_arid,
    input wire [7:0] pcis_arlen,input wire [2:0] pcis_arsize,
    input wire pcis_arvalid,output wire pcis_arready,
    output wire [511:0] pcis_rdata,output wire [5:0] pcis_rid,
    output wire [1:0] pcis_rresp,output wire pcis_rlast,
    output wire pcis_rvalid,input wire pcis_rready,
    input wire loader_ready,input wire loader_error,
    output reg error,output wire [15:0] credit_blocks,output reg [31:0] received_bytes,
    output wire stream_valid,input wire stream_ready,
    output wire [511:0] stream_data,output wire stream_last
);
    localparam integer DEPTH=1<<BLOCK_ADDRESS_BITS;
    localparam integer COUNT_BITS=BLOCK_ADDRESS_BITS+1;
    // 32 write transactions, independently queued write data and responses.
    // A sender that withholds AW indefinitely can fill the W queue; that is
    // not a wait for SHA/HBM. Primed queued traffic retires one beat per clock.
    (* ram_style="distributed" *) reg [81:0] aw_memory [0:31];
    (* ram_style="distributed" *) reg [590:0] w_memory [0:63];
    (* ram_style="distributed" *) reg [7:0] b_memory [0:31];
    (* ram_style="distributed" *) reg [13:0] ar_memory [0:31];
    reg [4:0] aw_write,aw_read,b_write,b_read,ar_write,ar_read;
    reg [5:0] w_write,w_read;
    reg [5:0] aw_count,b_count,ar_count,outstanding_writes;
    reg [6:0] w_count;
    reg [7:0] write_beat,read_beat;
    reg transaction_error;
    reg [COUNT_BITS-1:0] reserved_blocks,block_count;
    reg [BLOCK_ADDRESS_BITS-1:0] block_write,block_read;
    (* ram_style="block" *) reg [512:0] blocks [0:DEPTH-1];
    reg [511:0] partial_block;
    // Count reserves all four slots, including both private read stages.
    reg [512:0] block_read_data_q;
    reg block_read_pending_q;
    // HOST_BLOCK_READ_STAGE: private unreset BRAM-output pipeline.
    reg [512:0] block_output_data_q;
    reg block_output_pending_q;
    reg [1:0] block_output_slot_q;
    reg [1:0] output_write_q,output_read_q,block_return_slot_q;
    reg [2:0] output_count_q;
    reg [3:0] output_slots_valid_q;
    reg [512:0] output_slots_q[0:3];
    wire [512:0] output_block=output_slots_q[output_read_q];
    wire output_valid=output_slots_valid_q[output_read_q];
    wire output_take=rst_n && output_valid && stream_ready;


    initial if(IMAGE_BYTES==0 || IMAGE_BYTES[5:0]!=0 || BLOCK_ADDRESS_BITS<8 || BLOCK_ADDRESS_BITS>12)
        $fatal(1,"Invalid fixed-model ingress geometry");

    wire [COUNT_BITS-1:0] free_blocks=COUNT_BITS'(DEPTH)-block_count-reserved_blocks;
    assign credit_blocks=(rst_n && !error && !loader_error && !loader_ready && received_bytes<IMAGE_BYTES)
        ? 16'(free_blocks) : 16'b0;
    wire [8:0] incoming_beats={1'b0,pcis_awlen}+9'd1;
    wire grant_reservation=credit_blocks>=16'(incoming_beats);
    assign pcis_awready=rst_n && outstanding_writes<32;
    assign pcis_wready=rst_n && w_count<64;
    assign pcis_bvalid=rst_n && b_count!=0;
    assign {pcis_bid,pcis_bresp}=pcis_bvalid ? b_memory[b_read] : 8'b0;
    assign pcis_arready=rst_n && ar_count<32;
    assign pcis_rvalid=rst_n && ar_count!=0;
    assign pcis_rdata=0;
    assign pcis_rid=pcis_rvalid ? ar_memory[ar_read][13:8] : 6'b0;
    assign pcis_rresp=2'b11;
    assign pcis_rlast=pcis_rvalid && read_beat==ar_memory[ar_read][7:0];
    assign stream_valid=rst_n && output_valid;
    // PRIVATE_INGRESS_IDLE113: only invalid private payload may differ.
    // The sole production consumer writes only on stream_valid && ready.
    assign stream_data=output_block[511:0];
    assign stream_last=stream_valid && output_block[512];

    wire aw_take=pcis_awvalid && pcis_awready;
    wire w_take=pcis_wvalid && pcis_wready;
    // Accepted words reserve the original 64-entry capacity immediately.
    // A pending word is not readable until its next-edge RAM commit finishes.
    reg w_ingress_pending;
    reg [576:0] w_ingress_word;
    reg [5:0] w_ingress_address;
    wire [6:0] committed_w_count=w_count-7'(w_ingress_pending);
    always @(posedge clk)begin
        if(!rst_n)w_ingress_pending<=0;
        else w_ingress_pending<=w_take;
        // Private payload is not reset or qualified by late ready/error logic.
        // Only the separately registered accepted-beat bit permits its use.
        w_ingress_word<={pcis_wlast,pcis_wstrb,pcis_wdata};
        w_ingress_address<=w_write;
    end
    wire b_take=pcis_bvalid && pcis_bready;
    wire ar_take=pcis_arvalid && pcis_arready;
    wire r_take=pcis_rvalid && pcis_rready;
    // Hold a private active header; AW queue ownership ends only at B enqueue.
    reg [81:0] aw_head;
    reg aw_head_valid;
    // Header-only policy is stable for the whole burst. One private
    // admission cycle removes its size/length calculation from beat commit.
    reg aw_policy_valid,aw_policy_ok;
    // Private rolling AXI address; carry bits prevent 4 KiB wraparound.
    reg [16:0] beat_address_q,next_beat_address_q,beat_stride_q;
    wire capture_aw_policy=rst_n && aw_head_valid && !aw_policy_valid;
    wire capture_aw_header=rst_n && !aw_head_valid && aw_count!=0;
    wire aw_reserved=aw_head[81];
    wire [5:0] active_id=aw_head[80:75];
    wire [2:0] active_size=aw_head[74:72];
    wire [7:0] active_len=aw_head[71:64];
    wire [63:0] active_address=aw_head[63:0];
    // Count at W acceptance, not after the wide FIFO's read-address mux.
    // Seven bits represent all counts from zero through 64 without overflow.
    function automatic [6:0] enabled_bytes(input [63:0] enables);
        reg [6:0] tree [1:127];
        integer j;
        begin
            for(j=0;j<64;j=j+1)tree[64+j]={6'b0,enables[j]};
            for(j=63;j>0;j=j-1)tree[j]=tree[2*j]+tree[2*j+1];
            enabled_bytes=tree[1];
        end
    endfunction

    // Compute run shape before the private W queue. A subtree may be empty;
    // two nonempty contiguous children join only across their shared boundary.
    // Select the first enabled index with the same balanced six-level tree.
    function automatic [6:0] strobe_run(input [63:0] enables);
        reg any_tree [1:127];
        reg run_tree [1:127];
        reg [5:0] first_tree [1:127];
        integer j,level,midpoint;
        begin
            for(j=0;j<64;j=j+1)begin
                any_tree[64+j]=enables[j];
                run_tree[64+j]=1'b1;
                first_tree[64+j]=6'(j);
            end
            for(level=5;level>=0;level=level-1)begin
                for(j=(1<<level);j<(2<<level);j=j+1)begin
                    midpoint=(j-(1<<level))*(64>>level)+(32>>level);
                    any_tree[j]=any_tree[2*j] || any_tree[2*j+1];
                    run_tree[j]=run_tree[2*j] && run_tree[2*j+1] &&
                        (!any_tree[2*j] || !any_tree[2*j+1] ||
                         (enables[midpoint-1] && enables[midpoint]));
                    first_tree[j]=any_tree[2*j] ? first_tree[2*j] : first_tree[2*j+1];
                end
            end
            strobe_run={any_tree[1] && run_tree[1],first_tree[1]};
        end
    endfunction

    // Private prefetch copy: the RAM word remains owned until process_beat.
    reg [590:0] w_head;
    reg w_head_valid;
    wire [63:0] strobes=w_head[575:512];
    wire [511:0] incoming_data=w_head[511:0];
    wire process_beat=rst_n && aw_head_valid && aw_policy_valid && aw_count!=0 && w_head_valid && committed_w_count!=0;
    // Never read a just-written empty/refilling slot: wait until it was queued
    // before this edge. Existing queued words may replace a consumed head.
    wire capture_w_head=rst_n && ((!w_head_valid && committed_w_count!=0) || (process_beat && committed_w_count>1));
    wire [5:0] w_capture_index=w_read+6'(process_beat);
    wire final_beat=write_beat==active_len;
    wire finish_write=process_beat && final_beat;
    wire finish_read=r_take && pcis_rlast;
    wire block_pop=rst_n && block_count!=0 && output_count_q<4;

    // Compare in units of the fixed AXI beat size. Keep a carry bit so an
    // out-of-aperture address cannot wrap into a valid 12-bit stream offset.
    // First beats retain AXI's possibly unaligned original address.
    function automatic address_matches(input [11:0] base,input [7:0] beat,
        input [2:0] size,input [11:0] expected);
        begin
            if(beat==0)address_matches=base==expected;
            else case(size)
                3'd0: address_matches=({1'b0,base}+13'(beat))=={1'b0,expected};
                3'd1: address_matches=expected[0]==0 &&
                    ({1'b0,base[11:1]}+12'(beat))=={1'b0,expected[11:1]};
                3'd2: address_matches=expected[1:0]==0 &&
                    ({1'b0,base[11:2]}+11'(beat))=={1'b0,expected[11:2]};
                3'd3: address_matches=expected[2:0]==0 &&
                    ({1'b0,base[11:3]}+10'(beat))=={1'b0,expected[11:3]};
                3'd4: address_matches=expected[3:0]==0 &&
                    ({1'b0,base[11:4]}+9'(beat))=={1'b0,expected[11:4]};
                3'd5: address_matches=expected[4:0]==0 &&
                    ({2'b0,base[11:5]}+9'(beat))=={2'b0,expected[11:5]};
                3'd6: address_matches=expected[5:0]==0 &&
                    ({3'b0,base[11:6]}+9'(beat))=={3'b0,expected[11:6]};
                default: address_matches=1'b0;
            endcase
        end
    endfunction

    // AXI narrow and full-width INCR bursts. No crossing of a 4 KiB boundary.
    // The shell does not carry AxBURST; its contract fixes it to INCR.
    wire [16:0] beat_bytes=17'd1<<active_size;
    wire [16:0] aligned_address={5'b0,active_address[11:0]} & ~(beat_bytes-17'd1);
    wire [16:0] transaction_end=aligned_address+((17'(active_len)+17'd1)<<active_size);
    // INGRESS_LANE205: the checked strobe run starts at received_bytes.
    // Compare its span in seven bits using the existing admitted stride.
    wire [5:0] lane_offset=received_bytes[5:0] & (beat_stride_q[5:0]-6'd1);
    wire [6:0] lane_span={1'b0,lane_offset}+byte_count;
    wire [6:0] byte_count=w_head[583:577];
    reg [511:0] merged_block;
    integer n;
    always @* begin
        merged_block=partial_block;
        for(n=0;n<64;n=n+1)begin
            if(strobes[n])merged_block[n*8+:8]=incoming_data[n*8+:8];
        end
    end
    wire beat_ok=aw_reserved && !error && !loader_error && !loader_ready && !transaction_error &&
        aw_policy_ok &&
        (beat_address_q=={5'b0,received_bytes[11:0]}) &&
        byte_count!=0 && w_head[590] && w_head[589:584]==received_bytes[5:0] && (lane_span<=beat_stride_q[6:0]) &&
        w_head[576]==final_beat && received_bytes<IMAGE_BYTES &&
        32'(byte_count)<=IMAGE_BYTES-received_bytes;
    wire accept_bytes=process_beat && beat_ok;
    wire block_push=accept_bytes && ({1'b0,received_bytes[5:0]}+byte_count==7'd64);
    wire image_last=received_bytes+32'(byte_count)==IMAGE_BYTES;

    always @(posedge clk)begin
        if(!rst_n)begin
            aw_write<=0;aw_read<=0;w_write<=0;w_read<=0;b_write<=0;b_read<=0;ar_write<=0;ar_read<=0;
            aw_count<=0;w_count<=0;b_count<=0;ar_count<=0;outstanding_writes<=0;
            write_beat<=0;read_beat<=0;transaction_error<=0;aw_head_valid<=0;aw_policy_valid<=0;aw_policy_ok<=0;w_head_valid<=0;
            beat_address_q<=0;next_beat_address_q<=0;beat_stride_q<=0;
            reserved_blocks<=0;block_count<=0;block_write<=0;block_read<=0;
            error<=0;received_bytes<=0;
        end else begin
            if(finish_write)aw_policy_valid<=0;
            else if(capture_aw_policy)aw_policy_valid<=1;
            if(capture_aw_policy)begin
                aw_policy_ok<=active_size<=6 && active_address[63:12]==0 && transaction_end<=4096;
                beat_address_q<={5'b0,active_address[11:0]};
                next_beat_address_q<=aligned_address+beat_bytes;
                beat_stride_q<=beat_bytes;
            end else if(process_beat)begin
                beat_address_q<=next_beat_address_q;
                next_beat_address_q<=next_beat_address_q+beat_stride_q;
            end
            if(finish_write)aw_head_valid<=0;
            else if(capture_aw_header)aw_head_valid<=1;
            if(capture_w_head)w_head_valid<=1;
            else if(process_beat)w_head_valid<=0;
            aw_count<=aw_count+6'(aw_take)-6'(finish_write);
            w_count<=w_count+7'(w_take)-7'(process_beat);
            b_count<=b_count+6'(finish_write)-6'(b_take);
            ar_count<=ar_count+6'(ar_take)-6'(finish_read);
            outstanding_writes<=outstanding_writes+6'(aw_take)-6'(b_take);
            reserved_blocks<=reserved_blocks+
                ((aw_take && grant_reservation) ? COUNT_BITS'(incoming_beats) : COUNT_BITS'(0))-
                COUNT_BITS'(process_beat && aw_reserved);
            block_count<=block_count+COUNT_BITS'(block_push)-COUNT_BITS'(block_pop);
            if(aw_take)aw_write<=aw_write+1'b1;
            if(w_take)w_write<=w_write+1'b1;
            if(b_take)b_read<=b_read+1'b1;
            if(ar_take)ar_write<=ar_write+1'b1;
            if(finish_read)begin ar_read<=ar_read+1'b1;read_beat<=0;end
            else if(r_take)read_beat<=read_beat+1'b1;
            if(process_beat)begin
                w_read<=w_read+1'b1;
                if(!beat_ok)begin error<=1;transaction_error<=1;end
                if(final_beat)begin
                    aw_read<=aw_read+1'b1;b_write<=b_write+1'b1;
                    write_beat<=0;transaction_error<=0;
                end else write_beat<=write_beat+1'b1;
            end
            if(loader_error)error<=1;
            if(accept_bytes)received_bytes<=received_bytes+32'(byte_count);
            if(block_push)block_write<=block_write+1'b1;
            if(block_pop)block_read<=block_read+1'b1;
        end
    end
    // Data arrays deliberately have no reset. Validity/ownership and the
    // contiguous byte rule ensure a complete block is initialized before use.
    always @(posedge clk)begin
        if(capture_aw_header)aw_head<=aw_memory[aw_read];
        if(capture_w_head)w_head<=w_memory[w_capture_index];
        if(aw_take)aw_memory[aw_write]<={grant_reservation,pcis_awid,pcis_awsize,pcis_awlen,pcis_awaddr};
        // Commit only the previously accepted private beat; metadata
        // is computed from its captured strobes, not live host inputs.
        if(rst_n && w_ingress_pending)w_memory[w_ingress_address]<=
            {strobe_run(w_ingress_word[575:512]),enabled_bytes(w_ingress_word[575:512]),w_ingress_word};
        if(finish_write)b_memory[b_write]<={active_id,beat_ok ? 2'b00 : 2'b10};
        if(ar_take)ar_memory[ar_write]<={pcis_arid,pcis_arlen};
        if(accept_bytes)partial_block<=merged_block;
        if(block_push)blocks[block_write]<={image_last,merged_block};

    end
    // Payload never resets. Reserved ownership precedes publication.
    always @(posedge clk)begin
        if(!rst_n)begin
            block_read_pending_q<=0;block_return_slot_q<=0;
            block_output_pending_q<=0;block_output_slot_q<=0;
            output_write_q<=0;output_read_q<=0;output_count_q<=0;output_slots_valid_q<=0;
        end else begin
            block_read_pending_q<=block_pop;
            block_output_pending_q<=block_read_pending_q;
            if(block_read_pending_q)block_output_slot_q<=block_return_slot_q;
            output_count_q<=output_count_q+3'(block_pop)-3'(output_take);
            if(block_pop)begin
                block_return_slot_q<=output_write_q;
                output_write_q<=output_write_q+2'd1;
            end
            if(output_take)begin
                output_slots_valid_q[output_read_q]<=0;
                output_read_q<=output_read_q+2'd1;
            end
            if(block_output_pending_q)output_slots_valid_q[block_output_slot_q]<=1;
        end
        if(block_pop)block_read_data_q<=blocks[block_read];
        // Payload may refresh while invalid. The delayed reservation
        // publishes only its matching word, and reset drops both stages.
        block_output_data_q<=block_read_data_q;
    end
    generate for(genvar output_slot=0;output_slot<4;output_slot=output_slot+1)begin:output_return_slots
        always @(posedge clk)
            if(rst_n && block_output_pending_q && block_output_slot_q==2'(output_slot))
                output_slots_q[output_slot]<=block_output_data_q;
    end endgenerate

endmodule
