#!/usr/bin/env python3
"""Check SHA stream-assembly equivalence records; fresh reproduction is optional."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess

HERE=Path(__file__).resolve().parent
CONFIGS={'shared4096':(1,4096),'shared7265984':(1,7265984),
         'shared409632':(1,409632),'local112688':(0,112688),'local1110':(0,1110)}
BASELINE='f5a2b98f77924c37f80314bd2812fab5bb15d6fd75b016886be57cde579e6f33'
CANDIDATE='d004ab01cf7faa75a48a7e2ff59e7fe8dd28a53cc7113ae8575774300a55b117'


def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()


def reconstruct():
    spec=importlib.util.spec_from_file_location('recorded_wrapper_instrumentation',HERE/'verify_sha_wordpack.py')
    ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    baseline=(HERE/'baseline.sv').read_text();candidate=(HERE/'candidate.sv').read_text()
    assert sha(HERE/'baseline.sv')==BASELINE and sha(HERE/'candidate.sv')==CANDIDATE
    old="                    block_q[511-int'(offset_q[5:0])*8 -: 8]<=next_byte;"
    assert baseline.count(old)==1
    assert candidate==baseline.replace(old,'                    block_q<={block_q[503:0],next_byte};')
    top=ref.TOP
    pairs=[("    wire [31:0] current_word=block_b[511-int'(off_b[5:2])*32 -:32];",'''    wire [1023:0] doubled_block={block_b,block_b};
    wire [1023:0] rotated_block=doubled_block<<{off_b[5:0],3'b0};
    wire [511:0] expected_block=rotated_block[1023:512];'''),('''        if(state_a==1) begin
            if(off_a[1:0]==1) assert(packed_a[7:0]==current_word[31:24]);
            if(off_a[1:0]==2) assert(packed_a[15:0]==current_word[31:16]);
            if(off_a[1:0]==3) assert(packed_a[23:0]==current_word[31:8]);
        end''','        if(state_a==1) assert(block_a==expected_block);'),('''    generate for(genvar w=0;w<16;w=w+1) begin
        always @(posedge clk) if(past_valid && state_a==1 &&
            (off_a[1:0]==0 || off_a[5:2]!=w))
            assert(block_a[511-w*32 -:32]==block_b[511-w*32 -:32]);
    end endgenerate''','')]
    for old,new in pairs:
        assert top.count(old)==1;top=top.replace(old,new)
    text=ref.instrument(candidate,'packing_candidate',False)+'\n'+ref.instrument(baseline,'packing_reference',False)+'\n'+top
    assert (HERE/'miter.sv').read_text()==text


def check(model):
    manifest=json.loads((HERE/'PACKAGE.json').read_text())
    actual={str(p.relative_to(HERE))for p in HERE.rglob('*')if p.is_file()and p.name!='PACKAGE.json'}
    assert actual==set(manifest['files'])
    for name,pin in manifest['files'].items():assert sha(HERE/name)==pin,name
    reconstruct()
    for relative in ['rtl/su_sha256.sv','tang/hardware/project/swic/su_sha256.sv',
                     '../home-authorization/hardware/project/swic/su_sha256.sv']:
        assert sha(model/relative)==CANDIDATE,relative
    commands={'prepare':['yosys','-Q','-T','prove.ys'],
        'base':['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t','4','--dump-vcd','base.vcd','model.smt2'],
        'induction':['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-i','-t','4','--dump-vcd','induction.vcd','model.smt2']}
    for name,(shared,limit)in CONFIGS.items():
        folder=HERE/'records'/name;d=json.loads((folder/'RESULT.json').read_text())
        assert d['result']=='PASS'and not d['cover_only']and(d['shared'],d['max_bytes'])==(shared,limit)
        assert d['baseline_sha256']==BASELINE and d['candidate_sha256']==CANDIDATE
        assert d['miter_sha256']==sha(HERE/'miter.sv')
        assert d['reference_helper_sha256']==sha(HERE/'verify_sha_wordpack.py')
        assert set(d['records'])==set(commands)
        recipe=(folder/'prove.ys').read_text()
        assert recipe==f'''read_verilog -formal -D SYNTHESIS -sv miter.sv
chparam -set SHARED {shared} -set LIMIT {limit} -set FAST_COVER 0 packing_miter
prep -top packing_miter -flatten
async2sync
dffunmap
memory_map
opt
dffunmap
opt_clean
write_smt2 -wires model.smt2
'''
        assert d['recipe_sha256']==sha(folder/'prove.ys')
        for stage,command in commands.items():
            r=d['records'][stage];log=folder/(stage+'.log')
            assert r['command']==command and r['exit_code']==0 and r['passed']and r['log_sha256']==sha(log)
            if stage!='prepare':assert 'Status: PASSED'in log.read_text()
        assert 'Temporal induction successful'in(folder/'induction.log').read_text()
    witness=HERE/'controls/launch-witness';d=json.loads((witness/'RESULT.json').read_text())
    assert d['result']=='PASS'and d['cover_only']and d['candidate_sha256']==CANDIDATE
    r=d['records']['cover'];assert r['exit_code']==0 and r['passed']and r['log_sha256']==sha(witness/'cover.log')
    assert 'Reached cover statement in step 67'in(witness/'cover.log').read_text()
    mutant=HERE/'controls/changed-byte';d=json.loads((mutant/'RESULT.json').read_text())
    r=d['records']['mutated-buffer-must-fail'];assert d['result']=='PASS'and r['exit_code']==1 and r['expected_result_matched']
    assert r['log_sha256']==sha(mutant/'mutated-buffer-must-fail.log')
    assert 'Status: FAILED'in(mutant/'mutated-buffer-must-fail.log').read_text()
    text=(HERE/'miter.sv').read_text();old='block_q<={block_q[503:0],next_byte};'
    assert text.count(old)==1 and(mutant/'miter.sv').read_text()==text.replace(old,"block_q<={block_q[503:0],(next_byte ^ 8'h01)};")
    return commands


def logical(raw):
    first,rest=raw.split(b'\n',1)
    assert first.startswith(b'; SMT-LIBv2 description generated by Yosys ')
    return rest


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--model',type=Path,default=HERE.parents[1])
    modes=p.add_mutually_exclusive_group();modes.add_argument('--compile-only',action='store_true');modes.add_argument('--replay',action='store_true')
    p.add_argument('--output',type=Path);a=p.parse_args();commands=check(a.model.resolve());records=[]
    if a.compile_only or a.replay:
        assert a.output and not a.output.exists()and not a.output.resolve().is_relative_to(a.model.resolve())
        a.output.mkdir(parents=True)
        for name in CONFIGS:
            out=a.output/name;out.mkdir();source=HERE/'records'/name
            shutil.copyfile(HERE/'miter.sv',out/'miter.sv');shutil.copyfile(source/'prove.ys',out/'prove.ys')
            stages=['prepare','base','induction']if a.replay else['prepare']
            for stage in stages:
                with(out/(stage+'.log')).open('w')as log:r=subprocess.run(commands[stage],cwd=out,stdout=log,stderr=subprocess.STDOUT)
                assert r.returncode==0,(name,stage)
                if stage=='prepare':assert logical((out/'model.smt2').read_bytes())==logical((source/'model.smt2').read_bytes()),'Fresh logical model differs'
                else:assert 'Status: PASSED'in(out/(stage+'.log')).read_text()
            records.append(dict(case=name,result='PASS',logical_model_identical=True,fresh_solver_stages=2 if a.replay else 0))
    result=dict(result='PASS',wrapper_configurations=5,unbounded_induction_records=5,launch_witness=True,changed_byte_control=True,
        fresh_compilations=len(records),fresh_solver_queries=2*len(records)if a.replay else 0,
        scope='Two-state wrapper equivalence under common arbitrary compressor responses and a common initial reset; complete blocks agree on every compression launch. No SHA specification, signature-security, mapping, timing or whole-machine theorem.')
    if a.output:(a.output/'RESULT.json').write_text(json.dumps(dict(**result,records=records),indent=2)+'\n')
    print(json.dumps(result))


if __name__=='__main__':main()
