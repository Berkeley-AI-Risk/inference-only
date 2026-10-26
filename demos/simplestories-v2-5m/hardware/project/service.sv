`timescale 1ns/1ps
`default_nettype none

// PRIVATE fixed-model read service. Not connected to the public host bus.
// Expected digests are compiled into a local, read-only ROM, indexed by page.
// Raw DDR can never set an expected digest or change a sealed inference copy.
// A production parent must supply the trusted boot lock and DDR/KV arbitration.
module board1_verified_ddr_page_service #(
    parameter integer BANKS=8,
    parameter integer ADDR_W=25,
    parameter integer IMAGE_WORDS=227062,
    parameter integer WEIGHT_WORDS=211800,
    parameter integer MAX_OUTSTANDING=32,
    parameter integer DDR_WATCHDOG_CYCLES=50000000,
    parameter DIGEST_HEX="digests32.memh",
    parameter integer LOCAL_METADATA=1,
    parameter METADATA_HEX="metadata192.memh"
) (
    input wire clk,reset_n,cancel_i,model_locked_i,
    input wire request_valid_i,
    output wire request_ready_o,
    input wire [ADDR_W-1:0] request_word_i,
    output wire response_valid_o,
    input wire response_ready_i,
    output wire [255:0] response_data_o,
    output wire ddr_request_valid_o,
    input wire ddr_request_ready_i,
    output wire [ADDR_W-1:0] ddr_request_word_o,
    input wire ddr_response_valid_i,
    input wire [255:0] ddr_response_data_i,
    input wire ddr_response_error_i,
    output wire fault_o
);
    localparam integer BANK_W=$clog2(BANKS);
    localparam integer PAGES=(IMAGE_WORDS+127)/128;
    localparam integer WEIGHT_PAGES=(WEIGHT_WORDS+127)/128;
    localparam integer WATCH_W=$clog2(DDR_WATCHDOG_CYCLES+1);
    localparam [2:0] IDLE=0,ROM_READ=1,ROM_CAPTURE=2,ALLOCATE=3,FILL=4,SCAN=5;
    logic [2:0] dma_state_q;
    logic fault_q,locked_seen_q;
    wire [BANKS-1:0] bank_begin_ready,bank_fill_ready,bank_read_ready;
    wire [BANKS-1:0] bank_assigned,bank_verified,bank_fault,bank_response_valid;
    logic [BANKS-1:0] bank_begin_valid,bank_fill_valid,bank_read_valid,bank_response_ready;
    wire [10:0] bank_page [0:BANKS-1];
    wire [255:0] bank_response_data [0:BANKS-1];
    wire enabled=model_locked_i && !fault_o;
    assign fault_o=fault_q || (|bank_fault);

    // Payload is resetless; only pointers/counts are reset or cancelled.
    (* ram_style="distributed" *) logic [17:0] request_fifo [0:63];
    logic [5:0] request_write_q,request_read_q;
    logic [6:0] request_count_q;
    logic [17:0] head_word;
    logic head_valid_q;
    // Explicit registered FIFO head breaks the async RAM -> selected bank
    // ready -> pop/pointer feedback timing path. It permits one consumed word
    // every two clocks; measure the end-to-end trade-off against routed MHz.
    wire head_load=enabled && !cancel_i && !head_valid_q && request_count_q!=0;
    wire [10:0] head_page=head_word[17:7];
    wire [BANK_W-1:0] head_bank=head_page[BANK_W-1:0];
    logic [BANK_W:0] response_fifo [0:31];
    logic [4:0] response_write_q,response_read_q;
    logic [5:0] response_count_q;
    wire [BANK_W:0] response_source=response_fifo[response_read_q];
    wire [BANK_W-1:0] response_bank=response_source[BANK_W-1:0];
    wire metadata_head=LOCAL_METADATA!=0 && head_word>=18'd211920 && head_word<18'd214248;
    wire metadata_ready,metadata_valid;
    wire [255:0] metadata_data;
    wire metadata_read=enabled && !cancel_i && head_valid_q && response_count_q<6'd32 &&
        metadata_head && metadata_ready;
    wire metadata_response_ready=enabled && !cancel_i && response_count_q!=0 &&
        response_source[BANK_W] && response_ready_i;
    wire request_fire=request_valid_i && request_ready_o;
    wire response_fire=response_valid_o && response_ready_i;
    wire read_fire=(| (bank_read_valid & bank_read_ready)) || metadata_read;
    assign request_ready_o=enabled && !cancel_i && request_count_q<7'd64;
    assign response_valid_o=enabled && !cancel_i && response_count_q!=0 &&
        (response_source[BANK_W] ? metadata_valid : bank_response_valid[response_bank]);
    assign response_data_o=response_valid_o ?
        (response_source[BANK_W] ? metadata_data : bank_response_data[response_bank]) : 256'd0;

    // The fixed projection row scales/exponents are only 55,872 useful bytes.
    // Keep them in immutable on-chip ROM instead of evicting streaming pages
    // and rehashing a metadata page at each group boundary. No new parameters
    // or model-changing command are exposed to a user.
    generate if(LOCAL_METADATA!=0) begin: g_metadata
        (* rom_style="block" *) logic [191:0] memory [0:2327];
        logic [191:0] data_q;
        logic valid_q;
        wire [11:0] address=12'(head_word-18'd211920);
        assign metadata_valid=valid_q;
        assign metadata_ready=!valid_q || metadata_response_ready;
        for(genvar m=0;m<8;m=m+1) begin: g_expand
            assign metadata_data[m*32 +: 32]={8'd0,data_q[m*24 +: 24]};
        end
        always_ff @(posedge clk) begin
            if(metadata_read) data_q<=memory[address];
        end
        always_ff @(posedge clk or negedge reset_n) begin
            if(!reset_n) valid_q<=0;
            else if(cancel_i || fault_o) valid_q<=0;
            else if(metadata_ready) valid_q<=metadata_read;
        end
        initial $readmemh(METADATA_HEX,memory);
    end else begin: g_external_metadata
        assign metadata_valid=0;
        assign metadata_ready=0;
        assign metadata_data=0;
    end endgenerate

    logic [10:0] fill_page_q;
    wire [BANK_W-1:0] fill_bank=fill_page_q[BANK_W-1:0];
    logic [7:0] issued_q,received_q,page_words_q;
    wire [8:0] outstanding={1'b0,issued_q}-{1'b0,received_q};
    logic [WATCH_W-1:0] ddr_watchdog_q;
    wire ddr_request_fire=ddr_request_valid_o && ddr_request_ready_i;
    wire ddr_response_legal=dma_state_q==FILL && outstanding!=0 &&
        bank_fill_ready[fill_bank] && !ddr_response_error_i;
    wire ddr_response_fire=ddr_response_valid_i && ddr_response_legal && enabled;
    assign ddr_request_valid_o=enabled && dma_state_q==FILL &&
        issued_q<page_words_q && outstanding<9'(MAX_OUTSTANDING);
    assign ddr_request_word_o=ddr_request_valid_o ? ADDR_W'({fill_page_q,issued_q[6:0]}) : {ADDR_W{1'b0}};

    // Narrow synchronous ROM is never writable. The evidence generator pins
    // the exact model image, zero-tail convention, table bytes and source hash.
    (* rom_style="block" *) logic [31:0] digest_rom [0:PAGES*8-1];
    logic [2:0] digest_word_q;
    logic [31:0] digest_data_q;
    logic [255:0] expected_digest_q;
    always_ff @(posedge clk) begin
        if(dma_state_q==ROM_READ)
            digest_data_q<=digest_rom[{fill_page_q,digest_word_q}];
        if(dma_state_q==ROM_CAPTURE)
            expected_digest_q<={expected_digest_q[223:0],digest_data_q};
        if(request_fire) request_fifo[request_write_q]<=request_word_i[17:0];
        if(head_load) head_word<=request_fifo[request_read_q];
        if(read_fire) response_fifo[response_write_q]<={metadata_read,head_bank};
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) head_valid_q<=0;
        else if(cancel_i || fault_o || read_fire) head_valid_q<=0;
        else if(head_load) head_valid_q<=1;
    end

    // Private weight frontier survives temporary consumer request gaps.
    // No public input selects it; a foreground non-weight page revokes it.
    logic remembered_weight_valid_q;
    logic [10:0] remembered_weight_page_q;
    wire foreground_scan=head_valid_q && !metadata_head;
    wire remembered_scan=remembered_weight_valid_q && (!head_valid_q || metadata_head);
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            remembered_weight_valid_q<=0;remembered_weight_page_q<=0;
        end else if(cancel_i || fault_o) remembered_weight_valid_q<=0;
        else if(enabled && head_valid_q && !metadata_head) begin
            remembered_weight_valid_q<=head_word<18'(WEIGHT_WORDS);
            remembered_weight_page_q<=head_page;
        end
    end

    // Registered look-ahead scanner: one bank candidate per cycle. It removes
    // the async FIFO -> BANKS-way priority scan -> DMA control timing chain.
    // The next fixed-model fill can be chosen while previous banks hash.
    // A stale scan may waste a harmless prefetch; ALLOCATE rechecks ownership.
    logic [10:0] scan_base_q;
    logic [BANK_W-1:0] scan_offset_q;
    wire [11:0] probe_page={1'b0,scan_base_q}+12'(scan_offset_q);
    wire candidate_valid=probe_page<12'(PAGES) &&
        (scan_offset_q==0 || ({1'b0,scan_base_q}<12'(WEIGHT_PAGES) && probe_page<12'(WEIGHT_PAGES))) &&
        !(bank_assigned[probe_page[BANK_W-1:0]] &&
            bank_page[probe_page[BANK_W-1:0]]==probe_page[10:0]) &&
        bank_begin_ready[probe_page[BANK_W-1:0]];

    always_comb begin
        bank_begin_valid=0;bank_fill_valid=0;bank_read_valid=0;bank_response_ready=0;
        if(enabled) begin
            if(dma_state_q==ALLOCATE) bank_begin_valid[fill_bank]=1;
            if(ddr_response_fire) bank_fill_valid[fill_bank]=1;
            if(!cancel_i) begin
                if(head_valid_q && response_count_q<6'd32 && !metadata_head &&
                    bank_verified[head_bank] && bank_page[head_bank]==head_page)
                    bank_read_valid[head_bank]=1;
                if(response_count_q!=0 && !response_source[BANK_W])
                    bank_response_ready[response_bank]=response_ready_i;
            end
        end
    end

    genvar b;
    generate for(b=0;b<BANKS;b=b+1) begin: g_bank
        board1_verified_page_bank #(.IMAGE_WORDS(IMAGE_WORDS)) u_bank (
            .clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i),
            .begin_valid_i(bank_begin_valid[b]),.begin_ready_o(bank_begin_ready[b]),
            .begin_page_i(fill_page_q),.expected_digest_i(expected_digest_q),
            .fill_valid_i(bank_fill_valid[b]),.fill_ready_o(bank_fill_ready[b]),
            .fill_data_i(ddr_response_data_i),.fill_last_i(received_q==page_words_q-8'd1),
            .read_valid_i(bank_read_valid[b]),.read_ready_o(bank_read_ready[b]),
            .read_word_i(head_word[6:0]),.response_valid_o(bank_response_valid[b]),
            .response_ready_i(bank_response_ready[b]),.response_data_o(bank_response_data[b]),
            .assigned_o(bank_assigned[b]),.verified_o(bank_verified[b]),
            .page_o(bank_page[b]),.fault_o(bank_fault[b]));
    end endgenerate

    wire protocol_error=(request_fire && request_word_i>=ADDR_W'(IMAGE_WORDS)) ||
        (ddr_response_valid_i && !ddr_response_legal) ||
        (locked_seen_q && !model_locked_i) ||
        (dma_state_q==FILL && ddr_watchdog_q==WATCH_W'(DDR_WATCHDOG_CYCLES-1));
`ifndef SYNTHESIS
    logic x_error;
    always_comb begin
        x_error=$isunknown(cancel_i) || $isunknown(model_locked_i) ||
            $isunknown(request_valid_i) || $isunknown(ddr_response_valid_i);
        if(request_valid_i) x_error=x_error || $isunknown(request_word_i);
        if(response_valid_o) x_error=x_error || $isunknown(response_ready_i);
        if(ddr_request_valid_o) x_error=x_error || $isunknown(ddr_request_ready_i);
        if(ddr_response_valid_i) x_error=x_error || $isunknown(ddr_response_data_i) ||
            $isunknown(ddr_response_error_i);
    end
`endif

    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            fault_q<=0;locked_seen_q<=0;dma_state_q<=IDLE;
            request_write_q<=0;request_read_q<=0;request_count_q<=0;
            response_write_q<=0;response_read_q<=0;response_count_q<=0;
            fill_page_q<=0;page_words_q<=0;issued_q<=0;received_q<=0;
            digest_word_q<=0;ddr_watchdog_q<=0;scan_base_q<=0;scan_offset_q<=0;
        end else if(fault_o || protocol_error
`ifndef SYNTHESIS
            || x_error
`endif
        ) begin
            fault_q<=1;request_count_q<=0;response_count_q<=0;
        end else begin
            if(model_locked_i) locked_seen_q<=1;
            if(cancel_i) begin
                request_write_q<=0;request_read_q<=0;request_count_q<=0;
                response_write_q<=0;response_read_q<=0;response_count_q<=0;
            end else begin
                if(request_fire) request_write_q<=request_write_q+6'd1;
                if(read_fire) request_read_q<=request_read_q+6'd1;
                case({request_fire,read_fire})
                    2'b10:request_count_q<=request_count_q+7'd1;
                    2'b01:request_count_q<=request_count_q-7'd1;
                    default: ;
                endcase
                if(read_fire) response_write_q<=response_write_q+5'd1;
                if(response_fire) response_read_q<=response_read_q+5'd1;
                case({read_fire,response_fire})
                    2'b10:response_count_q<=response_count_q+6'd1;
                    2'b01:response_count_q<=response_count_q-6'd1;
                    default: ;
                endcase
            end
            if(dma_state_q!=FILL || ddr_request_fire || ddr_response_fire) ddr_watchdog_q<=0;
            else ddr_watchdog_q<=ddr_watchdog_q+1'b1;
            // CLEAR intentionally does not cancel raw reads or SHA. This
            // permits all old raw responses to drain without an epoch alias.
            if(enabled) case(dma_state_q)
                IDLE: if(!cancel_i && (foreground_scan || remembered_scan)) begin
                    scan_base_q<=foreground_scan ? head_page : remembered_weight_page_q;
                    scan_offset_q<=0;dma_state_q<=SCAN;
                end
                SCAN: begin
                    if(cancel_i) dma_state_q<=IDLE;
                    else if(candidate_valid) begin
                        fill_page_q<=probe_page[10:0];
                        page_words_q<=probe_page==12'(PAGES-1) ? 8'(IMAGE_WORDS-(PAGES-1)*128) : 8'd128;
                        digest_word_q<=0;dma_state_q<=ROM_READ;
                    end else if(scan_offset_q==BANK_W'(BANKS-1)) dma_state_q<=IDLE;
                    else scan_offset_q<=scan_offset_q+1'b1;
                end
                ROM_READ: dma_state_q<=ROM_CAPTURE;
                ROM_CAPTURE: begin
                    digest_word_q<=digest_word_q+3'd1;
                    dma_state_q<=digest_word_q==3'd7 ? ALLOCATE : ROM_READ;
                end
                ALLOCATE: if(bank_begin_ready[fill_bank]) begin
                    issued_q<=0;received_q<=0;dma_state_q<=FILL;
                end
                FILL: begin
                    if(ddr_request_fire) issued_q<=issued_q+8'd1;
                    if(ddr_response_fire) begin
                        received_q<=received_q+8'd1;
                        if(received_q==page_words_q-8'd1) dma_state_q<=IDLE;
                    end
                end
                default: fault_q<=1;
            endcase
        end
    end
    initial begin
        if(BANKS<2 || BANKS>16 || (BANKS&(BANKS-1))!=0 || ADDR_W<18 ||
            IMAGE_WORDS<1 || PAGES>2048 || WEIGHT_WORDS<1 || WEIGHT_WORDS>IMAGE_WORDS ||
            MAX_OUTSTANDING<1 || MAX_OUTSTANDING>128 || DDR_WATCHDOG_CYCLES<2 || DIGEST_HEX=="" ||
            (LOCAL_METADATA!=0 && (IMAGE_WORDS!=227062 || METADATA_HEX=="")))
            $fatal(1,"unsupported fixed verified-page service geometry");
        $readmemh(DIGEST_HEX,digest_rom);
    end
endmodule
`default_nettype wire
