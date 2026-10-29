"""Standalone replay of the normal guard-word capsule (Python standard library).

Reads only the supplied capsule and a fresh output directory. Original absolute
paths in receipts are annotations resolved through the capsule index. Requires
Yosys, Z3, Icarus Verilog and vvp on PATH. Earlier imported proof records are
verified as supplied evidence; this run freshly solves the 27 new queries.
"""
import argparse,gzip,hashlib,json,posixpath,re,subprocess,time
from pathlib import Path,PurePosixPath


def sha(raw):return hashlib.sha256(raw).hexdigest()
def need(ok,msg):
    if not ok:raise ValueError(msg)


class Packet:
    def __init__(self,root):
        self.root=Path(root).resolve();self.index=json.loads((self.root/'INDEX.json').read_bytes())
        self.files=self.index['files'];self.original=self.index['recorded_workspace'].rstrip('/')
        need(self.index['schema']=='closed-native-guard-returned-word-local-capsule-v3','Known capsule schema required')
    def name(self,path,owner=None):
        path=str(path)
        if path.startswith('/'):
            need(path.startswith(self.original+'/'),'External original path refused');path=path[len(self.original)+1:]
        elif owner is not None:path=posixpath.normpath(posixpath.join(posixpath.dirname(owner),path))
        need(not PurePosixPath(path).is_absolute()and'..'not in PurePosixPath(path).parts,'Unsafe capsule path')
        need(path in self.files,'Missing capsule member: '+path);return path
    def raw(self,path):
        name=self.name(path);row=self.files[name];member=PurePosixPath(row['object'])
        need(not member.is_absolute()and'..'not in member.parts and member.parts[0]=='objects','Unsafe object')
        packed=(self.root/str(member)).read_bytes()
        need(len(packed)==row['compressed_bytes']and sha(packed)==row['compressed_sha256'],'Changed compressed object')
        raw=gzip.decompress(packed);need(len(raw)==row['bytes']and sha(raw)==row['sha256'],'Changed raw evidence');return raw
    def json(self,path):return json.loads(self.raw(path))
    def extract(self,name,dest):
        dest=Path(dest);dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(self.raw(name))


def point_queries(e):
    top='siv_bridge_row_data';d=e.json('runs/siv-guard-accepted-plaintext-r1/FINISHED.json')
    run=e.name(d['source_run']+'/design.smt2');model=e.raw(run).decode();ctx=d['source_context']
    imports=ctx['global_source_assertions'];need(len(imports)==408 and len(set(imports))==408,'All 408 proved prerequisites required')
    lines=model.splitlines();start=next(i for i,line in enumerate(lines)if line.startswith('(declare-datatype '));fields=[];depth=0
    for line in lines[start:]:
        clean=line.split(';',1)[0].strip();depth+=clean.count('(')-clean.count(')')
        m=re.fullmatch(r'\((\|[^|]+\|) (.+)\)',clean)
        if m:fields.append((m[1],m[2]))
        if depth==0:break
    need(fields and fields[0]==('|'+top+'_is|','Bool'),'Complete native state constructor required')
    p='(set-logic ALL)\n'+model+'\n';args=[]
    for j,(name,sort)in enumerate(fields):
        if name=='|'+top+'_is|':args.append('false')
        else:
            symbol=f'row_state_0_field_{j}';p+=f'(declare-fun {symbol} () {sort})\n';args.append(symbol)
    p+=f'(define-fun s0 () |{top}_s| (|{top}_mk| '+' '.join(args)+'))\n'
    p+=f'(assert ({top}_h s0))\n(assert ({top}_u s0))\n'
    p+=''.join(f'(assert (|{top}_a {j}| s0))\n'for j in imports)
    root=lambda n:f'(|{top}_n {n}| s0)';g=lambda n:root('u_guard.'+n);b=lambda n:root('u_bridge.'+n)
    p+='(assert (and (bvult '+b('layer_q')+' (_ bv6 3)) (bvult '+b('position_q')+' (_ bv2048 12)) (bvult '+b('head_q')+' (_ bv2 2))))\n'
    p+='(assert (or (not '+root('reset_n')+') (= (= '+b('u_codec.state_q')+' (_ bv19 5)) '+b('u_codec.fault_q')+')))\n'
    rel='((_ extract 3 0) '+g('f_prefix_target_position')+')'
    base='(bvadd (concat #b0 '+rel+' #b00) (concat #b000 '+rel+'))';off='(bvsub '+g('f_stage_point_slot')+' '+base+')'
    word='(ite (= '+off+' (_ bv4 7)) (_ bv8 4) (concat #b0 (ite '+g('f_stage_role')+' #b1 #b0) ((_ extract 1 0) '+off+')))'
    total='(bvadd (concat '+g('f_stage_positions')+' #b00) (concat #b00 '+g('f_stage_positions')+'))'
    match=('(and '+g('f_stage_record_valid')+' '+g('f_prefix_row_valid')+' (= '+g('f_stage_layer')+' '+g('f_prefix_target_layer')+')'+
        ' (= '+g('f_stage_page')+' ((_ extract 10 4) '+g('f_prefix_target_position')+')) (= '+g('f_stage_head')+' '+g('f_prefix_target_head')+')'+
        ' (bvuge '+g('f_stage_point_slot')+' '+base+') (bvult '+g('f_stage_point_slot')+' (bvadd '+base+' (_ bv5 7))) (bvult '+g('f_stage_point_slot')+' '+total+'))')
    shift='(concat (_ bv0 248) '+g('f_stage_point_chunk')+' #b00000)';memory=f'(|{top}_m u_bridge.f_row_record_plain| s0)'
    plain='((_ extract 31 0) (bvlshr (select '+memory+' '+word+') '+shift+'))'
    capture='(=> (and '+root('reset_n')+' '+g('live')+' (= '+g('state_q')+' (_ bv7 5)) '+g('f_entry_target_match')+') (= '+g('word_q')+' (select '+memory+' '+g('m_rd_word')+')))'
    helper='(=> (and '+root('reset_n')+' (= '+g('owner_q')+' (_ bv1 2))) (not '+g('f_stage_record_valid')+'))'
    inv='(=> (and '+root('reset_n')+' '+g('f_stage_owned')+' '+match+') (= '+g('f_stage_value')+' '+plain+'))'
    for theorem in(capture,helper,inv):p+='(assert '+theorem+')\n'
    active=p+'(assert '+root('reset_n')+')\n(assert '+g('live')+')\n(assert '+g('s_rd_rsp_valid')+')\n'
    selected=(active+'(assert (= '+g('f_prefix_target_layer')+' '+g('f_request_layer')+'))\n'+
        '(assert (= '+g('f_prefix_target_position')+' '+g('f_request_position')+'))\n'+
        '(assert (= (concat #b0 (ite '+g('f_prefix_target_head')+' #b1 #b0)) '+g('f_request_head')+'))\n'+
        '(assert (= '+g('f_stage_point_slot')+' '+g('target_slot_q')+'))\n')
    actual='((_ extract 31 0) (bvlshr '+g('s_rd_rsp_data')+' '+shift+'))'
    expected='((_ extract 31 0) (bvlshr (select '+memory+' '+g('f_request_word')+') '+shift+'))'
    qs={'actual-accepted-normal-return-consistent':active,'actual-current-request-row-and-stage-point-consistent':selected,
        'actual-busy-inputs-can-differ-from-accepted-request':selected+'(assert (distinct '+g('s_rd_word')+' '+g('f_request_word')+'))\n',
        'accepted-current-return-establishes-owned-matching-stage':selected+'(assert (not (and '+g('f_stage_owned')+' '+match+')))\n',
        'accepted-current-return-selects-exact-request-word':selected+'(assert (distinct '+word+' '+g('f_request_word')+'))\n',
        'actual-response-chunk-is-accepted-request-current-plaintext':selected+'(assert (distinct '+actual+' '+expected+'))\n'}
    for k in range(8):
        case=selected+'(assert (= '+g('f_stage_point_chunk')+' (_ bv'+str(k)+' 3)))\n'
        qs[f'accepted-response-chunk-{k}-nonempty']=case
        qs[f'accepted-response-chunk-{k}-value']=case+'(assert (distinct ((_ extract '+str(32*k+31)+' '+str(32*k)+') '+g('s_rd_rsp_data')+') ((_ extract '+str(32*k+31)+' '+str(32*k)+') (select '+memory+' '+g('f_request_word')+'))))\n'
    suffix='(check-sat-using (then simplify propagate-values solve-eqs simplify smt))\n(exit)\n'
    return{n:(body+suffix).encode()for n,body in qs.items()}


def rule(mode):
    q='(set-logic QF_BV)\n(declare-fun actual () (_ BitVec 256))\n(declare-fun expected () (_ BitVec 256))\n(declare-fun target_slot () (_ BitVec 7))\n'
    for k in range(8):
        q+=f'(define-fun point_{k} () (_ BitVec 10) (concat target_slot (_ bv{k} 3)))\n'
        for n in('actual','expected'):q+=f'(declare-fun {n}_{k} () (_ BitVec 256))\n'
        if mode!='omit-actual-independence':q+=f'(assert (= actual_{k} actual))\n'
        if mode!='omit-expected-independence':q+=f'(assert (= expected_{k} expected))\n'
        if mode!='omit-final-chunk'or k!=7:q+=f'(assert (= ((_ extract {32*k+31} {32*k}) actual_{k}) ((_ extract {32*k+31} {32*k}) expected_{k})))\n'
    return(q+'(assert (distinct actual '+('(_ bv0 256)'if mode=='nonempty'else'expected')+'))\n(check-sat)\n(exit)\n').encode()


def execute(command,cwd,log,timeout):
    with(log).open('w')as stream:
        try:return subprocess.run(command,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT,timeout=timeout).returncode
        except subprocess.TimeoutExpired:return None


def admit_replay(index,report,script_digest):
    need(report['schema']=='standalone-native-guard-return-word-replay-v1'and report['passed'],'Completed recorded replay required')
    need(report['replay_script_sha256']==script_digest,'Replay entrypoint changed')
    need(report['exact_source_graph_replayed']and report['portable_component_replay_complete'],'Source and component replay required')
    need(not report['whole_device_session_theorem']and not report['original_workspace_files_opened'],'Component/portable scope required')
    need(not report['all_imported_antecedent_solver_queries_freshly_replayed'],'Do not promote selected replay to all imported proofs')
    wanted={(r['query'],r['decoded_query_sha256'],r['expected'])for r in index['replay_queries']}
    got={(r['query'],r['decoded_query_sha256'],r['answer'])for r in report['independently_reconstructed_and_freshly_solved_queries']if r['passed']}
    need(len(wanted)==27 and wanted==got and len(report['independently_reconstructed_and_freshly_solved_queries'])==27,'All 27 exact source/rule query replays required')
    need(report['native_replays']==[{'scope':'native_positive','passed':True,'exit':0},
        {'scope':'native_corruption','passed':True,'exit':1},{'scope':'native_normal_word_corruption','passed':True,'exit':1}],'All native positive and corruption replays required')


def recorded(packet):
    e=Packet(packet);report=json.loads((e.root/'REPLAY.json').read_bytes())
    need(report['index_sha256']==sha((e.root/'INDEX.json').read_bytes()),'Replay index changed')
    admit_replay(e.index,report,sha(Path(__file__).read_bytes()))
    seen=set();manifests=0
    for name,row in e.files.items():
        if row['sha256']not in seen:e.raw(name);seen.add(row['sha256'])
        if not name.endswith('.json'):continue
        try:d=e.json(name)
        except(ValueError,UnicodeDecodeError):continue
        if not isinstance(d,dict)or'artifact_manifest'not in d:continue
        manifests+=1
        for path,digest in d['artifact_manifest'].items():need(e.files[e.name(path,name)]['sha256']==digest,'Nested manifest differs')
    points=point_queries(e)
    for row in e.index['replay_queries']:
        raw=e.raw(row['query']);raw=gzip.decompress(raw)if row['query_gzip']else raw
        name=PurePosixPath(row['query']).name.removesuffix('.gz').removesuffix('.smt2')
        expected=points[name]if'/siv-guard-accepted-plaintext-r1/'in row['query']else rule(name)
        need(raw==expected and sha(raw)==row['decoded_query_sha256'],'Recorded query reconstruction differs')
        need(e.raw(row['recorded_reply'])==(row['expected']+'\n').encode(),'Recorded reply differs')
    need(manifests==report['closed_manifests']and len(seen)==report['unique_objects'],'Recorded closure counts differ')
    return dict(passed=True,recorded_only=True,unique_objects=len(seen),closed_manifests=manifests,
        independently_reconstructed_queries=27,solver_executed=False,whole_device_session_theorem=False)


def replay(packet,out):
    e=Packet(packet);out=Path(out).resolve();out.mkdir(parents=True,exist_ok=False);begin=time.monotonic();seen=set();manifests=0
    for name,row in e.files.items():
        if row['sha256']not in seen:e.raw(name);seen.add(row['sha256'])
        if name.endswith('.json'):
            try:d=e.json(name)
            except(ValueError,UnicodeDecodeError):continue
            if not isinstance(d,dict)or'artifact_manifest'not in d:continue
            manifests+=1
            for path,digest in d['artifact_manifest'].items():need(e.files[e.name(path,name)]['sha256']==digest,'Nested manifest conflict')
    print('objects and closed manifests verified',len(seen),manifests,flush=True)
    expected_points=point_queries(e);plan=e.index['replay_plan'];root=plan['graph_source_run'];graph=out/'graph';graph.mkdir()
    inp=e.json(root+'/INPUTS.json')
    for name in inp['compile_sources']+['prove.ys']:
        need('/'not in name and'\\'not in name,'Flat graph source expected');e.extract(root+'/'+name,graph/name)
    ys=(graph/'prove.ys').read_text();need(not re.search(r'(?m)^\s*(?:exec|shell|script|plugin|tcl)\b',ys),'Unsafe Yosys script')
    code=execute(['yosys','-Q','prove.ys'],graph,graph/'replay.log',60);need(code==0,'Yosys replay failed')
    for name in plan['graph_targets']:
        reference=root+'/'+name
        if reference not in e.files:
            audit='runs/siv-guard-request-history-native-audit-r1'
            need(e.json(audit+'/FINISHED.json')['source_run']==e.original+'/'+root,'Graph audit source differs')
            reference=audit+'/source-replay/'+name
        need((graph/name).read_bytes()==e.raw(reference),'Source graph replay differs: '+name)
    print('source graph/IL/SMT exact replay passed',flush=True)
    queries=out/'queries';queries.mkdir();outcomes=[]
    for i,row in enumerate(e.index['replay_queries']):
        need(not(out/'STOP_REQUESTED').exists(),'Cooperative replay stop requested')
        raw=e.raw(row['query']);raw=gzip.decompress(raw)if row['query_gzip']else raw
        need(sha(raw)==row['decoded_query_sha256'],'Query digest differs')
        name=PurePosixPath(row['query']).name.removesuffix('.gz').removesuffix('.smt2')
        expected=expected_points[name]if'/siv-guard-accepted-plaintext-r1/'in row['query']else rule(name)
        need(raw==expected,'Independent point/rule query reconstruction differs: '+name)
        path=queries/(str(i)+'.smt2');path.write_bytes(raw);log=queries/(str(i)+'.log')
        code=execute(['z3','-memory:1024','-T:25','-smt2',path.name],queries,log,30)
        need(code==0 and log.read_bytes()==(row['expected']+'\n').encode(),'Fresh solver failure: '+name)
        outcomes.append(dict(query=row['query'],passed=True,answer=row['expected'],decoded_query_sha256=sha(raw)))
        print('solver',i+1,name,row['expected'],flush=True)
    need(len(outcomes)==27,'All 27 new queries required')
    natives=[]
    for key in('native_positive','native_corruption','native_normal_word_corruption'):
        run=plan[key];d=e.json(run+'/FINISHED.json');dest=out/key;dest.mkdir();command=d['compile_command']
        need(command[:7]==['iverilog','-g2012','-DSYNTHESIS','-s','native_guard_tb','-o','native.vvp'],'Known native build command required')
        for name in command[7:]:
            need('/'not in name and name.endswith('.sv'),'Flat native sources required');e.extract(run+'/'+name,dest/name)
        need(execute(command,dest,dest/'compile.log',60)==0,'Native compile failed')
        result=execute(['vvp','native.vvp'],dest,dest/'simulation.log',60)
        need(result==d['simulation_exit'],'Native outcome differs')
        need((dest/'trace.tsv').read_bytes()==e.raw(run+'/trace.tsv'),'Native cycle/value trace differs')
        log=(dest/'simulation.log').read_text()
        if key=='native_positive':need(result==0 and'normal_reads=72 canceled=1 hits=56 misses=17 DDR_writes=80 DDR_reads=161'in log,'Full native positive incomplete')
        else:need(result not in(None,0)and'UPPER_READ_MISMATCH'in log and('fault=0'if key=='native_normal_word_corruption'else'fault=1')in log,'Native control failed to detect expected defect')
        natives.append(dict(scope=key,passed=True,exit=result));print('native',key,'passed',flush=True)
    result=dict(schema='standalone-native-guard-return-word-replay-v1',passed=True,
        replay_script_sha256=sha(Path(__file__).read_bytes()),
        index_sha256=sha((e.root/'INDEX.json').read_bytes()),unique_objects=len(seen),closed_manifests=manifests,
        exact_source_graph_replayed=True,independently_reconstructed_and_freshly_solved_queries=outcomes,native_replays=natives,
        original_workspace_files_opened=False,all_imported_antecedent_solver_queries_freshly_replayed=False,
        portable_component_replay_complete=True,whole_device_session_theorem=False,seconds=time.monotonic()-begin)
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n');print('FINISHED portable component replay passed',flush=True)
    return result


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--packet',type=Path,required=True);p.add_argument('--out',type=Path);p.add_argument('--recorded-only',action='store_true');a=p.parse_args()
    if a.recorded_only:print(json.dumps(recorded(a.packet),sort_keys=True))
    else:
        if a.out is None:p.error('--out is required for fresh replay')
        replay(a.packet,a.out)
