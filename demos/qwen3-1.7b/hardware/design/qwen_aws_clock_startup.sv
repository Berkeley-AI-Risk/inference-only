// PRIVATE, fixed initialization/monitoring master for the pinned AWS clock block.
// Run on raw shell clk_main_a0, NOT an output held in reset by aws_clk_gen.
// No host input, model operation, clock recipe, or address/data programming port.
// Recipes are build-time choices. Only C1, main, HBM-ref and HBM-AXI are released.
// Reset must also reset the clock block's AXI fabric. CLEAR is NOT this reset.
// Failure closes ready permanently until that coordinated reset. Outstanding
// requests retain AXI VALID/payload until accepted; timeout does not retract them.
// Lock polling is not an instantaneous clock-fault detector or tamper guarantee.
module qwen_aws_clock_startup #(
    parameter integer TIMEOUT_CYCLES=250000000,
    parameter integer POLL_INTERVAL=1024
) (
    input wire clk,input wire rst_n,
    output reg ready,output reg failed,output reg [3:0] error_code,
    output wire [31:0] m_awaddr,output wire m_awvalid,input wire m_awready,
    output wire [31:0] m_wdata,output wire [3:0] m_wstrb,
    output wire m_wvalid,input wire m_wready,
    input wire [1:0] m_bresp,input wire m_bvalid,output wire m_bready,
    output wire [31:0] m_araddr,output wire m_arvalid,input wire m_arready,
    input wire [31:0] m_rdata,input wire [1:0] m_rresp,
    input wire m_rvalid,output wire m_rready
);
    localparam [31:0] RESET_ADDR=32'h00058014,LOCK_ADDR=32'h00058020;
    localparam [31:0] HOLD_MASK=32'hfffffffe,RELEASE_MASK=32'hfffffc7e;
    localparam [31:0] LOCK_MASK=32'h00000140; // C at bit 6, HBM at bit 8.
    localparam integer TIMER_BITS=$clog2(TIMEOUT_CYCLES+1);
    localparam integer POLL_BITS=POLL_INTERVAL>1 ? $clog2(POLL_INTERVAL) : 1;
    localparam [3:0] HOLD_W=0,HOLD_B=1,HOLD_AR=2,HOLD_R=3,
        LOCK_AR=4,LOCK_R=5,LOCK_WAIT=6,RELEASE_W=7,RELEASE_B=8,
        VERIFY_AR=9,VERIFY_R=10,MONITOR_WAIT=11,MONITOR_AR=12,
        MONITOR_R=13,STOP=14;
    reg [3:0] state;
    reg aw_done,w_done,startup_done;
    reg [TIMER_BITS-1:0] startup_timer,transaction_timer;
    reg [POLL_BITS-1:0] poll_timer;
    initial begin
        if(TIMEOUT_CYCLES<16 || POLL_INTERVAL<1 || POLL_INTERVAL>=TIMEOUT_CYCLES)
            $fatal(1,"Unsupported fixed clock startup timers");
    end

    wire writing=state==HOLD_W || state==RELEASE_W;
    wire reading=state==HOLD_AR || state==LOCK_AR || state==VERIFY_AR || state==MONITOR_AR;
    wire waiting=state==LOCK_WAIT || state==MONITOR_WAIT || state==STOP;
    assign m_awaddr=RESET_ADDR;
    assign m_wdata=state==HOLD_W || state==HOLD_B ? HOLD_MASK : RELEASE_MASK;
    assign m_wstrb=4'hf;
    assign m_awvalid=rst_n && writing && !aw_done;
    assign m_wvalid=rst_n && writing && !w_done;
    assign m_bready=rst_n && (state==HOLD_B || state==RELEASE_B);
    assign m_araddr=state==HOLD_AR || state==HOLD_R || state==VERIFY_AR || state==VERIFY_R
        ? RESET_ADDR : LOCK_ADDR;
    assign m_arvalid=rst_n && reading;
    assign m_rready=rst_n && (state==HOLD_R || state==LOCK_R || state==VERIFY_R || state==MONITOR_R);
    wire aw_take=m_awvalid && m_awready;
    wire w_take=m_wvalid && m_wready;
    wire b_take=m_bvalid && m_bready;
    wire ar_take=m_arvalid && m_arready;
    wire r_take=m_rvalid && m_rready;
    wire progress=aw_take || w_take || b_take || ar_take || r_take;
    wire timer_expired=!failed && ((!startup_done && startup_timer==TIMER_BITS'(TIMEOUT_CYCLES-1))
        || (!waiting && !progress && transaction_timer==TIMER_BITS'(TIMEOUT_CYCLES-1)));
    wire bad_write=b_take && m_bresp!=0;
    wire bad_read=r_take && m_rresp!=0;
    wire bad_readback=r_take && (state==HOLD_R && m_rdata!=HOLD_MASK
        || state==VERIFY_R && m_rdata!=RELEASE_MASK);
    wire lost_lock=r_take && state==MONITOR_R && (m_rdata&LOCK_MASK)!=LOCK_MASK;
    wire fail_now=failed || timer_expired || bad_write || bad_read || bad_readback || lost_lock;

    // Private polling state only: never gate this counter with CSR read data.
    // Entering either wait state always starts from zero. On a fault the
    // original state machine still stops; the unused counter is not exposed.
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) poll_timer<=0;
        else if(state==LOCK_WAIT || state==MONITOR_WAIT) begin
            if(poll_timer!=POLL_BITS'(POLL_INTERVAL-1)) poll_timer<=poll_timer+1'b1;
        end else poll_timer<=0;
    end

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            ready<=0;failed<=0;error_code<=0;state<=HOLD_W;
            aw_done<=0;w_done<=0;startup_done<=0;
            startup_timer<=0;transaction_timer<=0;
        end else begin
            if(!startup_done && !failed && !timer_expired) startup_timer<=startup_timer+1'b1;
            if(waiting || progress) transaction_timer<=0;
            else if(!failed && !timer_expired) transaction_timer<=transaction_timer+1'b1;
            if(fail_now) begin
                ready<=0;failed<=1;
                if(!failed) begin
                    if(bad_write) error_code<=2;
                    else if(bad_read) error_code<=3;
                    else if(bad_readback) error_code<=4;
                    else if(lost_lock) error_code<=5;
                    else error_code<=1;
                end
            end
            case(state)
                HOLD_W,RELEASE_W: begin
                    if(aw_take) aw_done<=1;
                    if(w_take) w_done<=1;
                    if((aw_done || aw_take) && (w_done || w_take))
                        state<=state==HOLD_W ? HOLD_B : RELEASE_B;
                end
                HOLD_B: if(b_take) state<=fail_now ? STOP : HOLD_AR;
                RELEASE_B: if(b_take) state<=fail_now ? STOP : VERIFY_AR;
                HOLD_AR: if(ar_take) state<=HOLD_R;
                LOCK_AR: if(ar_take) state<=LOCK_R;
                VERIFY_AR: if(ar_take) state<=VERIFY_R;
                MONITOR_AR: if(ar_take) state<=MONITOR_R;
                HOLD_R: if(r_take) state<=fail_now ? STOP : LOCK_AR;
                LOCK_R: if(r_take) begin
                    if(fail_now) state<=STOP;
                    else if((m_rdata&LOCK_MASK)==LOCK_MASK) begin
                        aw_done<=0;w_done<=0;state<=RELEASE_W;
                    end else begin state<=LOCK_WAIT;end
                end
                VERIFY_R: if(r_take) state<=fail_now ? STOP : MONITOR_AR;
                MONITOR_R: if(r_take) begin
                    if(fail_now) state<=STOP;
                    else begin
                        ready<=1;startup_done<=1;state<=MONITOR_WAIT;
                    end
                end
                LOCK_WAIT,MONITOR_WAIT: begin
                    if(fail_now) state<=STOP;
                    else if(poll_timer==POLL_BITS'(POLL_INTERVAL-1))
                        state<=state==LOCK_WAIT ? LOCK_AR : MONITOR_AR;
                end
                default: state<=STOP;
            endcase
        end
    end
endmodule
