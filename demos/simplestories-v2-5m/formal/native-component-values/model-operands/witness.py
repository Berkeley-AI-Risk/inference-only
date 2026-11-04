"""Exercise native bank fill/hash/read/reuse and actual-only read defects.

Finite operating evidence complements the induction rules. Python hashlib
supplies test digests; this is not a universal theorem about RTL SHA-256.
"""
from concurrent.futures import ThreadPoolExecutor
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
from prepare import sha, write_json


def digest(page, words):
    image = b''.join(b''.join(((page*0x100000+word*0x100+lane+1)&0xffffffff).to_bytes(4,'little')
                               for lane in range(8)) for word in range(words))
    return hashlib.sha256(image.ljust(4096,b'\0')).hexdigest()


BENCH = r'''
`timescale 1ns/1ps
module tb;
  reg clk=0; always #5 clk=~clk;
  reg reset_n=0,cancel_read_i=0,begin_valid_i=0,fill_valid_i=0,fill_last_i=0;
  reg read_valid_i=0,response_ready_i=0;
  reg [10:0] begin_page_i=0;
  reg [255:0] expected_digest_i=0,fill_data_i=0;
  reg [6:0] read_word_i=0;
  wire begin_ready_o,fill_ready_o,read_ready_o,response_valid_o,assigned_o,verified_o,fault_o;
  wire [255:0] response_data_o;
  wire [10:0] page_o;
  board1_verified_page_bank dut(.*);
  integer compared=0;
  function automatic [255:0] pattern(input integer p,input integer w);
    integer lane;
    begin for(lane=0;lane<8;lane=lane+1)
      pattern[lane*32 +: 32]=p*32'h100000+w*32'h100+lane+1;
    end
  endfunction
  task automatic tick; begin @(posedge clk); #1; end endtask
  task automatic check_value(input integer p,input integer w);
    begin
      if(!response_valid_o || !verified_o || fault_o || page_o!=p)
        $fatal(1,"BAD_VALID page=%0d word=%0d state=%0d fault=%0d",p,w,dut.state_q,fault_o);
      if(response_data_o!==pattern(p,w)) begin
        $display("NUMERIC_MISMATCH page=%0d word=%0d expected=%064h actual=%064h verified=%0d fault=%0d",
          p,w,pattern(p,w),response_data_o,verified_o,fault_o);
        $fatal(1,"read value mismatch");
      end
      compared=compared+1;
      $display("WORD page=%0d word=%0d data=%064h",p,w,response_data_o);
    end
  endtask
  task automatic fill_page(input integer p,input integer words,input [255:0] d);
    integer i,cycles;
    begin
      @(negedge clk); begin_page_i=p;expected_digest_i=d;begin_valid_i=1;
      #1;if(!begin_ready_o)$fatal(1,"begin not ready");tick();
      @(negedge clk);begin_valid_i=0;
      for(i=0;i<words;i=i+1) begin
        fill_valid_i=1;fill_data_i=pattern(p,i);fill_last_i=(i==words-1);
        #1;if(!fill_ready_o)$fatal(1,"fill not ready");tick();
        @(negedge clk);
      end
      fill_valid_i=0;fill_last_i=0;cycles=0;
      while(!verified_o && !fault_o && cycles<30000)begin tick();cycles=cycles+1;end
      if(!verified_o || fault_o)$fatal(1,"hash/verification failed");
      $display("SEALED page=%0d words=%0d hash_cycles=%0d",p,words,cycles);
    end
  endtask
  task automatic read_page(input integer p,input integer words);
    integer i;
    begin
      for(i=0;i<words;i=i+1) begin
        @(negedge clk);read_valid_i=1;read_word_i=i;response_ready_i=1;
        #1;if(!read_ready_o)$fatal(1,"read not ready");tick();check_value(p,i);
      end
      @(negedge clk);read_valid_i=0;tick();
    end
  endtask
  integer j;
  initial begin
    repeat(3)tick();@(negedge clk);reset_n=1;
    fill_page(0,128,256'hDIGEST0);
    read_page(0,128);
    // A held old response prevents replacement even with a new begin offer.
    @(negedge clk);read_valid_i=1;read_word_i=13;response_ready_i=0;tick();check_value(0,13);
    @(negedge clk);read_valid_i=0;begin_valid_i=1;begin_page_i=1773;
    for(j=0;j<3;j=j+1)begin
      #1;if(begin_ready_o)$fatal(1,"evicted a held response");tick();check_value(0,13);
    end
    @(negedge clk);begin_valid_i=0;response_ready_i=1;tick();
    // Cancellation drops read validity while retaining the verified page.
    @(negedge clk);read_valid_i=1;read_word_i=27;response_ready_i=0;tick();check_value(0,27);
    @(negedge clk);read_valid_i=0;cancel_read_i=1;#1;
    if(response_valid_o)$fatal(1,"cancel leaked response");tick();
    @(negedge clk);cancel_read_i=0;response_ready_i=1;
    fill_page(1773,118,256'hDIGEST1);
    read_page(1773,118);
    $display("PASS compared=%0d actual_reset_count=1",compared);
    $finish;
  end
  initial begin #2000000;$fatal(1,"witness timeout");end
endmodule
'''


def service_witness():
    from check_model_rom import validate
    binding=validate();image=Path(binding['model_image_path']).read_bytes()
    folder=HERE/'witnesses/service';folder.mkdir(parents=True,exist_ok=True)
    native=(HERE/'service-project/native.sv').read_bytes()
    manifest=json.loads((HERE/'SERVICE-SOURCES.json').read_text())
    if sha(native)!=manifest['source_sha256']:raise ValueError('Service source changed')
    (folder/'native.sv').write_bytes(native)
    for name,expected in manifest['tables'].items():
        data=(HERE/'service-project'/name).read_bytes()
        if sha(data)!=expected:raise ValueError('Table changed')
        (folder/name).write_bytes(data)
    image_hex=''.join(format(int.from_bytes(image[i:i+32],'little'),'064x')+'\n' for i in range(0,len(image),32))
    (folder/'image256.memh').write_text(image_hex)
    bench=r'''
`timescale 1ns/1ps
module tb;
  reg clk=0;always #5 clk=~clk;
  reg reset_n=0,cancel_i=0,model_locked_i=0,request_valid_i=0,response_ready_i=0;
  reg [18:0] request_word_i=0;
  wire request_ready_o,response_valid_o,ddr_request_valid_o,fault_o;
  wire [255:0] response_data_o;
  wire [18:0] ddr_request_word_o;
  reg ddr_request_ready_i=0,ddr_response_valid_i=0,ddr_response_error_i=0;
  reg [255:0] ddr_response_data_i=0;
  reg [255:0] image[0:227061];
  integer requests[0:11];integer expected[0:11];integer raw_q[0:31];
  integer cycle=0,accepted=0,compared=0,raw_count=0,raw_write=0,raw_read=0,raw_requests=0;
  reg accept_raw,return_raw;
  board1_verified_ddr_page_service #(.BANKS(4),.ADDR_W(19)) dut(.*);
  initial begin
    $readmemh("image256.memh",image);
    requests[0]=0;requests[1]=1;requests[2]=127;requests[3]=128;
    requests[4]=511;requests[5]=211920;requests[6]=214247;requests[7]=227061;
    requests[8]=512;requests[9]=0;requests[10]=211921;requests[11]=127;
    repeat(3)@(negedge clk);reset_n=1;model_locked_i=1;
  end
  always @(negedge clk) if(reset_n)begin
    request_valid_i=(accepted<12 && cycle%3!=0);
    request_word_i=accepted<12 ? requests[accepted] : 0;
    response_ready_i=(cycle%5!=0);
    ddr_request_ready_i=(raw_count<32 && cycle%7!=0);
    ddr_response_valid_i=(raw_count>0 && cycle%4!=0);
    ddr_response_data_i=ddr_response_valid_i ? image[raw_q[raw_read]] : 0;
  end
  always @(posedge clk) if(reset_n)begin
    cycle=cycle+1;
    if(fault_o)$fatal(1,"service fault at cycle %0d",cycle);
    if(request_valid_i && request_ready_o)begin expected[accepted]=request_word_i;accepted=accepted+1;end
    if(response_valid_o && response_ready_i)begin
      if(compared>=accepted || response_data_o!==image[expected[compared]])begin
        $display("SERVICE_MISMATCH ordinal=%0d address=%0d expected=%064h actual=%064h",compared,expected[compared],image[expected[compared]],response_data_o);
        $fatal(1,"service value mismatch");
      end
      $display("SERVICE_WORD ordinal=%0d address=%0d data=%064h",compared,expected[compared],response_data_o);
      compared=compared+1;
      if(compared==12)begin
        $display("PASS service_compared=12 raw_reads=%0d actual_reset_count=1",raw_requests);
        $finish;
      end
    end
    accept_raw=ddr_request_valid_o && ddr_request_ready_i;
    return_raw=ddr_response_valid_i;
    if(accept_raw)begin
      if(ddr_request_word_o>=227062)$fatal(1,"bad raw address");
      raw_q[raw_write]=ddr_request_word_o;raw_write=(raw_write+1)%32;raw_requests=raw_requests+1;
    end
    if(return_raw)raw_read=(raw_read+1)%32;
    case({accept_raw,return_raw})
      2'b10:raw_count=raw_count+1;
      2'b01:raw_count=raw_count-1;
    endcase
  end
  initial begin #10000000;$fatal(1,"service witness timeout");end
endmodule
'''
    (folder/'tb.sv').write_text(bench)
    cp=subprocess.run(['iverilog','-g2012','-D','SYNTHESIS','-s','tb','-o','sim','native.sv','tb.sv'],
                      cwd=folder,capture_output=True,text=True,timeout=60)
    (folder/'compile.log').write_text(cp.stdout+cp.stderr)
    if cp.returncode:raise ValueError('Service witness compilation failed')
    cp=subprocess.run(['vvp','sim'],cwd=folder,capture_output=True,text=True,timeout=60)
    raw=cp.stdout+cp.stderr;(folder/'run.log').write_text(raw)
    lines=re.findall(r'^SERVICE_WORD ordinal=(\d+) address=(\d+) data=([0-9a-f]{64})$',raw,re.M)
    addresses=[0,1,127,128,511,211920,214247,227061,512,0,211921,127]
    passed=cp.returncode==0 and len(lines)==len(addresses) and 'PASS service_compared=12' in raw
    for index,(ordinal,address,data) in enumerate(lines):
        if int(ordinal)!=index or int(address)!=addresses[index] or int(data,16)!=int.from_bytes(image[int(address)*32:(int(address)+1)*32],'little'):
            passed=False
    result=dict(schema='Native-model-service-operating-evidence-v1',passed=passed,compared_values=len(lines),exit_code=cp.returncode,
        model_image_sha256=sha(image),actual_source_sha256=sha(native),bench_sha256=sha(bench.encode()),
        transcript_sha256=sha(raw.encode()),image_hex_sha256=sha(image_hex.encode()),production_banks=4,
        raw_memory_model='Ordered faithful reads at the private raw DDR seam for this finite experiment only',
        public_CLEAR_tested=False,custom_upstream_DDR_path_proved=False,unbounded_proof=False,whole_model_consumption_proved=False)
    write_json(HERE/'SERVICE-OPERATING-EVIDENCE.json',result);print(json.dumps(result,indent=2))
    return 0 if passed else 1


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--service',action='store_true');args=ap.parse_args()
    if args.service:return service_witness()
    native = (HERE/'project/native.sv').read_text()
    source = json.loads((HERE/'SOURCES.json').read_text())
    if sha(native.encode()) != source['source_sha256']: raise ValueError('Native source changed')
    bench = BENCH.replace('DIGEST0',digest(0,128)).replace('DIGEST1',digest(1773,118))
    variants = {
      'native':native,
      'wrong-word':native.replace("prefetch_read1 ? {next_block,1'b1} : read_word_i", "prefetch_read1 ? {next_block,1'b1} : (read_word_i ^ 7'd1)"),
      'stale-read':native.replace('if(memory_read) read_data_q<=memory_q[memory_read_address];',
          "if(memory_read && !(read_fire && page_o==11'd1773)) read_data_q<=memory_q[memory_read_address];"),
    }
    for name,text in variants.items():
        if name!='native' and text==native: raise ValueError('Mutation did not apply: '+name)
    def run(item):
        name,text=item;folder=HERE/'witnesses'/name;folder.mkdir(parents=True,exist_ok=True)
        (folder/'native.sv').write_text(text);(folder/'tb.sv').write_text(bench)
        compiled=subprocess.run(['iverilog','-g2012','-D','SYNTHESIS','-s','tb','-o','sim','native.sv','tb.sv'],cwd=folder,
                                capture_output=True,text=True,timeout=60)
        (folder/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:raise ValueError('Compile failed: '+name)
        cp=subprocess.run(['vvp','sim'],cwd=folder,capture_output=True,text=True,timeout=60)
        raw=cp.stdout+cp.stderr;(folder/'run.log').write_text(raw)
        lines=re.findall(r'^WORD page=(\d+) word=(\d+) data=([0-9a-f]{64})$',raw,re.M)
        for page,word,data in lines:
            expected=sum(((int(page)*0x100000+int(word)*0x100+lane+1)&0xffffffff)<<(32*lane) for lane in range(8))
            if int(data,16)!=expected:raise ValueError('Incorrect positive transcript')
        if name=='native':
            passed=cp.returncode==0 and 'PASS compared=251 actual_reset_count=1' in raw and len(lines)==251
            for page,words in [(0,128),(1773,118)]:
                if not set(range(words))<=set(int(w) for p,w,d in lines if int(p)==page):passed=False
        else:
            mismatch=re.search(r'NUMERIC_MISMATCH page=(\d+) word=(\d+) expected=([0-9a-f]{64}) actual=([0-9a-f]{64}) verified=1 fault=0',raw)
            passed=cp.returncode!=0 and bool(mismatch) and mismatch[3]!=mismatch[4]
        result=dict(case=name,passed=passed,exit_code=cp.returncode,compared_values=len(lines),
                    native_source_sha256=sha(native.encode()),actual_source_sha256=sha(text.encode()),
                    bench_sha256=sha(bench.encode()),transcript_sha256=sha(raw.encode()),
                    numerical_defect_detected=name!='native' and passed,unbounded_proof=False)
        write_json(folder/'RESULT.json',result);return name,result
    with ThreadPoolExecutor(max_workers=3) as pool:results=dict(pool.map(run,variants.items()))
    result=dict(schema='Native-bank-operating-evidence-v1',passed=all(x['passed'] for x in results.values()),cases=results,
                whole_model_consumption_proved=False,RTL_SHA256_correspondence_proved=False)
    write_json(HERE/'OPERATING-EVIDENCE.json',result)
    print(json.dumps(result,indent=2))
    return 0 if result['passed'] else 1


if __name__=='__main__':raise SystemExit(main())
