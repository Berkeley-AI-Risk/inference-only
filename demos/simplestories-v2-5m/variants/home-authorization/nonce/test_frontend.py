#!/usr/bin/env python3
"""Deterministic functional tests of health screening/conditioning, not entropy tests."""
import argparse,hashlib,json,shutil,subprocess,tempfile,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True)
p.add_argument('--sample-bytes',type=int,choices=[32,512],default=512);a=p.parse_args()
out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
samples=bytes((13*i+7)%256 for i in range(a.sample_bytes))
digest=hashlib.sha256(b'SAWIC-NONCE-v1'.ljust(16,b'\0')+samples).hexdigest()
digest2=hashlib.sha256(b'SAWIC-NONCE-v1'.ljust(16,b'\0')+bytes((29*i+11)%256 for i in range(a.sample_bytes))).hexdigest()
tb='''`timescale 1ns/1ps
module tb_nonce;
reg clk=0;always #5 clk=~clk;
reg reset_n=0,request=0,valid=0;reg[7:0]data=0;
wire enabled,nv,fault;wire[255:0]nonce;
nonce_frontend #(.SAMPLE_BYTES(SAMPLE_COUNT),.STARTUP_CYCLES(4),.TIMEOUT_CYCLES(10000)) dut(
 .clk(clk),.reset_n(reset_n),.request_i(request),.entropy_enable_o(enabled),
 .entropy_valid_i(valid),.entropy_byte_i(data),.nonce_valid_o(nv),.nonce_o(nonce),.fault_o(fault));
task reset;
begin reset_n=0;request=0;valid=0;repeat(3)@(negedge clk);reset_n=1;@(negedge clk);end
endtask
task collect(input integer mode);
integer i;begin
 request=1;wait(dut.state_q==2);@(negedge clk);i=0;
 while(i<SAMPLE_COUNT&&!fault)begin
  valid=1;data=mode==0?8'(13*i+7):mode==1?8'haa:mode==2?8'(i%2):8'(29*i+11);
  @(posedge clk);if(dut.state_q==2)i=i+1;
  @(negedge clk);
 end
 valid=0;
end endtask
initial begin
 reset();collect(0);wait(nv||fault);
 if(fault||nonce!==256'hDIGEST)$fatal(1,"conditioned digest mismatch");
 repeat(10)begin @(negedge clk);if(!nv||nonce!==256'hDIGEST)$fatal(1,"unstable nonce");end
 $display("PASS full collection, independent SHA-256 match and stable ready");
 request=0;@(negedge clk);if(nv||nonce!=0)$fatal(1,"nonce exposed after withdrawal");
 $display("PASS output masking after request withdrawal");
 repeat(10)@(negedge clk);collect(3);wait(nv||fault);
 if(fault||nonce!==256'hSECOND_DIGEST)$fatal(1,"second request reused stale sample data");
 $display("PASS fresh synchronous RAM data on second request without reset");
 reset();collect(1);wait(fault);if(nv||nonce!=0)$fatal(1,"stuck source accepted");
 request=0;repeat(20)@(negedge clk);if(!fault)$fatal(1,"fault not latched");
 $display("PASS repeated-byte rejection and sticky fault");
 reset();collect(2);wait(fault);if(nv)$fatal(1,"biased source accepted");
 $display("PASS severe bit-bias rejection");
 reset();request=1;repeat(10020)@(negedge clk);if(!fault||nv)$fatal(1,"missing-source timeout");
 $display("PASS missing entropy timeout");
 reset();request=1;wait(dut.state_q==2);request=0;repeat(10)@(negedge clk);
 if(nv||nonce!=0||fault)$fatal(1,"cancelled collection became usable");
 $display("PASS cancelled collection discarded");
 $display("PASS all nonce frontend functional cases");$finish;
end
endmodule
'''.replace('SAMPLE_COUNT',str(a.sample_bytes)).replace('SECOND_DIGEST',digest2).replace('DIGEST',digest)
build=Path(tempfile.mkdtemp(prefix='nonce-test-'));(build/'tb_nonce.sv').write_text(tb)
sources=[ROOT/'nonce/nonce_frontend.sv',ROOT/'rtl/vendor/sha.sv',ROOT/'rtl/vendor/su_sha256.sv']
for q in sources:shutil.copyfile(q,build/q.name)
cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_nonce','-j','1','--Mdir','obj']+[q.name for q in sources]+['tb_nonce.sv']
start=time.monotonic()
with (out/'build.log').open('w')as log:subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
with (out/'run.log').open('w')as log:run=subprocess.run([str(build/'obj/Vtb_nonce')],cwd=build,stdout=log,stderr=subprocess.STDOUT)
text=(out/'run.log').read_text();passed=run.returncode==0 and 'PASS all nonce frontend' in text
record={'result':'PASS' if passed else 'FAIL','elapsed_seconds':time.monotonic()-start,'build_directory':str(build),
 'source_sha256':{str(q.relative_to(ROOT)):hashlib.sha256(q.read_bytes()).hexdigest()for q in sources},
 'testbench_sha256':hashlib.sha256(tb.encode()).hexdigest(),'expected_digest':digest,'sample_bytes':a.sample_bytes,'physical_entropy_claim':False}
(out/'RESULT.json').write_text(json.dumps(record,indent=2)+'\n');print(json.dumps(record,indent=2));raise SystemExit(0 if passed else 1)
