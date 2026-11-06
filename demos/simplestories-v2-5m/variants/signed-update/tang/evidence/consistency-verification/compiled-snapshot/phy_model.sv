`timescale 1ns/1ps
module board1_gowin_ddr3_raw_controller_shell (
    input  wire         clk_50mhz,
    input  wire         reset_button_n,

    output wire         trusted_clk_25mhz_o,
    output wire         core_clk_25mhz_o,
    output wire         trusted_reset_n_o,
    output wire         app_clk_100mhz_o,
    output wire         app_reset_n_o,
    output wire         controller_pll_lock_o,
    output wire         controller_init_calib_complete_o,

    output wire         app_cmd_ready_o,
    input  wire [2:0]   app_cmd_i,
    input  wire         app_cmd_en_i,
    input  wire [28:0]  app_addr_i,
    output wire         app_wr_data_ready_o,
    input  wire [255:0] app_wr_data_i,
    input  wire         app_wr_data_en_i,
    input  wire         app_wr_data_end_i,
    input  wire [31:0]  app_wr_data_mask_i,
    output wire [255:0] app_rd_data_o,
    output wire         app_rd_data_valid_o,
    output wire         app_rd_data_end_o,
    input  wire         app_burst_i,
    input  wire         app_self_refresh_req_i,
    input  wire         app_refresh_req_i,

    output wire [14:0]  ddr_addr,
    output wire [2:0]   ddr_bank,
    output wire         ddr_cs,
    output wire         ddr_ras,
    output wire         ddr_cas,
    output wire         ddr_we,
    output wire         ddr_ck,
    output wire         ddr_ck_n,
    output wire         ddr_cke,
    output wire         ddr_odt,
    output wire         ddr_reset_n,
    output wire [3:0]   ddr_dm,
    inout  wire [31:0]  ddr_dq,
    inout  wire [3:0]   ddr_dqs,
    inout  wire [3:0]   ddr_dqs_n
);

    // Simulation-only memory/clock model at the exact raw controller seam.
    // Vendor DDR PHY/calibration/analog timing are not simulated or certified.
    reg core_clk=0,trusted_clk=0,app_clk=0;
    always #20 core_clk=~core_clk;
    always #40 trusted_clk=~trusted_clk;
    always #5 app_clk=~app_clk;
    assign core_clk_25mhz_o=core_clk;
    assign trusted_clk_25mhz_o=trusted_clk;
    assign app_clk_100mhz_o=app_clk;
    reg [6:0] calibration_q=0;
    wire good=reset_button_n && calibration_q==127;
    always @(posedge app_clk or negedge reset_button_n)
        if(!reset_button_n) calibration_q<=0;
        else if(calibration_q<127) calibration_q<=calibration_q+1;
    assign trusted_reset_n_o=reset_button_n;
    assign app_reset_n_o=reset_button_n;
    assign controller_pll_lock_o=good;
    assign controller_init_calib_complete_o=good;
    reg [31:0] cycles_q=0;
    always @(posedge app_clk) cycles_q<=cycles_q+1;
    assign app_cmd_ready_o=good && cycles_q[2:0]!=7;
    assign app_wr_data_ready_o=good && cycles_q[3:0]!=13;
    reg [255:0] memory[0:524287];
    reg [18:0] pending_address[0:127];
    reg [31:0] pending_due[0:127];
    reg [6:0] write_q=0,read_q=0;
    reg [7:0] count_q=0;
    reg [255:0] response_q;
    reg response_valid_q=0;
    integer model_writes=0,model_reads=0,runtime_writes=0;
    wire command=app_cmd_en_i && app_cmd_ready_o;
    wire issue=command && app_cmd_i==1;
    wire retire=count_q!=0 && pending_due[read_q]<=cycles_q;
    wire [18:0] address=app_addr_i[21:3];
    assign app_rd_data_o=response_q;
    assign app_rd_data_valid_o=response_valid_q;
    assign app_rd_data_end_o=response_valid_q;
    always @(posedge app_clk or negedge reset_button_n) begin
        if(!reset_button_n) begin write_q<=0;read_q<=0;count_q<=0;response_valid_q<=0;model_writes<=0;model_reads<=0;runtime_writes<=0;end
        else begin
            response_valid_q<=retire;
            if(command && app_cmd_i==0) begin
                if(!app_wr_data_en_i || !app_wr_data_ready_o || !app_wr_data_end_i || app_wr_data_mask_i!=0)
                    $fatal(1,"unpaired physical write");
                memory[address]<=app_wr_data_i;
                if(address<227062) model_writes<=model_writes+1;else runtime_writes<=runtime_writes+1;
            end
            if(issue) begin
                if(count_q==128) $fatal(1,"physical model queue overflow");
                pending_address[write_q]<=address;pending_due[write_q]<=cycles_q+4;
                write_q<=write_q+1;
                if(address<227062) model_reads<=model_reads+1;
            end
            if(retire) begin response_q<=memory[pending_address[read_q]];read_q<=read_q+1;end
            case({issue,retire})
                2'b10:count_q<=count_q+1;
                2'b01:count_q<=count_q-1;
                default:begin end
            endcase
            if(app_burst_i || app_self_refresh_req_i || app_refresh_req_i) $fatal(1,"unexpected manual PHY control");
        end
    end
    assign ddr_addr=0;assign ddr_bank=0;assign ddr_cs=1;assign ddr_ras=1;
    assign ddr_cas=1;assign ddr_we=1;assign ddr_ck=app_clk;assign ddr_ck_n=~app_clk;
    assign ddr_cke=good;assign ddr_odt=0;assign ddr_reset_n=reset_button_n;assign ddr_dm=0;
    assign ddr_dq=32'bz;assign ddr_dqs=4'bz;assign ddr_dqs_n=4'bz;
endmodule
`default_nettype wire
