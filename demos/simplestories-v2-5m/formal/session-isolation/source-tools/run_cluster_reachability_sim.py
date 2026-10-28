"""Full native zero-weight jobs after CLEAR, without any hard-reset edge.

Behavioral arithmetic RTL is used for simulation; this is a reachability and
protocol check, not a vendor primitive verification or a replacement for proof.
"""
import argparse
import json
from pathlib import Path
import shutil
import subprocess

from run_attention_ownership import HERE, load
from record_progress import sha


BENCH=r'''
`timescale 1ns/1ps
module tb;
reg clk=0;always #5 clk=~clk;
reg reset_n=1,clear_i=1,model_locked_i=1,upstream_fail_closed_i=0;
reg start_valid_i=0,metadata_valid_i=0,weight_valid_i=0,done_ready_i=0;
reg [2:0]fixed_layer_i=0;reg[3:0]fixed_job_i=0;reg[5:0]fixed_group_i=0;
reg signed[7:0]activation_exponent_i=0,metadata_exponent_i=15;
reg[15:0]metadata_multiplier_i=1;reg[12:0]metadata_row_index_i=0;
reg metadata_last_i=0,weight_last_i=0;reg signed[15:0]activation_i=0;
reg[639:0]weight_data_i=0;
wire start_ready_o,metadata_ready_o,weight_ready_o,result_valid_o,done_valid_o,busy_o,fail_closed_o,result_last_o;
wire[12:0]result_row_index_o;wire signed[49:0]result_scaled_raw_o;
wire signed[7:0]result_source_exponent_o;
integer cycles=0,received=0,lanes=64,base=0,jobs=0,stall_cycles=0;
wire result_ready_i=(cycles%7!=0)&&(cycles%11!=0);
reg old_stall=0;reg[71:0]old_result;
wire[71:0]result_bus={result_row_index_o,result_scaled_raw_o,result_source_exponent_o,result_last_o};
board1_clustered_projection_scale2 dut(.*);
always @(posedge clk)begin
    cycles<=cycles+1;
    if(reset_n!==1'b1)$fatal(1,"Unexpected physical reset");
    if(cycles>80000)$fatal(1,"Job did not complete");
    if(!clear_i && fail_closed_o!==1'b0)$fatal(1,"Native fail-closed");
    if(!clear_i && old_stall && (!result_valid_o || result_bus!==old_result))$fatal(1,"Stalled result changed");
    old_stall<=!clear_i && result_valid_o && !result_ready_i;
    old_result<=result_bus;
    if(!clear_i && result_valid_o && !result_ready_i)stall_cycles<=stall_cycles+1;
    if(!clear_i && result_valid_o && result_ready_i)begin
        if(result_row_index_o!==13'(base+received) || result_scaled_raw_o!==50'sd0 ||
           result_source_exponent_o!==8'sd0 || result_last_o!==(received==lanes-1))
            $fatal(1,"Wrong current row %0d index %0d raw %0d exponent %0d last %0d",received,result_row_index_o,result_scaled_raw_o,result_source_exponent_o,result_last_o);
        received<=received+1;
    end
end
task job(input integer job_id,group_id,row_count,column_count);
    integer i;
    begin
        @(negedge clk);clear_i=1;start_valid_i=0;metadata_valid_i=0;weight_valid_i=0;done_ready_i=0;
        repeat(2)@(negedge clk);
        lanes=row_count;base=group_id*64;received=0;
        fixed_layer_i=(job_id==7)?7:0;fixed_job_i=4'(job_id);fixed_group_i=6'(group_id);
        clear_i=0;start_valid_i=1;
        @(posedge clk);while(!start_ready_o)@(posedge clk);
        @(negedge clk);start_valid_i=0;
        for(i=0;i<row_count;i=i+1)begin
            metadata_valid_i=1;metadata_row_index_i=13'(base+i);metadata_last_i=(i==row_count-1);
            @(posedge clk);while(!metadata_ready_o)@(posedge clk);
            @(negedge clk);
        end
        metadata_valid_i=0;
        for(i=0;i<column_count;i=i+1)begin
            weight_valid_i=1;weight_last_i=(i==column_count-1);
            @(posedge clk);while(!weight_ready_o)@(posedge clk);
            @(negedge clk);
        end
        weight_valid_i=0;
        while(!done_valid_o)@(negedge clk);
        if(received!=row_count)$fatal(1,"Missing rows %0d of %0d",received,row_count);
        done_ready_i=1;@(negedge clk);done_ready_i=0;
        jobs=jobs+1;
        $display("JOB_PASS job=%0d group=%0d rows=%0d columns=%0d cycles=%0d",job_id,group_id,row_count,column_count,cycles);
    end
endtask
genvar t,r;
generate for(t=0;t<4;t=t+1)begin
    for(r=0;r<16;r=r+1)begin
        initial begin
            dut.g_tile[t].u_tile.multiplier_q[r]=16'h1234;
            dut.g_tile[t].u_tile.exponent_q[r]=8'h66;
            POISON_ACCUMULATOR
        end
    end
end endgenerate
initial begin
    repeat(3)@(negedge clk);
    job(0,0,64,256);job(4,10,42,256);job(7,62,51,256);job(6,0,64,682);
    if(stall_cycles==0)$fatal(1,"No output stalls exercised");
    $display("PASS jobs=%0d stalls=%0d physical_reset_edges=0",jobs,stall_cycles);$finish;
end
endmodule
'''


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    rows={}
    for variant in('baseline','kv-protected'):
        _,root,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release',variant)
        target=out/variant;target.mkdir();files={}
        for name in('cluster-engine.sv','cluster-tile.sv')+(()if variant=='baseline'else('cluster-mul.sv',)):
            raw=(root/'project'/name).read_bytes();(target/name).write_bytes(raw);files[name]=sha(raw)
        poison=('dut.g_tile[t].u_tile.g_lane[r].u_mac.product_q=26\'sd123;\n'+
            'dut.g_tile[t].u_tile.g_lane[r].u_mac.accumulator_q=48\'sd987654;'if variant=='baseline'else
            'dut.g_tile[t].u_tile.g_lane[0].accumulator_q[r]=35\'sd987654;')
        bench=BENCH.replace('POISON_ACCUMULATOR',poison);(target/'tb.sv').write_text(bench)
        command=[shutil.which('iverilog'),'-g2012','-s','tb','-o','sim.vvp',*files,'tb.sv']
        with(target/'compile.log').open('w')as log:
            cp=subprocess.run(command,cwd=target,stdout=log,stderr=subprocess.STDOUT,timeout=30)
        compile_exit=cp.returncode;simulation_exit=None
        if not compile_exit:
            with(target/'simulation.log').open('w')as log:
                cp=subprocess.run([shutil.which('vvp'),'sim.vvp'],cwd=target,stdout=log,stderr=subprocess.STDOUT,timeout=30)
            simulation_exit=cp.returncode
        raw=(target/'simulation.log').read_bytes()if(target/'simulation.log').exists()else b''
        passed=not compile_exit and simulation_exit==0 and b'PASS jobs=4 stalls='in raw and b'physical_reset_edges=0'in raw
        rows[variant]=dict(passed=passed,compile_exit=compile_exit,simulation_exit=simulation_exit,
            compile_command=command,source_sha256=files,bench_sha256=sha(bench.encode()),
            simulation_log_sha256=sha(raw),binding=binding,primitive_mode='behavioral RTL simulation')
        print(variant,passed,raw.decode().strip(),flush=True)
    result=dict(full_native_jobs_reachable=all(r['passed']for r in rows.values()),
        results=rows,formal_induction=False,physical_reset_edges=0,hardware_access=False,
        runner_sha256=sha(Path(__file__).read_bytes()))
    (out/'runner.py').write_bytes(Path(__file__).read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    return 0 if result['full_native_jobs_reachable']else 1


if __name__=='__main__':raise SystemExit(main())
