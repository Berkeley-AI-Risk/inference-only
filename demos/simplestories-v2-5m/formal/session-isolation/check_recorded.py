"""Portable recorded-byte/query checker; no compiler, solver or FPGA execution."""
import argparse
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import re
import sys
from types import SimpleNamespace

HERE=Path(__file__).resolve().parent
EXPECTED_INDEX_SHA256='23caf4bbd70db6d01a3e3b1b01dde166f7ae270afb61588db283dcfbcd3458c3'


def sha(raw):return hashlib.sha256(raw).hexdigest()
def need(condition,message):
    if not condition:raise ValueError(message)
def safe(root,name):
    p=PurePosixPath(name)
    need(p.parts and not p.is_absolute()and'..'not in p.parts and'\\'not in name,'Unsafe evidence path')
    target=root
    for part in p.parts:
        target=target/part;need(not target.is_symlink(),'Symlink evidence member')
    return target
def load(name,path):
    spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m);return m


class Evidence:
    def __init__(self,model):
        self.model=Path(model).resolve();self.root=self.model/'evidence/session-isolation'
        raw=safe(self.root,'INDEX.json').read_bytes()
        need(sha(raw)==EXPECTED_INDEX_SHA256,'Session evidence index changed')
        self.index=json.loads(raw)
        need(self.index['schema']=='current-simplestories-session-isolation-evidence-v1','Unknown evidence schema')
        need(len(self.index['files'])<30000 and self.index['raw_total_bytes']<6_000_000_000,'Evidence size budget exceeded')
        need(len(self.index['selected_components'])==82 and len(self.index['selected_sensitivity'])==13,'Selected scope census changed')
        need(self.index['whole_device_session_theorem']is False,'Unqualified whole-device claim')
    def raw(self,name):
        row=self.index['files'][name];compressed=safe(self.root,row['object']).read_bytes()
        need(len(compressed)==row['compressed_bytes']and sha(compressed)==row['compressed_sha256'],'Compressed member changed')
        with gzip.GzipFile(fileobj=io.BytesIO(compressed),mode='rb')as z:
            raw=z.read(row['bytes']+1);need(not z.read(1),'Member exceeds declared decompression size')
        need(len(raw)==row['bytes']and sha(raw)==row['sha256'],'Recorded member changed')
        return raw
    def json(self,name):return json.loads(self.raw(name))
    def objects(self):
        seen={};total=0
        for name,row in self.index['files'].items():
            safe(self.root,name);digest=row['sha256'];total+=row['bytes']
            need(re.fullmatch('[0-9a-f]{64}',digest)and row['object']=='objects/'+digest+'.gz','Noncanonical object')
            need(0<=row['bytes']<=128_000_000 and 0<row['compressed_bytes']<100_000_000,'Member size budget exceeded')
            need(not Path(name).name.startswith('private-vendor-'),'Licensed vendor source must not be distributed')
            if digest in seen:need(seen[digest]==row,'Inconsistent duplicate object');continue
            self.raw(name);seen[digest]=row
        need(total==self.index['raw_total_bytes'],'Raw evidence total differs')
        return len(seen)


def virtual_path(evidence):
    origin=PurePosixPath(evidence.index['recorded_workspace'])
    public=PurePosixPath(evidence.index['recorded_public_model'])
    class RecordedPath:
        def __init__(self,value):self.p=value.p if isinstance(value,RecordedPath)else PurePosixPath(str(value))
        def __truediv__(self,value):return RecordedPath(self.p/str(value))
        def __str__(self):return str(self.p)
        def __hash__(self):return hash(self.p)
        def __eq__(self,other):return isinstance(other,RecordedPath)and self.p==other.p
        @property
        def parent(self):return RecordedPath(self.p.parent)
        @property
        def parents(self):return tuple(RecordedPath(p)for p in self.p.parents)
        @property
        def name(self):return self.p.name
        def resolve(self):return self
        def with_name(self,name):return RecordedPath(self.p.with_name(name))
        def _logical(self):
            need('..'not in self.p.parts,'Noncanonical recorded path')
            if self.p==origin:return ''
            if origin in self.p.parents:return self.p.relative_to(origin).as_posix()
            return None
        def read_bytes(self):
            logical=self._logical()
            if logical is not None:return evidence.raw(logical)
            need(str(self.p)in evidence.index['external_public_paths']and public in self.p.parents,'Unmapped external recorded path')
            return safe(evidence.model,evidence.index['external_public_paths'][str(self.p)]).read_bytes()
        def read_text(self):return self.read_bytes().decode()
        def is_file(self):return self._logical()in evidence.index['files']or str(self.p)in evidence.index['external_public_paths']
        def stat(self):return SimpleNamespace(st_size=len(self.read_bytes()))
    return RecordedPath


def check(model):
    e=Evidence(model);objects=e.objects();index=e.index;tools=HERE/'source-tools'
    for name,row in index['source_tools'].items():
        raw=safe(tools,name).read_bytes();need(dict(bytes=len(raw),sha256=sha(raw))==row,'Source/audit tool changed')
    helper=load('_session_query_templates',tools/'join_parent_conclusions.py')
    # audit() imports this pure query reconstruction module by its original
    # name. Loading is explicit and does not add a directory to sys.path.
    old=sys.modules.get('join_parent_conclusions');sys.modules['join_parent_conclusions']=helper
    try:
        ledger=load('_session_recorded_ledger',tools/'record_progress.py')
        path=virtual_path(e);ledger.Path=path;ledger.HERE=path(index['recorded_workspace'])
        need(set(ledger.CASES)==set(index['selected_components'])and set(ledger.MUTANTS)==set(index['selected_sensitivity']),
            'Selected proof inventory differs from preserved ledger')
        for name,scope in ledger.CASES.items():
            need(ledger.audit(name,scope)==index['selected_components'][name],'Recorded component qualification differs: '+name)
        for name in ledger.MUTANTS:
            # The public index uses the same label passed during packaging.
            need(ledger.audit(name,'Actual RTL corruption sensitivity')==index['selected_sensitivity'][name],
                'Recorded mutation qualification differs: '+name)
    finally:
        if old is None:sys.modules.pop('join_parent_conclusions',None)
        else:sys.modules['join_parent_conclusions']=old
    binder=load('_session_native_binding',e.model/'formal/implementation-assurance/run_handoff.py')
    for variant,expected in index['native_joins'].items():
        need(binder.binding(e.model,variant)[2]==expected,'Current native source/image binding differs')
    source_audits=0
    for relative in index['source_audits']:
        record=e.json('runs/'+relative)
        for filename,digest in record.get('artifact_manifest',{}).items():
            need(sha(path(filename).read_bytes())==digest,'Recorded source-audit input changed')
        if 'passed'in record:need(record['passed']is True,'Selected source audit or simulation incomplete')
        source_audits+=1
    # Check original solver outcomes, rather than accepting copied pass flags.
    phases=0;unknowns=0
    for name in index['selected_directories']:
        prefix='runs/'+name+'/'
        if prefix+'INPUTS.json'not in index['files']or prefix+'FINISHED.json'not in index['files']:continue
        inp=e.json(prefix+'INPUTS.json');fin=e.json(prefix+'FINISHED.json')
        for label,row in fin.get('results',{}).items():
            if not isinstance(row,dict)or 'log_sha256'not in row:continue
            log=e.raw(prefix+label+'.log');need(sha(log)==row['log_sha256'],'Solver log changed')
            if row['passed']:
                mutant=bool(inp.get('mutant'));expected=b'FAILED'if mutant else b'PASSED'
                need(re.findall(rb'Status: (\w+)',log)==[expected]and row['exit']==(1 if mutant else 0),'Recorded solver outcome differs')
                if label.endswith('induction'):
                    need(b'Temporal induction successful.'in log and'--smtc'not in row['command'],'Incomplete or constrained induction')
            else:unknowns+=1
            phases+=1
    roster=e.json('NATIVE-STORE-ROSTER.json')
    need(roster['memory_specific_signoff']is False and roster['whole_device_memory_signoff']is False,'Memory roster promoted to signoff')
    return dict(passed=True,selected_components=82,detected_sensitivity_cases=13,current_native_images=4,
        objects_checked=objects,source_audits=source_audits,original_solver_phases_checked=phases,
        incomplete_phases_preserved=unknowns,new_compiler_or_solver_execution=False,
        whole_device_session_theorem=False,hardware_access=False)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--model',type=Path,default=HERE.parents[1])
    args=p.parse_args();print(json.dumps(check(args.model),sort_keys=True))


if __name__=='__main__':main()
