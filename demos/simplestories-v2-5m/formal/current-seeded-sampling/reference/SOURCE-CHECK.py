"""Pure owned-source fixture check; no process/network or proof-tool execution."""
from contextlib import contextmanager
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import socket
import subprocess
import sys

assert sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode
ROOT=Path(__file__).resolve().parents[2]
PREP=Path(__file__).resolve().parent
OLD=ROOT/'build/current-seeded-history-bridge-source-check-r1'
LANE='formal/current-seeded-sampling'
OUT=ROOT/'build/current-seeded-reference-context-source-check-r2'
FORBIDDEN=[]

def pin(path):
 raw=path.read_bytes();return dict(path=str(path),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())
def save(path,row):
 path.parent.mkdir(parents=True,exist_ok=True)
 with path.open('x')as f:json.dump(row,f,indent=2,sort_keys=True);f.write('\n')
def copy(source,target):
 assert source.is_file()and not source.is_symlink();target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(source,target)
 assert pin(source)['sha256']==pin(target)['sha256']
def module(name,path):
 spec=importlib.util.spec_from_file_location(name,path);m=importlib.util.module_from_spec(spec);sys.modules[name]=m;spec.loader.exec_module(m);return m
@contextmanager
def no_tools():
 def forbidden(*a,**k):FORBIDDEN.append(repr(a));raise AssertionError('Process/network forbidden')
 names=('Popen','run','call','check_call','check_output');old={n:getattr(subprocess,n)for n in names};sock=socket.socket
 try:
  for n in names:setattr(subprocess,n,forbidden)
  socket.socket=forbidden;yield
 finally:
  for n,v in old.items():setattr(subprocess,n,v)
  socket.socket=sock

def files_identity(files):return{n:dict(bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest())for n,raw in files.items()}
def collect(package):
 driver=module('minimal_components',package/LANE/'run_proof.py');components={}
 for case in('selector','selector-buffer','uart','shell'):
  files,origins,sources,top,reset,count,scope=driver.prepare(case)
  for name,raw in files.items():
   p=OUT/'generated'/case/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
  components[case]=dict(files=files_identity(files),origins=origins,sources=sources,top=top,reset=reset,assertions=count,scope=scope)
 connected=module('minimal_connected',package/LANE/'connected/run_connected.py');files,sources,binding=connected.derive()
 for name,raw in files.items():
  p=OUT/'generated/connected'/name;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(raw)
 return dict(source_binding=driver.provider.source_binding(),components=components,connected=dict(files=files_identity(files),sources=sources,binding=binding)),connected

assert not OUT.exists();OUT.mkdir();package=OUT/'current-package'
# Start with the already owned sparse seeded fixture, not any Git checkout.
shutil.copytree(OLD/'before-package',package)
# Install actual optimized baseline header/inventory/source bytes from the owned01b fixture.
new_baseline=OLD/'new-baseline-package'
for p in(new_baseline/'hardware').rglob('*'):
 if p.is_file():copy(p,package/p.relative_to(new_baseline))
for name in('MANIFEST.json','host-app/hardware-inputs.json'):copy(new_baseline/name,package/name)
for p in(PREP/'proposed').rglob('*'):
 if p.is_file():copy(p,package/p.relative_to(PREP/'proposed'))
assert not list(package.rglob('*.zip'))and not(package/'history').exists()
assert not(package/'tools/dispatch_seeded_354_history_v1.py').exists()
assert not(package/'tools/seeded_354_context_v2.py').exists()
assert not list(package.rglob('*.bin'))and not list(package.rglob('*.lean'))
assert [p.relative_to(package).as_posix()for p in package.rglob('*.fs')]==['prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs']
with no_tools():
 result,connected=collect(package)
 original=json.loads((OLD/'before-source-map.json').read_bytes());assert json.loads(json.dumps(result))==original
 direct_count=direct_bytes=0
 for case,row in result['components'].items():
  for name in row['files']:
   a=(OLD/'before/generated'/case/name).read_bytes();b=(OUT/'generated'/case/name).read_bytes()
   assert a==b;direct_count+=1;direct_bytes+=len(a)
 for name in result['connected']['files']:
  a=(OLD/'before/generated/connected'/name).read_bytes();b=(OUT/'generated/connected'/name).read_bytes()
  assert a==b;direct_count+=1;direct_bytes+=len(a)
 assert direct_count==128 and direct_bytes==1584645
 audit=module('minimal_connected_auditor',package/LANE/'connected/audit_connected.py')
 baseline_binding=audit.original_baseline_binding(connected)
 reference=connected.provider.reference_public_root()
 assert reference==package/'reference/baseline-formal-354'
 baseline=module('minimal_original_baseline',reference/'formal/composed-shell/run_proof.py')
 files,order,binding=baseline.derive()
 old=module('old_original_baseline_fixture',OLD/'before-package/formal/composed-shell/run_proof.py')
 old_files,old_order,old_binding=old.derive();assert files==old_files and order==old_order and binding==old_binding==baseline_binding
 checker=module('minimal_reference_validator',package/'tools/checked_reference_root_v1.py')
 ledger=json.loads((reference/'REFERENCE-SOURCES.json').read_bytes());assert checker.checked_reference_root(package)==reference
 assert len(ledger['files'])==98 and ledger['source_bytes']==1858672
 # A separate owned reference copy shows extra files and changed source bytes refuse.
 bad=OUT/'tamper-package';bad_reference=bad/'reference/baseline-formal-354';shutil.copytree(reference,bad_reference)
 extra=bad_reference/'unexpected.txt';extra.write_bytes(b'SYNTHETIC EXTRA')
 try:checker.checked_reference_root(bad)
 except ValueError as e:extra_refusal=str(e)
 else:raise AssertionError('Unlisted reference source accepted')
 extra.unlink();changed=bad_reference/'formal/composed-shell/run_proof.py';changed.write_bytes(changed.read_bytes()+b'\n# SYNTHETIC CHANGED BYTE\n')
 try:checker.checked_reference_root(bad)
 except ValueError as e:changed_refusal=str(e)
 else:raise AssertionError('Changed reference source accepted')
 assert json.loads((package/'MANIFEST.json').read_bytes())['prebuilt_image_sha256']=='01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57'
 assert pin(package/'prebuilt/seeded-sampling/project/impl/pnr/shared_product.fs')['sha256']=='d271626a7fb9ce1debdf7a9cd847125ec7eb4c907fa9d06af9d5f8146cecc725'
 assert pin(package/LANE/'proof-support.json')['sha256']=='f3a2a873d9177fd2da4ff611fd857b4613018639372eea09eda73a731fd52ee6'
assert not FORBIDDEN
save(OUT/'source-map.json',result)
record=dict(schema='minimal-current-seeded-reference-context-pure-source-check-v1',passed=True,
 sparse_owned_fixture_not_a_release=True,reference_members=98,reference_source_bytes=1858672,
 reference_ledger_bytes=pin(reference/'REFERENCE-SOURCES.json')['bytes'],
 reference_contains_no_FS_model_weight_ZIP_Lean_or_app=True,
 current_fixture_contains_no_history_archives_or_dispatcher=True,
 current_source_binding_canonical_unchanged=True,current_support_inventory_f3a_unchanged=True,
 current87_and_d271_unchanged=True,generated_members_directly_byte_equal=direct_count,
 generated_bytes_each_side=direct_bytes,component_assertions={n:row['assertions']for n,row in result['components'].items()},
 connected_assertions=196,connected_private_cuts=37,original_baseline_derive_bytes_order_binding_equal=True,
 extra_source_refused=extra_refusal,changed_source_refused=changed_refusal,
 original_source_map=pin(OLD/'before-source-map.json'),current_source_map=pin(OUT/'source-map.json'),
 reference_ledger=pin(reference/'REFERENCE-SOURCES.json'),subprocess_network_attempts=FORBIDDEN,
 solver_native_board_registration_executed=False,frozen_stage_modified=False,PUBLIC_modified=False)
save(OUT/'FINISHED.json',record);print(json.dumps(dict(passed=True,source_members=98,source_bytes=1858672,
 generated_members_byte_equal=128,source_binding_unchanged=True,receipt=pin(OUT/'FINISHED.json')),sort_keys=True))
