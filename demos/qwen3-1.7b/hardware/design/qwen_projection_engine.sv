// PRIVATE Qwen3-1.7B projection engine. None of these arithmetic or memory
// ports is an application interface. The fixed sequencer owns kind/layer and
// all activation/result routing. The fixed-model memory reader owns weights.
//
// kind: 0 Q, 1 K, 2 V, 3 O, 4 gate, 5 up, 6 down, 7 vocabulary head.
// Matrix dimensions are fixed below; no dimensions or raw addresses are inputs.
//
// One memory request per 32 output rows: accept request, then 32 FP32 scales,
// then 256 or 768 weight beats. Each beat contains 32 rows x 8 signed bytes.
// The reader must hold each valid response until accepted, authenticate data
// before asserting valid, and drain/invalidate ALL old responses on abort.
// That reader/authentication is not implemented by this numerical engine.
module qwen_projection_engine (
    input wire clk,
    input wire rst_n,
    input wire clear,
    input wire op_valid,
    output wire op_ready,
    input wire [2:0] op_kind,
    input wire [4:0] op_layer,
    input wire activation_valid,
    output wire activation_ready,
    input wire [15:0] activation,
    output wire result_valid,
    input wire result_ready,
    output wire [17:0] result_index,
    output wire [15:0] result,
    output wire done_valid,
    input wire done_ready,
    output reg done_error,
    output wire busy,

    output wire memory_request_valid,
    input wire memory_request_ready,
    output wire [2:0] memory_kind,
    output wire [4:0] memory_layer,
    output wire [12:0] memory_tile,
    input wire scales_valid,
    output wire scales_ready,
    input wire [1023:0] row_scales,
    input wire weights_valid,
    output wire weights_ready,
    input wire [2047:0] weights,
    input wire memory_error,
    output wire memory_abort,
    input wire memory_quiescent
);
    localparam [2:0] IDLE=0, QUANTIZE=1, REQUEST=2, SCALES=3, RUN=4, DONE=5, ABORTING=6;
    reg [2:0] state, kind;
    reg [4:0] layer;
    reg [12:0] tile;
    reg [9:0] group_index;
    reg [31:0] vector_scale;
    reg report_error_after_abort;
    // One PRIVATE next-tile scale slot. The old tile retains its own scales
    // and output index until its last result is accepted. Payload is not reset;
    // validity is reset/CLEAR/new-operation owned.
    reg tile_input_done, next_request_accepted, next_scales_valid;
    reg [12:0] input_tile;
    wire [1:0] tile_start_ready;
    reg [1023:0] next_scales;
    wire long_vector=kind==6;
    wire [9:0] last_group=long_vector ? 10'd767 : 10'd255;
    wire [12:0] last_element=long_vector ? 13'd6143 : 13'd2047;
    reg [12:0] last_tile;
    always @* begin
        case(kind)
            1,2: last_tile=13'd31;
            4,5: last_tile=13'd191;
            7: last_tile=13'd4747;
            default: last_tile=13'd63;
        endcase
    end
    wire alive=rst_n && !clear && state!=ABORTING;
    wire sub_clear=clear || state==ABORTING;
    assign memory_abort=!rst_n || sub_clear;
    assign op_ready=state==IDLE && alive;
    wire op_accept=op_valid && op_ready;
    wire valid_geometry=op_kind==7 || op_layer<28;
    wire quant_start=op_accept && valid_geometry && !memory_error;
    // PRIVATE_QUANT_START: retain the accepted geometry, not live op_kind.
    // A later fault enters ABORTING and clears the child; unchanged masks
    // prevent activation/result/memory transfers during that fault cycle.
    reg [1:0] quant_start_q;
    always @(posedge clk) begin
        if(!rst_n || sub_clear)quant_start_q<=0;
        else quant_start_q<={quant_start && op_kind==6,quant_start && op_kind!=6};
    end
    assign busy=state!=IDLE;
    assign done_valid=state==DONE && alive;

    wire [1:0] quant_in_ready,quant_out_valid,quant_error,quant_busy;
    wire [10:0] short_index;
    wire [12:0] long_index;
    wire [15:0] short_code,long_code;
    wire [31:0] short_scale,long_scale;
    wire accept_quant=state==QUANTIZE && alive && !memory_error;
    // PRIVATE_QUANTIZER_INPUT_STAGE: one accepted activation, not a host
    // operand port. Keep the original acceptance and cancellation guards;
    // split the late upstream valid path from numerical child state enables.
    reg activation_pending;
    reg [15:0] activation_sample;
    wire quantizer_input_ready=long_vector ? quant_in_ready[1] : quant_in_ready[0];
    wire activation_stage_ready=!activation_pending || quantizer_input_ready;
    always @(posedge clk) begin
        if(!rst_n || sub_clear) activation_pending<=0;
        else if(!accept_quant) activation_pending<=0;
        else if(activation_stage_ready) begin
            activation_pending<=activation_valid;
            if(activation_valid) activation_sample<=activation;
        end
    end
    qwen_activation_quantizer #(.ELEMENTS(2048)) quant_short(
        .clk(clk),.rst_n(rst_n),.clear(sub_clear),.start(quant_start_q[0]),
        .in_valid(activation_pending && accept_quant && !long_vector),.in_ready(quant_in_ready[0]),
        .activation(activation_sample),.out_valid(quant_out_valid[0]),.out_ready(accept_quant && !long_vector),
        .out_index(short_index),.code(short_code),.vector_scale(short_scale),
        .out_error(quant_error[0]),.busy(quant_busy[0])
    );
    qwen_activation_quantizer #(.ELEMENTS(6144)) quant_long(
        .clk(clk),.rst_n(rst_n),.clear(sub_clear),.start(quant_start_q[1]),
        .in_valid(activation_pending && accept_quant && long_vector),.in_ready(quant_in_ready[1]),
        .activation(activation_sample),.out_valid(quant_out_valid[1]),.out_ready(accept_quant && long_vector),
        .out_index(long_index),.code(long_code),.vector_scale(long_scale),
        .out_error(quant_error[1]),.busy(quant_busy[1])
    );
    assign activation_ready=accept_quant && activation_stage_ready;
    wire quant_valid=long_vector ? quant_out_valid[1] : quant_out_valid[0];
    wire quant_failed=long_vector ? quant_error[1] : quant_error[0];
    wire [12:0] quant_index=long_vector ? long_index : {2'b0,short_index};
    wire [15:0] quant_code=long_vector ? long_code : short_code;
    wire [31:0] quant_scale=long_vector ? long_scale : short_scale;
    wire quant_write=accept_quant && quant_valid && !quant_failed;

    // Eight independently written banks provide one complete 8-code word each
    // compute cycle. No RAM contents are reset; a completed quantization pass
    // establishes validity before the engine permits any weight request.
    wire weight_accept=weights_valid && weights_ready;
    // PRIVATE_ACTIVATION_PREFETCH: prepare both legal successors of the
    // registered group index, regardless of the upstream weight-valid cone.
    // At the next edge group_index either stays or advances exactly once;
    // its new parity selects the corresponding registered RAM result.
    // The last odd group wraps to even group zero for the next tile.
    wire [8:0] even_read_group=group_index==last_group ? 9'd0
        : group_index[9:1]+{8'b0,group_index[0]};
    wire [8:0] odd_read_group=group_index[9:1];
    wire [127:0] activation_word;
    genvar bank;
    generate for(bank=0;bank<8;bank=bank+1) begin: activation_banks
        (* ram_style="block" *) reg [15:0] even_codes [0:383];
        (* ram_style="block" *) reg [15:0] odd_codes [0:383];
        reg [15:0] read_even_code,read_odd_code;
        always @(posedge clk) if(rst_n) begin
            if(quant_write && quant_index[2:0]==3'(bank) && !quant_index[3])
                even_codes[quant_index[12:4]]<=quant_code;
            if(quant_write && quant_index[2:0]==3'(bank) && quant_index[3])
                odd_codes[quant_index[12:4]]<=quant_code;
            read_even_code<=even_codes[even_read_group];
            read_odd_code<=odd_codes[odd_read_group];
        end
        assign activation_word[bank*16 +: 16]=group_index[0] ? read_odd_code : read_even_code;
    end endgenerate

    wire lookahead_request=state==RUN && tile_input_done
        && input_tile!=last_tile && !next_request_accepted;
    assign memory_request_valid=(state==REQUEST || lookahead_request)
        && alive && !memory_error;
    wire lookahead_request_take=lookahead_request && memory_request_ready
        && alive && !memory_error;
    assign memory_kind=kind;
    assign memory_layer=layer;
    // Result delivery never changes the outstanding input request index.
    assign memory_tile=lookahead_request ? input_tile+13'd1 : input_tile;
    wire selected_start_ready=long_vector ? tile_start_ready[1] : tile_start_ready[0];
    assign scales_ready=((state==SCALES && selected_start_ready)
        || (state==RUN && next_request_accepted && !next_scales_valid))
        && alive && !memory_error;
    wire lookahead_scale_take=state==RUN && scales_valid && scales_ready;
    wire launch_tile=alive && !memory_error && selected_start_ready
        && ((state==SCALES && scales_valid) || (state==RUN && next_scales_valid));
    wire [1023:0] launch_scales=next_scales_valid ? next_scales : row_scales;
    always @(posedge clk) begin
        if(lookahead_scale_take) next_scales<=row_scales;
    end
    wire [1:0] tile_in_ready,tile_out_valid,tile_error,tile_busy;
    wire [4:0] short_row,long_row;
    wire [15:0] short_result,long_result;
    wire tile_valid=long_vector ? tile_out_valid[1] : tile_out_valid[0];
    wire tile_failed=long_vector ? tile_error[1] : tile_error[0];
    wire [4:0] tile_row=long_vector ? long_row : short_row;
    wire run_enabled=state==RUN && alive && !memory_error;
    assign weights_ready=run_enabled && (long_vector ? tile_in_ready[1] : tile_in_ready[0]);
    assign result_valid=run_enabled && tile_valid && !tile_failed;
    assign result_index={tile,tile_row};
    assign result=long_vector ? long_result : short_result;
    wire take_result=run_enabled && result_ready && !tile_failed;
    qwen_projection_tile32_overlap #(.GROUPS(256)) tile_short(
        .clk(clk),.rst_n(rst_n),.clear(sub_clear),.start(launch_tile && !long_vector),
        .start_ready(tile_start_ready[0]),
        .row_scales(launch_scales),.vector_scale(vector_scale),
        .in_valid(weights_valid && run_enabled && !long_vector),.in_ready(tile_in_ready[0]),
        .activations(activation_word),.weights(weights),
        .out_valid(tile_out_valid[0]),.out_ready(take_result && !long_vector),
        .out_row(short_row),.result(short_result),.out_error(tile_error[0]),.busy(tile_busy[0])
    );
    qwen_projection_tile32_overlap #(.GROUPS(768)) tile_long(
        .clk(clk),.rst_n(rst_n),.clear(sub_clear),.start(launch_tile && long_vector),
        .start_ready(tile_start_ready[1]),
        .row_scales(launch_scales),.vector_scale(vector_scale),
        .in_valid(weights_valid && run_enabled && long_vector),.in_ready(tile_in_ready[1]),
        .activations(activation_word),.weights(weights),
        .out_valid(tile_out_valid[1]),.out_ready(take_result && long_vector),
        .out_row(long_row),.result(long_result),.out_error(tile_error[1]),.busy(tile_busy[1])
    );

    always @(posedge clk) begin
        if(!rst_n || clear) begin
            state<=ABORTING; kind<=0; layer<=0; tile<=0; group_index<=0;
            vector_scale<=32'h3f800000; done_error<=0; report_error_after_abort<=0;
            tile_input_done<=0; next_request_accepted<=0; next_scales_valid<=0;
            input_tile<=0;
        end else if(state==ABORTING) begin
            if(memory_quiescent && !(|quant_busy) && !(|tile_busy)) begin
                if(report_error_after_abort) begin state<=DONE; done_error<=1; end
                else state<=IDLE;
            end
        end else if(state!=IDLE && state!=DONE && memory_error) begin
            state<=ABORTING; report_error_after_abort<=1;
        end else begin
            case(state)
                IDLE: if(op_accept) begin
                    kind<=op_kind;
                    layer<=op_kind==7 ? 5'd0 : op_layer;
                    tile<=0; group_index<=0; done_error<=0;
                    tile_input_done<=0; next_request_accepted<=0; next_scales_valid<=0;
                    input_tile<=0;
                    if(!valid_geometry || memory_error) begin state<=ABORTING; report_error_after_abort<=1; end
                    else state<=QUANTIZE;
                end
                QUANTIZE: if(quant_valid) begin
                    if(quant_failed) begin state<=ABORTING; report_error_after_abort<=1; end
                    else if(quant_index==last_element) begin vector_scale<=quant_scale; state<=REQUEST; end
                end
                REQUEST: if(memory_request_ready) state<=SCALES;
                SCALES: if(launch_tile) begin
                    state<=RUN;
                    tile_input_done<=0; next_request_accepted<=0; next_scales_valid<=0;
                end
                RUN: begin
                    if(launch_tile) begin
                        input_tile<=input_tile+1'b1;
                        tile_input_done<=0; next_request_accepted<=0; next_scales_valid<=0;
                    end
                    if(weight_accept) begin
                        group_index<=group_index==last_group ? 10'd0 : group_index+1'b1;
                        if(group_index==last_group) tile_input_done<=1;
                    end
                    if(lookahead_request_take) next_request_accepted<=1;
                    if(lookahead_scale_take) next_scales_valid<=1;
                    if(tile_valid && tile_failed) begin state<=ABORTING; report_error_after_abort<=1; end
                    else if(result_valid && result_ready && tile_row==31) begin
                        if(tile==last_tile) state<=DONE;
                        else tile<=tile+1'b1;
                    end
                end
                DONE: if(done_ready) begin state<=IDLE; report_error_after_abort<=0; end
                default: begin state<=ABORTING; report_error_after_abort<=1; end
            endcase
        end
    end
endmodule
