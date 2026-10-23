#!/usr/bin/env python3
"""Validate archived fresh numerical replay results and current source bindings.

Standard library only. No model computation, compiler, RTL, network or hardware
is invoked; run reference/seeded-sampling/run_reference.py for a fresh replay.
"""
import argparse
import ast
import hashlib
import json
import math
from pathlib import Path, PurePosixPath

ROOT=Path(__file__).resolve().parents[1]
RECORD='evidence/seeded-sampling/numerical-reference.json'
ARCHIVE_SHA='45b0fec3309f6fffa46a832109e35d26cafdc76cb63d88b3d88796640bf8774c'
SOURCE='reference/seeded-sampling/SOURCE.json'
SOURCE_SHA='bc5e2dce531cf10b05590dee483f9f561f5fd8b5bfa82f73022ef93952667897'
INDEX_SHAS={'goldens':'a66052169a9abc7f6a509413e798d4d61fd2bcb4beac06b1a7dc7d9987f0477b',
    'domain-goldens':'8e4a3bcc11a6626490f2b5d630b8347dde8e707f1b5ac3b4d041b9f0f6097ab1'}
RECEIPTS={'native_all48':('native',48,2136,'8f732bf78fe0e3fd0c01b7ba97b5a5954c9a0d52d624bc37285a751d97b48aeb'),
    'scalar_around128':('scalar',1,128,'77e6355f4e636677f1b4a646ea45c0d5e971e2629735312f7bdc87673f1d1e2e'),
    'native_seed_domain':('native',6,192,'5cc3640f9d4db46c0e8b1f1a293dda6c9a3cdc545cfb52b7dd17c8e60500ecda')}
SCOPE=('Fresh offline portable reference executions and exact public-image ROM reconstruction. '
    'Archived result validation; this evidence checker does not rerun the model. Host elapsed times '
    'are observations, not FPGA throughput or compiler-binary portability guarantees.')

def need(ok,message):
    if not ok:raise ValueError(message)
def fields(value,names):need(type(value)is dict and set(value)==set(names.split()),'Unexpected numerical evidence fields')
def sha(raw):return hashlib.sha256(raw).hexdigest()
def positive(value):need(type(value)in(int,float)and math.isfinite(value)and value>0,'Invalid replay elapsed time')
def regular(package,name):
    relative=PurePosixPath(name);need(not relative.is_absolute()and'..'not in relative.parts,'Unsafe reference path')
    path=package/name;need(path.is_file()and not path.is_symlink(),'Nonregular reference input');return path.read_bytes()

def validate(data,package=ROOT):
    package=Path(package);lane=package/'reference/seeded-sampling'
    fields(data,'schema passed scope source_inventory golden_indices reconstruction replays native_tests origin_closure_sha256 claims')
    need(data['schema']=='seeded-numerical-reference-validation-v1'and data['passed']is True and data['scope']==SCOPE,
         'Wrong numerical replay scope')
    need(data['source_inventory']==dict(path=SOURCE,sha256=SOURCE_SHA),'Numerical source inventory differs')
    source_raw=regular(package,SOURCE);need(sha(source_raw)==SOURCE_SHA,'Frozen portable source inventory changed')
    source=json.loads(source_raw)
    for name,digest in source['files'].items():
        need(sha(regular(package,'reference/seeded-sampling/'+name))==digest,'Portable numerical source changed: '+name)
    for name,digest in source['package_inputs'].items():
        need(sha(regular(package,name))==digest,'Portable numerical package input changed: '+name)
    expected_indices={};indices={}
    for name,cases,outputs in [('goldens',48,2136),('domain-goldens',6,192)]:
        path='reference/seeded-sampling/'+name+'/INDEX.json';raw=regular(package,path)
        need(sha(raw)==INDEX_SHAS[name],'Numerical golden index changed')
        indices[name]=json.loads(raw)
        expected_indices[name]=dict(path=path,sha256=INDEX_SHAS[name],cases=cases,outputs=outputs)
    need(data['golden_indices']==expected_indices,'Numerical fixture census differs')
    fields(data['replays'],'native_all48 scalar_around128 native_seed_domain')
    for name,(engine,count,outputs,digest)in RECEIPTS.items():
        replay=data['replays'][name]
        fields(replay,'source_receipt_sha256 engine cases outputs_compared elapsed_seconds source_inventory_sha256 hardware_access network_access rtl_executed')
        need(replay['source_receipt_sha256']==digest and replay['engine']==engine
            and replay['outputs_compared']==outputs and replay['source_inventory_sha256']==SOURCE_SHA,
            'Fresh replay origin/engine/output identity differs')
        need(all(replay[key]is False for key in('hardware_access','network_access','rtl_executed')),'Unsupported replay execution claim')
        positive(replay['elapsed_seconds'])
        index=indices['domain-goldens'if name=='native_seed_domain'else'goldens']
        names=['around128-t2-seed-a.json']if name=='scalar_around128'else sorted(index['files'])
        need(len(replay['cases'])==count and [r['case']for r in replay['cases']]==names,'Fresh replay case membership differs')
        total=0
        for row in replay['cases']:
            fields(row,'case outputs all_head_digests_match final_kv_matches final_prng_matches seconds')
            raw=regular(package,'reference/seeded-sampling/'+('domain-goldens'if name=='native_seed_domain'else'goldens')+'/'+row['case'])
            pin=index['files'][row['case']];need(pin==dict(bytes=len(raw),sha256=sha(raw)),'Golden payload bytes changed')
            golden=json.loads(raw)
            need(row['outputs']==golden['output_count']and all(row[key]is True for key in
                ('all_head_digests_match','final_kv_matches','final_prng_matches')),'Missing exact head/token/KV/PRNG replay result')
            positive(row['seconds']);total+=row['outputs']
        need(total==outputs,'Fresh replay token census differs')
    reconstruction=data['reconstruction']
    fields(reconstruction,'schema passed source_inventory_sha256 image_sha256 canonical_rom_manifest_sha256 files all_rom_files_equal full_image_roundtrip_equal hardware_access network_access source_receipt_sha256')
    receipt=json.loads(regular(package,'reference/evidence/q0-receipt.json'))['rom']['files']
    need(reconstruction['files']=={name:dict(bytes=size,sha256=digest)for name,(size,digest)in receipt.items()},
        'Reconstructed ROM byte identities differ')
    need(reconstruction['schema']=='portable-seeded-rom-reconstruction-v1'and reconstruction['passed']is True
        and reconstruction['source_inventory_sha256']==SOURCE_SHA
        and reconstruction['image_sha256']==source['model_image_sha256']
        and reconstruction['canonical_rom_manifest_sha256']==source['original_canonical_rom_manifest_sha256']
        and reconstruction['source_receipt_sha256']=='b5af773c14fab7102311aa700b28bb6aa3856825d9a28d2ed5a42876f541ad0e'
        and reconstruction['all_rom_files_equal']is True and reconstruction['full_image_roundtrip_equal']is True
        and reconstruction['hardware_access']is False and reconstruction['network_access']is False,
        'Wrong reconstructed ROM/image verification scope')
    tests=data['native_tests'];fields(tests,'passed methods method_count test_source_sha256 command')
    test_raw=regular(package,'reference/seeded-sampling/test_reference.py')
    methods=sorted(n.name for n in ast.walk(ast.parse(test_raw))if isinstance(n,ast.FunctionDef)and n.name.startswith('test_'))
    need(tests==dict(passed=True,methods=methods,method_count=8,test_source_sha256=sha(test_raw),
        command='python -I -B reference/seeded-sampling/test_reference.py --engine native'),'Native validation method/source census differs')
    need(data['origin_closure_sha256']=='2daa1a9afab55503fdaa87c18eea22c6729812863c4e2aba379cdf4a6e26220c','Changed original validation closure')
    need(data['claims']=={key:False for key in('hardware_access','network_access','rtl_executed','checker_replays_model',
        'physical_configuration_attested','timing_qualified','distribution_proof','compiler_binary_portability_promised')},
        'Unsupported numerical validation claim')
    return dict(passed=True,archived_native_reference_cases=48,archived_native_outputs=2136,
        archived_scalar_outputs=128,archived_additional_seed_outputs=192,canonical_rom_files_reconstructed=8,
        hardware_access=False,integer_model_replayed=False,compiler_invoked=False)

def check(package=ROOT):
    raw=regular(Path(package),RECORD);need(sha(raw)==ARCHIVE_SHA,'Frozen numerical replay archive changed')
    return validate(json.loads(raw),package)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--package',type=Path,default=ROOT)
    print(json.dumps(check(parser.parse_args().package),indent=2))
