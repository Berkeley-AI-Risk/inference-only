"""Freeze selected session evidence and prepare a current-main source-only overlay."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import time

HERE=Path(__file__).resolve().parent
MODEL='demos/simplestories-v2-5m'
ROOTS='''PROGRESS.json PROOF-INSTANTIATION-BINDINGS.json HIERARCHY-BINDINGS.json
MEMORY-BINDINGS.json OPAQUE-STATE-AUDIT.json NATIVE-STORE-ROSTER.json
ATTENTION-CONTRACT-JOIN.json SEMANTIC-PERMISSION-JOIN.json SEMANTIC-RESULT-JOIN.json
PROJECTION-CONTRACT-JOIN.json CLUSTER-CONTRACT-JOIN.json SHELL-CONTRACT-JOIN.json
SAMPLER-CONTRACT-JOIN.json ENCODING-REPLAY.json SOURCE-INVENTORY.json
COMPONENT-SOURCE-CLASSES.json MUTABLE-ARRAY-CENSUS.json'''.split()
AUDITS='''core-model-drain-audit-r3 core-model-drain-seeded-audit-r3
kv-session-drain-source-join-r2 kv-staging-cache-write-source-join-r4
connected-kv-drain-source-join-r2 connected-drain-join-r3 model-drain-join-r4
kv-staging-full-sim-r2 assembled-cluster-parallel-r2-audit-r3
assembled-cluster-serial-r3-audit-r2'''.split()


def sha(raw):return hashlib.sha256(raw).hexdigest()
def encode(value):return(json.dumps(value,indent=2,sort_keys=True)+'\n').encode()
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--work',type=Path,required=True)
    ap.add_argument('--parent',required=True);ap.add_argument('--tree',required=True);args=ap.parse_args()
    work=args.work.resolve();work.mkdir(parents=True,exist_ok=False);begin=time.monotonic()
    export=HERE.parents[1]/'fpga-demo/public-release'
    gp=load('_session_git',HERE.parent/'layout-migration/prepare_git.py')
    basis_rows=gp.files(export)
    if gp.tree_sha(basis_rows)!=args.tree:raise ValueError('Declared export is not the actual current remote tree')
    for folder in ('basis','package'):
        dest=work/folder;dest.mkdir()
        for name in basis_rows:
            p=dest/name;p.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(export/name,p)
    (work/'BASIS.json').write_bytes(encode(dict(commit=args.parent,tree=args.tree,
        manifest_sha256=sha((export/'MANIFEST.json').read_bytes()),manifest_files=len(basis_rows)-1)))
    progress=load('_session_progress',HERE/'record_progress.py')
    records={n:progress.audit(n,k)for n,k in progress.CASES.items()}
    mutants={n:progress.audit(n,'Actual RTL corruption sensitivity')for n in progress.MUTANTS}
    if len(records)!=82 or len(mutants)!=13 or any(r['status']!='proved_component'for r in list(records.values())+list(mutants.values())):
        raise ValueError('Selected completion ledger is incomplete')
    available={p.name for p in(HERE/'runs').iterdir()if p.is_dir()}
    selected=set(records)|set(mutants)|set(progress.PARTITIONS.values())|{Path(p).parts[1]for p in progress.CERTIFICATES.values()}|set(AUDITS)
    roots=set(ROOTS);external={}
    public_model=(export/MODEL).resolve()
    def visit(value):
        if isinstance(value,dict):
            for k,v in value.items():visit(k);visit(v)
        elif isinstance(value,list):
            for v in value:visit(v)
        elif isinstance(value,str):
            if '/runs/'in value or value.startswith('runs/'):
                selected.update(part for part in value.split('/')if part in available)
            p=Path(value)
            if p.is_absolute()and p.is_file():
                if p.parent==HERE and p.suffix=='.json':roots.add(p.name)
                elif HERE not in p.parents and public_model in p.parents:
                    external[str(p)]=p.relative_to(public_model).as_posix()
    inspected=set();inspected_roots=set()
    while selected-inspected or roots-inspected_roots:
        for name in sorted(roots-inspected_roots):visit(json.loads((HERE/name).read_bytes()));inspected_roots.add(name)
        for name in sorted(selected-inspected):
            if name not in available:raise ValueError('Missing selected run')
            for p in(HERE/'runs'/name).glob('*.json'):
                try:visit(json.loads(p.read_bytes()))
                except UnicodeError:pass
            inspected.add(name)
    evidence=work/'package'/MODEL/'evidence/session-isolation';objects=evidence/'objects';objects.mkdir(parents=True)
    formal=work/'package'/MODEL/'formal/session-isolation';tools=formal/'source-tools';tools.mkdir(parents=True)
    source_tools={}
    for p in sorted(HERE.iterdir()):
        if p.is_file()and(p.suffix=='.py'or p.name.endswith('.inc.sv')):
            raw=p.read_bytes();(tools/p.name).write_bytes(raw);source_tools[p.name]=dict(bytes=len(raw),sha256=sha(raw))
    inventory={};stored={};pending=[]
    def compress(digest,raw):
        packed=gzip.compress(raw,compresslevel=6,mtime=0)
        if len(packed)>=100_000_000:raise ValueError('Oversized Git evidence object')
        p=objects/(digest+'.gz');p.write_bytes(packed)
        return dict(object='objects/'+p.name,compressed_bytes=len(packed),compressed_sha256=sha(packed))
    with ThreadPoolExecutor(max_workers=2)as pool:
        def capture(path,logical):
            if path.is_symlink()or Path(logical).is_absolute()or'..'in Path(logical).parts:raise ValueError('Unsafe evidence member')
            raw=path.read_bytes();digest=sha(raw)
            if len(raw)>128_000_000:raise ValueError('Evidence member exceeds reviewed size budget')
            if digest not in stored:
                f=pool.submit(compress,digest,raw);stored[digest]=f;pending.append(f)
                if len(pending)>=4:pending.pop(0).result()
            inventory[logical]=dict(bytes=len(raw),sha256=digest)
        for name in sorted(roots):capture(HERE/name,name)
        for name in sorted(selected):
            for p in sorted((HERE/'runs'/name).rglob('*')):
                if p.is_file()and'__pycache__'not in p.parts and p.name!='sim':capture(p,p.relative_to(HERE).as_posix())
        for f in pending:f.result()
    stored={h:f.result()for h,f in stored.items()}
    inventory={n:dict(row,**stored[row['sha256']])for n,row in inventory.items()}
    binder=load('_session_binding',HERE.parent/'formal-assurance/run_handoff.py')
    joins={v:binder.binding(work/'basis',v)[2]for v in ('baseline','seeded-sampling','kv-protected','encrypted-memory')}
    index=dict(schema='current-simplestories-session-isolation-evidence-v1',files=inventory,
        source_tools=source_tools,selected_directories=sorted(selected),selected_components=records,
        selected_sensitivity=mutants,partitions=progress.PARTITIONS,certificates=progress.CERTIFICATES,
        recorded_workspace=str(HERE),recorded_public_model=str(public_model),external_public_paths=external,
        source_audits=[name+'/FINISHED.json'for name in AUDITS],native_joins=joins,
        raw_total_bytes=sum(r['bytes']for r in inventory.values()),
        compressed_unique_bytes=sum(r['compressed_bytes']for r in stored.values()),
        whole_device_session_theorem=False,physical_RAM_erasure_proved=False,hardware_changed=False,
        scope='Current native RAM/parent correspondence and accepted-work CLEAR/drain component facts, their exact sources, queries, replies, source audits and semantic controls. Numerical/service seams, initial tracking conditions and vendor premises remain explicit. No full-device token-output/session-isolation or mapped-image theorem.')
    raw=encode(index);(evidence/'INDEX.json').write_bytes(raw)
    for original,public in external.items():
        if not(work/'basis'/MODEL/public).is_file():raise ValueError('External source binding absent from current public basis')
    (work/'ASSEMBLY.json').write_bytes(encode(dict(passed=True,selected_runs=len(selected),files=len(inventory),objects=len(stored),
        raw_bytes=index['raw_total_bytes'],compressed_bytes=index['compressed_unique_bytes'],
        index_sha256=sha(raw),seconds=time.monotonic()-begin)))
    print(json.dumps(dict(passed=True,selected_runs=len(selected),files=len(inventory),objects=len(stored),
        raw_GB=round(index['raw_total_bytes']/1e9,3),compressed_MB=round(index['compressed_unique_bytes']/1e6,1),index_sha256=sha(raw))),flush=True)


if __name__=='__main__':main()
