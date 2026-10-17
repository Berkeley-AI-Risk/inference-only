// Token commands/results ONLY. No model, K/V, tensor or arithmetic port crosses
// this boundary. IDs are assigned by the shell register controller, not by the
// application, and associate results with the currently live request.
//
// Contract: at most one ordinary command outstanding; one subsequent CLEAR may
// cancel it. No next ordinary command before consuming the latest result. The
// source enforces this contract. CLEAR can replace an unaccepted pending normal
// command and bypass an active STEP; it does not wait for STEP's result FIFO.
// Old results already in the return FIFO are discarded by source-side ID checks.
// Fabric reset is coordinated across both domains; CLEAR never resets a FIFO.
module qwen_token_command_cdc (
    input wire rst_n,input wire shell_clk,input wire core_clk,
    input wire command_valid,output wire command_ready,
    input wire [31:0] command_id,input wire [7:0] command_opcode,input wire [31:0] command_token,
    output wire result_valid,input wire result_ready,
    output wire [31:0] result_id,output wire [3:0] result_status,output wire [31:0] result_token,
    output wire core_cmd_valid,output wire core_cmd_clear_valid,input wire core_cmd_ready,
    output wire [7:0] core_cmd_opcode,output wire [31:0] core_cmd_token,
    input wire core_response_valid,output wire core_response_ready,
    input wire [3:0] core_response_status,input wire [31:0] core_response_token
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] core_reset_release;
    wire core_reset_n=core_reset_release[2];
    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)core_reset_release<=0;
        else core_reset_release<={core_reset_release[1:0],1'b1};
    end
    wire forward_valid,forward_ready;
    wire [71:0] forward_data;
    wire returned_valid,returned_ready;
    wire [67:0] returned_data;
    reg pending_valid,active;
    reg [71:0] pending;
    reg [31:0] active_id;
    wire pending_clear=pending_valid && pending[39:32]==8'd3;
    wire incoming_clear=forward_valid && forward_data[39:32]==8'd3;
    wire running=core_reset_n;
    wire command_take=core_cmd_valid && core_cmd_ready;
    wire clear_take=command_take && core_cmd_opcode==8'd3;
    wire discard_response=pending_clear || clear_take;
    wire response_take=core_response_valid && core_response_ready;

    qwen_async_stream_fifo #(.WIDTH(72),.ADDRESS_BITS(2),.MEMORY_STYLE("block")) commands(
        .rst_n(rst_n),.source_clk(shell_clk),.source_valid(command_valid),.source_ready(command_ready),
        .source_data({command_id,command_opcode,command_token}),
        .destination_clk(core_clk),.destination_valid(forward_valid),.destination_ready(forward_ready),.destination_data(forward_data));
    qwen_async_stream_fifo #(.WIDTH(68),.ADDRESS_BITS(2),.MEMORY_STYLE("block")) results(
        .rst_n(rst_n),.source_clk(core_clk),.source_valid(returned_valid),.source_ready(returned_ready),
        .source_data(returned_data),.destination_clk(shell_clk),
        .destination_valid(result_valid),.destination_ready(result_ready),.destination_data({result_id,result_status,result_token}));

    // A queued CLEAR suppresses an unaccepted ordinary command immediately.
    // The native sequencer itself suppresses its old response on CLEAR accept.
    assign core_cmd_valid=running && pending_valid && (pending_clear || (!active && !incoming_clear));
    // PRIVATE: exact CLEAR qualification from owned pending registers.
    // No raw FIFO lookahead reaches this dedicated abort qualification.
    assign core_cmd_clear_valid=running && pending_valid && pending[39:32]==8'd3 && pending[31:0]==32'd0;
    assign core_cmd_opcode=pending[39:32];
    assign core_cmd_token=pending[31:0];
    assign forward_ready=running && (!pending_valid || command_take || (incoming_clear && !pending_clear));
    assign core_response_ready=running && (!active || discard_response || returned_ready);
    assign returned_valid=running && active && !discard_response && core_response_valid;
    assign returned_data={active_id,core_response_status,core_response_token};

    always @(posedge core_clk or negedge core_reset_n)begin
        if(!core_reset_n)begin pending_valid<=0;pending<=0;active<=0;active_id<=0;end
        else begin
            if(response_take && !discard_response)active<=0;
            if(command_take)begin pending_valid<=0;active<=1;active_id<=pending[71:40];end
            if(forward_valid && forward_ready)begin pending_valid<=1;pending<=forward_data;end
        end
    end
endmodule
