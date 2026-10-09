`timescale 1ns/1ps
`default_nettype none

// Private one-way ownership handoff at the Gowin application interface.
// Boot authenticates the fixed full-image readback using the existing boot
// composition. Runtime uses its own pipelined normalized adapter. Neither
// owner may access the controller until selected; runtime never owns model
// writes. A successful boot lock plus two quiescent app edges transfers
// ownership permanently until common hard reset. No public control or CLEAR.
//
// Both adapters see calibration throughout boot but only the selected one
// sees read returns. Writes are paired command+data, fixed x32/BL8 (32 bytes).
// This tracks controller acceptance, not persistence: the subsequent complete
// authenticated readback is the boot write/read-order check.
module hdp_reference #(
    parameter integer WATCHDOG_CYCLES=50000000
) (
    input wire clk,reset_n,
    input wire controller_good_i,boot_locked_i,boot_fault_i,runtime_fault_i,
    input wire [2:0] boot_cmd_i,runtime_cmd_i,
    input wire boot_cmd_en_i,runtime_cmd_en_i,
    input wire [28:0] boot_addr_i,runtime_addr_i,
    input wire [255:0] boot_data_i,runtime_data_i,
    input wire boot_data_en_i,runtime_data_en_i,
    input wire boot_data_end_i,runtime_data_end_i,
    input wire [31:0] boot_mask_i,runtime_mask_i,
    output wire boot_cmd_ready_o,runtime_cmd_ready_o,
    output wire boot_data_ready_o,runtime_data_ready_o,
    output wire boot_read_valid_o,runtime_read_valid_o,
    output wire [255:0] read_data_o,
    output wire read_end_o,
    input wire app_cmd_ready_i,app_data_ready_i,
    output wire [2:0] app_cmd_o,
    output wire app_cmd_en_o,
    output wire [28:0] app_addr_o,
    output wire [255:0] app_data_o,
    output wire app_data_en_o,app_data_end_o,
    output wire [31:0] app_mask_o,
    input wire app_read_valid_i,app_read_end_i,
    input wire [255:0] app_read_data_i,
    output wire runtime_locked_o,
    output logic fault_o,
    output wire obs_runtime,obs_controller_seen,obs_lock_seen,
    output wire [($clog2(WATCHDOG_CYCLES+1)+6):0] obs_private
);
    localparam integer WW=$clog2(WATCHDOG_CYCLES+1);
    logic runtime_q,quiet_q,controller_seen_q,lock_seen_q;
    logic [5:0] pending_q;
    logic [WW-1:0] watchdog_q;
    logic x_error;
    wire selected_en=runtime_q ? runtime_cmd_en_i : boot_cmd_en_i;
    wire selected_data_en=runtime_q ? runtime_data_en_i : boot_data_en_i;
    wire selected_end=runtime_q ? runtime_data_end_i : boot_data_end_i;
    wire [31:0] selected_mask=runtime_q ? runtime_mask_i : boot_mask_i;
    wire [18:0] selected_word=app_addr_o[21:3];
    wire selected_write=app_cmd_o==3'd0;
    wire selected_read=app_cmd_o==3'd1;
    wire model_address=selected_word<19'd227062;
    wire kv_address=selected_word>=19'd227072 && selected_word<19'd448256;
    wire aligned=app_addr_o[28:22]==0 && app_addr_o[2:0]==0;
    wire valid_region=runtime_q ? ((selected_read && model_address) || kv_address) : model_address;
    wire bad_command=(selected_en && (!aligned || !valid_region || (!selected_read && !selected_write))) ||
        (selected_data_en && (!selected_en || !selected_write)) ||
        (selected_en && selected_write && (!selected_data_en || !selected_end || selected_mask!=0 ||
            (app_cmd_ready_i != app_data_ready_i)));
    wire return_legal=app_read_valid_i && pending_q!=0 && app_read_end_i;
    wire bad_return=app_read_valid_i && (pending_q==0 || !app_read_end_i || !controller_good_i);
    wire bad_credit=selected_en && selected_read && app_cmd_ready_i && pending_q==32 && !return_legal;
    wire waiting=boot_locked_i && !runtime_q;
    wire timeout_now=waiting && watchdog_q==WW'(WATCHDOG_CYCLES-1);
    wire terminal_now=boot_fault_i || runtime_fault_i || (controller_seen_q && !controller_good_i) ||
        (lock_seen_q && !boot_locked_i) || bad_command || bad_return || bad_credit || timeout_now || x_error;
    wire enabled=reset_n && controller_good_i && !fault_o;

    // Ready depends only on registered ownership/fault, not same-cycle
    // command checks. Otherwise adapter enable->policy->ready can loop.
    // Current violations suppress the final physical enables and set fault.
    assign boot_cmd_ready_o=enabled && !runtime_q && app_cmd_ready_i;
    assign runtime_cmd_ready_o=enabled && runtime_q && app_cmd_ready_i;
    assign boot_data_ready_o=enabled && !runtime_q && app_data_ready_i;
    assign runtime_data_ready_o=enabled && runtime_q && app_data_ready_i;
    assign app_cmd_o=runtime_q ? runtime_cmd_i : boot_cmd_i;
    assign app_addr_o=runtime_q ? runtime_addr_i : boot_addr_i;
    assign app_data_o=runtime_q ? runtime_data_i : boot_data_i;
    assign app_cmd_en_o=selected_en && enabled && !terminal_now;
    assign app_data_en_o=selected_data_en && enabled && !terminal_now;
    assign app_data_end_o=selected_end && app_data_en_o;
    assign app_mask_o=selected_mask;
    assign boot_read_valid_o=app_read_valid_i && !runtime_q && reset_n && !fault_o;
    assign runtime_read_valid_o=app_read_valid_i && runtime_q && reset_n && !fault_o;
    assign read_data_o=app_read_data_i;
    assign read_end_o=app_read_end_i;
    assign runtime_locked_o=runtime_q && boot_locked_i && !fault_o && reset_n;
    wire command_fire=app_cmd_en_o && app_cmd_ready_i;
    wire read_fire=command_fire && selected_read;
    wire can_switch=enabled && boot_locked_i && !runtime_q && pending_q==0 &&
        !boot_cmd_en_i && !boot_data_en_i && !app_read_valid_i && !terminal_now;

    always_comb begin
        x_error=0;
`ifndef SYNTHESIS
`ifndef FORMAL
        x_error=$isunknown(controller_good_i) || $isunknown(boot_locked_i) ||
            $isunknown(boot_fault_i) || $isunknown(runtime_fault_i) || $isunknown(app_cmd_ready_i) ||
            $isunknown(app_data_ready_i) || $isunknown(app_read_valid_i) ||
            $isunknown(selected_en) || $isunknown(selected_data_en);
        if(selected_en) x_error=x_error || $isunknown(app_cmd_o) || $isunknown(app_addr_o);
        if(selected_data_en) x_error=x_error || $isunknown(app_data_o) ||
            $isunknown(selected_end) || $isunknown(selected_mask);
        if(app_read_valid_i) x_error=x_error || $isunknown(app_read_end_i) || $isunknown(app_read_data_i);
`endif
`endif
    end
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin
            runtime_q<=0;quiet_q<=0;controller_seen_q<=0;lock_seen_q<=0;
            pending_q<=0;watchdog_q<=0;fault_o<=0;
        end else begin
            if(controller_good_i) controller_seen_q<=1;
            if(boot_locked_i) lock_seen_q<=1;
            if(terminal_now) fault_o<=1;
            if(!waiting || command_fire || return_legal || can_switch) watchdog_q<=0;
            else if(!fault_o && !timeout_now) watchdog_q<=watchdog_q+1'b1;
            if(!fault_o && !terminal_now) begin
                quiet_q<=can_switch;
                if(can_switch && quiet_q) runtime_q<=1;
                case({read_fire,return_legal})
                    2'b10:pending_q<=pending_q+6'd1;
                    2'b01:pending_q<=pending_q-6'd1;
                    default: ;
                endcase
            end
        end
    end
    assign obs_runtime=runtime_q;
    assign obs_controller_seen=controller_seen_q;
    assign obs_lock_seen=lock_seen_q;
    assign obs_private={quiet_q,pending_q,watchdog_q};
    initial if(WATCHDOG_CYCLES<4) $fatal(1,"invalid boot handoff watchdog");
`ifdef FORMAL
    logic past_valid;
    always_ff @(posedge clk) begin
        past_valid<=1;
        if(reset_n) begin
            assert(pending_q<=32);
            assert(!(boot_read_valid_o && runtime_read_valid_o));
            if(runtime_locked_o) assert(!boot_cmd_ready_o && !boot_data_ready_o);
            if(app_cmd_en_o && selected_write && runtime_q) assert(kv_address);
            if(app_cmd_en_o && !runtime_q) assert(model_address);
            if(fault_o) assert(!app_cmd_en_o && !app_data_en_o && !runtime_locked_o);
            if(past_valid && $past(reset_n) && !$past(runtime_q) && runtime_q)
                assert($past(pending_q)==0 && !$past(app_read_valid_i) && $past(boot_locked_i));
            if(past_valid && $past(reset_n) && $past(runtime_q)) assert(runtime_q);
        end
    end
`endif
endmodule
`default_nettype wire
