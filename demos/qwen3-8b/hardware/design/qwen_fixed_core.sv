// PRIVATE numerical engine for the fixed_qwen_sequencer operation schedule.
// All ports below are internal, including model-memory and K/V transport.
// Only a separate APPEND/STEP/CLEAR wrapper may be application-visible.
//
// Memory contract: model response bytes must ALREADY have been authenticated
// and held against modification by the reader. This module is not that reader.
// model_quiescent means no outstanding responses; kv_quiescent during abort
// additionally means K/V validity has been invalidated. Per-attention aborts
// cancel reads only; they must NOT invalidate the K/V cache between layers.
//
// Operations 9..11 are implemented together by the complete attention engine
// at operation 9. Operations 10/11 only retire that already-completed result.
// HEAD streams into a greedy selector: no full logit RAM or host logit port.
module qwen_fixed_core #(
    parameter integer ATTENTION_CORES=1,
    parameter SILU_ROM_FILE="silu-bf16.hex",
    parameter EXP_ROM_FILE="softmax-exp2.hex"
) (
    input wire clk, input wire rst_n,
    input wire op_valid, output wire op_ready,
    input wire [4:0] op_code,
    input wire [5:0] op_layer,
    input wire [14:0] op_position, input wire [17:0] op_token,
    output wire core_done, output wire core_error, output wire [31:0] core_next_token,
    input wire core_abort, output wire core_quiescent,

    output wire model_request_valid, input wire model_request_ready,
    output wire [33:0] model_address, output wire [18:0] model_bytes,
    input wire model_data_valid, output wire model_data_ready,
    input wire [2047:0] model_data, input wire model_data_last,
    input wire model_error, output wire model_abort, input wire model_quiescent,

    output wire kv_write_start_valid, input wire kv_write_start_ready,
    output wire [5:0] kv_write_layer, output wire [14:0] kv_write_position,
    output wire kv_write_valid, input wire kv_write_ready,
    output wire kv_write_value, output wire [9:0] kv_write_index,
    output wire [15:0] kv_write_data,
    input wire kv_write_done_valid, output wire kv_write_done_ready,
    input wire kv_write_done_error,
    input wire kv_error, output wire kv_abort, input wire kv_quiescent,

    input wire [ATTENTION_CORES-1:0] key_valid, output wire [ATTENTION_CORES-1:0] key_ready,
    output wire [ATTENTION_CORES*15-1:0] key_position,
    input wire [ATTENTION_CORES*2048-1:0] keys,
    input wire [ATTENTION_CORES-1:0] value_valid, output wire [ATTENTION_CORES-1:0] value_ready,
    output wire [ATTENTION_CORES*15-1:0] value_position,
    output wire [ATTENTION_CORES-1:0] value_group,
    input wire [ATTENTION_CORES*1024-1:0] values,
    output wire [5:0] attention_memory_layer,
    output wire [ATTENTION_CORES*3-1:0] attention_memory_head,
    input wire [ATTENTION_CORES-1:0] attention_memory_error,
    output wire [ATTENTION_CORES-1:0] attention_memory_abort,
    input wire [ATTENTION_CORES-1:0] attention_memory_quiescent
);
    localparam [4:0] FLUSH=0, IDLE=1, COMPLETE=2, M_PLAN=3, M_HEADER=4, M_DATA=5,
        N_START=6, N_FEED=7, N_WAIT=8, P_START=9, P_FEED=10, P_WAIT=11,
        R_START=12, R_FEED=13, R_WAIT=14, E_RUN=15, S_RUN=16,
        W_START=17, W_FEED=18, W_WAIT=19, A_START=20, A_FEED=21, A_WAIT=22;
    localparam [3:0] X=0,Z=1,Q=2,K=3,V=4,A=5,T=6,G=7,U=8;
    localparam [2:0] PS_IDLE=0, PS_PLAN=1, PS_HEADER=2, PS_DATA=3,
        PW_PLAN=4, PW_HEADER=5, PW_DATA=6;
    // Simulator read-only visibility does not create any synthesized ports.
    reg [4:0] state /* verilator public_flat_rd */;
    reg [4:0] code /* verilator public_flat_rd */;
    reg [5:0] layer /* verilator public_flat_rd */;
    reg [14:0] position /* verilator public_flat_rd */;
    reg [17:0] token;
    reg failed, report_failure, head_valid, attention_committed;
    reg [15:0] best_value;
    reg [17:0] best_token;
    reg [5:0] head;
    reg [13:0] output_count;
    reg [17:0] projection_output_count;
    wire external_quiet=model_quiescent && kv_quiescent && (&attention_memory_quiescent);
    wire aborting=!rst_n || core_abort || state==FLUSH;
    wire fault;
    wire control_fault;
    wire operating=!aborting && !fault;
    wire norm_operating,projection_operating,rotary_operating,elementwise_operating,silu_operating,attention_operating,kv_wait_operating;
    assign op_ready=rst_n && !core_abort && state==IDLE && external_quiet;
    assign core_quiescent=rst_n && state==FLUSH && external_quiet;
    assign core_done=rst_n && !core_abort && state==COMPLETE && external_quiet && (failed || !control_fault);
    assign core_error=failed;
    // Private payload: the sequencer samples it only with core_done.
    // Keep error/opcode masking; public response gating is unchanged.
    assign core_next_token=!failed && code==23 ? {14'b0,best_token} : 32'b0;
    // Latch fault/report_failure before asking a reader/writer to withdraw its
    // response. An immediate fault -> abort -> response_valid suppression
    // path can erase the fault before the clock (or form a combinational loop).
    // 'operating' already masks requests, tensor writes and successful commit
    // in the detection cycle. FLUSH asserts cancellation from the next clock.
    assign model_abort=aborting;
    assign kv_abort=aborting;

    wire norm_active=state==N_START || state==N_FEED || state==N_WAIT;
    wire projection_active=state==P_START || state==P_FEED || state==P_WAIT;
    wire rotary_active=state==R_START || state==R_FEED || state==R_WAIT;
    wire attention_active=state==A_START || state==A_FEED || state==A_WAIT;

    // Fixed tensor routing. The two operand banks always use the same element
    // index; residuals and gate products read different banks in parallel.
    reg [3:0] source_a,source_b,destination;
    reg [13:0] feed_length,feed_base;
    reg [2:0] projection_kind,norm_kind;
    wire norm_head=code==3 || code==5;
    always @* begin
        projection_kind=0;
        case(code)
            2:projection_kind=0; 4:projection_kind=1; 6:projection_kind=2;
            12:projection_kind=3; 15:projection_kind=4; 16:projection_kind=5;
            19:projection_kind=6; 22:projection_kind=7;
            default:begin end
        endcase
        norm_kind=0;
        case(code)
            1:norm_kind=0; 3:norm_kind=1; 5:norm_kind=2;
            14:norm_kind=3; 21:norm_kind=4;
            default:begin end
        endcase
        source_a=Z;source_b=Z;destination=X;feed_length=4096;feed_base=0;
        case(code)
            1,14,21:begin source_a=X;source_b=X;destination=Z;end
            2:destination=Q;
            3:begin source_a=Q;source_b=Q;destination=Q;feed_length=128;feed_base={1'b0,head,7'b0};end
            4:destination=K;
            5:begin source_a=K;source_b=K;destination=K;feed_length=128;feed_base={1'b0,head,7'b0};end
            6:destination=V;
            7:begin
                source_a=head<32 ? Q : K;source_b=source_a;destination=source_a;
                feed_length=128;feed_base={2'b0,head[4:0],7'b0};
            end
            8:begin source_a=K;source_b=K;feed_length=2048;end
            9:begin source_a=Q;source_b=Q;destination=A;end
            12:begin source_a=A;source_b=A;destination=T;end
            13,20:begin source_a=X;source_b=T;destination=X;end
            15:destination=G;
            16:destination=U;
            17:begin source_a=G;source_b=G;destination=G;feed_length=12288;end
            18:begin source_a=G;source_b=U;destination=G;feed_length=12288;end
            19:begin source_a=G;source_b=G;destination=T;feed_length=12288;end
            default:begin end
        endcase
    end

    // One synchronous private operand fetch per accepted input clock.
    reg [13:0] feed_count, sample_index;
    reg sample_valid;
    wire feed_active=state==N_FEED || state==P_FEED || state==R_FEED || state==E_RUN
        || state==S_RUN || state==W_FEED || state==A_FEED;
    wire consumer_ready;
    // PRIVATE_TENSOR_GUARDS: each active operation retains all errors
    // relevant to that state, including every state-independent error.
    // These are port qualifiers, not replacements for the main fault latch.
    wire tensor_feed_operating=(state==N_FEED && norm_operating)
        || (state==P_FEED && projection_operating)
        || (state==R_FEED && rotary_operating)
        || (state==E_RUN && elementwise_operating)
        || (state==S_RUN && silu_operating)
        || (state==W_FEED && !aborting && !control_fault)
        || (state==A_FEED && attention_operating);
    wire feed_advance=tensor_feed_operating && (!sample_valid || consumer_ready);
    wire feed_issue=feed_advance && feed_count<feed_length;
    // PRIVATE_TENSOR_READ_AHEAD: only the private read-data registers may
    // refresh on a rejected cycle. The original feed_issue still controls
    // sample validity/index; all consumption, faults and writes are unchanged.
    // Hold a valid stalled sample, and never issue an out-of-range fetch.
    wire private_tensor_read=feed_active && (!sample_valid || consumer_ready)
        && feed_count<feed_length;
    wire sample_take=feed_active && sample_valid && consumer_ready && operating;
    wire feed_finished=sample_take && sample_index==feed_length-1'b1;
    wire [3:0] read_a_tensor=state==W_FEED ? (feed_count<1024 ? K : V) : source_a;
    wire [3:0] read_b_tensor=state==W_FEED ? read_a_tensor : source_b;
    wire [13:0] read_index=state==W_FEED ? {4'b0,feed_count[9:0]} : feed_base+feed_count;
    wire [15:0] operand_a,operand_b;
    reg tensor_write /* verilator public_flat_rd */;
    reg [3:0] tensor_write_bank /* verilator public_flat_rd */;
    reg [13:0] tensor_write_index /* verilator public_flat_rd */;
    reg [15:0] tensor_write_data /* verilator public_flat_rd */;
    qwen_private_tensors tensors(
        .clk(clk),.enable(1'b1),.read_enable(private_tensor_read),.read_a_tensor(read_a_tensor),
        .read_b_tensor(read_b_tensor),.read_index(read_index),.read_a(operand_a),.read_b(operand_b),
        .write_enable(tensor_write),.write_tensor(tensor_write_bank),
        .write_index(tensor_write_index),.write_data(tensor_write_data));

    // Fixed-vector loads use a single wide beat buffer followed by a scalar
    // private RAM write stream. The projection path consumes full wide beats.
    reg [2047:0] model_buffer;
    reg buffer_valid;
    reg [6:0] buffer_index;
    reg [13:0] load_count,load_elements;
    reg [5:0] load_beats;
    reg [1:0] load_target; // 0 embedding, 1 norm weights, 2 rotary pairs
    wire [15:0] loaded_value=model_buffer[15:0];
    wire load_take=state==M_DATA && buffer_valid && operating;
    wire load_finished=load_take && load_count==load_elements-1'b1;
    // PRIVATE_EMPTY_BEAT_CAPTURE: refresh only invalid private payload.
    // Original admission/validity and all consumption guards remain unchanged.
    always @(posedge clk) begin
        if(!buffer_valid) model_buffer<=model_data;
        else if(load_take) model_buffer<={16'b0,model_buffer[2047:16]};
    end
    (* ram_style="block" *) reg [15:0] norm_weights [0:4095];
    (* ram_style="distributed" *) reg [31:0] rotary_coefficients [0:63];
    reg [15:0] norm_weight_sample;
    reg [6:0] coefficient_count;
    wire [31:0] rotary_coefficient=rotary_coefficients[coefficient_count[5:0]];
    always @(posedge clk) if(operating) begin
        if(load_take && load_target==1) norm_weights[load_count[11:0]]<=loaded_value;
        if(load_take && load_target==2) begin
            if(load_count[0]) rotary_coefficients[load_count[6:1]][31:16]<=loaded_value;
            else rotary_coefficients[load_count[6:1]][15:0]<=loaded_value;
        end
        if(feed_issue && state==N_FEED) norm_weight_sample<=norm_weights[feed_count[11:0]];
    end

    reg [2:0] projection_memory_state;
    reg [12:0] projection_memory_tile;
    reg [10:0] projection_memory_group;
    wire p_memory_request_valid,p_memory_request_ready;
    wire [2:0] p_memory_kind;
    wire [5:0] p_memory_layer;
    wire [12:0] p_memory_tile;
    wire p_scales_ready,p_weights_ready,p_abort;
    wire scales_phase=projection_active && projection_memory_state==PS_DATA;
    wire weights_phase=projection_active && projection_memory_state==PW_DATA;
    wire [10:0] projection_last_group=projection_kind==6 ? 11'd1535 : 11'd511;
    assign p_memory_request_ready=projection_active && projection_memory_state==PS_IDLE && projection_operating;
    wire address_input_valid=operating && (state==M_PLAN || (projection_active
        && (projection_memory_state==PS_PLAN || projection_memory_state==PW_PLAN)));
    wire address_input_ready,address_result_valid,address_result_error;
    reg [2:0] address_region,address_operation;
    reg [17:0] address_index;
    always @* begin
        address_region=projection_memory_state==PS_PLAN ? 3'd1 : 3'd0;
        address_operation=projection_kind;address_index={5'b0,projection_memory_tile};
        if(state==M_PLAN) begin
            address_region=load_target==0 ? 3'd3 : (load_target==1 ? 3'd2 : 3'd4);
            address_operation=load_target==1 ? norm_kind : 3'd0;
            address_index=load_target==0 ? token : (load_target==2 ? {3'b0,position} : 18'd0);
        end
    end
    qwen_model_address address_decoder(
        .clk(clk),.rst_n(rst_n),.clear(aborting),.request_valid(address_input_valid),
        .request_ready(address_input_ready),.request_region(address_region),
        .request_operation(address_operation),.request_layer(layer),.request_index(address_index),
        .result_valid(address_result_valid),.result_ready(model_request_ready && operating),
        .result_address(model_address),.result_bytes(model_bytes),.result_error(address_result_error));
    assign model_request_valid=address_result_valid && !address_result_error && operating;
    assign model_data_ready=operating && ((state==M_DATA && !buffer_valid)
        || (scales_phase && p_scales_ready) || (weights_phase && p_weights_ready));
    wire model_take=model_data_valid && model_data_ready;
    wire model_last_expected=state==M_DATA ? (load_beats+1'b1==load_elements[12:7])
        : (scales_phase || projection_memory_group==projection_last_group);
    // Inspect malformed held beats without depending on ready; avoid a
    // combinational ready -> fault -> ready cycle.
    wire model_last_bad=model_data_valid && (state==M_DATA || scales_phase || weights_phase)
        && model_data_last!=model_last_expected;

    wire n_input_ready,n_output_valid,n_error,n_busy;
    wire [11:0] n_index;
    wire [15:0] n_result;
    qwen_rms_norm norm(
        .clk(clk),.rst_n(rst_n),.clear(aborting || !norm_active),
        .start(state==N_START && !n_busy && norm_operating),.head_mode(norm_head),
        .in_valid(state==N_FEED && sample_valid && norm_operating),.in_ready(n_input_ready),
        .activation(operand_a),.norm_weight(norm_weight_sample),.out_valid(n_output_valid),
        .out_ready(norm_active && norm_operating),.out_index(n_index),.result(n_result),.out_error(n_error),.busy(n_busy));

    wire p_start_ready,p_input_ready,p_done_valid,p_done_error,p_busy;
    wire p_result_valid /* verilator public_flat_rd */;
    wire [17:0] p_result_index /* verilator public_flat_rd */;
    wire [15:0] p_result /* verilator public_flat_rd */;
    qwen_projection_engine projection(
        .clk(clk),.rst_n(rst_n),.clear(aborting || !projection_active),
        .op_valid(state==P_START && projection_operating),.op_ready(p_start_ready),.op_kind(projection_kind),.op_layer(layer),
        .activation_valid(state==P_FEED && sample_valid && projection_operating),.activation_ready(p_input_ready),.activation(operand_a),
        .result_valid(p_result_valid),.result_ready(projection_active && projection_operating),.result_index(p_result_index),.result(p_result),
        .done_valid(p_done_valid),.done_ready(projection_active && projection_operating),.done_error(p_done_error),.busy(p_busy),
        .memory_request_valid(p_memory_request_valid),.memory_request_ready(p_memory_request_ready),
        .memory_kind(p_memory_kind),.memory_layer(p_memory_layer),.memory_tile(p_memory_tile),
        .scales_valid(scales_phase && model_data_valid && projection_operating),.scales_ready(p_scales_ready),.row_scales(model_data[1023:0]),
        .weights_valid(weights_phase && model_data_valid && projection_operating),.weights_ready(p_weights_ready),.weights(model_data),
        .memory_error(model_error),.memory_abort(p_abort),.memory_quiescent(model_quiescent));

    wire r_input_ready,r_table_ready,r_output_valid,r_error,r_busy;
    wire [5:0] r_pair_index;
    wire [15:0] r_low,r_high;
    reg [1:0] pair_pending;
    reg [5:0] pair_index;
    reg [15:0] pair_low,pair_high;
    wire r_output_ready=rotary_active && pair_pending==0 && rotary_operating;
    qwen_rotary_head rotary(
        .clk(clk),.rst_n(rst_n),.clear(aborting || !rotary_active),
        .start(state==R_START && !r_busy && rotary_operating),
        .in_valid(state==R_FEED && sample_valid && rotary_operating),.in_ready(r_input_ready),.activation(operand_a),
        .table_valid(state==R_FEED && coefficient_count<64 && rotary_operating),.table_ready(r_table_ready),
        .cosine(rotary_coefficient[15:0]),.sine(rotary_coefficient[31:16]),
        .out_valid(r_output_valid),.out_ready(r_output_ready),.out_pair_index(r_pair_index),
        .low_result(r_low),.high_result(r_high),.out_error(r_error),.busy(r_busy));

    wire e_input_ready,e_output_valid,e_error;
    wire [15:0] e_result;
    qwen_bf16_elementwise elementwise(
        .clk(clk),.rst_n(rst_n),.clear(aborting || state!=E_RUN),
        .in_valid(state==E_RUN && sample_valid && elementwise_operating),.in_ready(e_input_ready),
        .multiply(code==18),.a(operand_a),.b(operand_b),.out_valid(e_output_valid),
        .out_ready(state==E_RUN && elementwise_operating),.result(e_result),.out_error(e_error));
    wire s_input_ready,s_output_valid,s_error;
    wire [15:0] s_result;
    qwen_silu_rom #(.ROM_FILE(SILU_ROM_FILE)) silu(
        .clk(clk),.rst_n(rst_n),.clear(aborting || state!=S_RUN),
        .in_valid(state==S_RUN && sample_valid && silu_operating),.in_ready(s_input_ready),.activation(operand_a),
        .out_valid(s_output_valid),.out_ready(state==S_RUN && silu_operating),.result(s_result),.out_error(s_error));

    wire a_start_ready,a_query_ready,a_result_valid,a_done_valid,a_error;
    wire [11:0] a_index;
    wire [15:0] a_result;
    qwen_attention_layer #(.CORES(ATTENTION_CORES),.EXP_ROM_FILE(EXP_ROM_FILE)) attention(
        .clk(clk),.rst_n(rst_n),.clear(aborting || !attention_active),
        .start_valid(state==A_START && attention_operating),.start_ready(a_start_ready),
        .op_layer(layer),.context_length({1'b0,position}+16'd1),
        // Do not feed the child's combinational query-fault signal back into
        // query_valid through the parent's aggregate fault. Any other fault
        // masks commit and clears the child at the following clock.
        .query_valid(state==A_FEED && sample_valid && !aborting),.query_ready(a_query_ready),.query(operand_a),
        .key_valid(key_valid),.key_ready(key_ready),.key_position(key_position),.keys(keys),
        .value_valid(value_valid),.value_ready(value_ready),.value_position(value_position),.value_group(value_group),.values(values),
        .memory_layer(attention_memory_layer),.memory_head(attention_memory_head),
        .memory_error(attention_memory_error),.memory_abort(attention_memory_abort),.memory_quiescent(attention_memory_quiescent),
        .result_valid(a_result_valid),.result_ready(attention_active && attention_operating),.result_index(a_index),.result(a_result),
        .done_valid(a_done_valid),.done_ready(attention_active && attention_operating),.done_error(a_error));

    assign kv_write_start_valid=state==W_START && !aborting && !control_fault;
    assign kv_write_layer=layer;assign kv_write_position=position;
    assign kv_write_valid=state==W_FEED && sample_valid && !aborting && !control_fault;
    assign kv_write_value=sample_index[10];assign kv_write_index=sample_index[9:0];
    assign kv_write_data=operand_a;
    assign kv_write_done_ready=state==W_WAIT && kv_wait_operating;
    assign consumer_ready=state==N_FEED ? n_input_ready : state==P_FEED ? p_input_ready
        : state==R_FEED ? r_input_ready : state==E_RUN ? e_input_ready
        : state==S_RUN ? s_input_ready : state==W_FEED ? kv_write_ready
        : state==A_FEED ? a_query_ready : 1'b0;

    wire [17:0] projection_rows=projection_kind==7 ? 18'd151936
        : (projection_kind==1 || projection_kind==2) ? 18'd1024
        : (projection_kind==4 || projection_kind==5) ? 18'd12288 : 18'd4096;
    wire invalid_projection_output=p_result_valid && (p_result_index!=projection_output_count
        || p_result_index>=projection_rows || (&p_result[14:7]));
    wire invalid_projection_request=p_memory_request_valid && (p_memory_kind!=projection_kind
        || p_memory_layer!=(projection_kind==7 ? 6'd0 : layer));
    // These guards are used only in COMPLETE and W_START. Neither state
    // can consume model beats (M_DATA or projection-active), so model_last_bad
    // is identically false there. The general fault detector still checks it.
    // Retain every state-independent error, including held memory errors.
    assign control_fault=!failed && (model_error || kv_error || (|attention_memory_error)
        || (address_result_valid && address_result_error));
    assign fault=!failed && state!=FLUSH && state!=IDLE &&
        (model_error || kv_error || (|attention_memory_error) || model_last_bad
        || (address_result_valid && address_result_error)
        || (state==M_DATA && buffer_valid && (&loaded_value[14:7]))
        || (norm_active && n_output_valid && (n_error || {2'b0,n_index}>=feed_length))
        || (projection_active && (invalid_projection_output || invalid_projection_request || (p_done_valid && p_done_error)))
        || (rotary_active && r_output_valid && r_error)
        || (state==E_RUN && e_output_valid && e_error) || (state==S_RUN && s_output_valid && s_error)
        || (attention_active && a_done_valid && a_error)
        || (state==W_WAIT && kv_write_done_valid && kv_write_done_error));

    // PRIVATE_STATE_LOCAL_GUARDS: used only under their existing state predicates.
    // Preserve every state-independent error and each active child error.
    // The aggregate fault detector, same-cycle rejection and state updates remain.
    assign norm_operating=!aborting && !control_fault && (failed || !(n_output_valid && (n_error || {2'b0,n_index}>=feed_length)));
    assign projection_operating=!aborting && !control_fault && (failed || !(model_last_bad || invalid_projection_output || invalid_projection_request || (p_done_valid && p_done_error)));
    assign rotary_operating=!aborting && !control_fault && (failed || !(r_output_valid && r_error));
    assign elementwise_operating=!aborting && !control_fault && (failed || !(e_output_valid && e_error));
    assign silu_operating=!aborting && !control_fault && (failed || !(s_output_valid && s_error));
    assign attention_operating=!aborting && !control_fault && (failed || !(a_done_valid && a_error));
    assign kv_wait_operating=!aborting && !control_fault && (failed || !(kv_write_done_valid && kv_write_done_error));

    always @* begin
        tensor_write=0;tensor_write_bank=destination;tensor_write_index=output_count;tensor_write_data=0;
        begin
            if(load_take && load_target==0) begin
                tensor_write=1;tensor_write_bank=X;tensor_write_index=load_count;tensor_write_data=loaded_value;
            end else if(norm_active && n_output_valid && norm_operating) begin
                tensor_write=1;tensor_write_index=feed_base+{2'b0,n_index};tensor_write_data=n_result;
            end else if(projection_active && p_result_valid && code!=22 && projection_operating) begin
                tensor_write=1;tensor_write_index=p_result_index[13:0];tensor_write_data=p_result;
            end else if(rotary_active && pair_pending!=0 && rotary_operating) begin
                tensor_write=1;tensor_write_index=feed_base+{8'b0,pair_index}+(pair_pending==2 ? 14'd64 : 14'd0);
                tensor_write_data=pair_pending==1 ? pair_low : pair_high;
            end else if(state==E_RUN && e_output_valid && elementwise_operating) begin tensor_write=1;tensor_write_data=e_result;end
            else if(state==S_RUN && s_output_valid && silu_operating) begin tensor_write=1;tensor_write_data=s_result;end
            else if(attention_active && a_result_valid && attention_operating) begin
                tensor_write=1;tensor_write_bank=A;tensor_write_index={2'b0,a_index};tensor_write_data=a_result;
            end
        end
    end

    function automatic bf16_greater(input [15:0] a,input [15:0] b);
        begin
            if(a[14:0]==0 && b[14:0]==0) bf16_greater=0;
            else if(a[15]!=b[15]) bf16_greater=!a[15];
            else bf16_greater=a[15] ? a[14:0]<b[14:0] : a[14:0]>b[14:0];
        end
    endfunction

    always @(posedge clk) begin
        if(!rst_n || core_abort) begin
            state<=FLUSH;code<=0;layer<=0;position<=0;token<=0;failed<=0;report_failure<=0;
            head_valid<=0;attention_committed<=0;best_value<=0;best_token<=0;head<=0;
            output_count<=0;projection_output_count<=0;feed_count<=0;sample_index<=0;sample_valid<=0;
            buffer_valid<=0;buffer_index<=0;load_count<=0;load_elements<=0;load_beats<=0;load_target<=0;
            coefficient_count<=0;pair_pending<=0;pair_index<=0;pair_low<=0;pair_high<=0;
            projection_memory_state<=PS_IDLE;projection_memory_tile<=0;projection_memory_group<=0;
        end else if(fault) begin
            state<=FLUSH;failed<=1;report_failure<=1;head_valid<=0;attention_committed<=0;
            sample_valid<=0;buffer_valid<=0;pair_pending<=0;projection_memory_state<=PS_IDLE;
        end else begin
            if(!feed_active) sample_valid<=0;
            else if(feed_advance) begin
                sample_valid<=feed_issue;
                if(feed_issue) begin sample_index<=feed_count;feed_count<=feed_count+1'b1;end
            end
            // PRIVATE_VECTOR_ACCEPT: M_DATA cannot also consume projection beats.
            if(state==M_DATA && model_data_valid && operating && !buffer_valid) begin
                buffer_valid<=1;buffer_index<=0;load_beats<=load_beats+1'b1;
            end
            if(load_take) begin
                load_count<=load_count+1'b1;
                if(buffer_index==127) buffer_valid<=0;else buffer_index<=buffer_index+1'b1;
            end
            if(projection_active) begin
                case(projection_memory_state)
                    PS_IDLE:if(p_memory_request_valid && p_memory_request_ready) begin
                        projection_memory_tile<=p_memory_tile;projection_memory_group<=0;projection_memory_state<=PS_PLAN;
                    end
                    PS_PLAN:if(address_input_valid && address_input_ready) projection_memory_state<=PS_HEADER;
                    PS_HEADER:if(model_request_valid && model_request_ready) projection_memory_state<=PS_DATA;
                    PS_DATA:if(model_take) projection_memory_state<=PW_PLAN;
                    PW_PLAN:if(address_input_valid && address_input_ready) projection_memory_state<=PW_HEADER;
                    PW_HEADER:if(model_request_valid && model_request_ready) projection_memory_state<=PW_DATA;
                    PW_DATA:if(model_take) begin
                        if(projection_memory_group==projection_last_group) projection_memory_state<=PS_IDLE;
                        else projection_memory_group<=projection_memory_group+1'b1;
                    end
                    default:projection_memory_state<=PS_IDLE;
                endcase
                if(p_result_valid && operating) begin
                    projection_output_count<=projection_output_count+1'b1;
                    if(code==22 && (projection_output_count==0 || bf16_greater(p_result,best_value))) begin
                        best_value<=p_result;best_token<=p_result_index;
                    end
                end
            end
            if(state==R_FEED && coefficient_count<64 && r_table_ready && operating)
                coefficient_count<=coefficient_count+1'b1;
            if(rotary_active && r_output_valid && r_output_ready) begin
                pair_pending<=1;pair_index<=r_pair_index;pair_low<=r_low;pair_high<=r_high;
            end else if(rotary_active && pair_pending==1) pair_pending<=2;
            else if(rotary_active && pair_pending==2) pair_pending<=0;

            case(state)
                FLUSH:if(external_quiet && !core_abort) begin
                    state<=report_failure ? COMPLETE : IDLE;report_failure<=0;
                end
                IDLE:if(op_valid && op_ready) begin
                    code<=op_code;layer<=op_layer;position<=op_position;token<=op_token;
                    failed<=0;head<=0;output_count<=0;projection_output_count<=0;
                    feed_count<=0;sample_valid<=0;pair_pending<=0;coefficient_count<=0;
                    load_count<=0;load_beats<=0;buffer_valid<=0;projection_memory_state<=PS_IDLE;
                    if(op_code>23 || (op_code>0 && op_code<21 && op_layer>=36)
                            || (op_code==0 && op_token>=151936)) begin
                        failed<=1;report_failure<=1;state<=FLUSH;
                    end else case(op_code)
                        0:begin load_target<=0;load_elements<=4096;head_valid<=0;attention_committed<=0;state<=M_PLAN;end
                        1,3,5,14,21:begin
                            load_target<=1;load_elements<=(op_code==3 || op_code==5) ? 14'd128 : 14'd4096;state<=M_PLAN;
                        end
                        2,4,6,12,15,16,19,22:begin state<=P_START;if(op_code==22) head_valid<=0;end
                        7:begin load_target<=2;load_elements<=128;state<=M_PLAN;end
                        8:state<=W_START;
                        9:begin attention_committed<=0;state<=A_START;end
                        10,11:begin
                            if(attention_committed) state<=COMPLETE;
                            else begin failed<=1;report_failure<=1;state<=FLUSH;end
                        end
                        13,18,20:state<=E_RUN;
                        17:state<=S_RUN;
                        23:begin
                            if(head_valid) state<=COMPLETE;
                            else begin failed<=1;report_failure<=1;state<=FLUSH;end
                        end
                        default:begin failed<=1;report_failure<=1;state<=FLUSH;end
                    endcase
                end
                M_PLAN:if(address_input_valid && address_input_ready) state<=M_HEADER;
                M_HEADER:if(model_request_valid && model_request_ready) state<=M_DATA;
                M_DATA:if(load_finished) state<=load_target==0 ? COMPLETE : (load_target==1 ? N_START : R_START);
                N_START:if(!n_busy) begin feed_count<=0;sample_valid<=0;state<=N_FEED;end
                N_FEED:if(feed_finished) state<=N_WAIT;
                N_WAIT:if(n_output_valid && operating && {2'b0,n_index}==feed_length-1'b1) begin
                    if(norm_head && head!=(code==3 ? 6'd31 : 6'd7)) begin head<=head+1'b1;state<=N_START;end
                    else state<=COMPLETE;
                end
                P_START:if(p_start_ready) begin feed_count<=0;sample_valid<=0;state<=P_FEED;end
                P_FEED:if(feed_finished) state<=P_WAIT;
                P_WAIT:if(p_done_valid && operating) begin
                    if(projection_output_count!=projection_rows || projection_memory_state!=PS_IDLE) begin
                        failed<=1;report_failure<=1;state<=FLUSH;head_valid<=0;
                    end else begin if(code==22) head_valid<=1;state<=COMPLETE;end
                end
                R_START:if(!r_busy) begin
                    feed_count<=0;sample_valid<=0;coefficient_count<=0;pair_pending<=0;state<=R_FEED;
                end
                R_FEED:if(feed_finished) state<=R_WAIT;
                R_WAIT:if(pair_pending==2 && pair_index==63) begin
                    if(head==39) state<=COMPLETE;else begin head<=head+1'b1;state<=R_START;end
                end
                E_RUN:if(e_output_valid && operating) begin
                    if(output_count==feed_length-1'b1) state<=COMPLETE;else output_count<=output_count+1'b1;
                end
                S_RUN:if(s_output_valid && operating) begin
                    if(output_count==feed_length-1'b1) state<=COMPLETE;else output_count<=output_count+1'b1;
                end
                W_START:if(kv_write_start_ready) begin feed_count<=0;sample_valid<=0;state<=W_FEED;end
                W_FEED:if(feed_finished) state<=W_WAIT;
                W_WAIT:if(kv_write_done_valid && operating) state<=COMPLETE;
                A_START:if(a_start_ready) begin feed_count<=0;sample_valid<=0;state<=A_FEED;end
                A_FEED:if(feed_finished) state<=A_WAIT;
                A_WAIT:if(a_done_valid && operating) begin attention_committed<=1;state<=COMPLETE;end
                COMPLETE:if(core_done) state<=IDLE;
                default:begin failed<=1;report_failure<=1;state<=FLUSH;end
            endcase
        end
    end
    wire unused_internal=^{p_abort,p_busy};
endmodule
