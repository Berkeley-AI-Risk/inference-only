"""Package frozen current proof evidence into deterministic gzip objects.

This creates an overlay under a new private output directory. The shared
public export, hardware, other agents' files and Git index are untouched.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import time

HERE=Path(__file__).resolve().parent
MODEL='demos/simplestories-v2-5m'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(value):return(json.dumps(value,indent=2,sort_keys=True)+'\n').encode()


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--selection',type=Path,required=True)
    ap.add_argument('--out',type=Path,required=True);args=ap.parse_args()
    selection=json.loads(args.selection.read_bytes())
    if not selection['passed']or len(selection['canonical_component_audits'])!=22:raise ValueError('Incomplete selection')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    formal=out/'overlay'/MODEL/'formal/authentication-access';formal.mkdir(parents=True)
    evidence=out/'overlay'/MODEL/'evidence/authentication-access';objects=evidence/'objects';objects.mkdir(parents=True)
    tools={}
    # These are preserved source builders/auditors. Public entry points are
    # the separate recorded-byte checker and frozen-query/model replay tool.
    for path in sorted(HERE.iterdir()):
        if path.is_file()and(path.suffix=='.py'or path.name.endswith('.inc.sv')):
            target=formal/'source-tools'/path.name;target.parent.mkdir(exist_ok=True)
            shutil.copyfile(path,target);tools[path.name]=dict(bytes=path.stat().st_size,sha256=sha(path.read_bytes()))
    inventory={};stored={};omitted={};started=time.monotonic()
    def compress(digest,raw):
        compressed=gzip.compress(raw,compresslevel=6,mtime=0)
        target=objects/(digest+'.gz');target.write_bytes(compressed)
        if len(compressed)>=100_000_000:raise ValueError('Oversized Git object')
        return dict(object='objects/'+target.name,compressed_bytes=len(compressed),compressed_sha256=sha(compressed))
    pool=ThreadPoolExecutor(max_workers=4)
    pending=[]
    def capture(path,logical=None):
        logical=logical or path.relative_to(HERE).as_posix()
        if path.is_symlink()or'..'in Path(logical).parts or Path(logical).is_absolute():raise ValueError('Unsafe evidence input')
        raw=path.read_bytes();digest=sha(raw)
        if path.name.startswith('private-vendor-'):
            omitted[logical]=dict(bytes=len(raw),sha256=digest,reason='Licensed vendor source; supply installed matching simlib for fresh elaboration.');return
        if digest not in stored:
            future=pool.submit(compress,digest,raw);stored[digest]=future;pending.append(future)
            # Bound retained uncompressed work to eight objects.
            if len(pending)>=8:pending.pop(0).result()
        inventory[logical]=dict(bytes=len(raw),sha256=digest)
    for name,wanted in selection['canonical_component_audits'].items():
        path=HERE/name;raw=path.read_bytes()
        if wanted!=dict(bytes=len(raw),sha256=sha(raw)):raise ValueError('Canonical source audit changed after selection')
        capture(path)
    for name in selection['selected_run_directories']:
        for path in sorted((HERE/'runs'/name).rglob('*')):
            if path.is_file():capture(path)
    for name in('CURRENT-ATTENTION-SOURCE-JOIN-r2.json','CURRENT-KV-PARENT-SOURCE-JOIN-r1.json',
            'current-kv-parent-plan-r1.json','encrypted-kv-parent-plan-r2.json'):
        capture(HERE/name)
    capture(HERE/'runs/current-control-source-query-audit-r1.json')
    capture(args.selection,'EVIDENCE-SELECTION.json')
    for folder in('encrypted-kv-history-r1','encrypted-kv-parent-source-r2'):
        for path in sorted((HERE/folder).rglob('*')):
            if path.is_file():capture(path)
    # Preserve the exact source-only current proof fixtures used by the two
    # attention scopes and protected joint cache model. They are evidence,
    # not another released design or an additional repository checkout.
    fixtures={
        'protected-cache':HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1',
        'protected-attention':HERE.parent/'build/protected-attention-proof-inputs-v5-coordinate',
        'baseline-attention':HERE.parent/'build/baseline-attention-proof-inputs-v1'}
    for role,root in fixtures.items():
        manifest=json.loads((root/'MANIFEST.json').read_bytes())
        for relative,wanted in manifest['files'].items():
            path=root/relative;raw=path.read_bytes()
            if wanted!=dict(bytes=len(raw),sha256=sha(raw)):raise ValueError('Source fixture changed: '+relative)
            capture(path,'source-fixtures/'+role+'/'+relative)
        capture(root/'MANIFEST.json','source-fixtures/'+role+'/MANIFEST.json')
    for future in pending:future.result()
    pool.shutdown()
    stored={digest:future.result()for digest,future in stored.items()}
    inventory={name:dict(row,**stored[row['sha256']])for name,row in inventory.items()}
    index=dict(schema='current-simplestories-authentication-access-evidence-v1',
        files=inventory,omitted_vendor_source_files=omitted,source_tools=tools,
        component_audits=selection['canonical_component_audits'],native_joins=selection['native_joins'],
        selected_directories=list(selection['selected_run_directories']),
        raw_total_bytes=sum(r['bytes']for r in inventory.values()),
        compressed_unique_bytes=sum(r['compressed_bytes']for r in stored.values()),
        hardware_changed=False,hardware_access=False,whole_machine_numerical_or_training_capacity_theorem=False,
        scope='Exact current RTL/source/audit/solver/query/response/counterexample bytes. Partial and unknown results retain their original receipts. Hash resistance, trusted on-chip state and vendor functional-model assumptions are explicit; mapped-bitstream and physical security are not certified.')
    (evidence/'INDEX.json').write_bytes(encode(index))
    result=dict(passed=True,files=len(inventory),objects=len(stored),omitted_vendor_files=len(omitted),
        selected_directories=len(selection['selected_run_directories']),raw_bytes=index['raw_total_bytes'],
        compressed_unique_bytes=index['compressed_unique_bytes'],index_sha256=sha((evidence/'INDEX.json').read_bytes()),seconds=time.monotonic()-started)
    (out/'ASSEMBLY.json').write_bytes(encode(result));print(json.dumps(result))


if __name__=='__main__':main()
