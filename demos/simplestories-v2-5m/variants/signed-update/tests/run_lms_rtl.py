#!/usr/bin/env python3
import json
import subprocess
import time
import tempfile
import shutil
import hashlib
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'evidence/rtl-lms'
OUT.mkdir(parents=True,exist_ok=True)
vectors=json.loads((ROOT/'evidence/generated/lms-vectors.json').read_text())
base=vectors[-1]
for name,at in [('leaf-out-of-range',3),('ots-type',7),('lms-type',1131),
                ('chain-byte',50),('authentication-path',1150),('randomizer',8)]:
    v=dict(base);s=bytearray.fromhex(v['signature'])
    s[at]=32 if name=='leaf-out-of-range' else s[at]^1
    v.update(name=name,signature=s.hex(),expected=False);vectors.append(v)
v=dict(base);v.update(name='wrong-public-root',key=v['key'][:-2]+f'{int(v["key"][-2:],16)^1:02x}',expected=False);vectors.append(v)
calls=[]
for i,v in enumerate(vectors):
    msg=bytes.fromhex(v['message']);sig=bytes.fromhex(v['signature'])
    for label,data in [('message',msg.ljust(256,b'\0')),('signature',sig)]:
        (OUT/f'{i}-{label}.hex').write_text(''.join(f'{b:02x}\n' for b in data))
    key=bytes.fromhex(v['key'])
    calls.append(f'run_case({i}, {len(msg)}, 128\'h{key[8:24].hex()}, 256\'h{key[24:].hex()}, 1\'b{int(v["expected"])});')
tb='''`timescale 1ns/1ps
module tb_lms;
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,start=0;
  reg [127:0] identifier;reg [255:0] root;
  reg [8:0] length;
  wire [10:0] sa;wire [7:0] ma;
  reg [7:0] signature[0:1291];reg [7:0] message[0:255];
  wire busy,done,valid,fault;
  integer total_cycles=0;
  su_lms_verify dut(.clk(clk),.reset_n(reset_n),.start_i(start),
    .public_i_i(identifier),.public_root_i(root),.message_length_i(length),
    .signature_address_o(sa),.signature_byte_i(signature[sa]),
    .message_address_o(ma),.message_byte_i(message[ma]),
    .busy_o(busy),.done_o(done),.valid_o(valid),.fault_o(fault));
  task run_case(input integer n,input integer len,input [127:0] id,
                input [255:0] expected_root,input expected);
    integer cycles;string path;
    begin
      reset_n=0;start=0;repeat(3) @(negedge clk);
      path=$sformatf("OUT/%0d-signature.hex",n);$readmemh(path,signature);
      path=$sformatf("OUT/%0d-message.hex",n);$readmemh(path,message);
      identifier=id;root=expected_root;length=9'(len);
      reset_n=1;@(negedge clk);start=1;@(negedge clk);start=0;
      cycles=0;
      while(!done && cycles<3000000) begin
        if(valid) $fatal(1,"early validity");
        @(negedge clk);cycles=cycles+1;
      end
      if(!done || valid!==expected) $fatal(1,"vector %0d done=%0d valid=%0d expected=%0d fault=%0d state=%0d cycles=%0d",n,done,valid,expected,fault,dut.state_q,cycles);
      total_cycles=total_cycles+cycles;
      $display("PASS vector=%0d cycles=%0d expected=%0d",n,cycles,expected);
    end
  endtask
  initial begin
CALLS
    $display("PASS all LMS vectors total_cycles=%0d",total_cycles);$finish;
  end
endmodule
'''.replace('OUT',str(OUT)).replace('CALLS','\n'.join(calls))
(OUT/'tb_lms.sv').write_text(tb)
build=Path(tempfile.mkdtemp(prefix='swic-lms-'))
sources=[ROOT/'rtl/vendor/sha.sv',ROOT/'rtl/su_sha256.sv',ROOT/'rtl/su_lms_verify.sv',OUT/'tb_lms.sv']
for source in sources:shutil.copyfile(source,build/source.name)
inputs=[ROOT/'evidence/generated/lms-vectors.json']+sorted(OUT.glob('*-message.hex'))+sorted(OUT.glob('*-signature.hex'))
source_hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in sources}
input_hashes={str(s.relative_to(ROOT)):hashlib.sha256(s.read_bytes()).hexdigest() for s in inputs}
cmd=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_lms','-j','1',
     '--Mdir','obj']+[s.name for s in sources]
t=time.time()
with (OUT/'build.log').open('w') as log:
    subprocess.run(cmd,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
with (OUT/'run.log').open('w') as log:
    subprocess.run([str(build/'obj/Vtb_lms')],stdout=log,stderr=subprocess.STDOUT,check=True)
for name,digest in {**source_hashes,**input_hashes}.items():
    assert hashlib.sha256((ROOT/name).read_bytes()).hexdigest()==digest,'input changed during run: '+name
result={'result':'PASS','vectors':len(vectors),'elapsed_seconds':time.time()-t,
        'build_command':cmd,'build_directory':str(build),
        'source_sha256':source_hashes,'input_sha256':input_hashes,
        'cases':[{'name':v['name'],'expected':v['expected']} for v in vectors]}
(OUT/'result.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps({k:result[k] for k in ('result','vectors','elapsed_seconds')},indent=2))
