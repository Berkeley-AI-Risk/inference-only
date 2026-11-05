#!/usr/bin/env python3
"""Four-state reset phase sweep and bounded proof of the extracted startup RTL.

These checks concern digital sequencing, not analog metastability or timing.
"""
import argparse,hashlib,json,subprocess,sys,time
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import startup_reset_phase as phase
import startup_reset_qualifier as qualifier

ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
p.add_argument('--qualified',action='store_true')
p.add_argument('--original',action='store_true')
p.add_argument('--vendor-primitives',type=Path)
a=p.parse_args();out=a.output.resolve();out.mkdir(exist_ok=False)
source=(ROOT/'integration/project/top.sv').read_text()
assert not(a.qualified and a.original)
top=source if a.original else (qualifier if a.qualified else phase).transform('top.sv',source)
start=top.index('    wire common_async_reset_n=')
end=top.index('    wire app_cmd_ready',start)
excerpt=top[start:end]
dut='''`timescale 1ns/1ps
module startup_reset(input core_clk,board_reset_n,trusted_reset_n,app_reset_n,
                     output core_reset_n_o);
'''+excerpt+'''assign core_reset_n_o=core_reset_n;
endmodule
'''
(out/'startup_reset.sv').write_text(dut)

bench=r'''`timescale 1ns/1ps
module tb;
  reg clk=0,run_clock=1;
  always #20 if(run_clock)clk=~clk;
  reg b=1,t=1,a=1;
  wire ready;
  startup_reset dut(clk,b,t,a,ready);
  integer edges=0, checks=0, cases=0, pulse,mask;
  // Count active edges since all three source resets became inactive.
  always @(negedge clk or negedge b or negedge t or negedge a) begin
    if(!(b&&t&&a))edges=0;
    else if(edges<3)edges=edges+1;
    #0.001;
    if(ready !== ((b&&t&&a)&&(edges==3)))
      $fatal(1,"release sequencing mismatch time=%0t edges=%0d ready=%b",$time,edges,ready);
    checks=checks+1;
  end
  always @(posedge clk)begin
    #0.002;
    if(ready !== ((b&&t&&a)&&(edges==3)))$fatal(1,"rising-edge mismatch");
    checks=checks+1;
  end
  task assert_mask(input integer m);
    begin b=(m&1)==0;t=(m&2)==0;a=(m&4)==0;end
  endtask
  initial begin
    // All seven nonempty reset combinations, 320 sub-ns release phases,
    // and both short and multi-cycle assertion pulses. No coincident stimulus.
    #0.125;b=0;t=0;a=0;
    for(mask=1;mask<8;mask=mask+1)begin
      for(pulse=0;pulse<320;pulse=pulse+1)begin
        @(posedge clk);#0.125;assert_mask(mask);
        #(0.25+0.5*pulse);b=1;t=1;a=1;
        #0.001;if(ready!==0)$fatal(1,"early release");
        repeat(4)@(negedge clk);
        #0.01;if(ready!==1)$fatal(1,"release failed");
        cases=cases+1;
      end
    end
    // Assertion must work without a clock; release must wait for clock edges.
    @(negedge clk);#0.125;run_clock=0;b=0;
    #0.01;if(ready!==0)$fatal(1,"stopped-clock assertion failed");
    #103;b=1;
    #161;if(ready!==0)$fatal(1,"stopped-clock release escaped");
    run_clock=1;repeat(4)@(negedge clk);
    #0.01;if(ready!==1)$fatal(1,"restart release failed");
    $display("PASS reset phase sweep cases=%0d checks=%0d; stopped-clock assertion/restart",cases,checks);
    $finish;
  end
endmodule
'''
if a.qualified:
    bench=bench.replace('integer edges=0, checks=0, cases=0, pulse,mask;', '''integer edges=0, checks=0, cases=0, pulse,mask;
  reg seen_falling=0;
  always @(negedge clk or negedge b or negedge t or negedge a) begin
    if(!(b&&t&&a))seen_falling=0;else seen_falling=1;
    #0.001;if(dut.core_phase_release_q!==seen_falling)$fatal(1,"entry phase mismatch");
  end''')
    bench=bench.replace('always @(negedge clk or negedge b or negedge t or negedge a) begin\n    if(!(b&&t&&a))edges=0;',
        'always @(posedge clk or negedge b or negedge t or negedge a) begin\n    if(!(b&&t&&a)||!seen_falling)edges=0;')
if a.original:
    bench=bench.replace('always @(negedge clk or negedge b or negedge t or negedge a) begin','always @(posedge clk or negedge b or negedge t or negedge a) begin')
(out/'tb.sv').write_text(bench)

# Use the vendor's unmodified divider model, extracted by module boundaries.
vendor=a.vendor_primitives or ROOT/'vendor-research/gowin-1.9.12.04/IDE/simlib/gw5a/prim_sim.v'
vendor_text=vendor.read_text();s=vendor_text.index('module CLKDIV(')
divider=vendor_text[s:vendor_text.index('endmodule',s)+len('endmodule')]
(out/'CLKDIV.v').write_text('`timescale 1ns/1ps\n'+divider+'\n')
vendor_bench=r'''`timescale 1ns/1ps
module GSR;
  wire GSRO=1; // Hierarchical GSR.GSRO used by the unmodified vendor primitive.
  reg pll=0,reset_n=0;
  always #10 pll=~pll;
  wire core,trusted;
  CLKDIV #(.DIV_MODE("2"))c(core,1'b0,pll,reset_n);
  CLKDIV #(.DIV_MODE("4"))t(trusted,1'b0,pll,reset_n);
  reg[2:0] tr;
  always @(posedge trusted or negedge reset_n)
    if(!reset_n)tr<=0;else tr<={tr[1:0],1'b1};
  wire ready;
  startup_reset dut(core,reset_n,tr[2],reset_n,ready);
  realtime last_core_rise,last_trusted_rise;
  integer alignments=0,releases=0,i;
  always @(posedge core)last_core_rise=$realtime;
  always @(posedge trusted)begin
    last_trusted_rise=$realtime;
    #0.001;
    if(reset_n && last_core_rise!=last_trusted_rise)$fatal(1,"unaligned divided rising edges");
    if(reset_n)alignments=alignments+1;
  end
  always @(posedge ready)begin
    if(core!==0)$fatal(1,"reset release is not on falling edge");
    if($realtime-last_core_rise!=20.0)$fatal(1,"not a half-cycle from rising edge");
    releases=releases+1;
  end
  initial begin
    #0.125;reset_n=1;#0.125;reset_n=0;
    for(i=0;i<160;i=i+1)begin
      #(20.25+0.5*i);reset_n=1;
      #800;if(ready!==1)$fatal(1,"vendor-clock startup failed");
      reset_n=0;#0.001;if(ready!==0)$fatal(1,"async assertion failed");
    end
    if(releases!=160)$fatal(1,"missing startup releases");
    $display("PASS vendor divided clocks alignments=%0d startups=%0d",alignments,releases);
    $finish;
  end
endmodule
'''
if a.qualified or a.original:
    vendor_bench=vendor_bench.replace('if(core!==0)','if(core!==1)').replace('falling edge','rising edge')
    vendor_bench=vendor_bench.replace('!=20.0','!=0.0').replace('not a half-cycle from rising edge','not on rising edge')
(out/'tb_vendor.sv').write_text(vendor_bench)

# Sampled-edge proof: arbitrary reset histories; one step per active falling
# core edge. A saturating count supplies an independent sequential spec.
formal=dut+r'''
module proof(input core_clk,board_reset_n,trusted_reset_n,app_reset_n);
  wire ready;
  startup_reset dut(core_clk,board_reset_n,trusted_reset_n,app_reset_n,ready);
  wire all_clear=board_reset_n&&trusted_reset_n&&app_reset_n;
  reg [1:0] stable_edges;
  always @(negedge core_clk or negedge all_clear)
    if(!all_clear)stable_edges<=0;
    else if(stable_edges<3)stable_edges<=stable_edges+1;
  always @*begin
    assert(ready==(stable_edges==3));
    if(!all_clear)assert(!ready);
  end
endmodule
'''
if a.qualified:
    # Expose only the qualifier reset seam to the independent count spec.
    formal=formal.replace('output core_reset_n_o);','output core_reset_n_o, output qualified_reset_n_o);')
    formal=formal.replace('assign core_reset_n_o=core_reset_n;','assign core_reset_n_o=core_reset_n;\nassign qualified_reset_n_o=qualified_async_reset_n;')
    formal=formal.replace('  startup_reset dut(core_clk,board_reset_n,trusted_reset_n,app_reset_n,ready);\n  wire all_clear=board_reset_n&&trusted_reset_n&&app_reset_n;',
        '  wire all_clear;\n  startup_reset dut(core_clk,board_reset_n,trusted_reset_n,app_reset_n,ready,all_clear);')
    formal=formal.replace('always @(negedge core_clk or negedge all_clear)','always @(posedge core_clk or negedge all_clear)')
if a.original:formal=formal.replace('always @(negedge core_clk or negedge all_clear)','always @(posedge core_clk or negedge all_clear)')
(out/'proof.sv').write_text(formal)
(out/'prove.ys').write_text('''read_verilog -formal -sv proof.sv
prep -top proof -flatten
async2sync
opt_clean
sat -verify -prove-asserts -tempinduct -tempinduct-def -seq 2 -maxsteps 12 -set core_clk 0 -set-at 1 board_reset_n 0 -set-at 1 trusted_reset_n 0 -set-at 1 app_reset_n 0 -set-def-inputs -dump_vcd failure.vcd
''')
if a.qualified:
    path=out/'prove.ys';text=path.read_text().replace('async2sync','clk2fflogic')
    text=text.replace('-maxsteps 12 -set core_clk 0','-maxsteps 24')
    path.write_text(text)
if a.original:
    p=out/'prove.ys';p.write_text(p.read_text().replace('-set core_clk 0','-set core_clk 1'))
results=[]
def run(name,cmd):
    tick=time.monotonic()
    with (out/(name+'.log')).open('w')as log:
        code=subprocess.run(cmd,cwd=out,stdout=log,stderr=subprocess.STDOUT).returncode
    results.append({'name':name,'exit_code':code,'elapsed_seconds':time.monotonic()-tick})
    assert code==0,(name,code)
try:
    run('compile-sweep',['iverilog','-g2012','-s','tb','-o','sweep.vvp','startup_reset.sv','tb.sv'])
    run('sweep',['vvp','sweep.vvp'])
    run('compile-vendor',['iverilog','-g2012','-s','GSR','-o','vendor.vvp','startup_reset.sv','CLKDIV.v','tb_vendor.sv'])
    # GSR is a hierarchical instance name, not a preprocessor identifier.
    run('vendor',['vvp','vendor.vvp'])
    run('formal',['yosys','-Q','-s','prove.ys'])
finally:
    record={'result':'PASS'if len(results)==5 and all(r['exit_code']==0 for r in results)else'FAIL',
            'stages':results,'base_top_sha256':hashlib.sha256(source.encode()).hexdigest(),
            'transformed_top_sha256':hashlib.sha256(top.encode()).hexdigest(),
            'reset_excerpt_sha256':hashlib.sha256(excerpt.encode()).hexdigest(),
            'vendor_model_sha256':hashlib.sha256(vendor.read_bytes()).hexdigest(),
            'configuration':'original-rising-three-stage'if a.original else'phase-qualified-entry'if a.qualified else'falling-three-stage',
            'scope':'Actual extracted reset RTL: four-state phase and stopped-clock sweep; unmodified vendor divided-clock phase/startup simulation; inductive sampled-edge equivalence to saturating-count release specification. No analog metastability, PVT, whole-chip or physical security proof.',
            'files_sha256':{f.name:hashlib.sha256(f.read_bytes()).hexdigest()for f in out.iterdir()if f.is_file()}}
    (out/'RESULT.json').write_text(json.dumps(record,indent=2)+'\n')
    print(json.dumps(record,indent=2))
