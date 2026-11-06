#!/usr/bin/env python3
"""Private compositional proof of byte versus word SHA block assembly."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import time

HERE=Path(__file__).resolve().parent
SOURCE=HERE.parent/'sawic-home-release-20261104/package/demos/simplestories-v2-5m/variants/signed-update/rtl/su_sha256.sv'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def candidate(text):
    assert sha(text.encode())=='f5a2b98f77924c37f80314bd2812fab5bb15d6fd75b016886be57cde579e6f33'
    text=text.replace('    logic [511:0] block_q;','    logic [511:0] block_q;\n    logic [31:0] packed_word_q;')
    text=text.replace('block_q<=0;chain_q<=IV;','block_q<=0;packed_word_q<=0;chain_q<=IV;')
    old="                    block_q[511-int'(offset_q[5:0])*8 -: 8]<=next_byte;"
    assert text.count(old)==1
    return text.replace(old,"""                    packed_word_q<={packed_word_q[23:0],next_byte};
                    if(offset_q[1:0]==3)
                        block_q[511-int'(offset_q[5:2])*32 -: 32]<={packed_word_q[23:0],next_byte};""")


def instrument(text,name,word):
    text=text.replace('module su_sha256 #(',f'module {name} #(',1)
    marker='    input wire [255:0] shared_digest_i\n);'
    assert text.count(marker)==1
    text=text.replace(marker,'''    input wire [255:0] shared_digest_i,
    input wire formal_local_busy_i,formal_local_done_i,
    input wire [255:0] formal_local_digest_i,
    output wire [2:0] formal_state_o,
    output wire [31:0] formal_packed_o,
    output wire [63:0] formal_lengths_o
);''')
    old='''    board1_sha256_compact_compress u_compress(
        .clk_i(clk),.reset_n_i(reset_n),.start_i(state_q==LAUNCH),
        .block_i(block_q),.state_i(chain_q),.busy_o(compressor_busy),
        .done_o(compressor_done),.state_o(compressor_digest));'''
    assert text.count(old)==1
    text=text.replace(old,'''    // Explicit common child-response contract for this wrapper-only proof.
    assign compressor_busy=formal_local_busy_i;
    assign compressor_done=formal_local_done_i;
    assign compressor_digest=formal_local_digest_i;''')
    at=text.index('\nendmodule')
    observe='\n    assign formal_state_o=state_q;\n    assign formal_lengths_o={length_q,padded_q};\n    assign formal_packed_o='+('packed_word_q' if word else "32'd0")+';\n'
    return text[:at]+observe+text[at:]


TOP=r'''
module packing_miter #(parameter integer SHARED=1, LIMIT=4096, FAST_COVER=0)(
    input wire clk,reset_n,start_i,byte_valid_i,
    input wire [31:0] length_i,
    input wire [7:0] byte_i,
    input wire shared_accept_i,shared_done_i,
    input wire [255:0] shared_digest_i,
    input wire local_busy,local_done,
    input wire [255:0] local_digest);
    wire ready_a,ready_b,busy_a,busy_b,done_a,done_b,fault_a,fault_b,req_a,req_b;
    wire [31:0] off_a,off_b,packed_a,packed_b;
    wire [2:0] state_a,state_b;
    wire [255:0] digest_a,digest_b,chain_a,chain_b;
    wire [511:0] block_a,block_b;
    wire [63:0] lengths_a,lengths_b;
    packing_candidate #(.USE_SHARED_COMPRESSOR(SHARED),.MAX_BYTES(LIMIT)) a(
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.length_i(length_i),
        .byte_valid_i(byte_valid_i),.byte_ready_o(ready_a),.byte_i(byte_i),
        .byte_offset_o(off_a),.busy_o(busy_a),.done_o(done_a),.fault_o(fault_a),.digest_o(digest_a),
        .shared_request_o(req_a),.shared_block_o(block_a),.shared_state_o(chain_a),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i),
        .formal_local_busy_i(local_busy),.formal_local_done_i(local_done),.formal_local_digest_i(local_digest),
        .formal_state_o(state_a),.formal_packed_o(packed_a),.formal_lengths_o(lengths_a));
    packing_reference #(.USE_SHARED_COMPRESSOR(SHARED),.MAX_BYTES(LIMIT)) b(
        .clk(clk),.reset_n(reset_n),.start_i(start_i),.length_i(length_i),
        .byte_valid_i(byte_valid_i),.byte_ready_o(ready_b),.byte_i(byte_i),
        .byte_offset_o(off_b),.busy_o(busy_b),.done_o(done_b),.fault_o(fault_b),.digest_o(digest_b),
        .shared_request_o(req_b),.shared_block_o(block_b),.shared_state_o(chain_b),
        .shared_accept_i(shared_accept_i),.shared_done_i(shared_done_i),.shared_digest_i(shared_digest_i),
        .formal_local_busy_i(local_busy),.formal_local_done_i(local_done),.formal_local_digest_i(local_digest),
        .formal_state_o(state_b),.formal_packed_o(packed_b),.formal_lengths_o(lengths_b));
    reg past_valid=0;
    reg [7:0] witness_cycle=0;
    always @(posedge clk) past_valid<=1;
    always @(posedge clk) if(witness_cycle<70) witness_cycle<=witness_cycle+1;
    always @* if(!past_valid) assume(!reset_n);
    always @* if(FAST_COVER) begin
        assume(length_i==0);
        assume(reset_n==(witness_cycle!=0));
        assume(start_i==(witness_cycle==1));
        assume(!local_busy);
        assume(shared_accept_i);
    end
    wire [31:0] current_word=block_b[511-int'(off_b[5:2])*32 -:32];
    always @(posedge clk) if(past_valid) begin
        assert({ready_a,busy_a,done_a,fault_a,req_a,off_a,digest_a,chain_a,state_a}==
               {ready_b,busy_b,done_b,fault_b,req_b,off_b,digest_b,chain_b,state_b});
        assert(lengths_a==lengths_b);
        if(state_a==0 || state_a==2 || state_a==3) begin
            assert(off_a[5:0]==0);
            assert(block_a==block_b);
        end
        if(state_a==1) begin
            if(off_a[1:0]==1) assert(packed_a[7:0]==current_word[31:24]);
            if(off_a[1:0]==2) assert(packed_a[15:0]==current_word[31:16]);
            if(off_a[1:0]==3) assert(packed_a[23:0]==current_word[31:8]);
        end
        cover(state_a==2 && !fault_a);
    end
    generate for(genvar w=0;w<16;w=w+1) begin
        always @(posedge clk) if(past_valid && state_a==1 &&
            (off_a[1:0]==0 || off_a[5:2]!=w))
            assert(block_a[511-w*32 -:32]==block_b[511-w*32 -:32]);
    end endgenerate
endmodule
'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--shared',type=int,choices=[0,1],default=1)
    p.add_argument('--limit',type=int,default=4096)
    p.add_argument('--cover',action='store_true')
    a=p.parse_args();out=a.output.resolve();out.mkdir(parents=True,exist_ok=False)
    baseline=SOURCE.read_text();new=candidate(baseline)
    (out/'baseline.sv').write_text(baseline);(out/'candidate.sv').write_text(new)
    (out/'miter.sv').write_text(instrument(new,'packing_candidate',True)+'\n'+instrument(baseline,'packing_reference',False)+'\n'+TOP)
    (out/'prove.ys').write_text(f'''read_verilog -formal -D SYNTHESIS -sv miter.sv
chparam -set SHARED {a.shared} -set LIMIT {a.limit} -set FAST_COVER {int(a.cover)} packing_miter
{'chformal -assert -remove' if a.cover else ''}
prep -top packing_miter -flatten
async2sync
dffunmap
memory_map
opt
dffunmap
opt_clean
write_smt2 -wires model.smt2
''')
    commands=[('prepare',['yosys','-Q','-T','prove.ys'])]
    if a.cover:
        commands.append(('cover',['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-c','-t','66:68','--dump-vcd','cover.vcd','model.smt2']))
    else:
        commands += [('base',['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t','4','--dump-vcd','base.vcd','model.smt2']),
                     ('induction',['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-i','-t','4','--dump-vcd','induction.vcd','model.smt2'])]
    records={}
    for name,command in commands:
        started=time.monotonic();log=out/(name+'.log')
        with log.open('w') as stream:r=subprocess.run(command,cwd=out,stdout=stream,stderr=subprocess.STDOUT)
        raw=log.read_bytes();ok=r.returncode==0 and (name=='prepare' or b'Status: PASSED' in raw)
        records[name]=dict(command=command,exit_code=r.returncode,passed=ok,elapsed_seconds=time.monotonic()-started,log_sha256=sha(raw))
        print(json.dumps(dict(stage=name,**records[name])),flush=True)
        if not ok:break
    passed=len(records)==len(commands) and all(r['passed'] for r in records.values())
    result=dict(result='PASS' if passed else 'NOT_PROVEN',shared=a.shared,max_bytes=a.limit,cover_only=a.cover,records=records,
                baseline_sha256=sha(baseline.encode()),candidate_sha256=sha(new.encode()),miter_sha256=sha((out/'miter.sv').read_bytes()),
                scope='Compositional byte/word wrapper equivalence with common arbitrary compressor responses, including all actual wrapper control/padding and local/shared busy/accept logic. Block values agree at every compression launch. Idle/intermediate shared-block outputs need not match. No compressor algorithm, physical or whole-machine theorem.',
                production_RTL_changed=False)
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
    raise SystemExit(0 if passed else 1)


if __name__=='__main__':main()
