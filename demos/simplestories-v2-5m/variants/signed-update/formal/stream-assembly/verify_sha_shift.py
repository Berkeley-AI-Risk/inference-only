#!/usr/bin/env python3
"""Prove fixed-wiring SHA block assembly against the reset-full byte wrapper."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('word_reference', HERE/'verify_sha_wordpack.py')
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--shared', type=int, choices=[0, 1], required=True)
    p.add_argument('--limit', type=int, required=True)
    p.add_argument('--cover', action='store_true')
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    baseline = reference.SOURCE.read_text()
    assert digest(baseline.encode()) == 'f5a2b98f77924c37f80314bd2812fab5bb15d6fd75b016886be57cde579e6f33'
    old = "                    block_q[511-int'(offset_q[5:0])*8 -: 8]<=next_byte;"
    assert baseline.count(old) == 1
    candidate = baseline.replace(old, '                    block_q<={block_q[503:0],next_byte};')
    top = reference.TOP
    old = "    wire [31:0] current_word=block_b[511-int'(off_b[5:2])*32 -:32];"
    assert top.count(old) == 1
    top = top.replace(old, '''    wire [1023:0] doubled_block={block_b,block_b};
    wire [1023:0] rotated_block=doubled_block<<{off_b[5:0],3'b0};
    wire [511:0] expected_block=rotated_block[1023:512];''')
    old = '''        if(state_a==1) begin
            if(off_a[1:0]==1) assert(packed_a[7:0]==current_word[31:24]);
            if(off_a[1:0]==2) assert(packed_a[15:0]==current_word[31:16]);
            if(off_a[1:0]==3) assert(packed_a[23:0]==current_word[31:8]);
        end'''
    assert top.count(old) == 1
    top = top.replace(old, '        if(state_a==1) assert(block_a==expected_block);')
    old = '''    generate for(genvar w=0;w<16;w=w+1) begin
        always @(posedge clk) if(past_valid && state_a==1 &&
            (off_a[1:0]==0 || off_a[5:2]!=w))
            assert(block_a[511-w*32 -:32]==block_b[511-w*32 -:32]);
    end endgenerate'''
    assert top.count(old) == 1
    top = top.replace(old, '')
    miter = reference.instrument(candidate, 'packing_candidate', False)+'\n'+reference.instrument(baseline, 'packing_reference', False)+'\n'+top
    (out/'baseline.sv').write_text(baseline)
    (out/'candidate.sv').write_text(candidate)
    (out/'miter.sv').write_text(miter)
    (out/'reference-helper.py').write_bytes((HERE/'verify_sha_wordpack.py').read_bytes())
    (out/'prove.ys').write_text(f'''read_verilog -formal -D SYNTHESIS -sv miter.sv
chparam -set SHARED {a.shared} -set LIMIT {a.limit} -set FAST_COVER {int(a.cover)} packing_miter
prep -top packing_miter -flatten
async2sync
dffunmap
memory_map
opt
dffunmap
opt_clean
write_smt2 -wires model.smt2
''')
    commands = [('prepare', ['yosys', '-Q', '-T', 'prove.ys'])]
    if a.cover:
        commands.append(('cover', ['yosys-smtbmc', '-s', 'z3', '--presat', '--noprogress', '-c', '-t', '66:68', '--dump-vcd', 'cover.vcd', 'model.smt2']))
    else:
        commands += [('base', ['yosys-smtbmc', '-s', 'cvc5', '--presat', '--noprogress', '-t', '4', '--dump-vcd', 'base.vcd', 'model.smt2']),
                     ('induction', ['yosys-smtbmc', '-s', 'cvc5', '--presat', '--noprogress', '-i', '-t', '4', '--dump-vcd', 'induction.vcd', 'model.smt2'])]
    records = {}
    for name, command in commands:
        start = time.monotonic()
        log = out/(name+'.log')
        with log.open('w') as stream:
            r = subprocess.run(command, cwd=out, stdout=stream, stderr=subprocess.STDOUT)
        raw = log.read_bytes()
        passed = r.returncode == 0 and (name == 'prepare' or b'Status: PASSED' in raw)
        records[name] = dict(command=command, exit_code=r.returncode, passed=passed,
                             elapsed_seconds=time.monotonic()-start, log_sha256=digest(raw))
        print(json.dumps(dict(stage=name, passed=passed, elapsed_seconds=records[name]['elapsed_seconds'])), flush=True)
        if not passed:
            break
    passed = len(records) == len(commands) and all(r['passed'] for r in records.values())
    result = dict(result='PASS' if passed else 'NOT_PROVEN', shared=a.shared, max_bytes=a.limit,
        cover_only=a.cover, records=records, baseline_sha256=digest(baseline.encode()),
        candidate_sha256=digest(candidate.encode()), miter_sha256=digest(miter.encode()),
        reference_helper_sha256=digest((out/'reference-helper.py').read_bytes()),
        recipe_sha256=digest((out/'prove.ys').read_bytes()), production_RTL_changed=False,
        scope='Compositional wrapper equivalence under common arbitrary compressor responses. Control, length/padding, chain and externally meaningful outputs agree; during fill, the shift buffer is an explicitly proved rotation of the indexed buffer. Complete512-bit blocks agree at every compressor launch. Intermediate shared block outputs need not agree. No SHA specification, mapped timing or whole-chip theorem.')
    (out/'RESULT.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(dict(result=result['result'], shared=a.shared, max_bytes=a.limit)), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == '__main__':
    main()
