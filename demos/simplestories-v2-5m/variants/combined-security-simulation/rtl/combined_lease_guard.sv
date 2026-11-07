`timescale 1ns/1ps
`default_nettype none
// Private local integration guard. Time/epoch inputs terminate at explicitly
// modeled trusted services in the testbench. They are not host commands.
module combined_lease_guard #(
    parameter logic [63:0] LEASE_TICKS=64'd20000000
)(
    input wire clk,power_reset_n,session_reset_n,
    input wire admitted_i,context_valid_i,home_enabled_i,home_failed_i,new_lease_i,
    input wire [255:0] context_i,
    input wire [31:0] epoch_i,
    input wire [63:0] trusted_now_i,
    input wire clear_i,consumer_idle_i,
    input wire step_valid_i,step_ready_i,
    input wire token_valid_i,token_ready_i,
    output wire append_allowed_o,step_allowed_o,publication_allowed_o,runtime_reset_n_o,
    output wire expired_o,
    output logic failed_o,
    input wire memory_read_accepted_i,memory_response_i,
    output wire memory_response_owned_o,memory_response_live_o,
    output wire memory_issue_allowed_o,drained_o,
    output logic [63:0] dropped_response_count_o
);
    logic permission_q,step_owned_q,clear_pending_q;
    logic [63:0] deadline_q,last_time_q;
    logic [255:0] context_q,step_context_q;
    logic [31:0] epoch_q,step_epoch_q;
    logic [6:0] reads_q;
    logic ledger_fault_q;
    wire time_expired=permission_q && trusted_now_i>=deadline_q;
    wire binding_fault=permission_q && (epoch_i!=epoch_q || context_i!=context_q || !context_valid_i || !admitted_i);
    wire fail_now=failed_o || ledger_fault_q || home_failed_i || time_expired || binding_fault || trusted_now_i<last_time_q;
    wire live=power_reset_n && session_reset_n && permission_q && home_enabled_i && !fail_now;
    assign expired_o=time_expired;
    wire clear_event=clear_i && live;
    assign append_allowed_o=live && !clear_i && !clear_pending_q;
    assign step_allowed_o=append_allowed_o && !step_owned_q;
    assign publication_allowed_o=live && !clear_i && !clear_pending_q && step_owned_q && step_context_q==context_i && step_epoch_q==epoch_i;
    assign runtime_reset_n_o=live;
    assign memory_response_owned_o=reads_q!=0;
    assign memory_response_live_o=memory_response_owned_o && live;
    assign memory_issue_allowed_o=live && reads_q<7'd32;
    assign drained_o=reads_q==0;
    // The ledger deliberately survives session/consumer reset. Old physical
    // reads must retire here before a later lease can open a fresh consumer.
    always_ff @(posedge clk or negedge power_reset_n) begin
        if(!power_reset_n) begin reads_q<=0;ledger_fault_q<=0;dropped_response_count_o<=0;end
        else begin
            case({memory_read_accepted_i,memory_response_i})
                2'b10: reads_q<=reads_q+1'b1;
                2'b01: if(reads_q!=0) reads_q<=reads_q-1'b1;
                default: begin end
            endcase
            if((memory_response_i && reads_q==0) || (memory_read_accepted_i && (reads_q>=32 || !live))) ledger_fault_q<=1;
            if(memory_response_i && reads_q!=0 && !live) dropped_response_count_o<=dropped_response_count_o+1'b1;
        end
    end
    always_ff @(posedge clk or negedge power_reset_n) begin
        if(!power_reset_n) begin
            permission_q<=0;step_owned_q<=0;clear_pending_q<=0;deadline_q<=0;last_time_q<=0;failed_o<=0;
            context_q<=0;epoch_q<=0;step_context_q<=0;step_epoch_q<=0;
        end else begin
            last_time_q<=trusted_now_i;
            if(!session_reset_n) begin permission_q<=0;step_owned_q<=0;clear_pending_q<=0;failed_o<=0;end
            else if(fail_now) begin permission_q<=0;step_owned_q<=0;clear_pending_q<=0;failed_o<=1;end
            else begin
                if(new_lease_i) begin
                    if(!admitted_i || !context_valid_i || (!permission_q && reads_q!=0) || epoch_i==0 ||
                       trusted_now_i>64'hffffffffffffffff-LEASE_TICKS) failed_o<=1;
                    else begin
                        permission_q<=1;context_q<=context_i;epoch_q<=epoch_i;deadline_q<=trusted_now_i+LEASE_TICKS;
                    end
                end
                // CLEAR cancels command authority while the live consumer
                // and its accepted memory work retain their drain ownership.
                if(clear_event) begin
                    step_owned_q<=0;clear_pending_q<=1;
                end else if(clear_pending_q) begin
                    step_owned_q<=0;
                    // A later non-CLEAR edge must see the actual aggregate
                    // consumer idle and no coincident external read/return.
                    if(consumer_idle_i && reads_q==0 && !memory_read_accepted_i && !memory_response_i)
                        clear_pending_q<=0;
                end else begin
                    if(step_valid_i && step_ready_i && step_allowed_o) begin
                        step_owned_q<=1;step_context_q<=context_i;step_epoch_q<=epoch_i;
                    end
                    if(token_valid_i && token_ready_i && publication_allowed_o) step_owned_q<=0;
                end
            end
        end
    end
endmodule
`default_nettype wire
