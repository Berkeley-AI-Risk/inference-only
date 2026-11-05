#!/usr/bin/env python3
"""Check actual flash-loader reset sequencing over reset phases and clock stops."""
from pathlib import Path
import argparse,hashlib,json,subprocess,time
p=argparse.ArgumentParser(description=__doc__)
source_group=p.add_mutually_exclusive_group(required=True)
source_group.add_argument('--build',type=Path)
source_group.add_argument('--project',type=Path)
p.add_argument('--output',type=Path,required=True);p.add_argument('--identity-buffers',type=int,default=0)
p.add_argument('--vendor-primitives',type=Path,default=Path('/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v'))
a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
project=a.project.resolve()if a.project else Path(json.loads((a.build/'STARTED.json').read_text())['directory'])/'project'
source=project/'swic/swic_qspi_boot_source.sv';text=source.read_text()
assert ('core_reset_pad_' if a.identity_buffers else 'qualified_core_reset_n')in text
sources=[source,project/'swic/swic_read03_master.sv',project/'fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv']
primitive=''
if a.identity_buffers:
    vendor=a.vendor_primitives
    library=vendor.read_text()
    for module in ['LUT1','MUX2']:
        start=library.index('module '+module+' ')
        primitive+=library[start:library.index('endmodule',start)+len('endmodule')]+'\n'
    start=library.index('primitive mux2 ')
    primitive+=library[start:library.index('endprimitive',start)+len('endprimitive')]+'\n'
    (out/'lut_primitives.v').write_text(primitive)
    sources.append(out/'lut_primitives.v')
bench=r'''`timescale 1ns/1ps
module tb;
  reg core=0,trusted=0,run_core=1,run_trusted=1;
  always #20 if(run_core)core=~core;
  always #40 if(run_trusted)trusted=~trusted;
  reg cr=1,tr=1;
  swic_qspi_boot_source dut(.core_clk_i(core),.trusted_clk_i(trusted),
    .core_reset_n_i(cr),.trusted_reset_n_i(tr),.allow_model_i(1'b0),
    .byte_ready_i(1'b0),.qspi_dq_i(4'd0));
  wire common=cr&&tr;
  integer cn=0,sn=0,checks=0,cases=0,mask,phase;
  reg saw_falling=0;
  always @(negedge core or negedge common)begin
    if(!common)saw_falling=0;else saw_falling=1;
    #0.001;if(dut.core_phase_release_q!==saw_falling)$fatal(1,"entry phase differs");
  end
  always @(posedge core or negedge common)begin
    if(!common||!saw_falling)cn=0;else if(cn<3)cn=cn+1;
    #0.002;if(dut.core_release_q!==((1<<cn)-1))$fatal(1,"core release count differs");
    checks=checks+1;
  end
  always @(posedge trusted or negedge common)begin
    if(!common)sn=0;else if(sn<3)sn=sn+1;
    #0.003;if(dut.slow_release_q!==((1<<sn)-1))$fatal(1,"trusted release count differs");
    checks=checks+1;
  end
  initial begin
    #0.125;cr=0;tr=0;
    for(mask=1;mask<4;mask=mask+1)begin
      for(phase=0;phase<400;phase=phase+1)begin
        @(posedge core);#0.125;cr=(mask&1)==0;tr=(mask&2)==0;
        #(0.25+0.4*phase);cr=1;tr=1;
        #0.001;if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"early release");
        repeat(4)@(posedge trusted);
        #0.01;if(dut.core_release_q!==7||dut.slow_release_q!==7)$fatal(1,"startup did not settle");
        cases=cases+1;
      end
    end
    @(negedge core);#0.125;run_core=0;run_trusted=0;cr=0;
    #0.01;if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"stopped clock reset escaped");
    #103;cr=1;#161;
    if(dut.core_release_q!==0||dut.slow_release_q!==0)$fatal(1,"release without clocks");
    run_core=1;run_trusted=1;repeat(4)@(posedge trusted);
    #0.01;if(dut.core_release_q!==7||dut.slow_release_q!==7)$fatal(1,"restart did not release");
    $display("PASS actual flash-loader reset phases=%0d checks=%0d, stopped clocks and restart",cases,checks);
    $finish;
  end
endmodule
'''
if a.identity_buffers:
    block='''  always @(negedge core or negedge common)begin
    if(!common)saw_falling=0;else saw_falling=1;
    #0.001;if(dut.core_phase_release_q!==saw_falling)$fatal(1,"entry phase differs");
  end'''
    assert bench.count(block)==1
    bench=bench.replace(block,'').replace('if(!common||!saw_falling)cn=0;','if(!common)cn=0;')
(out/'tb.sv').write_text(bench)
start=text.index('    wire common_reset_n=');end=text.index('    wire slow_reset_n=',start)
excerpt=text[start:end]
dut='''module reset_block(input core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i,
 output core_ready,slow_ready,qualified_core);
'''+excerpt+'''
assign core_ready=core_release_q[2];assign slow_ready=slow_release_q[2];
assign qualified_core=qualified_core_reset_n;
endmodule
'''
formal=dut+'''
module proof(input core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i);
wire c,s,qualified;wire common=core_reset_n_i&&trusted_reset_n_i;
reset_block dut(core_clk_i,trusted_clk_i,core_reset_n_i,trusted_reset_n_i,c,s,qualified);
reg[1:0] cn,sn;
always @(posedge core_clk_i or negedge qualified)
 if(!qualified)cn<=0;else if(cn<3)cn<=cn+1;
always @(posedge trusted_clk_i or negedge common)
 if(!common)sn<=0;else if(sn<3)sn<=sn+1;
always @*begin
 assert(c==(cn==3));assert(s==(sn==3));
 if(!common)begin assert(!c);assert(!s);end
end
endmodule
'''
if a.identity_buffers:
    formal=formal.replace('assign qualified_core=qualified_core_reset_n;',f'assign qualified_core=core_reset_pad_{a.identity_buffers-1};')
    # Yosys does not elaborate the vendor UDP table. For this binary proof,
    # use the documented LUT truth function; simulation above uses the actual
    # vendor LUT1/MUX2/UDP modules. INIT is fixed to the identity 2'h2.
    formal="module LUT1 #(parameter [1:0] INIT=2'h0)(output F,input I0);assign F=INIT[I0];endmodule\n"+formal
(out/'proof.sv').write_text(formal)
(out/'prove.ys').write_text('''read_verilog -formal -sv proof.sv
prep -top proof -flatten
clk2fflogic
opt_clean
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps 24 -set-at 1 core_reset_n_i 0 -set-at 1 trusted_reset_n_i 0 -set-def-inputs -dump_vcd failure.vcd
''')
results=[]
def run(name,command):
 t=time.monotonic()
 with (out/(name+'.log')).open('w')as log:code=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT).returncode
 results.append({'name':name,'exit_code':code,'elapsed_seconds':time.monotonic()-t})
 assert code==0,(name,code)
try:
 run('compile',['iverilog','-g2012','-s','tb','-o','sim.vvp',*[str(s)for s in sources],'tb.sv'])
 run('phase-sweep',['vvp','sim.vvp'])
 run('formal',['yosys','-Q','-s','prove.ys'])
finally:
 result={'result':'PASS'if len(results)==3 and all(r['exit_code']==0 for r in results)else'FAIL','stages':results,'actual_source_sha256':hashlib.sha256(source.read_bytes()).hexdigest(),'reset_excerpt_sha256':hashlib.sha256(excerpt.encode()).hexdigest(),'scope':'Actual flash-loader RTL: 1200 reset release phases/combinations with both real read masters and async FIFO elaborated; both clock stop/reset/restart; exact extracted reset block inductively matches count-based release specification. Digital semantics only; no analog or whole-chip proof.','files_sha256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest()for p in out.iterdir()if p.is_file()}}
 (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n');print(json.dumps(result,indent=2))
