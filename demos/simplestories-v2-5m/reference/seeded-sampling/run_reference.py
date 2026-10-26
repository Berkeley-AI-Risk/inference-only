#!/usr/bin/env python3
"""Replay all or selected fixed seeded model goldens, offline and without RTL."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import time

HERE=Path(__file__).resolve().parent
def module(name,path):
    spec=importlib.util.spec_from_file_location(name,path)
    value=importlib.util.module_from_spec(spec);sys.modules[name]=value;spec.loader.exec_module(value);return value
model=module('_portable_seeded_model',HERE/'model.py')

def read_goldens(domain=False):
    folder=HERE/('domain-goldens'if domain else'goldens')
    index=json.loads((folder/'INDEX.json').read_bytes());rows=[]
    model.require(index['cases']==(6 if domain else 48)and index['outputs']==(192 if domain else 2136),'Golden census differs')
    for name,pin in sorted(index['files'].items()):
        path=folder/name;raw=path.read_bytes()
        model.require(path.name==name and not path.is_symlink()and pin==dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest()),
                      'Golden inventory differs')
        data=json.loads(raw);data['_name']=name;rows.append(data)
    return rows

def verify_sources():
    source=json.loads((HERE/'SOURCE.json').read_bytes())
    for relative,pin in source['files'].items():
        path=HERE/relative
        model.require(path.is_file()and not path.is_symlink()and model.sha(path)==pin,'Portable reference source changed: '+relative)
    for relative,pin in source['package_inputs'].items():
        path=HERE.parents[1]/relative
        model.require(path.is_file()and not path.is_symlink()and model.sha(path)==pin,'Pinned package reference input changed: '+relative)
    return source

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--rom',type=Path,required=True,help='eight reconstructed canonical ROMs')
    parser.add_argument('--engine',choices=('scalar','native'),default='scalar')
    parser.add_argument('--build-dir',type=Path,help='native compiler output, outside source lane')
    parser.add_argument('--case',choices=('around128','prefix128','prefix512','prefix1024','prefix2047','prefix2048'))
    parser.add_argument('--temperature',choices=('0','0.5','1','2'))
    parser.add_argument('--seed',choices=('a','b'))
    parser.add_argument('--domain',action='store_true',help='six separate positive-temperature zero/all-ones seed fixtures')
    parser.add_argument('--output',type=Path,required=True,help='exclusive new replay result directory')
    args=parser.parse_args();source=verify_sources();goldens=read_goldens(args.domain)
    model.require(not args.domain or(args.case is None and args.seed is None),'--domain uses its own case and seed fixtures')
    if args.case:goldens=[g for g in goldens if g['case']==args.case]
    if args.temperature:goldens=[g for g in goldens if g['temperature']==args.temperature]
    if args.seed:goldens=[g for g in goldens if g['seed']==f'0x{getattr(model,"SEED_"+args.seed.upper()):032x}']
    model.require(goldens,'No selected golden');args.output.mkdir(parents=True,exist_ok=False)
    began=time.monotonic();loaded=model.load(args.rom,engine=args.engine,build_dir=args.build_dir)
    Model,sampler=loaded['Model'],loaded['sampler'];checkpoints={};matched=[]
    # For the exact nested prefix fixture, compute one shared prefill to the
    # longest selected prompt. This does not share generated-token trajectories.
    prefix=[g for g in goldens if g['case'].startswith('prefix')]
    if prefix:
        longest=max(prefix,key=lambda g:len(g['prompt_tokens']))['prompt_tokens']
        targets={len(g['prompt_tokens'])for g in prefix};oracle=Model(loaded['data'])
        for g in prefix:model.require(g['prompt_tokens']==longest[:len(g['prompt_tokens'])],'Prefix prompts are not nested')
        with(args.output/'progress.jsonl').open('x')as progress:
            for position,token in enumerate(longest,1):
                head=oracle.consume(token,position in targets)
                if position in targets:checkpoints[tuple(longest[:position])]=(oracle.fork(),head)
                if position%64==0 or position in targets:
                    row=dict(positions=position,elapsed_seconds=time.monotonic()-began)
                    progress.write(json.dumps(row)+'\n');progress.flush();print(json.dumps(row),flush=True)
    for golden in goldens:
        key=tuple(golden['prompt_tokens'])
        if key not in checkpoints:
            oracle=Model(loaded['data']);head=None
            for i,token in enumerate(key):head=oracle.consume(token,i+1==len(key))
            checkpoints[key]=(oracle,head)
        oracle,head=checkpoints[key];start=time.monotonic()
        actual=model.generate(oracle.fork(),head,sampler,('0','0.5','1','2').index(golden['temperature']),
                              int(golden['seed'],16),golden['output_count'])
        for field,value in actual.items():model.require(golden[field]==value,'Reference replay differs: '+golden['_name']+' / '+field)
        row=dict(case=golden['_name'],outputs=golden['output_count'],all_head_digests_match=True,
            final_kv_matches=True,final_prng_matches=True,seconds=time.monotonic()-start)
        matched.append(row);print(json.dumps(row),flush=True)
    model.require(verify_sources()==source,'Reference sources changed during replay')
    result=dict(schema='portable-seeded-reference-replay-v1',passed=True,engine=args.engine,
        cases=matched,outputs_compared=sum(r['outputs']for r in matched),
        source_inventory_sha256=model.sha(HERE/'SOURCE.json'),elapsed_seconds=time.monotonic()-began,
        hardware_access=False,network_access=False,rtl_executed=False)
    with(args.output/'FINISHED.json').open('x')as stream:json.dump(result,stream,indent=2);stream.write('\n')
    print(json.dumps({k:v for k,v in result.items()if k!='cases'}),flush=True)

if __name__=='__main__':main()
