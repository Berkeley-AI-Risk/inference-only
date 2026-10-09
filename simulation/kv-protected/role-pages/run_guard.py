#!/usr/bin/env python3
"""Drive real guard RTL with independent model-derived data and digests."""
import argparse
import hashlib
import json
from pathlib import Path
import random
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parent
RTL = ROOT.parents[2] / 'variants/kv-protected/hardware/project'
SHA = RTL / 'sha.sv'
sys.path.insert(0, str(ROOT))
from model import Guard, Memory, IntegrityFault, address, BASE_PATH
sys.path.insert(0, str(ROOT.parent))
from test_kv_integrity_model import payload
KV_BASE = 227072


def program(full_geometry=False):
    words, cases = [], []
    guard, memory = Guard(), Memory()

    def command(op, layer=0, position=0, head=0, word=0, data=None, fault=False, bad_shadow=False):
        descriptor = op << 252 | layer | position << 3 | head << 15 | word << 17 | int(fault) << 21 | int(bad_shadow) << 22
        words.append(f'{descriptor:064x}')
        if data is not None:
            words.append(f'{int.from_bytes(data, "little"):064x}')

    def reset(label):
        nonlocal guard, memory
        guard, memory = Guard(), Memory()
        command(0)
        cases.append(label)

    def put(layer, position, salt=0):
        data = payload(layer, position, salt)
        guard.populate(memory, layer, position, data)
        for i in range(18):
            command(1, layer, position, i // 9, i % 9, data[i * 32:(i + 1) * 32])
        for head in range(2):
            for role in range(2):
                command(6, layer, position, head, role, data=guard.tags[layer, position // 16, head, role][::-1])

    def read(layer, position, head=0, word=0):
        fault = False
        try:
            data = guard.read_word(memory, layer, position, head, word)
        except IntegrityFault:
            data, fault = bytes(32), True
        command(2, layer, position, head, word, data, fault=fault)

    def flip(layer, position, head, word, bit):
        off = (address(layer, position, head, word) - KV_BASE) * 32
        memory.data[off + bit // 8] ^= 1 << (bit % 8)
        command(4, layer, position, head, word, (1 << bit).to_bytes(32, 'little'))

    reset('all layers, partial/full pages, exact bytes and digests')
    for layer in range(6):
        for position in range(17):
            put(layer, position)
            read(layer, position, 0, 0)
            read(layer, position, 1, 8)
        for position in range(17):
            for head in range(2):
                for word in range(9):
                    read(layer, position, head, word)
    reset('CLEAR and new prefix reject old memory')
    put(0, 0)
    command(3);guard.clear()
    read(0, 0)
    reset('changed generation with old bytes replayed')
    put(0, 0)
    old = bytes(memory.data[:576])
    command(3);guard.clear()
    put(0, 0, 777)
    for i in range(18):
        memory.data[i*32:(i+1)*32] = old[i*32:(i+1)*32]
        command(5, 0, 0, i//9, i%9, old[i*32:(i+1)*32])
    read(0, 0)
    reset('altered old DDR must not be blessed by an append')
    put(0, 0)
    flip(0, 0, 0, 0, 91)
    put(0, 1)
    read(0, 0)
    reset('verified cache remains sealed after external change')
    put(0, 0);read(0, 0)
    flip(0, 0, 0, 0, 3)
    read(0, 0)  # returns correct sealed original, not newly changed DDR.
    put(0, 1);read(0, 0)  # append invalidates cache; changed bytes now fail.
    for index in range(18):
        reset(f'corruption in each row word {index}')
        put(0, 0)
        flip(0, 0, index//9, index%9, (index*17)%256)
        read(0, 0, index//9, 4 if 4 <= index%9 < 8 else 0)
    reset('cross-layer page substitution')
    put(0, 0);put(1, 0)
    for i in range(18):
        data=memory.data[(address(1,0,i//9,i%9)-KV_BASE)*32:][:32]
        memory.data[i*32:(i+1)*32]=data
        command(5,0,0,i//9,i%9,data)
    read(0,0)
    reset('cross-page substitution')
    for p in range(17): put(0,p)
    for i in range(18):
        data=memory.data[(address(0,16,i//9,i%9)-KV_BASE)*32:][:32]
        memory.data[i*32:(i+1)*32]=data
        command(5,0,0,i//9,i%9,data)
    read(0,0)
    reset('bad shadow read is rejected')
    put(0, 0)
    command(2, 0, 0, data=bytes(32), fault=True, bad_shadow=True)
    reset('bad shadow write is rejected')
    command(1, 0, 0, data=bytes(32), fault=True, bad_shadow=True)
    reset('skipped initial population word is rejected')
    command(1, 0, 0, word=1, data=bytes(32), fault=True)
    if full_geometry:
        reset('all 2048 positions in all six layers, no injected prefixes or tags')
        boundaries={0,1,14,15,16,17,1023,1024,2031,2032,2047}
        for position in range(2048):
            for layer in range(6):
                put(layer,position)
                if position in boundaries:
                    read(layer,position,0,0);read(layer,position,1,8)
        for layer in range(6):
            for position in (0,1023,2047):
                read(layer,position,0,0);read(layer,position,1,8)
        command(1,0,2048,data=bytes(32),fault=True)
    return words, cases


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--out', type=Path, required=True)
    parser.add_argument('--synthesis', action='store_true')
    parser.add_argument('--full-geometry',action='store_true')
    parser.add_argument('--verilator',action='store_true')
    parser.add_argument('--guard-source',type=Path,help='Separate private guard; copied into the test snapshot.')
    parser.add_argument('--hash-source',type=Path,help='Separate private hash; copied into the test snapshot.')
    parser.add_argument('--mutant',choices=('accept-bad-digest','ignore-cache-role','publish-first-tag'))
    args = parser.parse_args()
    # Keep generated snapshots outside the release. GNU Make requires
    # a space-free output path when the Verilator engine is selected.
    if args.verilator and not args.synthesis: parser.error('--verilator requires --synthesis; four-state tests use Icarus')
    out = args.out.absolute()
    package = ROOT.parents[2].resolve()
    if out.resolve().is_relative_to(package):
        parser.error('--out must be a fresh directory outside the release')
    out.mkdir(parents=True, exist_ok=False)
    words, cases = program(args.full_geometry)
    (out / 'program.memh').write_text('\n'.join(words) + '\n')
    (out / 'cases.json').write_text(json.dumps(cases, indent=2) + '\n')
    hash_source=ROOT/args.hash_source if args.hash_source else RTL/'kv_page_hash.sv'
    guard_source=ROOT/args.guard_source if args.guard_source else RTL/'kv_integrity_guard.sv'
    if guard_source.name!='kv_integrity_guard.sv': parser.error('Guard variant must retain its module filename')
    if hash_source.name!='kv_page_hash.sv': parser.error('Private variant must retain the kv_page_hash.sv filename')
    inputs = [Path(__file__), ROOT / 'model.py', BASE_PATH, ROOT.parent / 'test_kv_integrity_model.py',
              guard_source, ROOT / 'guard_tb.sv', hash_source, SHA]
    hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (out / 'inputs').mkdir()
    for i,p in enumerate(inputs):
        (out / 'inputs' / f'{i}-{p.name}').write_bytes(p.read_bytes())
    sources=[ROOT/'guard_tb.sv',guard_source,hash_source,SHA]
    # Compile local snapshots so the long run cannot pick up later edits.
    for path in sources: (out/path.name).write_bytes(path.read_bytes())
    if args.mutant:
        path=out/'kv_integrity_guard.sv'
        text=path.read_text()
        before,after={
            'accept-bad-digest':('else if(hash_digest==expected_q)',"else if(1'b1)"),
            'ignore-cache-role':('wire cache_hit=cache_identity && cache_role_q==read_role;',
                                 'wire cache_hit=cache_identity;'),
            'publish-first-tag':('if(group_head_q && role_q)',"if(1'b1)")}[args.mutant]
        if text.count(before)!=1: raise ValueError('Nonunique mutation seam')
        path.write_text(text.replace(before,after))
    staged={p.name:hashlib.sha256((out/p.name).read_bytes()).hexdigest() for p in sources}
    (out/'INPUTS.json').write_text(json.dumps(dict(original=hashes,staged=staged,mutant=args.mutant),indent=2)+'\n')
    commands = [
        ['iverilog','-g2012'] + (['-DSYNTHESIS'] if args.synthesis else []) +
        ['-Pguard_tb.PROGRAM_WORDS='+str(len(words)),'-s','guard_tb','-o',str(out/'guard.vvp')]+[p.name for p in sources],
        ['vvp',str(out/'guard.vvp'),'+program='+str(out/'program.memh'),
         '+entries='+str(len(words)),'+metrics='+str(out/'cycles.csv')]
    ]
    if args.verilator:
        commands[0]=['verilator','--binary','--timing','--build-jobs','8',
            '-MAKEFLAGS','CURDIR='+str(out/'obj')+' OPT_FAST=-O3 OPT_SLOW=-O3',
            '-DSYNTHESIS','-Wno-fatal','-Wno-WIDTHTRUNC','-Wno-WIDTHEXPAND',
            '-Wno-TIMESCALEMOD','-Wno-INITIALDLY','--top-module','guard_tb',
            '-GPROGRAM_WORDS='+str(len(words)),'--Mdir',str(out/'obj')]+[p.name for p in sources]
        commands[1]=[str(out/'obj/Vguard_tb')]+commands[1][2:]
    start=time.monotonic();records=[]
    for i,argv in enumerate(commands):
        run=subprocess.run(argv,cwd=out,text=True,capture_output=True,timeout=1800)
        (out/f'{i}.stdout.log').write_text(run.stdout);(out/f'{i}.stderr.log').write_text(run.stderr)
        records.append(dict(argv=argv,returncode=run.returncode))
        print(run.stdout,end='',flush=True)
        compile_problem=(i==0 and (('%Warning' in run.stderr) if args.verilator else bool(run.stderr.strip())))
        if run.returncode or compile_problem:
            expected_failure=(i==1 and args.mutant and run.returncode and
                any(marker in run.stdout for marker in ('Read mismatch','Trusted digest mismatch')))
            if expected_failure:
                result=dict(passed=True,mutant=args.mutant,mutant_rejected=True,hardware_access=False,
                    commands=records,source_sha256=hashes,scope='Deliberately broken guard rejected by the real RTL testbench.')
                assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
                assert staged=={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in staged}
                (out/'FINISHED.json').write_text(json.dumps(result,indent=2)+'\n')
                print('GUARD_MUTANT_REJECTED '+args.mutant,flush=True)
                return
            print(run.stderr,flush=True)
            (out/'FAILED.json').write_text(json.dumps(records,indent=2)+'\n')
            raise SystemExit(1)
    if 'GUARD_ALL_PASS' not in run.stdout:
        raise RuntimeError('Missing final success marker')
    if args.mutant: raise ValueError('Bad guard unexpectedly passed')
    assert hashes=={str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    assert staged=={name:hashlib.sha256((out/name).read_bytes()).hexdigest() for name in staged}
    result=dict(passed=True,hardware_access=False,seconds=time.monotonic()-start,
                source_sha256=hashes,commands=records,cases=cases,synthesis_macro=args.synthesis,
                full_geometry=args.full_geometry,engine='verilator' if args.verilator else 'iverilog',
                whole_model_tested=False,scope='Private RTL guard with model-derived data/tags, fault and CLEAR simulation.')
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k not in ('source_sha256','commands','cases')},indent=2))


if __name__=='__main__':
    main()
