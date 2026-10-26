#!/usr/bin/env python3
"""Standard-library inventory and fixture check; does not replay the integer model."""
import hashlib
import json
from pathlib import Path, PurePosixPath
import re

HERE=Path(__file__).resolve().parent
PACKAGE=HERE.parents[1]
def require(ok,message):
    if not ok:raise ValueError(message)
def sha(raw):return hashlib.sha256(raw).hexdigest()
def read(path):return json.loads(path.read_bytes())

def check():
    source=read(HERE/'SOURCE.json')
    for name,digest in source['files'].items():
        relative=PurePosixPath(name)
        require(not relative.is_absolute()and'..'not in relative.parts,'Unsafe source inventory path')
        target=HERE/name
        require(target.is_file()and not target.is_symlink()and sha(target.read_bytes())==digest,'Portable source differs: '+name)
    for name,digest in source['package_inputs'].items():
        relative=PurePosixPath(name);require(not relative.is_absolute()and'..'not in relative.parts,'Unsafe package input path')
        target=PACKAGE/name
        require(target.is_file()and not target.is_symlink()and sha(target.read_bytes())==digest,'Reference package input differs: '+name)
    total=0
    for folder,cases,outputs in [('goldens',48,2136),('domain-goldens',6,192)]:
        index=read(HERE/folder/'INDEX.json');require(index['cases']==cases and index['outputs']==outputs,'Fixture census differs')
        require(set(index['files'])=={p.name for p in(HERE/folder).glob('*.json')if p.name!='INDEX.json'},'Fixture file census differs')
        observed=0
        for name,pin in index['files'].items():
            raw=(HERE/folder/name).read_bytes();require(pin==dict(bytes=len(raw),sha256=sha(raw)),'Golden bytes differ')
            data=json.loads(raw);count=data['output_count'];length=len(data['prompt_tokens'])
            require(type(count)is int and count>0 and count==len(data['generated_tokens'])and length>0,
                    'Golden dimensions differ')
            require(data['evaluated_positions']==length+count-1<=2048
                and data['maximum_occupied_tape']==length+count<=2049,'Golden context geometry differs')
            require(data['stop_at_eos']is False and data['temperature']in('0','0.5','1','2')
                and re.fullmatch('0x[0-9a-f]{32}',data['seed']),'Golden settings differ')
            require(all(type(t)is int and 0<=t<4019 for t in data['prompt_tokens']+data['generated_tokens']),
                    'Token outside fixed vocabulary')
            require(len(data['head_rows_sha256'])==count and all(re.fullmatch('[0-9a-f]{64}',d)for d in
                data['head_rows_sha256']+[data['final_kv_sha256'],data['source_reference_receipt_sha256']]),'Golden digest fields differ')
            require(len(data['final_prng_state'])==2 and all(re.fullmatch('0x[0-9a-f]{16}',d)for d in data['final_prng_state']),
                    'Golden PRNG state differs')
            require(data['model_image_sha256']==source['model_image_sha256'],'Golden model identity differs')
            observed+=count
        require(observed==outputs and len(index['files'])==cases,'Golden output census differs');total+=observed
    return dict(passed=True,reference_cases=48,additional_seed_domain_cases=6,total_reference_outputs=total,
        hardware_access=False,integer_model_replayed=False)

if __name__=='__main__':print(json.dumps(check(),indent=2))
