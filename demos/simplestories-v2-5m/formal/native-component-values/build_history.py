"""Generate a read-only accepted-argument/output history monitor for native RTL."""
from build_product import STATE, NORM, n, mem, bv, conj, disj, isin
from prepare import HERE, sha, write_json
from checkpoint import atomic_bytes


def main():
    zero_array='((as const (Array (_ BitVec 8) (_ BitVec 16))) '+bv(0,16)+')'
    zero='(mk-history false '+bv(0,9)+' '+bv(0,9)+' '+bv(0,4)+' '+bv(0,8)+' '+zero_array+')'
    desc=conj(['(bvult '+n('fixed_layer_i','a')+' '+bv(6,3)+')',
        disj(['(bvult '+n('fixed_norm_kind_i','a')+' '+bv(2,2)+')',
              conj(['(= '+n('fixed_norm_kind_i','a')+' '+bv(2,2)+')','(= '+n('fixed_layer_i','a')+' '+bv(5,3)+')'])]),
        '(bvsge '+n('input_exponent_i','a')+' #xe0)','(bvsle '+n('input_exponent_i','a')+' #x1f)'])
    role=('(ite (= '+n('fixed_norm_kind_i','a')+' '+bv(2,2)+') '+bv(12,4)+
        ' (bvadd (bvshl ((_ zero_extend 1) '+n('fixed_layer_i','a')+') '+bv(1,4)+') ((_ zero_extend 2) '+n('fixed_norm_kind_i','a')+')))')
    start=conj([n('start_valid_i','a'),n('start_ready_o','a')])
    capture=conj([n('input_valid_i','a'),n('input_ready_o','a')])
    result=conj([n('result_valid_o','a'),n('result_ready_i','a')])
    done=conj([n('done_valid_o','a'),n('done_ready_i','a')])
    beat=conj(['(= '+n('input_row_index_i','a')+' '+n('capture_index_q','a')+')',
        '(= '+n('input_last_i','a')+' (= '+n('capture_index_q','a')+' '+bv(255,8)+'))',
        '(not (= '+n('input_mantissa_i','a')+' #x8000))'])
    active=isin('state_q',list(range(1,15)),5)
    before=disj([isin(NORM+'state_q',[0,1,2,3,4,5,11,12],4),
        conj([isin(NORM+'state_q',[6],4),'(not '+n(NORM+'shift_client_q','a')+')'])])
    writing=disj([isin(NORM+'state_q',[7,8,9],4),
        conj([isin(NORM+'state_q',[6],4),n(NORM+'shift_client_q','a')])])
    clauses={
        'active-owner':'(= (h-active h) '+active+')',
        'captured-count-bound':'(bvule (h-captured h) '+bv(256,9)+')',
        'output-count-bound':'(bvule (h-ordinal h) '+bv(256,9)+')',
        'inactive-empty':'(=> (not (h-active h)) '+conj(['(= (h-captured h) '+bv(0,9)+')','(= (h-ordinal h) '+bv(0,9)+')'])+')',
        'capture-cursor':'(=> '+isin('state_q',[1],5)+' (= (h-captured h) ((_ zero_extend 1) '+n('capture_index_q','a')+')))',
        'complete-vector':'(=> '+isin('state_q',list(range(2,15)),5)+' (= (h-captured h) '+bv(256,9)+'))',
        'argument-role':'(=> (h-active h) (= (h-role h) '+n('selector_q','a')+'))',
        'argument-layer':'(=> (h-active h) (= '+n('layer_q','a')+' (ite (= (h-role h) '+bv(12,4)+') '+bv(5,3)+' ((_ extract 3 1) (h-role h)))))',
        'argument-exponent':'(=> (h-active h) (= (h-exponent h) '+n('input_exponent_q','a')+'))',
        'before-output':'(=> '+before+' (= (h-ordinal h) '+bv(0,9)+'))',
        'write-cursor':'(=> '+writing+' (= ((_ zero_extend 1) (h-ordinal h)) '+n(NORM+'scan_index_q','a')+'))',
        'complete-output':'(=> '+isin(NORM+'state_q',[10],4)+' (= (h-ordinal h) '+bv(256,9)+'))',
        'owned-vector':'(forall ((row (_ BitVec 8))) (=> '+conj(['(h-active h)','(bvult ((_ zero_extend 1) row) (h-captured h))'])+
            ' '+conj(['(= (select '+mem('vector_mem_q','a')+' row) (select (h-vector h) row))',
                       '(not (= (select (h-vector h) row) #x8000))'])+'))',
    }
    outcome=conj([
        '(=> '+n('result_valid_o','a')+' '+conj(['(h-active h)','(= (h-captured h) '+bv(256,9)+')',
            '(bvult (h-ordinal h) '+bv(256,9)+')',
            '(= '+n('result_row_index_o','a')+' ((_ extract 7 0) (h-ordinal h)))',
            '(= '+n('result_last_o','a')+' (= (h-ordinal h) '+bv(255,9)+'))'])+')',
        '(=> '+n('done_valid_o','a')+' '+conj(['(h-active h)','(= (h-captured h) '+bv(256,9)+')','(= (h-ordinal h) '+bv(256,9)+')'])+')'])
    retain='(mk-history (h-active h) (h-captured h) (h-ordinal h) (h-role h) (h-exponent h) (h-vector h))'
    on_capture='(mk-history (h-active h) (bvadd (h-captured h) '+bv(1,9)+') (h-ordinal h) (h-role h) (h-exponent h) (store (h-vector h) '+n('input_row_index_i','a')+' '+n('input_mantissa_i','a')+'))'
    on_result='(mk-history (h-active h) (h-captured h) (bvadd (h-ordinal h) '+bv(1,9)+') (h-role h) (h-exponent h) (h-vector h))'
    on_start='(mk-history true '+bv(0,9)+' '+bv(0,9)+' (argument-role a) '+n('input_exponent_i','a')+' '+zero_array+')'
    step=('(ite '+disj(['(not '+n('rst_n','a')+')',n('clear_i','a'),'(failed an)'])+' history-zero '+
        '(ite (start-fire a) '+on_start+' (ite (capture-fire a) '+on_capture+
        ' (ite (result-fire a) '+on_result+' (ite (done-fire a) history-zero '+retain+')))))')
    lines=['; Read-only history; history-next returns a value and cannot constrain native inputs.',
        '(declare-datatypes () ((History (mk-history (h-active Bool) (h-captured (_ BitVec 9)) (h-ordinal (_ BitVec 9)) (h-role (_ BitVec 4)) (h-exponent (_ BitVec 8)) (h-vector (Array (_ BitVec 8) (_ BitVec 16)))))))',
        '(define-fun history-zero () History '+zero+')',
        '(define-fun legal-descriptor ((a '+STATE+')) Bool '+desc+')',
        '(define-fun argument-role ((a '+STATE+')) (_ BitVec 4) '+role+')']
    for name,formula in [('start-fire',start),('capture-fire',capture),('result-fire',result),('done-fire',done),('legal-capture',beat)]:
        lines.append('(define-fun '+name+' ((a '+STATE+')) Bool '+formula+')')
    for i,(label,formula) in enumerate(clauses.items()):
        lines+=['; '+label,'(define-fun hinv'+str(i)+' ((a '+STATE+') (h History)) Bool '+formula+')']
    lines += ['(define-fun history-inv ((a '+STATE+') (h History)) Bool (or (failed a) '+conj(['(hinv'+str(i)+' a h)' for i in range(len(clauses))])+'))',
        '(define-fun history-next ((a '+STATE+') (an '+STATE+') (h History)) History '+step+')',
        '(define-fun history-output ((a '+STATE+') (h History)) Bool '+outcome+')']
    for line in lines:
        if not line.startswith(';') and line.count('(')!=line.count(')'):
            raise ValueError('Unbalanced generated history formula')
    text='\n'.join(lines)+'\n';atomic_bytes(HERE/'history.smt2',text.encode())
    write_json(HERE/'HISTORY.json',dict(schema='RMSNorm-accepted-history-v1',history_sha256=sha(text.encode()),
        clauses=list(clauses),observer_noninterference='Functional history-next observes native signals; no history signal occurs in native_t or native inputs.',
        argument='Accepted role/exponent and ordered 256 signed mantissas; full native RAM agrees with owned prefix.',
        production_dimensions_changed=False,proof_complete=False))
    print('Accepted-argument and output-history formulas generated:',len(clauses),'clauses.')


if __name__=='__main__':main()
