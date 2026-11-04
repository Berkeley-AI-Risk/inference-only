"""Source-bound native induction checks for the bounded RMSNorm pilot.

Run from any directory. SMT formulas and raw Z3 logs remain under queries/.
A passed local rule is never reported as a checked pilot. Outstanding
canonical-entry, operating-witness and defect-control obligations fail closed.
"""
import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from threading import Lock

from prepare import HERE, TOP, sha, verify_inventory, write_json
from checkpoint import atomic_bytes, snapshot
from build_product import n, bv, isin, conj, disj

STATE_LOCK=Lock()

RULES = {
    'rom-preserved': dict(dependencies=[], assumptions=[
        '(|'+TOP+'_i| a)', '(|'+TOP+'_t| a an)'], conclusion='(|'+TOP+'_i| an)'),
    'clear-base': dict(dependencies=['rom-preserved'], assumptions=[
        '(|'+TOP+'_i| a)', '(|'+TOP+'_i| b)',
        '(coupled a b)', '(coupled an bn)', '(|'+TOP+'_n clear_i| a)',
        '(|'+TOP+'_t| a an)', '(|'+TOP+'_t| b bn)'], conclusion='(relation an bn)'),
    'hard-reset-base': dict(dependencies=['rom-preserved'],assumptions=[
        '(|'+TOP+'_i| a)','(|'+TOP+'_i| b)',
        '(not (|'+TOP+'_n rst_n| a))','(not (|'+TOP+'_n rst_n| b))',
        '(|'+TOP+'_t| a an)','(|'+TOP+'_t| b bn)','(coupled an bn)'],conclusion='(relation an bn)'),
    'failure-preserved':dict(dependencies=[],assumptions=[
        '(|'+TOP+'_n rst_n| a)','(|'+TOP+'_n rst_n| an)',
        '(not (|'+TOP+'_n clear_i| a))','(failed a)','(|'+TOP+'_t| a an)'],conclusion='(failed an)'),
    'failure-suppresses-output':dict(dependencies=[],assumptions=[
        '(|'+TOP+'_n rst_n| a)','(failed a)'],conclusion='(and (not (|'+TOP+'_n result_valid_o| a)) (not (|'+TOP+'_n done_valid_o| a)))'),
    'idle-canonical-entry':dict(dependencies=['rom-preserved'],assumptions=[
        '(|'+TOP+'_i| a)','(reachable a)','(not (failed a))',
        '(|'+TOP+'_n start_ready_o| a)', '(|'+TOP+'_i| r0)',
        '(reference-zero r0)','(not (|'+TOP+'_n rst_n| r0))',
        '(|'+TOP+'_t| r0 b)','(coupled a b)'],conclusion='(relation a b)'),
    'product-preserved': dict(dependencies=['rom-preserved','clear-base','hard-reset-base','failure-preserved'], assumptions=[
        '(|'+TOP+'_i| a)', '(|'+TOP+'_i| b)',
        '(relation a b)', '(product-step a an b bn)'], conclusion='(relation an bn)'),
    'one-sided-output': dict(dependencies=['rom-preserved','clear-base','product-preserved'], assumptions=[
        '(|'+TOP+'_i| a)', '(|'+TOP+'_i| b)',
        '(coupled a b)', '(relation a b)'], conclusion='(output-meaning a b)'),
}
UNARY='(or (failed a) (reachable a))'
UNARY_NEXT='(or (failed an) (reachable an))'
NORM='u_frozen_vector_normalizer.'
ACTIVE=isin('state_q',list(range(1,15)),5)
ACTIVE_NEXT=isin('state_q',list(range(1,15)),5,'an')
NATIVE_EDGE=[n('rst_n','a'),n('rst_n','an'),'(|'+TOP+'_t| a an)']
RULES.update({
    'unary-base':dict(dependencies=[],assumptions=[
        n('rst_n','an'),'(|'+TOP+'_t| a an)',disj(['(not '+n('rst_n','a')+')',n('clear_i','a')])],conclusion=UNARY_NEXT),
    'unary-preserved':dict(dependencies=['unary-base','failure-preserved'],assumptions=NATIVE_EDGE+[UNARY],conclusion=UNARY_NEXT),
    'history-base':dict(dependencies=[],assumptions=[
        n('rst_n','an'),'(|'+TOP+'_t| a an)',disj(['(not '+n('rst_n','a')+')',n('clear_i','a')])],conclusion='(history-inv an history-zero)'),
    # Post-unary is the conclusion of the separately checked native unary
    # induction theorem. It allows failure and is not a future-health premise.
    'history-preserved':dict(dependencies=['unary-preserved','history-base'],assumptions=NATIVE_EDGE+[
        UNARY,UNARY_NEXT,'(history-inv a h)','(= hn (history-next a an h))'],conclusion='(history-inv an hn)'),
    'history-output':dict(dependencies=['history-preserved','failure-suppresses-output'],assumptions=[
        n('rst_n','a'),UNARY,'(history-inv a h)'],conclusion='(history-output a h)'),
    'protocol-admission':dict(dependencies=['unary-preserved'],assumptions=NATIVE_EDGE+[
        UNARY,'(not '+n('clear_i','a')+')'],conclusion='(=> (start-fire a) (or (failed an) '+conj([
            '(legal-descriptor a)',isin('state_q',[1],5,'an'),'(= '+n('capture_index_q','an')+' '+bv(0,8)+')',
            '(= '+n('selector_q','an')+' (argument-role a))','(= '+n('input_exponent_q','an')+' '+n('input_exponent_i','a')+')',
            '(= '+n('layer_q','an')+' '+n('fixed_layer_i','a')+')'])+'))'),
    'protocol-capture':dict(dependencies=['unary-preserved'],assumptions=NATIVE_EDGE+[
        UNARY,'(not '+n('clear_i','a')+')'],conclusion='(=> (capture-fire a) (or (failed an) '+conj([
            '(legal-capture a)',
            '(ite (= '+n('capture_index_q','a')+' '+bv(255,8)+') '+conj([isin('state_q',[2],5,'an'),'(= '+n('capture_index_q','an')+' '+bv(255,8)+')'])+
             ' '+conj([isin('state_q',[1],5,'an'),'(= '+n('capture_index_q','an')+' (bvadd '+n('capture_index_q','a')+' '+bv(1,8)+'))'])+')'])+'))'),
    'argument-start-correspondence':dict(dependencies=['product-preserved'],assumptions=[
        '(relation a b)','(coupled a b)'],conclusion='(=> '+conj(['(not (failed a))','(start-fire a)'])+' '+conj([
            n('start_valid_i','b'),n('start_ready_o','b')]+[
            '(= '+n(x,'a')+' '+n(x,'b')+')' for x in ['fixed_layer_i','fixed_norm_kind_i','input_exponent_i']])+')'),
    'argument-capture-correspondence':dict(dependencies=['product-preserved','protocol-capture','failure-preserved'],assumptions=[
        '(relation a b)','(product-step a an b bn)'],conclusion='(=> '+conj(['(not (failed a))','(tick a)',n('input_valid_i','b'),n('input_ready_o','b')])+
        ' '+disj(['(failed an)',n('clear_i','a'),conj(['(capture-fire a)']+[
            '(= '+n(x,'a')+' '+n(x,'b')+')' for x in ['input_row_index_i','input_mantissa_i','input_last_i']])])+')'),
    'accepted-events-tick':dict(dependencies=[],assumptions=['(coupled a b)'],conclusion='(=> '+disj([
        n('clear_i','a'),'(start-fire a)','(capture-fire a)','(result-fire a)','(done-fire a)'])+' (tick a))'),
    'watchdog-step':dict(dependencies=['unary-preserved'],assumptions=NATIVE_EDGE+[
        UNARY,'(not '+n('clear_i','a')+')'],conclusion='(=> '+conj(['(not (failed a))',ACTIVE])+' '+disj([
            '(failed an)',conj([isin('state_q',[0],5,'an'),'(done-fire a)']),
            conj([ACTIVE_NEXT,'(= '+n('compute_cycles_q','an')+' (bvadd '+n('compute_cycles_q','a')+' '+bv(1,32)+'))',
                '(bvult (bvsub '+bv(2000000,32)+' '+n('compute_cycles_q','an')+') (bvsub '+bv(2000000,32)+' '+n('compute_cycles_q','a')+'))'])])+')'),
    'watchdog-boundary':dict(dependencies=[],assumptions=NATIVE_EDGE+[
        '(not '+n('clear_i','a')+')',ACTIVE,'(bvuge '+n('compute_cycles_q','a')+' '+bv(1999999,32)+')'],conclusion='(failed an)'),
    'completed-value-contract':dict(dependencies=['history-output','one-sided-output','argument-start-correspondence','argument-capture-correspondence','watchdog-step'],assumptions=[
        '(relation a b)','(coupled a b)',UNARY,'(history-inv a h)'],
        conclusion='(and (history-output a h) (output-meaning a b))'),
})
# Native counter laws and a separate fixed-width ranking fact keep the timing
# argument independent of numerical fault-case search. Imports are proved
# implications, not unconditionally assumed postconditions.
RULES['watchdog-counter-update']=dict(dependencies=[],assumptions=NATIVE_EDGE+[
    '(not '+n('clear_i','a')+')'],conclusion='(=> '+conj([
        '(not (failed a))',ACTIVE,'(bvult '+n('compute_cycles_q','a')+' '+bv(1999999,32)+')'])+
    ' '+disj(['(= '+n('compute_cycles_q','an')+' (bvadd '+n('compute_cycles_q','a')+' '+bv(1,32)+'))',
        conj([isin('state_q',[0],5,'an'),'(done-fire a)','(= '+n('compute_cycles_q','an')+' '+bv(0,32)+')'])])+')')
RULES['watchdog-idle-exit']=dict(dependencies=[],assumptions=NATIVE_EDGE+[
    '(not '+n('clear_i','a')+')'],conclusion='(=> '+conj([ACTIVE,isin('state_q',[0],5,'an')])+' (done-fire a))')
RULES['watchdog-rank-arithmetic']=dict(dependencies=[],assumptions=[],conclusion='(=> '+conj([
    '(bvult '+n('compute_cycles_q','a')+' '+bv(1999999,32)+')',
    '(= '+n('compute_cycles_q','an')+' (bvadd '+n('compute_cycles_q','a')+' '+bv(1,32)+'))'])+
    ' '+conj(['(bvult '+n('compute_cycles_q','an')+' '+bv(2000000,32)+')',
        '(bvult (bvsub '+bv(2000000,32)+' '+n('compute_cycles_q','an')+') (bvsub '+bv(2000000,32)+' '+n('compute_cycles_q','a')+'))'])+')')
RULES['watchdog-step']['imports']=['unary-preserved','watchdog-counter-update','watchdog-idle-exit','watchdog-rank-arithmetic','watchdog-boundary']
RULES['watchdog-step']['dependencies']+=RULES['watchdog-step']['imports'][1:]
watchdog=RULES['watchdog-step']
watchdog['source_context']=list(watchdog['assumptions'])
watchdog['context_facts']=list(watchdog['imports'])
watchdog['passthrough']=[UNARY]
watchdog['imports']=[]
watchdog['assumptions']=list(watchdog['passthrough'])
for dep in watchdog['context_facts']:
    remainder=[fact for fact in RULES[dep]['assumptions'] if fact not in watchdog['source_context']]
    watchdog['assumptions'].append('(=> '+conj(remainder)+' '+RULES[dep]['conclusion']+')')
RULES['history-preserved']['assumptions'].remove(UNARY_NEXT)
RULES['history-preserved']['imports']=['unary-preserved']
RULES['reference-entry-feasible']=dict(dependencies=[],expected='sat',assumptions=[
    '(|'+TOP+'_i| r0)','(reference-zero r0)','(not '+n('rst_n','r0')+')',
    '(|'+TOP+'_t| r0 a)',n('rst_n','a'),n('model_lock_i','a'),
    '(not '+n('clear_i','a')+')','(not '+n('upstream_fault_i','a')+')',
    '(not '+n('input_valid_i','a')+')',n('start_valid_i','a'),
    '(= '+n('fixed_layer_i','a')+' '+bv(5,3)+')','(= '+n('fixed_norm_kind_i','a')+' '+bv(2,2)+')',
    '(= '+n('input_exponent_i','a')+' #xf4)',n('start_ready_o','a'),
    '(|'+TOP+'_t| a an)',n('rst_n','an'),isin('state_q',[1],5,'an')],conclusion='false')
RULES['completed-value-contract']['dependencies']+=['idle-canonical-entry','reference-entry-feasible','accepted-events-tick','watchdog-boundary']
RULES['product-preserved']['dependencies']+=['accepted-events-tick']
bank_address='(concat (h-role h) '+n('lane_index_q','a')+')'
bank_word='(select (|'+TOP+'_m u_norm_rom.norm_rom| a) '+bank_address+')'
RULES['coefficient-bank-binding']=dict(dependencies=['unary-preserved','history-preserved'],assumptions=[
    n('rst_n','a'),UNARY,'(history-inv a h)'],conclusion='(=> '+conj([
        '(not (failed a))',isin('state_q',[9,10,11,12,13],5)])+' '+conj([
        '(h-active h)','(bvule (h-role h) '+bv(12,4)+')',
        '(= '+n('rom_address','a')+' '+bank_address+')',
        '(= '+n('rom_coefficient','a')+' ((_ extract 9 0) '+bank_word+'))',
        '(= '+n('rom_multiplier','a')+' ((_ extract 25 10) '+bank_word+'))',
        '(= '+n('rom_tensor_exponent','a')+' ((_ extract 33 26) '+bank_word+'))'])+')')
RULES['completed-value-contract']['dependencies']+=['coefficient-bank-binding']
OPEN = [
    'canonical fresh-invocation argument/ordinal/done connection, including repeat admission',
    'nontrivial full-vector post-CLEAR native operating witness',
    'stale-state defect control',
    'deterministic wrong-bank/operand defect control',
]


def inputs():
    verify_inventory()
    compiled = json.loads((HERE/'COMPILE.json').read_text())
    product = json.loads((HERE/'PRODUCT.json').read_text())
    native = (HERE/'project/native.smt2').read_bytes()
    spec = (HERE/'product.smt2').read_bytes()
    if (sha(native) != compiled['native_smt_sha256'] or
        sha(native) != product['native_smt_sha256'] or sha(spec) != product['product_sha256']):
        raise ValueError('Frozen native/product identity changed')
    history=(HERE/'history.smt2').read_bytes()
    if sha(history)!=json.loads((HERE/'HISTORY.json').read_text())['history_sha256']:
        raise ValueError('Frozen history formula changed')
    return native.decode()+spec.decode()+history.decode()


def import_formulas(rule):
    result=[]
    for dep in RULES[rule].get('imports',[]):
        context=RULES[dep].get('source_context',RULES[dep]['assumptions'])
        result.append(RULES[dep]['conclusion'] if set(context)<=set(RULES[rule]['assumptions']) else
            '(=> '+conj(context)+' '+RULES[dep]['conclusion']+')')
    return result


def query_text(rule, body):
    state='|'+TOP+'_s|'
    return ('(set-option :produce-models true)\n'+body+
        '\n'.join('(declare-const '+s+' '+state+')' for s in ['a','an','b','bn','r0'])+'\n'+
        '(declare-const h History)\n(declare-const hn History)\n'+
        '\n'.join('(assert '+a+')' for a in RULES[rule]['assumptions'])+'\n'+
        '\n'.join('(assert '+formula+')' for formula in import_formulas(rule))+'\n'+
        '(assert (not '+RULES[rule]['conclusion']+'))\n(check-sat)\n')

