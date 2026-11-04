"""Finite native post-CLEAR replay and actual-only numerical defect controls.

These simulations are operating evidence, not unbounded proof. No DUT reset
is inserted after the interrupted old invocation. Only the reference's
resetless payloads are initialized to zero, as the canonical definition says.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

from prepare import HERE, TOP, ROM, modules, sha, verify_inventory, write_json
from checkpoint import atomic_bytes, snapshot


def testbench(actual_module):
    graph=json.loads((HERE/'project/native.json').read_text())['modules'][TOP]
    lines=['`timescale 1ns/1ps','module pilot_witness;',
        'reg clk=0; always #5 clk=~clk; integer cycles=0;',
        'always @(posedge clk) begin cycles=cycles+1; if(cycles>200000) $fatal(1,"WITNESS_TIMEOUT"); end']
    for c in ['a','b']:
        for name,port in graph['ports'].items():
            if name=='clk':continue
            width=len(port['bits']);shape=('['+str(width-1)+':0] ') if width>1 else ''
            typ='reg' if port['direction']=='input' else 'wire'
            lines.append(typ+' '+shape+c+'_'+name+('=0' if typ=='reg' else '')+';')
        connections=['.clk(clk)']+['.'+n+'('+c+'_'+n+')' for n in graph['ports'] if n!='clk']
        lines.append((actual_module if c=='a' else TOP)+' u_'+c+'('+','.join(connections)+');')
    lines += ['''
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
''']
    return '\n'.join(lines)+'\n'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--case',choices=['native','stale-state','wrong-operand'],default='native')
    ap.add_argument('--role',type=int,default=0)
    args=ap.parse_args()
    if not 0<=args.role<=12:raise ValueError('Role outside production range')
    verify_inventory()
    folder=HERE/'witnesses'/(args.case+'-role'+str(args.role))
    folder.mkdir(parents=True,exist_ok=False)
    native=(HERE/'project/native.sv').read_text()
    actual_module=TOP
    source=native
    mutation=None
    if args.case!='native':
        actual_module='pilot_actual_mutant'
        body=modules(native)[TOP]
        if args.case=='wrong-operand':
            before='vector_read_q}) <<< 12;';after='vector_read_q}) <<< 11;'
        else:
            before='if (vector_write_enable)';after="if (vector_write_enable && !(input_row_index_i==8'd0 && input_mantissa_i[15]))"
        if body.count(before)!=1:raise ValueError('Mutation site not unique')
        mutation=dict(before=before,after=after,reference_changed=False)
        body=body.replace(before,after).replace('module '+TOP,'module '+actual_module,1)
        source+='\n'+body+'\n'
    atomic_bytes(folder/'native-and-actual.sv',source.encode())
    atomic_bytes(folder/'testbench.sv',testbench(actual_module).encode())
    rom=folder/ROM;rom.parent.mkdir(parents=True,exist_ok=True);rom.write_bytes((HERE/'project'/ROM).read_bytes())
    compile_cmd=['iverilog','-g2012','-DSYNTHESIS','-s','pilot_witness','-o','sim','native-and-actual.sv','testbench.sv']
    started=time.monotonic()
    with (folder/'compile.log').open('w') as log:
        cp=subprocess.run(compile_cmd,cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60)
    result=dict(case=args.case,role=args.role,compile_exit=cp.returncode,
        source_sha256=sha(source.encode()),testbench_sha256=sha((folder/'testbench.sv').read_bytes()),
        rom_sha256=sha(rom.read_bytes()),mutation=mutation,actual_hard_resets=1,
        actual_clear_after_owned_old_work=True,reference_payload_zeroed_only=True,
        unbounded_proof=False,pilot_complete=False)
    if cp.returncode==0:
        with (folder/'simulation.log').open('w') as log:
            cp=subprocess.run(['vvp','sim','+ROLE='+str(args.role)],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=120)
        raw=(folder/'simulation.log').read_text()
        result.update(simulation_exit=cp.returncode,operating_witness=cp.returncode==0 and 'WITNESS_PASS' in raw,
            defect_detected=args.case!='native' and cp.returncode!=0 and 'RESULT_MISMATCH' in raw,
            simulation_log_sha256=sha(raw.encode()))
        if (folder/'values.csv').exists():result['values_sha256']=sha((folder/'values.csv').read_bytes())
    result['seconds']=time.monotonic()-started
    write_json(folder/'RESULT.json',result)
    snapshot('finite operating/defect evidence '+folder.name)
    print(json.dumps(result,indent=2))
    return 0 if result.get('operating_witness') or result.get('defect_detected') else 1


if __name__=='__main__':raise SystemExit(main())
