"""Offline checks of actual speculative-group mutation and cancellation events."""
if not __debug__:
    raise RuntimeError('Run the prefetch auditors with Python assertions enabled')
import copy
import importlib.util
from pathlib import Path

R=Path(__file__).resolve().parent
s=importlib.util.spec_from_file_location('numeric',R/'audit_numeric.py');n=importlib.util.module_from_spec(s);s.loader.exec_module(n)
need=n.require

def one(rows,event):
    found=[r for r in rows if r['event']==event];need(len(found)==1,f'Missing/duplicate {event}');return found[0]

def audit(rows,workload):
    for x in rows:need(x['profile']==0 and x['workload']==workload,'Wrong security control selection')
    pubs=[(x['position'],x['layer']) for x in rows if x['event']=='publication']
    wanted=[(p,l) for p in range(17) for l in range(28)]
    need(pubs[:476]==wanted,'Missing real context17 publication sequence')
    if workload in (4,5):
        node=0 if workload==4 else 8
        changed=one(rows,'stored_K_or_V1_changed');need(changed['node']==node and changed['group']==1,'Wrong mutated leaf')
        root=[x for x in rows if x['event']=='verification' and x['node']==node and x['group']==1 and x['root'] and x['ok']]
        bad=[x for x in rows if x['event']=='verification' and x['node']==node and x['group']==1 and not x['root'] and not x['ok']]
        need(len(root)==len(bad)==1 and changed['cycle']<root[0]['cycle']<bad[0]['cycle'],'Missing actual root pass / leaf rejection')
        need(not any(x['event']=='operand' and x['position']==16 and x['role']==node//8 for x in rows),'Affected group-one operand used')
        result=one(rows,'mutation_rejected');need(result['target_uses']==0,'Target uses not zero')
        need(len([x for x in rows if x['event']=='error_result'])==1 and not any(x['event']=='numerical_result' for x in rows),'Wrong numerical result after changed leaf')
        for x in rows:
            if x['event']=='operand':
                start=x['half']*64 if x['role'] else 0;length=64 if x['role'] else 128
                need(x['bits']==[n.word(0,x['position'],x['role'],x['KV_head'],i) for i in range(start,start+length)],'Unaffected operand differs')
        return {'workload':workload,'node':node,'root_pass':root[0],'leaf_rejection':bad[0],'result':result,'actual_affected_uses':0}
    a=one(rows,'attention_clear_with_queued_V1');ad=one(rows,'attention_clear_drained')
    b=one(rows,'session_clear_with_outstanding_V1');bd=one(rows,'session_clear_drained')
    need(a['cycle']<ad['old_return']<ad['cycle']<b['cycle']<bd['old_return']<bd['cycle'],'CLEAR / delayed return / reopen order')
    need(ad['blocked_checks']>0 and bd['blocked_checks']>0,'No blocked old-return checks')
    need(any(x['event']=='follow_pending' and x['head']==0 and x['group']==1 and x['cycle']<a['cycle'] for x in rows),'No actual queued V1')
    for start,end,node in ((a,ad,0),(b,bd,8)):
        held=[x for x in rows if x['event']=='request' and not x['update'] and x['group']==1 and x['node']==node and x['bytes']==4096 and x['initial_delay']==100 and x['cycle']<start['cycle']]
        need(held,'CLEAR did not hold the intended actual fetch')
        need(not any(start['cycle']<=x['cycle']<=end['cycle'] and x['event'] in ('operand','numerical_result') for x in rows),'Cancelled operand survived CLEAR/drain')
        # Observations are sampled before the active edge. CLEAR must gate data
        # immediately, while the registered queue must be gone after that edge.
        need(not any(start['cycle']<x['cycle']<=end['cycle'] and x['event']=='follow_pending' for x in rows),'Queued descriptor survived clearing edge')
    recovered=one(rows,'clear_recovery_passed');need(recovered['epoch']==1,'Fresh epoch recovery missing')
    recovery=[copy.deepcopy(x) for x in rows if x['phase']==3]
    need(all(x['epoch']==1 for x in recovery if x['event']=='verification'),'Old epoch verification used for recovery')
    # Normalize only the bookkeeping labels to reuse the independent context2,
    # changed-K numerical/slot audit; preserve all native cycles and data bits.
    for x in recovery:x['workload']=1;x['phase']=0
    detail=n.audit(recovery,0,1)
    need(pubs[476:]==[(p,l) for p in range(2) for l in range(28)],'Fresh publication sequence missing')
    return {'workload':workload,'queued_attention_CLEAR':{'start':a,'drained':ad},'outstanding_session_CLEAR':{'start':b,'drained':bd},'recovery':detail,'fresh_epoch':1}
