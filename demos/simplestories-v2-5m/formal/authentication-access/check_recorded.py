"""Check current authentication/access evidence without FPGA or SMT tools.

Checks exact recorded bytes, native source/image joins, source-audit receipts
and original solver outcomes. It neither reruns the source auditors nor creates
a new solver theorem. Use replay.py for a separate fresh model/query check.
"""
import argparse
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path, PurePosixPath
import re

HERE=Path(__file__).resolve().parent
EXPECTED_INDEX_SHA256='bda24dffe773081a301ab51d273ab9d6be0393adb9cb401184f55197c01bdcda'


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


class Evidence:
    def __init__(self,model):
        self.model=Path(model).resolve();self.root=self.model/'evidence/authentication-access'
        raw=safe(self.root,'INDEX.json').read_bytes()
        need(sha(raw)==EXPECTED_INDEX_SHA256,'Authentication/access index changed')
        self.index=json.loads(raw)
        need(self.index['schema']=='current-simplestories-authentication-access-evidence-v1','Unknown evidence schema')
        need(len(self.index['files'])<30000 and len(self.index['component_audits'])==22,'Unexpected evidence census')
        need(self.index['raw_total_bytes']<15_000_000_000,'Unexpected decompression budget')
    def raw(self,name):
        row=self.index['files'][name];raw=gzip.decompress(safe(self.root,row['object']).read_bytes())
        need(len(raw)==row['bytes']and sha(raw)==row['sha256'],'Recorded byte identity differs')
        return raw
    def json(self,name):return json.loads(self.raw(name))
    def pin(self,name,row):
        need(name in self.index['files']and all(self.index['files'][name][k]==row[k]for k in('bytes','sha256')),
            'Frozen proof input differs: '+name)
    def check_objects(self):
        seen={};total=0
        for logical,row in self.index['files'].items():
            safe(self.root,logical);digest=row['sha256']
            need(re.fullmatch('[0-9a-f]{64}',digest)and row['object']=='objects/'+digest+'.gz','Noncanonical object')
            need(0<=row['bytes']<=512_000_000 and 0<row['compressed_bytes']<100_000_000,'Evidence size bound exceeded')
            need(not Path(logical).name.startswith('private-vendor-'),'Vendor source bytes must not be distributed')
            total+=row['bytes']
            if digest in seen:
                need(seen[digest]==row,'Inconsistent duplicate object metadata');continue
            compressed=safe(self.root,row['object']).read_bytes()
            need(len(compressed)==row['compressed_bytes']and sha(compressed)==row['compressed_sha256'],'Compressed evidence differs')
            length=0;h=hashlib.sha256()
            with gzip.GzipFile(fileobj=io.BytesIO(compressed),mode='rb')as z:
                while True:
                    chunk=z.read(min(1024*1024,row['bytes']-length+1))
                    if not chunk:break
                    length+=len(chunk);need(length<=row['bytes'],'Decompression exceeds declared size');h.update(chunk)
            need(length==row['bytes']and h.hexdigest()==digest,'Raw evidence differs')
            seen[digest]=row
        need(total==self.index['raw_total_bytes'],'Raw evidence total differs')
        return len(seen)


def check(model):
    evidence=Evidence(model);objects=evidence.check_objects();index=evidence.index
    for name,row in index['source_tools'].items():
        raw=safe(evidence.model/'formal/authentication-access/source-tools',name).read_bytes()
        need(dict(bytes=len(raw),sha256=sha(raw))==row,'Preserved source/audit tool differs')
    for name,row in index['component_audits'].items():
        evidence.pin(name,row);need(evidence.json(name)['passed']is True,'Incomplete source-audited component')
    common_path=evidence.model/'formal/implementation-assurance/run_handoff.py'
    spec=importlib.util.spec_from_file_location('_authentication_native_binding',common_path)
    common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
    for variant,wanted in index['native_joins'].items():
        need(common.binding(evidence.model,variant)[2]==wanted,'Current native source/image association differs')
    runs=0;phase_results=0;unresolved=0;partial_aggregates=0
    for directory in index['selected_directories']:
        prefix='runs/'+directory+'/'
        if prefix+'INPUTS.json'not in index['files']or prefix+'FINISHED.json'not in index['files']:continue
        inputs=evidence.json(prefix+'INPUTS.json');finished=evidence.json(prefix+'FINISHED.json');runs+=1
        if 'inputs_sha256'in finished:
            need(finished['inputs_sha256']==index['files'][prefix+'INPUTS.json']['sha256'],'Run input receipt differs')
        for name,row in inputs.get('files',{}).items():
            logical=prefix+name
            if logical in index['omitted_vendor_source_files']:
                need(all(index['omitted_vendor_source_files'][logical][k]==row[k]for k in('bytes','sha256')),
                    'Omitted licensed vendor source provenance differs')
            else:evidence.pin(logical,row)
        partial_aggregates+=finished.get('passed')is False
        for label,row in finished.get('results',{}).items():
            if not isinstance(row,dict)or 'log_sha256'not in row:continue
            log=evidence.raw(prefix+label+'.log');need(sha(log)==row['log_sha256'],'Real solver log differs')
            if row.get('query_sha256'):
                need(index['files'][prefix+label+'.smt2']['sha256']==row['query_sha256'],'Solver query differs')
            if row.get('solver_responses_sha256'):
                need(index['files'][prefix+label+'.responses']['sha256']==row['solver_responses_sha256'],'Solver replies differ')
            for name,digest in row.get('traces',{}).items():need(index['files'][prefix+name]['sha256']==digest,'Counterexample differs')
            phase_results+=1
            if row['passed']:
                expected='FAILED'if inputs.get('mutant')else'PASSED'
                need(re.findall(rb'Status: (\w+)',log)==[expected.encode()]and row['exit']==(1 if inputs.get('mutant')else 0),
                    'Recorded solver outcome differs')
                if label.endswith('induction'):
                    need(b'Temporal induction successful.'in log and'--smtc'not in row['command'],'Incomplete/restricted induction')
            else:unresolved+=1
        # Manual split/ordered campaigns retain exact real query and log pins.
        for label,row in finished.get('solver_results',{}).items():
            need(isinstance(row,dict),'Malformed manual solver result')
            if row.get('log_sha256'):
                logical=prefix+label+'.log'
                need(logical in index['files']and index['files'][logical]['sha256']==row['log_sha256'],'Manual solver log differs')
            if row.get('query_sha256'):
                need(any(name.startswith(prefix)and name.endswith('.smt2')and r['sha256']==row['query_sha256']for name,r in index['files'].items()),
                    'Manual solver query absent')
            phase_results+=1;unresolved+=not row.get('passed',False)
    return dict(passed=True,source_audited_components=22,current_native_images=4,objects_checked=objects,
        recorded_runs=runs,recorded_phase_results=phase_results,unresolved_results_preserved=unresolved,
        original_partial_aggregate_receipts_preserved=partial_aggregates,
        new_compiler_or_solver_execution=False,whole_machine_numerical_or_training_capacity_theorem=False)


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--model',type=Path,default=HERE.parents[1])
    args=p.parse_args();print(json.dumps(check(args.model),sort_keys=True))


if __name__=='__main__':main()
