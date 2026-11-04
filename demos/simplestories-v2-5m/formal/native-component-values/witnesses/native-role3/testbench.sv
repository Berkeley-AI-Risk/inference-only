`timescale 1ns/1ps
module pilot_witness;
reg clk=0; always #5 clk=~clk; integer cycles=0;
always @(posedge clk) begin cycles=cycles+1; if(cycles>200000) $fatal(1,"WITNESS_TIMEOUT"); end
reg a_rst_n=0;
reg a_clear_i=0;
reg a_model_lock_i=0;
reg a_upstream_fault_i=0;
reg a_start_valid_i=0;
wire a_start_ready_o;
reg [2:0] a_fixed_layer_i=0;
reg [1:0] a_fixed_norm_kind_i=0;
reg [7:0] a_input_exponent_i=0;
reg a_input_valid_i=0;
wire a_input_ready_o;
reg [7:0] a_input_row_index_i=0;
reg [15:0] a_input_mantissa_i=0;
reg a_input_last_i=0;
wire a_result_valid_o;
reg a_result_ready_i=0;
wire [7:0] a_result_row_index_o;
wire [15:0] a_result_mantissa_o;
wire [7:0] a_result_exponent_o;
wire a_result_last_o;
wire a_done_valid_o;
reg a_done_ready_i=0;
wire a_busy_o;
wire a_range_fault_o;
board1_fixed_vector_rmsnorm_service u_a(.clk(clk),.rst_n(a_rst_n),.clear_i(a_clear_i),.model_lock_i(a_model_lock_i),.upstream_fault_i(a_upstream_fault_i),.start_valid_i(a_start_valid_i),.start_ready_o(a_start_ready_o),.fixed_layer_i(a_fixed_layer_i),.fixed_norm_kind_i(a_fixed_norm_kind_i),.input_exponent_i(a_input_exponent_i),.input_valid_i(a_input_valid_i),.input_ready_o(a_input_ready_o),.input_row_index_i(a_input_row_index_i),.input_mantissa_i(a_input_mantissa_i),.input_last_i(a_input_last_i),.result_valid_o(a_result_valid_o),.result_ready_i(a_result_ready_i),.result_row_index_o(a_result_row_index_o),.result_mantissa_o(a_result_mantissa_o),.result_exponent_o(a_result_exponent_o),.result_last_o(a_result_last_o),.done_valid_o(a_done_valid_o),.done_ready_i(a_done_ready_i),.busy_o(a_busy_o),.range_fault_o(a_range_fault_o));
reg b_rst_n=0;
reg b_clear_i=0;
reg b_model_lock_i=0;
reg b_upstream_fault_i=0;
reg b_start_valid_i=0;
wire b_start_ready_o;
reg [2:0] b_fixed_layer_i=0;
reg [1:0] b_fixed_norm_kind_i=0;
reg [7:0] b_input_exponent_i=0;
reg b_input_valid_i=0;
wire b_input_ready_o;
reg [7:0] b_input_row_index_i=0;
reg [15:0] b_input_mantissa_i=0;
reg b_input_last_i=0;
wire b_result_valid_o;
reg b_result_ready_i=0;
wire [7:0] b_result_row_index_o;
wire [15:0] b_result_mantissa_o;
wire [7:0] b_result_exponent_o;
wire b_result_last_o;
wire b_done_valid_o;
reg b_done_ready_i=0;
wire b_busy_o;
wire b_range_fault_o;
board1_fixed_vector_rmsnorm_service u_b(.clk(clk),.rst_n(b_rst_n),.clear_i(b_clear_i),.model_lock_i(b_model_lock_i),.upstream_fault_i(b_upstream_fault_i),.start_valid_i(b_start_valid_i),.start_ready_o(b_start_ready_o),.fixed_layer_i(b_fixed_layer_i),.fixed_norm_kind_i(b_fixed_norm_kind_i),.input_exponent_i(b_input_exponent_i),.input_valid_i(b_input_valid_i),.input_ready_o(b_input_ready_o),.input_row_index_i(b_input_row_index_i),.input_mantissa_i(b_input_mantissa_i),.input_last_i(b_input_last_i),.result_valid_o(b_result_valid_o),.result_ready_i(b_result_ready_i),.result_row_index_o(b_result_row_index_o),.result_mantissa_o(b_result_mantissa_o),.result_exponent_o(b_result_exponent_o),.result_last_o(b_result_last_o),.done_valid_o(b_done_valid_o),.done_ready_i(b_done_ready_i),.busy_o(b_busy_o),.range_fault_o(b_range_fault_o));

integer role=0,k,expected_count=0,actual_count=0,fd;
reg reference_active=0,actual_active=0,reference_done=0,actual_done=0;
reg [32:0] expected [0:255];
wire [32:0] aword={a_result_row_index_o,a_result_mantissa_o,a_result_exponent_o,a_result_last_o};
wire [32:0] bword={b_result_row_index_o,b_result_mantissa_o,b_result_exponent_o,b_result_last_o};
function [15:0] fresh_value(input integer row);
    fresh_value=((row%23)-11)*733;
endfunction
always @(negedge clk) if(actual_active) begin
    a_result_ready_i=(cycles%13)>=4;
    a_done_ready_i=(cycles%7)>=2;
end
always @(posedge clk) begin
    if(reference_active) begin
        if(b_range_fault_o) $fatal(1,"REFERENCE_FAULT");
        if(b_result_valid_o) begin
            if(expected_count>=256 || b_result_row_index_o!==expected_count[7:0] ||
               b_result_last_o!==(expected_count==255) || (^bword)===1'bx)
                $fatal(1,"REFERENCE_ORDER_OR_UNKNOWN");
            expected[expected_count]=bword;
            $fdisplay(fd,"reference,%0d,%h",expected_count,bword);
            expected_count=expected_count+1;
        end
        if(b_done_valid_o) begin
            if(expected_count!=256) $fatal(1,"REFERENCE_INCOMPLETE");
            reference_done=1;
        end
    end
    if(actual_active) begin
        if(a_range_fault_o) $fatal(1,"ACTUAL_FAULT");
        if(a_result_valid_o) begin
            if(actual_count>=256 || aword!==expected[actual_count])
                $fatal(1,"RESULT_MISMATCH row=%0d actual=%h expected=%h",actual_count,aword,expected[actual_count]);
            if(a_result_ready_i) begin
                $fdisplay(fd,"actual,%0d,%h",actual_count,aword);
                actual_count=actual_count+1;
            end
        end
        if(a_done_valid_o && a_done_ready_i) begin
            if(actual_count!=256) $fatal(1,"ACTUAL_INCOMPLETE");
            actual_done=1;
        end
    end
end

task start_actual(input integer layer,input integer kind,input integer exponent);
begin
    @(negedge clk); a_fixed_layer_i=layer; a_fixed_norm_kind_i=kind;
    a_input_exponent_i=exponent; a_start_valid_i=1;
    @(posedge clk); if(!a_start_ready_o) $fatal(1,"ACTUAL_START_REJECTED");
    @(negedge clk); a_start_valid_i=0;
end
endtask
task input_actual(input integer old_history);
integer row;
begin
    for(row=0;row<256;row=row+1) begin
        if(!old_history && row%7==0) begin
            @(negedge clk);a_input_valid_i=0;repeat(3) @(posedge clk);
        end
        @(negedge clk);a_input_valid_i=1;a_input_row_index_i=row;
        a_input_mantissa_i=old_history ? 3000+(row%31) : fresh_value(row);
        a_input_last_i=(row==255);
        @(posedge clk);if(!a_input_ready_o) $fatal(1,"ACTUAL_CAPTURE_REJECTED");
    end
    @(negedge clk);a_input_valid_i=0;
end
endtask

initial begin
    if(!$value$plusargs("ROLE=%d",role)) role=0;
    fd=$fopen("values.csv","w");
    a_model_lock_i=1;b_model_lock_i=1;
    a_result_ready_i=1;a_done_ready_i=1;b_result_ready_i=1;b_done_ready_i=1;
    // Only canonical-reference resetless payloads start at zero.
    for(k=0;k<256;k=k+1) u_b.vector_mem_q[k]=0;
    for(k=0;k<682;k=k+1) u_b.u_frozen_vector_normalizer.record_mem_q[k]=0;
    u_b.vector_read_q=0;u_b.u_frozen_vector_normalizer.record_read_q=0;
    u_b.u_norm_rom.coefficient_o=0;u_b.u_norm_rom.multiplier_o=0;
    u_b.u_norm_rom.tensor_exponent_o=0;
    u_b.u_frozen_vector_normalizer.u_shift.source_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.low_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.shifted_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.amount_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.left_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.negative_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.force_zero_q=0;
    u_b.u_frozen_vector_normalizer.u_shift.bad_count_q=0;
    repeat(4) @(posedge clk);
    @(negedge clk);a_rst_n=1;
    start_actual(0,0,-10);input_actual(1);
    wait(u_a.u_frozen_vector_normalizer.capture_index_q>=8);
    wait(u_a.state_q==5'd10);
    @(negedge clk);a_clear_i=1;
    repeat(2) @(posedge clk);
    @(negedge clk);a_clear_i=0;b_rst_n=1;
    // Compute the whole fresh canonical stream before the stalled actual run.
    reference_active=1;
    @(negedge clk);b_fixed_layer_i=(role==12)?5:role/2;
    b_fixed_norm_kind_i=(role==12)?2:role%2;b_input_exponent_i=-12;
    b_start_valid_i=1;
    @(posedge clk);if(!b_start_ready_o) $fatal(1,"REFERENCE_START_REJECTED");
    @(negedge clk);b_start_valid_i=0;
    for(k=0;k<256;k=k+1) begin
        @(negedge clk);b_input_valid_i=1;b_input_row_index_i=k;
        b_input_mantissa_i=fresh_value(k);b_input_last_i=(k==255);
        @(posedge clk);if(!b_input_ready_o) $fatal(1,"REFERENCE_CAPTURE_REJECTED");
    end
    @(negedge clk);b_input_valid_i=0;
    wait(reference_done);@(negedge clk);reference_active=0;
    actual_active=1;
    start_actual((role==12)?5:role/2,(role==12)?2:role%2,-12);
    input_actual(0);
    wait(actual_done);@(negedge clk);
    $fclose(fd);$display("WITNESS_PASS role=%0d rows=%0d cycles=%0d",role,actual_count,cycles);
    $finish;
end
endmodule

