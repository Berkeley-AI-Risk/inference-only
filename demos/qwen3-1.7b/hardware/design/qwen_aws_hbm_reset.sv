// Fixed reset fence for the pinned AWS cl_mem_hbm_wrapper.
// Reset BOTH APB/controller and AXI: AMD PG276 forbids AXI-only warm resets.
// The wrapper delays APB reset by four shell clocks, an async-assert/four-edge
// release synchronizer, and four reference clocks. AXI reset has four stages.
// Keep clocks running through ordinary FLR. Require fresh reset-clock edges,
// HBM ready LOW while reset is held, then fresh initialization before use.
// This is not a substitute for vendor-IP simulation or physical CDC checking.
module qwen_aws_hbm_reset (
    input wire shell_clk,input wire reference_clk,input wire memory_clk,
    input wire rst_n,input wire release_request,input wire flr_assert,
    input wire raw_hbm_ready,
    output wire clock_control_reset_n,
    output wire hbm_controller_reset_n,output wire hbm_axi_reset_n,
    output wire qualified_hbm_ready,output reg flr_reset_done
);
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] configuration_release;
    always @(posedge shell_clk or negedge rst_n)begin
        if(!rst_n)configuration_release<=0;
        else configuration_release<={configuration_release[1:0],1'b1};
    end
    assign clock_control_reset_n=configuration_release[2];

    // Even a short request for reset starts a complete new hold interval.
    // Timers begin after release_request rises; no earlier offline interval
    // can satisfy them. The reference/memory holds begin after eight shell
    // clocks, longer than the wrapper's initial four-shell-clock pipeline.
    wire request_n=rst_n && release_request;
    reg [6:0] shell_hold;
    reg shell_eight;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] reference_start,memory_start;
    reg [4:0] reference_hold,memory_hold;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] reference_done_sync,memory_done_sync;
    reg controller_released;
    always @(posedge shell_clk or negedge request_n)begin
        if(!request_n)begin
            shell_hold<=0;shell_eight<=0;reference_done_sync<=0;memory_done_sync<=0;
            controller_released<=0;
        end else begin
            if(shell_hold<7'd64)shell_hold<=shell_hold+1'b1;
            if(shell_hold==7'd7)shell_eight<=1;
            // Saturating counters' high bits are registered one-bit levels;
            // do not put combinational multi-bit compares before synchronizers.
            reference_done_sync<={reference_done_sync[1:0],reference_hold[4]};
            memory_done_sync<={memory_done_sync[1:0],memory_hold[4]};
            if(shell_hold==7'd64 && reference_done_sync[2] && memory_done_sync[2]
                    && !raw_hbm_ready)controller_released<=1;
        end
    end
    wire reference_start_reset_n=shell_eight;
    always @(posedge reference_clk or negedge reference_start_reset_n)begin
        if(!reference_start_reset_n)reference_start<=0;
        else reference_start<={reference_start[1:0],1'b1};
    end
    wire reference_counter_reset_n=reference_start[2];
    always @(posedge reference_clk or negedge reference_counter_reset_n)begin
        if(!reference_counter_reset_n)reference_hold<=0;
        else if(reference_hold<5'd16)reference_hold<=reference_hold+1'b1;
    end
    wire memory_start_reset_n=shell_eight;
    always @(posedge memory_clk or negedge memory_start_reset_n)begin
        if(!memory_start_reset_n)memory_start<=0;
        else memory_start<={memory_start[1:0],1'b1};
    end
    wire memory_counter_reset_n=memory_start[2];
    always @(posedge memory_clk or negedge memory_counter_reset_n)begin
        if(!memory_counter_reset_n)memory_hold<=0;
        else if(memory_hold<5'd16)memory_hold<=memory_hold+1'b1;
    end
    assign hbm_controller_reset_n=controller_released;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] axi_release;
    (* SHREG_EXTRACT="NO" *) reg [7:0] axi_settle;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] axi_settle_sync;
    always @(posedge memory_clk or negedge hbm_controller_reset_n)begin
        if(!hbm_controller_reset_n)axi_release<=0;
        else axi_release<={axi_release[1:0],1'b1};
    end
    wire axi_settle_reset_n=axi_release[2];
    always @(posedge memory_clk or negedge axi_settle_reset_n)begin
        if(!axi_settle_reset_n)axi_settle<=0;
        else axi_settle<={axi_settle[6:0],1'b1};
    end
    assign hbm_axi_reset_n=axi_release[2];
    always @(posedge shell_clk or negedge hbm_controller_reset_n)begin
        if(!hbm_controller_reset_n)axi_settle_sync<=0;
        else axi_settle_sync<={axi_settle_sync[1:0],axi_settle[7]};
    end
    assign qualified_hbm_ready=axi_settle_sync[2] && raw_hbm_ready;

    // The lifecycle owner separately checks core/memory reset and a 64-shell-
    // cycle FLR hold. Add fresh reference-clock and vendor-pipeline fences.
    // The capture is cleared OUTSIDE this FLR, including between clock edges.
    wire flr_capture_n=rst_n && flr_assert;
    (* SHREG_EXTRACT="NO" *) reg [7:0] flr_shell_edges;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] flr_reference_start,flr_memory_start;
    reg [4:0] flr_reference_hold,flr_memory_hold;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] flr_reference_sync,flr_memory_sync;
    // Start at "not observed reset" for each new FLR. Sample the memory-
    // domain reset level directly; only the last stage is inverted.
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] axi_reset_state_sync;
    wire flr_reference_start_reset_n=flr_shell_edges[7];
    always @(posedge reference_clk or negedge flr_reference_start_reset_n)begin
        if(!flr_reference_start_reset_n)flr_reference_start<=0;
        else flr_reference_start<={flr_reference_start[1:0],1'b1};
    end
    wire flr_reference_counter_reset_n=flr_reference_start[2];
    always @(posedge reference_clk or negedge flr_reference_counter_reset_n)begin
        if(!flr_reference_counter_reset_n)flr_reference_hold<=0;
        else if(flr_reference_hold<5'd16)flr_reference_hold<=flr_reference_hold+1'b1;
    end
    wire flr_memory_start_reset_n=flr_shell_edges[7];
    always @(posedge memory_clk or negedge flr_memory_start_reset_n)begin
        if(!flr_memory_start_reset_n)flr_memory_start<=0;
        else flr_memory_start<={flr_memory_start[1:0],1'b1};
    end
    wire flr_memory_counter_reset_n=flr_memory_start[2];
    always @(posedge memory_clk or negedge flr_memory_counter_reset_n)begin
        if(!flr_memory_counter_reset_n)flr_memory_hold<=0;
        else if(flr_memory_hold<5'd16)flr_memory_hold<=flr_memory_hold+1'b1;
    end
    always @(posedge shell_clk or negedge flr_capture_n)begin
        if(!flr_capture_n)begin
            flr_shell_edges<=0;flr_reference_sync<=0;flr_memory_sync<=0;flr_reset_done<=0;
            axi_reset_state_sync<=3'b111;
        end else begin
            flr_shell_edges<={flr_shell_edges[6:0],1'b1};
            axi_reset_state_sync<={axi_reset_state_sync[1:0],hbm_axi_reset_n};
            flr_reference_sync<={flr_reference_sync[1:0],flr_reference_hold[4]};
            flr_memory_sync<={flr_memory_sync[1:0],flr_memory_hold[4]};
            if(flr_reference_sync[2] && flr_memory_sync[2] && !raw_hbm_ready
                    && !hbm_controller_reset_n && !axi_reset_state_sync[2])flr_reset_done<=1;
        end
    end
endmodule
