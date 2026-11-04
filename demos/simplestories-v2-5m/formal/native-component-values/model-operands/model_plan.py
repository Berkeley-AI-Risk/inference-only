"""Join the native service's value invariants under an explicit raw-read contract.

M is an arbitrary fixed word image. Instantiation with the named model and
discharge of the upstream raw-read premise are separate, visible obligations.
"""
import json
from pathlib import Path
import sys

HERE=Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
from prepare import sha,write_json
from service_plan import TOP,S,n,bv,eq,conj,mem,bank


def main():
    target='u';value='(select model u)';offset='((_ extract 6 0) u)';page='((_ extract 17 7) u)'
    in_meta='(and (bvuge u '+bv(211920,18)+') (bvult u '+bv(214248,18)+'))'
    packed='(select '+mem('g_metadata.memory')+' ((_ extract 11 0) (bvsub u '+bv(211920,18)+')))'
    expanded='(concat '+' '.join('(concat #x00 ((_ extract '+str(i*24+23)+' '+str(i*24)+') '+packed+'))' for i in reversed(range(8)))+')'
    definitions=[
      '(define-fun target-in-image ((u (_ BitVec 18))) Bool (bvult u '+bv(227062,18)+'))',
      '(define-fun metadata-model ((a '+S+') (u (_ BitVec 18)) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool (=> '+in_meta+' '+eq(expanded,value)+'))',
    ]
    bank_clauses=[]
    for b in range(4):
        st=bank(b,'state_q');count=bank(b,'fill_count_q');words=bank(b,'valid_words_q');tag=bank(b,'page_o')
        active='(and (bvuge '+st+' #x1) (bvule '+st+' #x9))'
        sealed='(and (bvuge '+st+' #x3) (bvule '+st+' #x9))'
        prefix='(or '+sealed+' (and (or '+eq(st,'#x1')+' '+eq(st,'#x2')+') (bvult ((_ zero_extend 1) '+offset+') '+count+')))'
        clauses=[
          '(bvule '+st+' #x9)',
          '(=> '+active+' '+conj(['(bvult '+tag+' '+bv(1774,11)+')',
            eq(words,'(ite '+eq(tag,bv(1773,11))+' '+bv(118,8)+' '+bv(128,8)+')')])+')',
          '(=> '+eq(st,'#x1')+' (bvult '+count+' '+words+'))',
          '(=> '+eq(st,'#x2')+' '+conj(['(bvult '+words+' '+bv(128,8)+')','(bvuge '+count+' '+words+')','(bvult '+count+' '+bv(128,8)+')'])+')',
          '(=> '+sealed+' '+eq(count,bv(128,8))+')',
          '(=> '+conj([eq(tag,page),prefix])+' '+eq('(select '+mem('g_bank['+str(b)+'].u_bank.memory_q')+' '+offset+')',value)+')',
        ]
        for i,clause in enumerate(clauses):
            name='m-bank'+str(b)+'-'+str(i)
            definitions.append('(define-fun '+name+' ((a '+S+') (u (_ BitVec 18)) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool '+clause+')')
            bank_clauses.append('('+name+' a u model)')
    snapshot='(=> '+conj(['(s-valid h)',eq('(s-address h)','u')])+' '+eq('(s-word h)',value)+')'
    legal='(=> (s-valid h) (bvult (s-address h) '+bv(227062,18)+'))'
    definitions.append('(define-fun model-owned ((a '+S+') (h ServiceOrigin) (u (_ BitVec 18)) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool (or '+n('fault_o')+' '+conj(bank_clauses+[snapshot,legal])+'))')
    definitions.append('(define-fun joint-model ((a '+S+') (h ServiceOrigin) (q RequestOrigin) (r RawOrigin) (slot (_ BitVec 5)) (u (_ BitVec 18)) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool '+
        conj(['(target-in-image u)','(metadata-model a u model)','(service-inv a h slot)','(request-inv a q)','(raw-inv a r)','(model-owned a h u model)'])+')')
    raw_word='(concat (r-page r) ((_ extract 6 0) (r-returned r)))'
    definitions.append('(define-fun upstream-word ((a '+S+') (r RawOrigin) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool (=> '+n('ddr_response_fire')+' '+eq(n('ddr_response_data_i'),'(select model '+raw_word+')')+'))')
    meaning='(=> '+conj([n('response_valid_o'),eq(n('response_read_q'),'slot')])+' '+conj([
        '(s-valid h)','(bvult (s-address h) '+bv(227062,18)+')',
        '(=> '+eq('(s-address h)','u')+' '+eq(n('response_data_o'),value)+')'])+')'
    definitions.append('(define-fun fixed-model-return ((a '+S+') (h ServiceOrigin) (slot (_ BitVec 5)) (u (_ BitVec 18)) (model (Array (_ BitVec 18) (_ BitVec 256)))) Bool '+meaning+')')
    (HERE/'model-origin.smt2').write_text('\n'.join(definitions)+'\n')
    joint='(joint-model a h q r slot u model)';next_joint='(joint-model an hn qn rn slot u model)'
    edge=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)']
    external={}
    for prefix,plan,rules in [('service','SERVICE-PLAN.json',['service-reset-base','service-preserved','service-return-value']),
                              ('ingress','INGRESS-PLAN.json',['ingress-reset-base','ingress-preserved','ingress-dispatch-value']),
                              ('raw','RAW-PLAN.json',['raw-reset-base','raw-preserved','raw-issued-address','raw-returned-fill'])]:
        for rule in rules:external[prefix+':'+rule]=dict(plan=plan,rule=rule)
    rules={
      'metadata-model-preserved':dict(assumptions=['(|'+TOP+'_t| a an)','(metadata-model a u model)'],conclusion='(metadata-model an u model)'),
      'model-reset-base':dict(dependencies=['service:service-reset-base','ingress:ingress-reset-base','raw:raw-reset-base'],
          assumptions=['(not '+n('reset_n')+')',n('reset_n','an'),'(|'+TOP+'_t| a an)','(target-in-image u)','(metadata-model an u model)'],
          conclusion='(joint-model an service-zero request-zero raw-zero slot u model)'),
      'model-preserved':dict(dependencies=['metadata-model-preserved','service:service-preserved','ingress:ingress-preserved','ingress:ingress-dispatch-value','raw:raw-preserved','raw:raw-returned-fill'],
          assumptions=edge+[joint,'(= hn (service-next a h slot))','(= qn (request-next a q))','(= rn (raw-next a r))','(upstream-word a r model)'],conclusion=next_joint),
      'model-return-value':dict(dependencies=['service:service-return-value'],assumptions=[n('reset_n'),joint],conclusion='(fixed-model-return a h slot u model)'),
    }
    plans=['SERVICE-PLAN.json','INGRESS-PLAN.json','RAW-PLAN.json'];checks=['SERVICE-CHECKS.json','INGRESS-CHECKS.json','RAW-CHECKS.json']
    bodies=['service-project/native.smt2','service-origin.smt2','request-origin.smt2','raw-origin.smt2','model-origin.smt2']
    names=['SERVICE-SOURCES.json',*bodies,*plans,*checks]
    declarations=[]
    for plan in plans:
        for declaration in json.loads((HERE/plan).read_text())['declarations']:
            if declaration not in declarations:declarations.append(declaration)
    declarations+=['(declare-const u (_ BitVec 18))','(declare-const model (Array (_ BitVec 18) (_ BitVec 256)))']
    write_json(HERE/'MODEL-PLAN.json',dict(schema='Declarative-native-induction-v1',source_manifest='SERVICE-SOURCES.json',checks_file='MODEL-CHECKS.json',
        inputs={name:sha((HERE/name).read_bytes()) for name in names},bodies=bodies,declarations=declarations,external_facts=external,
        rules=rules,order=list(rules),observations=['u','slot','h','hn','r','rn']+[
          '(m-bank'+str(b)+'-'+str(i)+' an u model)' for b in range(4) for i in range(6)]+[
          '(model-owned an hn u model)','(service-inv an hn slot)','(request-inv an qn)','(raw-inv an rn)','(metadata-model an u model)'],
        property='Conditional fixed-model word identity through the complete four-bank service; upstream raw-read contract is explicit and remains to be discharged in the main proof'))
    print('Built a joint conditional model-value invariant with exact imported native engine obligations.')


if __name__=='__main__':main()
