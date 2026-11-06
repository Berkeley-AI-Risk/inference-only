"""Reconstruct the timing-disclosure summary from immutable recorded evidence.

Runs no implementation tool, solver or hardware. Endpoint classes are separate
checks; the vendor global 'setup' union also includes recovery endpoints.
"""
import argparse,gzip,hashlib,json
from pathlib import Path
SS=Path(__file__).resolve().parents[1]
def sha(b):return hashlib.sha256(b).hexdigest()
def read(p):return json.loads(p.read_text())
def pin(p):
 b=p.read_bytes();return dict(path=p.relative_to(SS).as_posix(),bytes=len(b),sha256=sha(b))
def stored(capsule,logical):
 row=capsule['bindings'][logical];p=SS/row['portable']['path'];raw=p.read_bytes()
 if len(raw)!=row['portable']['bytes'] or sha(raw)!=row['portable']['sha256']:raise ValueError('Changed compressed evidence')
 value=gzip.decompress(raw)
 if len(value)!=row['original']['bytes'] or sha(value)!=row['original']['sha256']:raise ValueError('Changed original evidence')
 return json.loads(value),pin(p)
def build():
 result={}
 for variant,folder in [('baseline','inference'),('kv-protected','kv-protected'),('encrypted-memory','encrypted-memory')]:
  path=SS/'evidence/current-greedy'/f'{variant}-CAPSULE.json';capsule=read(path);receipt,_=stored(capsule,capsule['roles']['build']);build=read(SS/'prebuilt'/folder/'BUILD.json')
  if receipt['image_sha256']!=build['image_sha256'] or receipt['timing_qualified'] is not False:raise ValueError('Selected native build association changed')
  wanted=receipt['native_timing_inspection_sha256'];matches=[k for k,v in capsule['bindings'].items() if v['original']['sha256']==wanted]
  if len(matches)!=1:raise ValueError('Ambiguous timing inspection')
  audit,obj=stored(capsule,matches[0]);c=audit['complete_endpoint_census']
  if not c['endpoint_census_complete'] or audit['image_sha256']!=build['image_sha256']:raise ValueError('Incomplete or wrong-image timing census')
  checks={k:dict(negative_endpoints=v['negative_endpoints'],negative_paths=v['negative_paths'],worst_slack_ns=v['worst_slack_ns'],clock_families=v['families']) for k,v in c['tables'].items()}
  result[variant]=dict(image_sha256=build['image_sha256'],evidence_capsule=pin(path),timing_inspection_object=obj,timing_inspection_sha256=wanted,checks=checks,global_violated_endpoints=c['global_violated_endpoints'],reported_nonvendor_negative_paths=len(c['nonvendor_negative_paths']),reported_nonvendor_screen_clear=c['nonvendor_screen_clear'],timing_qualified=False,complete_timing_signoff=audit['complete_timing_signoff'],captured_action_flags={k:capsule[k] for k in ['phase','release_qualified','semantic_closure_replay_pending','final_release_index']})
 p=SS/'evidence/seeded-sampling/current-native-summary-v8-baseline-selected-native.json';s=read(p);b=read(SS/'prebuilt/seeded-sampling/BUILD.json')
 if s['image_sha256']!=b['image_sha256'] or s['source_audit']['sha256']!=b['native_timing_inspection_sha256'] or not s['endpoint_census_complete'] or b['timing_qualified'] is not False:raise ValueError('Seeded native binding changed')
 checks={}
 for k,v in s['negative_endpoint_tables'].items():
  paths=v['negative_paths'];checks[k]=dict(negative_endpoints=v['negative_endpoint_count'],negative_paths=v['negative_path_count'],worst_negative_slack_ns=min([p['slack_ns'] for p in paths],default=None),all_listed_negative_paths_vendor_ddr=all(p['vendor_ddr'] for p in paths))
 result['seeded-sampling']=dict(image_sha256=b['image_sha256'],native_summary=pin(p),source_timing_report=s['source_timing_report'],checks=checks,global_violated_endpoints=s['global_violated_endpoints'],reported_nonvendor_screen_clear=s['nonvendor_screen_clear'],timing_qualified=False,complete_timing_signoff=s['complete_timing_signoff'])
 return dict(schema='SimpleStories-recorded-timing-disclosure-v1',scope='Recorded selected-image endpoint census; no new native build, timing closure, hardware execution or physical attestation.',variants=result,global_setup_note='The global setup union includes setup/recovery endpoints. Do not add the per-check endpoint counts as disjoint physical endpoints.')
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--write',action='store_true');a=p.parse_args();out=SS/'evidence/timing-disclosure.json';result=build()
 if a.write:
  tmp=out.with_suffix('.tmp');tmp.write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');tmp.replace(out)
 elif read(out)!=result:raise ValueError('Timing disclosure differs from its recorded sources')
 print(json.dumps(dict(passed=True,images=len(result['variants']),new_timing_run=False,new_hardware_execution=False)))
if __name__=='__main__':main()
