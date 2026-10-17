// Shell-clock token-only register endpoint plus private command/result CDC.
// This is NOT the complete AWS shell: bulk provisioning, vendor HBM, unused
// interface termination and physical constraints remain separate integration.
// core_* ports connect only to the fixed token machine, never to host registers.
module qwen_ocl_control (
    input wire rst_n,input wire shell_clk,input wire core_clk,
    input wire [31:0] ocl_awaddr,input wire ocl_awvalid,output wire ocl_awready,
    input wire [31:0] ocl_wdata,input wire [3:0] ocl_wstrb,input wire ocl_wvalid,output wire ocl_wready,
    output wire [1:0] ocl_bresp,output wire ocl_bvalid,input wire ocl_bready,
    input wire [31:0] ocl_araddr,input wire ocl_arvalid,output wire ocl_arready,
    output wire [31:0] ocl_rdata,output wire [1:0] ocl_rresp,output wire ocl_rvalid,input wire ocl_rready,
    output wire core_cmd_valid,output wire core_cmd_clear_valid,input wire core_cmd_ready,
    output wire [7:0] core_cmd_opcode,output wire [31:0] core_cmd_token,
    input wire core_response_valid,output wire core_response_ready,
    input wire [3:0] core_response_status,input wire [31:0] core_response_token,
    input wire core_model_ready,input wire core_model_loading,input wire core_model_error,
    input wire ingress_error,input wire [15:0] ingress_credit_blocks,input wire [31:0] ingress_received_bytes
);
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] shell_reset_release;
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] ready_sync,loading_sync,error_sync;
    wire shell_reset_n=shell_reset_release[2];
    (* ASYNC_REG="TRUE", SHREG_EXTRACT="NO" *) reg [2:0] status_core_reset_release;
    wire status_core_reset_n=status_core_reset_release[2];
    reg ready_source,loading_source,error_source;
    always @(posedge core_clk or negedge rst_n)begin
        if(!rst_n)status_core_reset_release<=0;
        else status_core_reset_release<={status_core_reset_release[1:0],1'b1};
    end
    // Source registers prevent combinational status glitches from crossing.
    // These are advisory copies, not the sequencer's actual boot permission.
    always @(posedge core_clk or negedge status_core_reset_n)begin
        if(!status_core_reset_n)begin ready_source<=0;loading_source<=0;error_source<=0;end
        else begin
            ready_source<=core_model_ready;
            loading_source<=core_model_loading;
            error_source<=core_model_error;
        end
    end
    always @(posedge shell_clk or negedge rst_n)begin
        if(!rst_n)shell_reset_release<=0;
        else shell_reset_release<={shell_reset_release[1:0],1'b1};
    end
    always @(posedge shell_clk or negedge shell_reset_n)begin
        if(!shell_reset_n)begin ready_sync<=0;loading_sync<=0;error_sync<=0;end
        else begin
            ready_sync<={ready_sync[1:0],ready_source};
            loading_sync<={loading_sync[1:0],loading_source};
            error_sync<={error_sync[1:0],error_source};
        end
    end
    // Synchronized status is advisory only. Native STEP permission is checked
    // again by the sequencer in the core clock domain, using the true signal.
    wire command_valid,command_ready,result_valid,result_ready;
    wire [31:0] command_id,command_token,result_id,result_token;
    wire [7:0] command_opcode;
    wire [3:0] result_status;
    qwen_ocl_token_registers registers(
        .clk(shell_clk),.rst_n(shell_reset_n),.model_ready(ready_sync[2]),
        .model_loading(loading_sync[2]),.model_error(error_sync[2]),.*);
    qwen_token_command_cdc crossing(.core_cmd_clear_valid(core_cmd_clear_valid),.*);
endmodule
