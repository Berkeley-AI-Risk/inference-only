"""Generate the declared native/canonical product and candidate invariant.

No engine runs here. Generated SMT is the reviewable logical statement.
The candidate may fail induction; none of its clauses is an input assumption
on the actual circuit. All native arithmetic and memories remain in native_t.
"""
import argparse
import json
from pathlib import Path
import re

from prepare import HERE, TOP, sha, verify_inventory, write_json

STATE = '|'+TOP+'_s|'
NORM = 'u_frozen_vector_normalizer.'
SHIFT = NORM+'u_shift.'


def n(name, state):
    return '(|'+TOP+'_n '+name+'| '+state+')'


def mem(name, state):
    return '(|'+TOP+'_m '+name+'| '+state+')'


def bv(value, width):
    return '(_ bv'+str(value)+' '+str(width)+')'


def conj(items):
    return '(and '+' '.join(items)+')' if items else 'true'


def disj(items):
    return '(or '+' '.join(items)+')' if items else 'false'


def eq(field, a='a', b='b'):
    return '(= '+n(field,a)+' '+n(field,b)+')'


def isin(field, values, width, state='a'):
    return disj(['(= '+n(field,state)+' '+bv(v,width)+')' for v in values])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--memory-encoding',choices=['quantified','finite'],default='quantified')
    args=ap.parse_args()
    verify_inventory()
    smt = (HERE/'project/native.smt2').read_text()
    wires = {m[1]:int(m[2]) for m in re.finditer(r'^; yosys-smt2-wire (\S+) (\d+)$',smt,re.M)}
    register_widths = {m[1]:int(m[2]) for m in re.finditer(r'^; yosys-smt2-register (\S+) (\d+)$',smt,re.M)}
    registers = list(register_widths)
    memories = [m[1] for m in re.finditer(r'^; yosys-smt2-memory (\S+) ',smt,re.M)]
    # Raw storage holding must exclude inputs. Equality of whole SMT state
    # objects would also freeze the next inputs and could make the product
    # inconsistent. Hold exactly the inventoried sequential cells/memories.
    hold = conj([eq(x,'b','bn') for x in registers]+[
        '(= '+mem(x,'b')+' '+mem(x,'bn')+')' for x in memories])
    fields = {x for x in wires if x.endswith('_q') and not x.startswith('$')}
    fields -= {'compute_cycles_q',NORM+'compute_cycles_q','vector_read_q',NORM+'record_read_q'}
    shift_payload = ['source_q','low_q','shifted_q','amount_q','left_q',
                     'negative_q','force_zero_q','bad_count_q']
    fields -= {SHIFT+x for x in shift_payload}
    fields.update(['range_fault_o',NORM+'range_fault_o']+
        [NORM+'result_'+x+'_o' for x in ['row_index','mantissa','exponent','last']])
    fields.update(x for x in wires if x.startswith(('u_exact_',SHIFT)) and
        x.endswith(('.response_valid_o','.response_result_o','.response_fault_o')))
    if not fields <= wires.keys():
        raise ValueError('Missing named native scalar field')
    root_lifetime={
        'capture_index_q':[1], 'lane_index_q':list(range(2,15)),
        'input_exponent_q':list(range(1,15)), 'layer_q':list(range(1,15)),
        'selector_q':list(range(1,15)), 'square_sum_q':[2,3,4],
        'radicand_q':[5,6], 'rms_q':list(range(7,15)),
        'rms_normalized_q':[11], 'weight_product_q':[12],
        'raw_q':[13], 'raw_source_exponent_q':[13]}
    normalizer_lifetime={
        'capture_index_q':[1], 'rows_q':list(range(1,13)),
        'scan_index_q':list(range(2,13)), 'candidate_q':list(range(2,13)),
        'all_fit_q':list(range(2,13)), 'any_nonzero_q':list(range(2,13)),
        'fit_length_pipe_q':[12], 'fit_source_pipe_q':[12],
        'fit_zero_pipe_q':[3,12], 'fit_first_pipe_q':[3], 'shift_client_q':[6]}
    clauses={}
    scalar_liveness={}
    for field in sorted(fields):
        guard='true'
        if field in root_lifetime:guard=isin('state_q',root_lifetime[field],5)
        elif field.startswith(NORM) and field[len(NORM):] in normalizer_lifetime:
            guard=isin(NORM+'state_q',normalizer_lifetime[field[len(NORM):]],4)
        elif field.startswith(NORM+'result_'):guard=isin(NORM+'state_q',[9],4)
        elif field.startswith(SHIFT) and field.endswith(('.response_result_o','.response_fault_o')):
            guard=n(SHIFT+'response_valid_o','a')
        elif field.startswith(('u_exact_isqrt.','u_exact_divider.')):
            group='sqrt' if field.startswith('u_exact_isqrt.') else 'div'
            if field.endswith(('.response_result_o','.response_fault_o')):
                guard=n(group+'_response_valid','a')
            elif field.endswith('_q') and not field.endswith('.busy_q'):
                busy=next(x for x in fields if x.startswith(field.split('.')[0]+'.') and x.endswith('.busy_q'))
                guard=n(busy,'a')
        scalar_liveness[field]=guard
        clauses['scalar-'+field]=eq(field) if guard=='true' else '(=> '+guard+' '+eq(field)+')'
    for x in shift_payload:
        states = [1,2,3] if x not in ['low_q','shifted_q'] else [2,3] if x=='low_q' else [3]
        clauses['shift-live-'+x]='(=> '+isin(SHIFT+'state_q',states,3)+' '+eq(SHIFT+x)+')'
    clauses['vector-read-live']='(=> '+isin('state_q',[3,9,10,11,12,13,14],5)+' '+eq('vector_read_q')+')'
    clauses['normalizer-read-live']='(=> '+isin(NORM+'state_q',[3,5,6,8,9,10,11,12],4)+' '+eq(NORM+'record_read_q')+')'
    for x in ['rom_coefficient','rom_multiplier','rom_tensor_exponent']:
        clauses['coefficient-read-'+x]='(=> '+isin('state_q',[9,10,11,12,13,14],5)+' '+eq(x)+')'
    root_active=isin('state_q',list(range(1,15)),5)
    norm_active=isin(NORM+'state_q',list(range(1,13)),4)
    clauses['root-clock-order']='(=> '+root_active+' (bvule '+n('compute_cycles_q','b')+' '+n('compute_cycles_q','a')+'))'
    clauses['normalizer-clock-order']='(=> '+norm_active+' (bvule '+n(NORM+'compute_cycles_q','b')+' '+n(NORM+'compute_cycles_q','a')+'))'
    for copy in ['a','b']:
        clauses['root-clock-bound-'+copy]='(bvult '+n('compute_cycles_q',copy)+' '+bv(2000000,32)+')'
        clauses['root-idle-clock-'+copy]='(=> '+isin('state_q',[0],5,copy)+' (= '+n('compute_cycles_q',copy)+' '+bv(0,32)+'))'
        clauses['normalizer-clock-bound-'+copy]='(bvult '+n(NORM+'compute_cycles_q',copy)+' '+bv(2000000,32)+')'
    clauses['role-selector-bound']='(bvule '+n('selector_q','a')+' '+bv(12,4)+')'
    clauses['layer-bound']='(bvult '+n('layer_q','a')+' '+bv(6,3)+')'
    clauses['input-exponent-bound']=conj([
        '(bvsge '+n('input_exponent_q','a')+' #xe0)',
        '(bvsle '+n('input_exponent_q','a')+' #x1f)'])
    clauses['complete-parent-capture']='(=> '+isin('state_q',list(range(2,15)),5)+' (= '+n('capture_index_q','a')+' '+bv(255,8)+'))'
    # These bounds/idle conditions are candidates to prove with the relation,
    # never assumptions supplied by a healthy-future or numerical child cut.
    # These clauses occur only in the non-failed arm of the invariant.
    # Native fault-state entries also assert their corresponding fault flag.
    clauses['root-state-domain']=isin('state_q',list(range(15)),5)
    clauses['normalizer-state-domain']=isin(NORM+'state_q',list(range(13)),4)
    clauses['normalizer-rows']='(=> '+norm_active+' (= '+n(NORM+'rows_q','a')+' '+bv(256,10)+'))'
    clauses['normalizer-scan-bound']='(=> '+isin(NORM+'state_q',list(range(2,13)),4)+' (bvult '+n(NORM+'scan_index_q','a')+' '+bv(256,10)+'))'
    clauses['normalizer-capture-bound']='(=> '+isin(NORM+'state_q',[1],4)+' (bvult '+n(NORM+'capture_index_q','a')+' '+bv(256,10)+'))'
    clauses['normalizer-idle-before-start']='(=> '+isin('state_q',list(range(8)),5)+' '+isin(NORM+'state_q',[0],4)+')'
    clauses['normalizer-captures-parent-stream']='(=> '+isin('state_q',list(range(8,14)),5)+' '+isin(NORM+'state_q',[1],4)+')'
    clauses['normalizer-computes-after-parent-stream']='(=> '+isin('state_q',[14],5)+' '+isin(NORM+'state_q',list(range(2,13)),4)+')'
    clauses['first-parent-lane']='(=> '+isin('state_q',[7],5)+' (= '+n('lane_index_q','a')+' '+bv(0,8)+'))'
    clauses['normalizer-capture-matches-parent-lane']='(=> '+isin('state_q',list(range(8,14)),5)+' (= '+n(NORM+'capture_index_q','a')+' ((_ zero_extend 2) '+n('lane_index_q','a')+')))'
    clauses['normalizer-result-row']='(=> '+isin(NORM+'state_q',[9],4)+' (= '+n(NORM+'result_row_index_o','a')+' '+n(NORM+'scan_index_q','a')+'))'
    clauses['normalizer-result-last']='(=> '+isin(NORM+'state_q',[9],4)+' (= '+n(NORM+'result_last_o','a')+' (= '+n(NORM+'scan_index_q','a')+' '+bv(255,10)+')))'
    expected_address='(concat '+n('selector_q','a')+' '+n('lane_index_q','a')+')'
    expected_word='(select '+mem('u_norm_rom.norm_rom','a')+' '+expected_address+')'
    clauses['owned-coefficient-table-value']='(=> '+isin('state_q',[9,10,11,12,13],5)+' '+conj([
        '(= '+n('rom_coefficient','a')+' ((_ extract 9 0) '+expected_word+'))',
        '(= '+n('rom_multiplier','a')+' ((_ extract 25 10) '+expected_word+'))',
        '(= '+n('rom_tensor_exponent','a')+' ((_ extract 33 26) '+expected_word+'))'])+')'
    sqrt_busy = [x for x in wires if x.startswith('u_exact_isqrt.') and x.endswith('.busy_q')]
    div_busy = [x for x in wires if x.startswith('u_exact_divider.') and x.endswith('.busy_q')]
    if len(sqrt_busy)!=1 or len(div_busy)!=1:
        raise ValueError('Native helper state inventory changed')
    for label,wait,fields0 in [('sqrt',6,[sqrt_busy[0],'sqrt_response_valid']),
                               ('divider',10,[div_busy[0],'div_response_valid'])]:
        clauses[label+'-idle-outside-wait']='(=> (not '+isin('state_q',[wait],5)+') '+conj(['(not '+n(x,'a')+')' for x in fields0])+')'
        clauses[label+'-busy-excludes-response']='(not '+conj([n(x,'a') for x in fields0])+')'
    clauses['shift-idle-at-external-wait']='(=> '+isin(NORM+'state_q',[0,1,9,10],4)+' '+conj([
        isin(SHIFT+'state_q',[0],3),'(not '+n(SHIFT+'response_valid_o','a')+')'])+')'
    clauses['shift-state-domain']=isin(SHIFT+'state_q',[0,1,2,3,5],3)
    clauses['shift-owned-by-wait']='(= '+isin(NORM+'state_q',[6],4)+' '+isin(SHIFT+'state_q',[1,2,3,5],3)+')'
    clauses['shift-response-owned']='(= '+n(SHIFT+'response_valid_o','a')+' '+isin(SHIFT+'state_q',[5],3)+')'
    # Universal finite-address prefix relations retain the actual arrays.
    # The ROMs remain constrained by native_i and its separate preservation law.
    for label,memory,width,count,active,partial in [
        ('vector','vector_mem_q',8,'capture_index_q',isin('state_q',list(range(2,15)),5),isin('state_q',[1],5)),
        ('normalizer',NORM+'record_mem_q',10,NORM+'capture_index_q',isin(NORM+'state_q',list(range(2,13)),4),isin(NORM+'state_q',[1],4))]:
        valid=disj([conj([active,'(bvult j '+bv(256,width)+')']) if width==10 else active,
                    conj([partial,'(bvult j '+n(count,'a')+')'])])
        # Exact finite-domain expansion: all 2**native_address_width values,
        # including the unused normalizer addresses. RAM geometry is unchanged.
        terms=[]
        for index in range(1<<width):
            address=bv(index,width)
            guard=re.sub(r'\bj\b',address,valid)
            terms.append('(=> '+guard+' (= (select '+mem(memory,'a')+' '+address+') (select '+mem(memory,'b')+' '+address+')))')
        clauses[label+'-captured-memory']=conj(terms) if args.memory_encoding=='finite' else '(forall ((j (_ BitVec '+str(width)+'))) (=> '+valid+' (= (select '+mem(memory,'a')+' j) (select '+mem(memory,'b')+' j))))'
    dead=disj([n('range_fault_o','a'),n(NORM+'range_fault_o','a')])
    blocked=disj([
        conj([isin('state_q',[0],5),'(not '+n('start_valid_i','a')+')']),
        conj([isin('state_q',[1],5),'(not '+n('input_valid_i','a')+')']),
        conj([isin('state_q',[14],5),isin(NORM+'state_q',[9],4),'(not '+n('result_ready_i','a')+')']),
        conj([isin('state_q',[14],5),isin(NORM+'state_q',[10],4),'(not '+n('done_ready_i','a')+')'])])
    healthy_controls=conj(['(not '+n('clear_i','a')+')',n('model_lock_i','a'),
        '(not '+n('upstream_fault_i','a')+')',
        '(=> (not '+isin('state_q',[0],5)+') (not '+n('start_valid_i','a')+'))',
        '(=> (not '+isin('state_q',[1],5)+') (not '+n('input_valid_i','a')+'))'])
    tick='(not '+conj([healthy_controls,blocked])+')'
    coupling=conj([n('rst_n','a'),n('rst_n','b'),eq('clear_i'),n('model_lock_i','b'),
        '(not '+n('upstream_fault_i','b')+')',n('result_ready_i','b'),n('done_ready_i','b'),
        '(= '+n('start_valid_i','b')+' '+conj([isin('state_q',[0],5,'b'),n('start_valid_i','a')])+')',
        '(= '+n('input_valid_i','b')+' '+isin('state_q',[1],5,'b')+')']+
        ['(= '+n(x,'b')+' (ite '+conj([isin('state_q',[0],5,'b'),n('start_valid_i','b')])+
         ' '+n(x,'a')+' '+bv(0,w)+'))' for x,w in [('fixed_layer_i',3),('fixed_norm_kind_i',2),('input_exponent_i',8)]]+[
        '(= '+n('input_row_index_i','b')+' (ite '+isin('state_q',[1],5,'b')+' '+n('capture_index_q','b')+' '+bv(0,8)+'))',
        '(= '+n('input_last_i','b')+' '+conj([isin('state_q',[1],5,'b'),'(= '+n('capture_index_q','b')+' '+bv(255,8)+')'])+')',
        '(= '+n('input_mantissa_i','b')+' (ite '+conj([isin('state_q',[1],5,'b'),n('input_valid_i','a'),n('input_ready_o','a')])+ ' '+n('input_mantissa_i','a')+' '+bv(0,16)+'))'])
    outputs=conj([
        '(=> '+n('result_valid_o','a')+' '+conj([n('result_valid_o','b')]+
            [eq('result_'+x+'_o') for x in ['row_index','mantissa','exponent','last']])+')',
        '(=> '+n('done_valid_o','a')+' '+n('done_valid_o','b')+')'])
    lines=['; Native/canonical product, generated by build_product.py.',
        '; Clauses below are a candidate invariant to prove, not DUT assumptions.',
        '(define-fun hold ((b '+STATE+') (bn '+STATE+')) Bool '+hold+')',
        '(define-fun coupled ((a '+STATE+') (b '+STATE+')) Bool '+coupling+')',
        '(define-fun tick ((a '+STATE+')) Bool '+tick+')',
        '(define-fun failed ((a '+STATE+')) Bool '+dead+')']
    for i,(label,clause) in enumerate(clauses.items()):
        lines += ['; '+label,'(define-fun inv'+str(i)+' ((a '+STATE+') (b '+STATE+')) Bool '+clause+')']
    unary=[label for label,formula in clauses.items() if re.search(r'\bb\b',formula) is None]
    zero=conj(['(= '+n(field,'r')+' '+('false' if width==1 else bv(0,width))+')'
        for field,width in register_widths.items()]+[
        '(= '+mem(memory,'r')+' ((as const (Array (_ BitVec '+str(addr)+') (_ BitVec '+str(width)+'))) '+bv(0,width)+'))'
        for memory,addr,width in [('vector_mem_q',8,16),(NORM+'record_mem_q',10,58)]])
    lines += ['(define-fun reachable ((a '+STATE+')) Bool '+conj([clauses[label] for label in unary])+')',
        '(define-fun reference-zero ((r '+STATE+')) Bool '+zero+')',
        '(define-fun relation ((a '+STATE+') (b '+STATE+')) Bool (or (failed a) '+
        conj(['(inv'+str(i)+' a b)' for i in range(len(clauses))])+'))',
        '(define-fun output-meaning ((a '+STATE+') (b '+STATE+')) Bool '+outputs+')',
        '(define-fun product-step ((a '+STATE+') (an '+STATE+') (b '+STATE+') (bn '+STATE+')) Bool '+
        conj(['(|'+TOP+'_t| a an)','(ite (tick a) (|'+TOP+'_t| b bn) (hold b bn))',
              '(coupled a b)','(coupled an bn)'])+')']
    text='\n'.join(lines)+'\n'
    (HERE/'product.smt2').write_text(text)
    manifest=dict(schema='RMSNorm-product-v1',native_smt_sha256=sha(smt.encode()),
        product_sha256=sha(text.encode()),scalar_fields=sorted(fields),
        storage_hold_registers=registers,storage_hold_memories=memories,
        candidate_clause_names=list(clauses),candidate_revision=9,memory_encoding=args.memory_encoding,
        canonical_inactive_inputs='Zero except generated ordered row/last during reference capture. Only admitted descriptor fields and accepted mantissas are shared; arbitrary unused DUT pins remain independent.',
        scalar_liveness=scalar_liveness,unary_reachable_clauses=unary,
        finite_memory_expansion=dict(vector_addresses=256,normalizer_addresses=1024,
            rule='Exhaustive enumeration of every value of the original native bit-vector address sort; no memory geometry or width change.'),
        initial_boundary='Actual CLEAR edge; arbitrary old DUT state and mutable payloads. No extra DUT reset.',
        canonical_schedule='Reference takes native productive cycles; reference sequential storage holds across neutral external waits, while its next inputs remain free.',
        actual_inputs='All two-state public-to-component attempts, faults, lock changes and stalls are unrestricted.',
        numerical_cuts=[],required_proof_rules=[
            'Native immutable initial ROM predicate is preserved by native_t.',
            'An actual CLEAR/native_t edge establishes relation for arbitrary old mutable states.',
            'relation and product-step preserve relation unboundedly.',
            'relation and current coupling entail one-sided output-meaning.',
            'Reference hold freezes exactly sequential state, so erased cycles are reference clock stutters.',
            'A canonical fresh-source invocation has the specified argument capture, finite horizon and output ordinals.',
            'Actual caller port/default-parameter specialization is source-bound, not a parent provenance proof.'],
        full_pilot_completion_requires=['all required rules checked','native full-vector post-CLEAR operating witness',
            'stale-state negative control','wrong-bank/operand negative control',
            'canonical fresh-invocation and ordinal/done connection, including repeat admission without an extra DUT reset'])
    write_json(HERE/'PRODUCT.json',manifest)
    print(json.dumps(dict(candidate_clauses=len(clauses),sequential_hold_registers=len(registers),
        native_mutable_memories=[x for x in memories if x in ['vector_mem_q',NORM+'record_mem_q']],
        solver_started=False),indent=2))


if __name__=='__main__': main()
