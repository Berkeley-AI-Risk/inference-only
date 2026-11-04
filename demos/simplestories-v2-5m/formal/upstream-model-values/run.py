"""Check recorded proof or freshly compile native RTL and run every solver query.

The formal inputs are native SystemVerilog, SMT transition systems/properties
and the explicit contract graph. Python checks source identity and proof-DAG
closure and orchestrates engines; Python compilation is not verification.
"""
import argparse,difflib,gzip,hashlib,json,os,pathlib,re,shutil,subprocess,time,importlib.util
from concurrent.futures import ThreadPoolExecutor,as_completed
from threading import Lock
from functools import lru_cache
HERE=pathlib.Path(__file__).resolve().parent;MODEL=HERE.parent.parent


def sha(raw):return hashlib.sha256(raw).hexdigest()
def load(path):return json.loads(path.read_text())
def save(path,value):
 path=pathlib.Path(path);path.parent.mkdir(parents=True,exist_ok=True);tmp=path.with_name(path.name+'.partial');tmp.write_text(json.dumps(value,indent=2,sort_keys=True)+'\n');tmp.replace(path)
def modules(raw):return {m[1]:m[0]for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw,re.M)}
def member(name):
 p=(HERE/name).resolve()
 if not p.is_relative_to(HERE)or p.is_symlink():raise ValueError('Packet path escapes its scope')
 return p

def packet_check():
 packet=load(HERE/'PACKAGE.json')
 for name,want in packet['files'].items():
  p=member(name);raw=p.read_bytes()
  if dict(bytes=len(raw),sha256=sha(raw))!=want:raise ValueError('Packet member changed: '+name)
 for name,want in load(HERE/'SOURCE-PINS.json').items():
  p=(MODEL/name).resolve()
  if not p.is_relative_to(MODEL)or sha(p.read_bytes())!=want:raise ValueError('Production source changed: '+name)
 return packet


def reconstruct():
 spec=importlib.util.spec_from_file_location('_checked_native_observer_audit',member('observer_audit.py'));audit=importlib.util.module_from_spec(spec);spec.loader.exec_module(audit);readonly=audit.readonly
 doc=load(HERE/'SOURCE-RECIPES.json');answer={}
 if set(doc['order'])!=set(doc['models'])or len(doc['order'])!=len(doc['models']):raise ValueError('Incomplete source construction order')
 recipes={k:doc['models'][k]for k in doc['order']}
 for label,r in recipes.items():
  if r['kind']=='modules':
   original={};observed={};boundary={}
   for item in r['modules']:
    key=item['key'];native=modules((MODEL/item['source']).read_text())[item['module']];original[key]=native;observed[key]=native;boundary[key]=native
    for change in item['changes']:
     before,after=change['before'],change['after']
     if observed[key].count(before)!=1:raise ValueError('Exact source anchor changed: '+label+' '+key)
     observed[key]=observed[key].replace(before,after,1)
     if change['kind']=='boot-boundary':
      if label!='parent'or key!='parent':raise ValueError('Unexpected functional source boundary')
      if boundary[key].count(before)!=1:raise ValueError('Exact original boot boundary changed')
      boundary[key]=boundary[key].replace(before,after,1)
   for key in original:
    added=[]
    for op,a,b,c,d in difflib.SequenceMatcher(None,boundary[key],observed[key],autojunk=False).get_opcodes():
     if op=='insert':added.append(observed[key][c:d])
     elif op!='equal':raise ValueError('Observation replaced functional source: '+label+' '+key)
    readonly(''.join(added),boundary[key])
   source=r['prefix']+r['separator'].join(observed.values())+r['suffix']
  elif r['kind']=='fragments':
   source=r['template']
   for f in r['fragments']:
    raw=answer[f['model']]if'model'in f else(MODEL/f['source']).read_text()
    if raw.count(f['text'])!=1 or source.count(f['marker'])!=1:raise ValueError('Native source fragment changed: '+label)
    source=source.replace(f['marker'],f['text'],1)
  else:raise ValueError('Unknown source construction')
  if sha(source.encode())!=r['source_sha256']or source!=member('models/'+label+'/native.sv').read_text():raise ValueError('Native source did not reconstruct: '+label)
  answer[label]=source
 # Literal identity of the readonly core history and actual core event aliases.
 c=answer['model-cdc'];h=answer['core-history'];p=load(HERE/'CORE-HISTORY-PROJECTION.json')
 if c.count(p['block'])!=1 or h.count(p['block'])!=1:raise ValueError('Core history projection differs')
 for x in ['wire f_source=core_reset_n_i && core_req_valid_i && core_req_ready_o;','wire f_delivery=core_reset_n_i && core_delivery;']:
  if x not in c or x not in h:raise ValueError('Core history event differs')
 if 'assign core_rsp_valid_o=core_delivery;'not in c or 'wire core_delivery=core_rsp_valid_o;'not in h:raise ValueError('Core delivery alias differs')
 return recipes,answer


@lru_cache(maxsize=None)
def body(path):
 p=member(path);raw=p.read_bytes();return gzip.decompress(raw).decode()if p.suffix=='.gz'else raw.decode()
def query(node,nodes):
 facts=list(node['assumptions'])
 for dep in node['dependencies']:
  prior=nodes[dep]
  if prior['expected']!='unsat':raise ValueError('SAT control used as theorem')
  assumption='(and '+' '.join(prior['assumptions'])+')'if prior['assumptions']else'true';facts.append('(=> '+assumption+' '+prior['conclusion']+')')
 return ('(set-option :produce-models true)\n'+'\n'.join(body(p)for p in node['bodies'])+'\n'+'\n'.join(node['declarations'])+'\n'+'\n'.join('(assert '+f+')'for f in facts)+'\n(assert (not '+node['conclusion']+'))\n(check-sat)\n').encode()


def proof_check():
 proof=load(HERE/'PROOF.json');nodes=proof['nodes'];evidence=load(HERE/'RECORDED-RESULTS.json');seen=set()
 for identifier in proof['order']:
  n=nodes[identifier]
  if identifier in seen or not set(n['dependencies'])<=seen:raise ValueError('Cyclic, forward or absent proof dependency')
  raw=query(n,nodes);r=evidence['results'][identifier]
  if not r['passed']or r['exit_code']!=0 or r['answers']!=[n['expected']]or sha(raw)!=r['query_sha256']:raise ValueError('Exact engine argument/reply changed: '+identifier)
  log=member(r['log']).read_bytes()
  if sha(log)!=r['log_sha256']or re.findall(rb'^(sat|unsat|unknown|timeout)$',log,re.M)!=[n['expected'].encode()]:raise ValueError('Engine reply changed')
  seen.add(identifier)
 if seen!=set(nodes)or len(seen)!=evidence['engine_queries']:raise ValueError('Incomplete proof census')
 graph=load(HERE/'CONTRACTS.json');roles=set()
 if graph['root']!='cache-model-word'or graph['whole_machine_theorem']:raise ValueError('Unexpected theorem scope')
 if set(graph['external_boundaries'])!={'physical-vendor-storage-owner-and-end','trusted-model-image-at-runtime-entry','static-metadata-ROM-model-binding','digital-RTL-clock-reset-semantics'}:raise ValueError('Unexpected external premise')
 for role in graph['roles']:
  if role['id']in roles or not set(role['requires'])<=roles or not role['providers']:raise ValueError('Incomplete/circular contract argument')
  if any(i not in nodes or nodes[i]['expected']!='unsat'for i in role['providers']):raise ValueError('Missing native/logical proof of a contract')
  roles.add(role['id'])
 if len(roles)!=17 or graph['root']not in roles:raise ValueError('Incomplete contract graph')
 return proof,evidence


def operating(out):
 spec=load(HERE/'operating/FIXTURE.json');results={}
 for suite in spec['suites']:
  original={n:member(suite['files'][n]).read_bytes()for n in suite['files']}
  for case in suite['cases']:
   folder=out/suite['name']/case['name'];folder.mkdir(parents=True);files=dict(original)
   for c in case.get('changes',[]):
    a,b=c['before'].encode(),c['after'].encode()
    count=files[c['file']].count(a);all_occurrences=c.get('replace_all',False)and c['file']=='bench.sv'and a==b'__FAILED__'
    if count<1 or(count!=1 and not all_occurrences):raise ValueError('Actual defect/stimulus site changed')
    files[c['file']]=files[c['file']].replace(a,b)if all_occurrences else files[c['file']].replace(a,b,1)
   for name,raw in files.items():(folder/name).write_bytes(raw)
   with(folder/'compile.log').open('w')as log:cp=subprocess.run(['iverilog','-g2012','-DSYNTHESIS','-s',suite['top'],'-o','sim',*files],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=60)
   if cp.returncode:raise ValueError('Native operating fixture did not compile')
   with(folder/'simulation.log').open('w')as log:cp=subprocess.run(['vvp','sim'],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=90)
   raw=(folder/'simulation.log').read_bytes();text=raw.decode();passed=cp.returncode==case['exit']and any(x in text for x in case['tags'])
   r=dict(passed=passed,exit=cp.returncode,log_sha256=sha(raw));save(folder/'RESULT.json',r);results[suite['name']+'/'+case['name']]=r
   if not passed:raise ValueError('Native operating/actual-defect control failed: '+case['name'])
 save(out/'RESULT.json',dict(passed=True,finite_evidence=True,cases=results));return results


def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--recorded-only',action='store_true');ap.add_argument('--out',type=pathlib.Path);ap.add_argument('--workers',type=int,default=8);args=ap.parse_args()
 if not 1<=args.workers<=16:raise ValueError('Choose 1..16 four-GiB solver jobs')
 packet=packet_check();recipes,sources=reconstruct();proof,recorded=proof_check()
 if args.recorded_only:print(json.dumps(dict(passed=True,recorded_only=True,engine_queries=len(proof['order']),actual_source_reconstructed=True,whole_machine_theorem=False)));return 0
 if not args.out or args.out.exists():raise ValueError('Fresh replay requires a new --out directory')
 out=args.out.resolve();out.mkdir(parents=True);started=time.monotonic()
 for label,r in recipes.items():
  folder=out/'compile'/label;folder.mkdir(parents=True);(folder/'native.sv').write_text(sources[label]);shutil.copyfile(member('models/'+label+'/compile.ys'),folder/'compile.ys')
  for name,row in r.get('tables',{}).items():shutil.copyfile(MODEL/row['source'],folder/name)
  with(folder/'yosys.log').open('w')as log:cp=subprocess.run(['yosys','-Q','compile.ys'],cwd=folder,stdout=log,stderr=subprocess.STDOUT,timeout=120)
  if cp.returncode or sha((folder/'native.smt2').read_bytes())!=r['native_smt_sha256']:raise ValueError('Fresh native compilation differs: '+label+'; use the pinned Yosys version')
 print('Native sources reconstructed and recompiled; replaying',len(proof['order']),'exact queries.',flush=True)
 state=dict(status='running',active_owned_jobs=[],solver_seconds=0,package_sha256=sha((HERE/'PACKAGE.json').read_bytes()));save(out/'STATE.json',state);lock=Lock();results={}
 def run(identifier):
  n=proof['nodes'][identifier];folder=out/'queries'/identifier;folder.mkdir(parents=True);q=query(n,proof['nodes']);path=folder/'query.smt2';path.write_bytes(q);before=time.monotonic();cmd=['z3','-memory:4096','-T:300',str(path)]
  with(folder/'z3.log').open('w')as log:
   proc=subprocess.Popen(cmd,stdout=log,stderr=subprocess.STDOUT,start_new_session=True)
   with lock:state['active_owned_jobs'].append(dict(pid=proc.pid,query=identifier));save(out/'STATE.json',state)
   try:code=proc.wait(timeout=310)
   except subprocess.TimeoutExpired:proc.kill();proc.wait();code=124
  raw=(folder/'z3.log').read_bytes();answers=[x.decode()for x in re.findall(rb'^(sat|unsat|unknown|timeout)$',raw,re.M)];seconds=time.monotonic()-before;r=dict(passed=code==0 and answers==[n['expected']],answers=answers,exit_code=code,seconds=seconds,query_sha256=sha(q),log_sha256=sha(raw));save(folder/'RESULT.json',r)
  with lock:state['solver_seconds']+=seconds;state['active_owned_jobs']=[x for x in state['active_owned_jobs']if x['pid']!=proc.pid];save(out/'STATE.json',state)
  return identifier,r
 with ThreadPoolExecutor(max_workers=args.workers)as pool:
  for f in as_completed([pool.submit(run,i)for i in proof['order']]):
   i,r=f.result();results[i]=r
   if len(results)%128==0 or not r['passed']:print('replayed',len(results),'/',len(proof['order']),i,r['passed'],flush=True)
 passed=all(x['passed']for x in results.values())
 controls=operating(out/'operating')if passed else{}
 state.update(status='finished',passed=passed);save(out/'STATE.json',state)
 result=dict(passed=passed,recorded_only=False,engine_queries=len(results),expected_unsat=sum(n['expected']=='unsat'for n in proof['nodes'].values()),expected_sat=sum(n['expected']=='sat'for n in proof['nodes'].values()),sources_recompiled=True,operating_controls_rerun=bool(controls),solver_seconds=sum(x['seconds']for x in results.values()),elapsed_seconds=time.monotonic()-started,cache_service_upstream_contract_discharged=passed,whole_machine_theorem=False,results=results);save(out/'RESULT.json',result);print(json.dumps({k:v for k,v in result.items()if k!='results'},indent=2));return 0 if passed else 1


if __name__=='__main__':raise SystemExit(main())
