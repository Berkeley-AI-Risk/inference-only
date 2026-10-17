// Fixed shell/core/HBM lifecycle owner. No application command inputs.
// rst_n is the shell reset; FLR is a management reset, not application CLEAR.
// Host guards and the private clock-control fabric share host_reset_n. Private
// machine reset and guard online fall together; the HBM AXI reset is asserted
// on the same fault/reset, with vendor reset-pipeline latency still to qualify.
// HBM is released BEFORE online so waiting for initialization cannot deadlock.
// Faults latch until shell reset; FLR alone cannot clear a hardware/monitor fault.
// HBM monitor reset pins must ALSO connect directly to the vendor HBM wrapper.
module qwen_aws_lifecycle #(
    parameter integer STARTUP_TIMEOUT_CYCLES=250000000,
    parameter integer FLR_HOLD_CYCLES=64
) (
    input wire shell_clk,input wire core_clk,input wire memory_clk,input wire rst_n,
    input wire flr_assert,output reg flr_done,
    input wire clock_ready,input wire clock_failed,input wire interface_fault,
    input wire generated_core_reset_n,input wire generated_memory_reset_n,
    input wire generated_reference_reset_n,input wire hbm_ready,
    input wire [1:0] hbm_monitor_reset_n,
    output wire host_reset_n,output wire machine_reset_n,output wire online,
    (* keep="true" *) output wire host_guard_ready,
    output wire hbm_shell_reset_n,output wire hbm_memory_reset_n,
    output reg failed,output reg [3:0] error_code
);
    localparam integer START_BITS=$clog2(STARTUP_TIMEOUT_CYCLES+1);
    localparam integer FLR_BITS=$clog2(FLR_HOLD_CYCLES+1);
    initial if(STARTUP_TIMEOUT_CYCLES<64 || FLR_HOLD_CYCLES<16)
        $fatal(1,"Unsupported fixed lifecycle timers");
    wire host_async_reset_n=rst_n && !flr_assert;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] host_release;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] core_reset_sync,memory_reset_sync,reference_reset_sync;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] monitor0_sync,monitor1_sync;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] hbm_memory_release,memory_release_sync;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] core_ack_sync,memory_ack_sync;
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [7:0] core_reset_edges,memory_reset_edges;
    reg started,monitors_seen;
    reg [START_BITS-1:0] startup_timer;
    reg [FLR_BITS-1:0] flr_timer;
    wire resets_ok=core_reset_sync[2] && memory_reset_sync[2] && reference_reset_sync[2];
    wire monitors_ok=monitor0_sync[2] && monitor1_sync[2];
    assign host_reset_n=host_release[2];
    assign hbm_shell_reset_n=host_reset_n && clock_ready && resets_ok && monitors_ok && !failed;
    assign hbm_memory_reset_n=hbm_memory_release[2];
    wire healthy=clock_ready && !clock_failed && !interface_fault && resets_ok && monitors_ok
        && hbm_ready && memory_release_sync[2];
    // Private pre-reset qualification, ONLY for host guards that also
    // receive host_reset_n. Never use this as a machine reset or ABI status.
    assign host_guard_ready=started && healthy;
    assign online=host_reset_n && started && healthy;
    assign machine_reset_n=online;

    always @(posedge shell_clk or negedge host_async_reset_n)begin
        if(!host_async_reset_n)host_release<=0;
        else host_release<={host_release[1:0],1'b1};
    end
    always @(posedge memory_clk or negedge hbm_shell_reset_n)begin
        if(!hbm_shell_reset_n)hbm_memory_release<=0;
        else hbm_memory_release<={hbm_memory_release[1:0],1'b1};
    end
    // Acknowledgements belong to THIS FLR, not a previous offline interval.
    // Hold their synchronizers clear outside FLR, then require eight new edges
    // in each generated clock domain. Otherwise a stopped clock could reuse
    // reset edges from calibration or from an earlier FLR. The shell timer and
    // acknowledgement are also cleared when FLR drops, even between clocks.
    wire flr_capture_n=rst_n && flr_assert;
    // Local release for functional shell FLR state. Assertion remains
    // asynchronous, including an FLR deassertion between clock edges.
    // Only this constant-one chain sees the raw combined reset. Ordinary
    // timer/acknowledgement recovery/removal and all data paths remain timed.
    (* ASYNC_REG="TRUE",SHREG_EXTRACT="NO" *) reg [2:0] flr_shell_release;
    wire flr_shell_capture_n=flr_shell_release[2];
    always @(posedge shell_clk or negedge flr_capture_n)begin
        if(!flr_capture_n)flr_shell_release<=0;
        else flr_shell_release<={flr_shell_release[1:0],1'b1};
    end
    always @(posedge core_clk or negedge flr_capture_n)begin
        if(!flr_capture_n)core_reset_edges<=0;
        else core_reset_edges<={core_reset_edges[6:0],1'b1};
    end
    always @(posedge memory_clk or negedge flr_capture_n)begin
        if(!flr_capture_n)memory_reset_edges<=0;
        else memory_reset_edges<={memory_reset_edges[6:0],1'b1};
    end
    always @(posedge shell_clk or negedge flr_shell_capture_n)begin
        if(!flr_shell_capture_n)begin
            core_ack_sync<=0;memory_ack_sync<=0;flr_timer<=0;flr_done<=0;
        end else begin
            core_ack_sync<={core_ack_sync[1:0],core_reset_edges[7]};
            memory_ack_sync<={memory_ack_sync[1:0],memory_reset_edges[7]};
            if(flr_timer<FLR_BITS'(FLR_HOLD_CYCLES))flr_timer<=flr_timer+1'b1;
            if(flr_timer>=FLR_BITS'(FLR_HOLD_CYCLES-1) && core_ack_sync[2] && memory_ack_sync[2])flr_done<=1;
        end
    end
    always @(posedge shell_clk or negedge rst_n)begin
        if(!rst_n)begin
            core_reset_sync<=0;memory_reset_sync<=0;reference_reset_sync<=0;
            monitor0_sync<=0;monitor1_sync<=0;memory_release_sync<=0;
        end else begin
            core_reset_sync<={core_reset_sync[1:0],generated_core_reset_n};
            memory_reset_sync<={memory_reset_sync[1:0],generated_memory_reset_n};
            reference_reset_sync<={reference_reset_sync[1:0],generated_reference_reset_n};
            monitor0_sync<={monitor0_sync[1:0],hbm_monitor_reset_n[0]};
            monitor1_sync<={monitor1_sync[1:0],hbm_monitor_reset_n[1]};
            memory_release_sync<={memory_release_sync[1:0],hbm_memory_reset_n};
        end
    end
    wire startup_expired=clock_ready && !started && startup_timer==START_BITS'(STARTUP_TIMEOUT_CYCLES-1);
    reg [3:0] fault_code;
    always @* begin
        fault_code=0;
        if(clock_failed)fault_code=1;
        else if(interface_fault && !flr_assert)fault_code=6;
        else if(monitors_seen && !monitors_ok)fault_code=3;
        else if(started && !flr_assert && (!clock_ready || !resets_ok || !memory_release_sync[2]))fault_code=4;
        else if(started && !flr_assert && !hbm_ready)fault_code=2;
        else if(!flr_assert && startup_expired)fault_code=5;
    end
    always @(posedge shell_clk or negedge rst_n)begin
        if(!rst_n)begin
            failed<=0;error_code<=0;started<=0;monitors_seen<=0;
            startup_timer<=0;
        end else begin
            if(monitors_ok)monitors_seen<=1;
            if(!failed && fault_code!=0)begin failed<=1;error_code<=fault_code;end
            if(failed || fault_code!=0 || flr_assert)started<=0;
            else if(host_reset_n && healthy)started<=1;
            if(started || flr_assert || failed || !clock_ready)startup_timer<=0;
            else if(!startup_expired)startup_timer<=startup_timer+1'b1;
        end
    end
endmodule
