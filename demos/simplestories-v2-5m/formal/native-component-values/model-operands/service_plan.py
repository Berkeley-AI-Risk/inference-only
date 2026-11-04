"""Specify production service response routing using a read-only watched slot.

The captured value is the actual sealed bank word or fixed metadata word at
dispatch. This closes routing, not the upstream fixed-model/storage premise.
"""
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
sys.path.insert(0,str(HERE.parent))
from prepare import sha,write_json

TOP = 'board1_verified_ddr_page_service'
S = '|'+TOP+'_s|'


def n(name,s='a'):return '(|'+TOP+'_n '+name+'| '+s+')'
def bv(v,w):return '(_ bv'+str(v)+' '+str(w)+')'
def eq(x,y):return '(= '+x+' '+y+')'
def conj(xs):return '(and '+' '.join(xs)+')'
def mem(name,s='a'):return '(|'+TOP+'_m '+name+'| '+s+')'
def bank(b,name):return n('g_bank['+str(b)+'].u_bank.'+name)
def same(x,y):return '(ite (= ((_ extract 2 2) '+x+') #b1) (= ((_ extract 2 2) '+y+') #b1) '+eq(x,y)+')'


def ingress_plan():
    """Connect accepted request words to ordered bank/metadata dispatches."""
    increment=lambda name,event:'(ite '+n(event)+' (bvadd ('+name+' q) '+bv(1,7)+') ('+name+' q))'
    args='(ite '+n('request_fire')+' (store (q-arguments q) (q-admitted q) ((_ extract 17 0) '+n('request_word_i')+')) (q-arguments q))'
    zero='(request-origin '+bv(0,7)+' '+bv(0,7)+' ((as const (Array (_ BitVec 7) (_ BitVec 18))) '+bv(0,18)+'))'
    count=n('request_count_q')
    clauses=[
        '(bvule '+count+' '+bv(64,7)+')',
        eq(count,'(bvsub (q-admitted q) (q-dispatched q))'),
        eq(n('request_write_q'),'((_ extract 5 0) (q-admitted q))'),
        eq(n('request_read_q'),'((_ extract 5 0) (q-dispatched q))'),
        '(=> '+n('head_valid_q')+' '+conj(['(not '+eq(count,bv(0,7))+')',
            eq(n('head_word'),'(select (q-arguments q) (q-dispatched q))')])+')',
    ]
    for i in range(64):
        index='(bvadd (q-dispatched q) '+bv(i,7)+')'
        entry='(select (q-arguments q) '+index+')'
        clauses.append('(=> (bvult '+bv(i,7)+' '+count+') '+conj([
            eq('(select '+mem('request_fifo')+' ((_ extract 5 0) '+index+'))',entry),
            '(bvult '+entry+' '+bv(227062,18)+')'])+')')
    definitions=[
        '(declare-datatypes () ((RequestOrigin (request-origin (q-admitted (_ BitVec 7)) (q-dispatched (_ BitVec 7)) (q-arguments (Array (_ BitVec 7) (_ BitVec 18)))))))',
        '(define-fun request-zero () RequestOrigin '+zero+')',
        '(define-fun request-next ((a '+S+') (q RequestOrigin)) RequestOrigin (ite (or (not '+n('reset_n')+') '+n('cancel_i')+') request-zero (request-origin '+
            ' '.join([increment('q-admitted','request_fire'),increment('q-dispatched','read_fire'),args])+')))',
    ]
    for i,clause in enumerate(clauses):
        definitions.append('(define-fun qinv'+str(i)+' ((a '+S+') (q RequestOrigin)) Bool '+clause+')')
    definitions.append('(define-fun request-inv ((a '+S+') (q RequestOrigin)) Bool (ite '+n('fault_o')+' (not '+n('request_ready_o')+') '+conj(['(qinv'+str(i)+' a q)' for i in range(len(clauses))])+'))')
    meaning='(=> '+n('read_fire')+' '+conj([n('head_valid_q'),'(not '+eq(count,bv(0,7))+')',
        eq(n('head_word'),'(select (q-arguments q) (q-dispatched q))'),'(bvult '+n('head_word')+' '+bv(227062,18)+')'])+')'
    definitions.append('(define-fun dispatch-origin ((a '+S+') (q RequestOrigin)) Bool '+meaning+')')
    (HERE/'request-origin.smt2').write_text('\n'.join(definitions)+'\n')
    rules={
        'ingress-reset-base':dict(assumptions=['(not '+n('reset_n')+')',n('reset_n','an'),'(|'+TOP+'_t| a an)'],conclusion='(request-inv an request-zero)'),
        'ingress-preserved':dict(assumptions=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)','(request-inv a q)','(= qn (request-next a q))'],conclusion='(request-inv an qn)'),
        'ingress-dispatch-value':dict(assumptions=[n('reset_n'),'(request-inv a q)'],conclusion='(dispatch-origin a q)'),
    }
    names=['SERVICE-SOURCES.json','service-project/native.sv','service-project/native.smt2','request-origin.smt2']
    write_json(HERE/'INGRESS-PLAN.json',dict(schema='Declarative-native-induction-v1',source_manifest='SERVICE-SOURCES.json',checks_file='INGRESS-CHECKS.json',
        inputs={name:sha((HERE/name).read_bytes()) for name in names},bodies=['service-project/native.smt2','request-origin.smt2'],
        declarations=['(declare-const a '+S+')','(declare-const an '+S+')','(declare-const q RequestOrigin)','(declare-const qn RequestOrigin)'],
        rules=rules,order=list(rules),observations=['q','qn']+[n(x,s) for s in ['a','an'] for x in ['fault_o','head_valid_q','head_word','request_count_q','request_read_q','request_write_q','request_fire','read_fire']]+
        ['(qinv'+str(i)+' an qn)' for i in range(len(clauses))],
        property='Dispatch address is the oldest accepted undispached request, with full 64-entry native FIFO and 128-slot read-only history ring'))


def raw_plan():
    """Bind sequential raw read/return ordinals to the actual page RAM fill."""
    phase=n('dma_state_q');page=n('fill_page_q');issued=n('issued_q');returned=n('received_q');words=n('page_words_q')
    allocate=conj([n('enabled'),eq(phase,bv(3,3)),'(or '+' '.join(conj([eq(n('fill_bank'),bv(b,2)),bank(b,'begin_ready_o')]) for b in range(4))+')'])
    zero='(raw-origin false '+bv(0,11)+' '+bv(0,8)+' '+bv(0,8)+')'
    increment=lambda field,event:'(ite '+n(event)+' (bvadd ('+field+' r) '+bv(1,8)+') ('+field+' r))'
    definitions=[
        '(declare-datatypes () ((RawOrigin (raw-origin (r-live Bool) (r-page (_ BitVec 11)) (r-issued (_ BitVec 8)) (r-returned (_ BitVec 8))))))',
        '(define-fun raw-zero () RawOrigin '+zero+')',
        '(define-fun allocation-fire ((a '+S+')) Bool '+allocate+')',
        '(define-fun raw-next ((a '+S+') (r RawOrigin)) RawOrigin (ite (not '+n('reset_n')+') raw-zero (ite (allocation-fire a) (raw-origin true '+page+' '+bv(0,8)+' '+bv(0,8)+') (raw-origin (r-live r) (r-page r) '+
            increment('r-issued','ddr_request_fire')+' '+increment('r-returned','ddr_response_fire')+'))))',
    ]
    active='(and (bvuge '+phase+' '+bv(1,3)+') (bvule '+phase+' '+bv(4,3)+'))'
    filling=eq(phase,bv(4,3))
    clauses=['(bvule '+phase+' '+bv(5,3)+')',
        '(=> '+active+' '+conj(['(bvult '+page+' '+bv(1774,11)+')',
            eq(words,'(ite '+eq(page,bv(1773,11))+' '+bv(118,8)+' '+bv(128,8)+')')])+')',
        '(=> '+filling+' '+conj(['(r-live r)',eq(page,'(r-page r)'),eq(issued,'(r-issued r)'),eq(returned,'(r-returned r)'),
            '(bvule '+returned+' '+issued+')','(bvule '+issued+' '+words+')','(bvult '+returned+' '+words+')',
            '(bvule (bvsub ((_ zero_extend 1) '+issued+') ((_ zero_extend 1) '+returned+')) '+bv(32,9)+')'])+')']
    for b in range(4):
        clauses.append('(=> '+conj([filling,eq(n('fill_bank'),bv(b,2))])+' '+conj([
            eq(bank(b,'state_q'),'#x1'),eq(bank(b,'page_o'),page),eq(bank(b,'valid_words_q'),words),eq(bank(b,'fill_count_q'),returned)])+')')
    for i,clause in enumerate(clauses):
        definitions.append('(define-fun rinv'+str(i)+' ((a '+S+') (r RawOrigin)) Bool '+clause+')')
    definitions.append('(define-fun raw-inv ((a '+S+') (r RawOrigin)) Bool (ite '+n('fault_o')+' (not '+n('ddr_request_valid_o')+') '+conj(['(rinv'+str(i)+' a r)' for i in range(len(clauses))])+'))')
    request='(=> '+n('ddr_request_fire')+' '+conj(['(r-live r)',
        eq(n('ddr_request_word_o'),'(concat #b0 (r-page r) ((_ extract 6 0) (r-issued r)))'),
        '(bvult (r-issued r) '+words+')'])+')'
    fillfacts=['(r-live r)','(bvult (r-returned r) (r-issued r))']
    for b in range(4):
        fillfacts.append('(=> '+eq(n('fill_bank'),bv(b,2))+' '+conj([
            eq(bank(b,'page_o'),'(r-page r)'),bank(b,'fill_fire'),
            eq('(select '+mem('g_bank['+str(b)+'].u_bank.memory_q','an')+' ((_ extract 6 0) (r-returned r)))',n('ddr_response_data_i'))])+')')
    fill='(=> '+n('ddr_response_fire')+' '+conj(fillfacts)+')'
    definitions += ['(define-fun issued-address ((a '+S+') (r RawOrigin)) Bool '+request+')',
                    '(define-fun returned-fill ((a '+S+') (an '+S+') (r RawOrigin)) Bool '+fill+')']
    (HERE/'raw-origin.smt2').write_text('\n'.join(definitions)+'\n')
    rules={
        'raw-reset-base':dict(assumptions=['(not '+n('reset_n')+')',n('reset_n','an'),'(|'+TOP+'_t| a an)'],conclusion='(raw-inv an raw-zero)'),
        'raw-preserved':dict(assumptions=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)','(raw-inv a r)','(= rn (raw-next a r))'],conclusion='(raw-inv an rn)'),
        'raw-issued-address':dict(assumptions=[n('reset_n'),'(raw-inv a r)'],conclusion='(issued-address a r)'),
        'raw-returned-fill':dict(assumptions=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)','(raw-inv a r)'],conclusion='(returned-fill a an r)'),
    }
    names=['SERVICE-SOURCES.json','service-project/native.sv','service-project/native.smt2','raw-origin.smt2']
    write_json(HERE/'RAW-PLAN.json',dict(schema='Declarative-native-induction-v1',source_manifest='SERVICE-SOURCES.json',checks_file='RAW-CHECKS.json',
        inputs={name:sha((HERE/name).read_bytes()) for name in names},bodies=['service-project/native.smt2','raw-origin.smt2'],
        declarations=['(declare-const a '+S+')','(declare-const an '+S+')','(declare-const r RawOrigin)','(declare-const rn RawOrigin)'],
        rules=rules,order=list(rules),observations=['r','rn']+[n(x,s) for s in ['a','an'] for x in ['fault_o','dma_state_q','fill_page_q','fill_bank','issued_q','received_q','page_words_q','ddr_request_fire','ddr_response_fire']]+
            ['(rinv'+str(i)+' an rn)' for i in range(len(clauses))],
        property='Raw read ordinal/address and accepted return offset own the actual page RAM write; upstream response-data identity remains open'))


def main():
    source = json.loads((HERE/'SERVICE-SOURCES.json').read_text())
    assert source['production_parameters']['BANKS']==4
    read = n('response_read_q');write=n('response_write_q');count=n('response_count_q')
    contains=lambda x:'(bvult ((_ zero_extend 1) (bvsub '+x+' '+read+')) '+count+')'
    source_at=lambda x:'(select '+mem('response_fifo')+' '+x+')'
    push=conj([n('read_fire'),eq(write,'slot')]);pop=conj([n('response_fire'),eq(read,'slot')])
    code='(concat (ite '+n('metadata_read')+' #b1 #b0) '+n('head_bank')+')'
    address=n('head_word');offset='((_ extract 6 0) '+address+')'
    packed='(select '+mem('g_metadata.memory')+' ((_ extract 11 0) (bvsub '+address+' '+bv(211920,18)+')))'
    expanded='(concat '+' '.join('(concat #x00 ((_ extract '+str(i*24+23)+' '+str(i*24)+') '+packed+'))' for i in reversed(range(8)))+')'
    data='(select '+mem('g_bank[3].u_bank.memory_q')+' '+offset+')'
    for b in reversed(range(3)):
        data='(ite '+eq(n('head_bank'),bv(b,2))+' (select '+mem('g_bank['+str(b)+'].u_bank.memory_q')+' '+offset+') '+data+')'
    data='(ite '+n('metadata_read')+' '+expanded+' '+data+')'
    pending='(ite '+push+' true (ite '+pop+' false (s-valid h)))'
    fields=[pending,'(ite '+push+' '+data+' (s-word h))','(ite '+push+' '+code+' (s-code h))',
            '(ite '+push+' '+address+' (s-address h))']
    for b in range(5):
        match = n('metadata_read') if b==4 else conj(['(not '+n('metadata_read')+')',eq(n('head_bank'),bv(b,2))])
        fields.append('(ite '+conj([n('read_fire'),match])+' '+write+' (s-slot'+str(b)+' h))')
    zero='(service-origin false '+bv(0,256)+' #b000 '+bv(0,18)+' '+' '.join([bv(0,5)]*5)+')'
    definitions=[
      '(declare-datatypes () ((ServiceOrigin (service-origin (s-valid Bool) (s-word (_ BitVec 256)) (s-code (_ BitVec 3)) (s-address (_ BitVec 18)) '+
          ' '.join('(s-slot'+str(b)+' (_ BitVec 5))' for b in range(5))+'))))',
      '(define-fun service-zero () ServiceOrigin '+zero+')',
      '(define-fun service-next ((a '+S+') (h ServiceOrigin) (slot (_ BitVec 5))) ServiceOrigin (ite (or (not '+n('reset_n')+') '+n('cancel_i')+') service-zero (service-origin '+' '.join(fields)+')))',
    ]
    meta='(= ((_ extract 2 2) (s-code h)) #b1)'
    class_slot='(s-slot3 h)'
    class_pending=conj([bank(3,'response_valid_q'),eq(bank(3,'state_q'),'#x9')])
    for b in reversed(range(3)):
        class_slot='(ite '+eq('code',bv(b,3))+' (s-slot'+str(b)+' h) '+class_slot+')'
        class_pending='(ite '+eq('code',bv(b,3))+' '+conj([bank(b,'response_valid_q'),eq(bank(b,'state_q'),'#x9')])+' '+class_pending+')'
    class_slot='(ite (= ((_ extract 2 2) code) #b1) (s-slot4 h) '+class_slot+')'
    class_pending='(ite (= ((_ extract 2 2) code) #b1) '+n('g_metadata.valid_q')+' '+class_pending+')'
    definitions += ['(define-fun class-slot ((h ServiceOrigin) (code (_ BitVec 3))) (_ BitVec 5) '+class_slot+')',
                    '(define-fun class-pending ((a '+S+') (code (_ BitVec 3))) Bool '+class_pending+')']
    meta_data='(concat '+' '.join('(concat #x00 ((_ extract '+str(i*24+23)+' '+str(i*24)+') '+n('g_metadata.data_q')+'))' for i in reversed(range(8)))+')'
    clauses=[
      '(bvule '+count+' '+bv(32,6)+')',
      eq(write,'(bvadd '+read+' ((_ extract 4 0) '+count+'))'),
      eq('(s-valid h)',contains('slot')),
      '(=> (s-valid h) '+eq(source_at('slot'),'(s-code h)')+')',
      '(=> (and (s-valid h) '+meta+') '+conj([n('g_metadata.valid_q'),eq(meta_data,'(s-word h)')])+')',
    ]
    for b in range(4):
        clauses.append('(=> '+conj(['(s-valid h)',eq('(s-code h)',bv(b,3))])+' '+conj([
            eq(bank(b,'state_q'),'#x9'),'(not '+bank(b,'fault_o')+')',bank(b,'response_valid_q'),
            eq(bank(b,'read_data_q'),'(s-word h)'),eq(bank(b,'page_o'),'((_ extract 17 7) (s-address h))')])+')')
    for index in range(32):
        other=bv(index,5)
        clauses.append('(=> '+conj(['(s-valid h)',contains(other),'(not '+eq(other,'slot')+')'])+
                       ' (not '+same('(s-code h)',source_at(other))+'))')
        clauses.append('(=> '+contains(other)+' '+conj([
            eq('(class-slot h '+source_at(other)+')',other),
            '(class-pending a '+source_at(other)+')'])+')')
    for i,clause in enumerate(clauses):
        definitions.append('(define-fun sinv'+str(i)+' ((a '+S+') (h ServiceOrigin) (slot (_ BitVec 5))) Bool '+clause+')')
    definitions.append('(define-fun service-inv ((a '+S+') (h ServiceOrigin) (slot (_ BitVec 5))) Bool (ite '+n('fault_o')+
                       ' (not '+n('response_valid_o')+') '+conj(['(sinv'+str(i)+' a h slot)' for i in range(len(clauses))])+'))')
    meaning='(=> '+conj([n('response_valid_o'),eq(read,'slot')])+' '+conj(['(s-valid h)',eq(n('response_data_o'),'(s-word h)')])+')'
    definitions.append('(define-fun service-value ((a '+S+') (h ServiceOrigin) (slot (_ BitVec 5))) Bool '+meaning+')')
    (HERE/'service-origin.smt2').write_text('\n'.join(definitions)+'\n')
    rules={
      'service-reset-base':dict(assumptions=['(not '+n('reset_n')+')',n('reset_n','an'),'(|'+TOP+'_t| a an)'],conclusion='(service-inv an service-zero slot)'),
      'service-preserved':dict(assumptions=[n('reset_n'),n('reset_n','an'),'(|'+TOP+'_t| a an)','(service-inv a h slot)','(= hn (service-next a h slot))'],conclusion='(service-inv an hn slot)'),
      'service-return-value':dict(assumptions=[n('reset_n'),'(service-inv a h slot)'],conclusion='(service-value a h slot)'),
    }
    names=['SERVICE-SOURCES.json','service-project/native.sv','service-project/native.smt2','service-project/metadata192.memh','service-project/digests32.memh','service-origin.smt2']
    write_json(HERE/'SERVICE-PLAN.json',dict(schema='Declarative-native-induction-v1',
        inputs={name:sha((HERE/name).read_bytes()) for name in names},source_manifest='SERVICE-SOURCES.json',checks_file='SERVICE-CHECKS.json',
        bodies=['service-project/native.smt2','service-origin.smt2'],declarations=['(declare-const a '+S+')','(declare-const an '+S+')',
            '(declare-const h ServiceOrigin)','(declare-const hn ServiceOrigin)','(declare-const slot (_ BitVec 5))'],
        order=list(rules),rules=rules,observations=['slot','h','hn']+[n(x,s) for s in ['a','an'] for x in
          ['fault_o','response_count_q','response_write_q','response_read_q','response_source','head_word','head_bank','metadata_read','read_fire','response_fire']]+
          ['(sinv'+str(i)+' an hn slot)' for i in range(len(clauses))],
        property='Response retains its actual bank/ROM word and address association from dispatch; fixed-model and ingress lineage remain open'))
    ingress_plan()
    raw_plan()
    print('Specified the actual four-bank service response routing with all 32 native FIFO slots.')


if __name__=='__main__':main()
