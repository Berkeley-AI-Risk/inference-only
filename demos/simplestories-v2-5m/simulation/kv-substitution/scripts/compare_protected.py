if not __debug__:
    raise SystemExit("Optimized Python is unsupported; run without -O or -OO")
"""Match the two FPGA layouts and independently verify all observed layer-4 SHA decisions."""
import hashlib
import json
from pathlib import Path
import struct
import sys

BASE=374528
ROLE_WORDS=((0,1,2,3,8),(4,5,6,7,8))
CASES=["honest","both","head1"]

def sha(data):
    return hashlib.sha256(data).hexdigest()

def rows(path):
    return [line.split() for line in path.read_text().splitlines()]

def word(hexstr):
    return bytes.fromhex(hexstr)[::-1]

def files_for(events,label):
    return [row[1:] for row in events if row[0]==label]

def digest(epoch,head,role,count,data):
    header=struct.pack(">16sQIIIIIII12x",b"IO-KV-ROLE-v2",epoch,4,0,head,role,count,16,32)
    return sha(header + b"".join(data[BASE+18*pos+9*head+i] for pos in range(count) for i in ROLE_WORDS[role]))

def analyze(name,folder,reference):
    events=rows(folder/(name+".trace"))
    assert events[0][0]=="BOOT_AUTHENTICATED" and "words=227062" in events[0] and "real_sha=1" in events[0]
    clean=name=="honest"
    failed_head=0 if name=="both" else 1
    writes={int(addr):word(data) for _,addr,data in files_for(events,"PHY_WR")}
    snapshot={}
    changed=[]
    for addr,original,alternative in files_for(events,"SNAPSHOT"):
        addr=int(addr)
        assert word(original)==writes[addr]
        snapshot[addr]=word(alternative)
        if original!=alternative:
            changed.append(addr)
    old_v=[BASE+head*9+i for head in range(2) for i in ROLE_WORDS[1][:-1]]
    assert changed==([] if clean else (old_v if name=="both" else old_v[4:]))
    original_v=b"".join(writes[a] for a in old_v)
    actual_v=b"".join(snapshot[a] for a in old_v)
    assert original_v==reference["original_v"]
    match=reference["changed_v"] if name=="both" else original_v[:128]+reference["changed_v"][128:]
    assert actual_v==(original_v if clean else match)
    queries=files_for(events,"QUERY")
    assert [int(x[0]) for x in queries]==list(range(4))
    assert queries==reference["query"]
    comparison=[]
    failed=[]
    published_tags={}
    for cycle,write,l,h,r,n,epoch,observed,expected in files_for(events,"DIGEST"):
        cycle,write,l,h,r,n,epoch=map(int,(cycle,write,l,h,r,n,epoch))
        assert l==4
        target=digest(epoch,h,r,n,writes)
        if write:
            assert observed==target
            published_tags[(h,r,n,epoch)]=observed
            continue
        overlay=writes|snapshot
        assert expected==target==published_tags[h,r,n,epoch]
        assert observed==digest(epoch,h,r,n,overlay)
        record=dict(cycle=cycle,head=h,role=r,positions=n,epoch=epoch,expected=expected,calculated=observed)
        comparison.append(record)
        if observed!=expected:
            failed.append(record)
    assert len(failed)==(0 if clean else 1)
    if failed:
        assert failed[0]["head"]==failed_head and failed[0]["role"]==1 and failed[0]==comparison[-1]
    returned=[]
    for cycle,addr,original,alternative in files_for(events,"PHY_RD"):
        addr=int(addr)
        assert word(original)==writes[addr]
        assert word(alternative)==snapshot.get(addr,writes[addr])
        returned.append(addr)
    changed_reads=[a for a in returned if a in changed]
    assert changed_reads==([] if clean else old_v[4*failed_head:4*failed_head+4])
    opts=files_for(events,"GUARD_OFFER")
    fault_offers=[x for x in opts if x[4]=="1"]
    valid_responses=[x for x in opts if x[4]=="0" and x[5]=="1"]
    if not clean:
        assert fault_offers and all(int(x[6],16)==0 and int(x[2])==failed_head for x in fault_offers)
        assert all(not (int(x[1])==0 and int(x[2])==failed_head and 4<=int(x[3])<8) for x in valid_responses)
    for _,pos,head,index,_,_,payload in valid_responses:
        assert word(payload)==writes[BASE+18*int(pos)+9*int(head)+int(index)]
    owner=None
    successful_values=[]
    semantic_faults=[]
    for x in events:
        if x[0]=="ATT_REQ":
            assert owner is None
            owner=tuple(map(int,x[2:5]))
        if x[0]=="ATT_RSP":
            assert owner is not None
            if int(x[2])==1:
                semantic_faults.append(list(owner))
            elif owner[2]==2:
                p,h,_=owner
                expected=b"".join(writes[BASE+18*p+9*h+i] for i in (4,5,6,7))
                assert word(x[3])==expected
                successful_values.append(list(owner))
            owner=None
    if not clean:
        assert [0,failed_head,2] not in successful_values
        assert owner==(0,failed_head,2) or list((0,failed_head,2)) in semantic_faults
    tokens=[int(x[1]) for x in files_for(events,"TOKEN")]
    assert tokens==([200,15] if clean else [200])
    guardfault=files_for(events,"GUARD_FAULT")
    out=files_for(events,"ATT_OUT")
    if clean:
        assert len(out)==4 and not guardfault and events[-1]==["COMPLETED","0","2","8038"]
        assert reference["attention"]==[(x[1],x[2]) for x in out]
    else:
        assert not out and len(guardfault)==1 and int(guardfault[0][0])==failed[0]["cycle"]+1
        assert events[-1]==["CLOSED",str(CASES.index(name)),"1","4019","1","256"]
    return dict(case=name,tokens=tokens,old_v_original_sha256=sha(original_v),old_v_image_sha256=sha(actual_v),
        target_query_sha256=sha(b"".join(word(q[2]) for q in queries)),modified_words=changed,
        modified_words_actually_read=changed_reads,physical_layer4_reads_in_order=returned,
        guard_verification= comparison,first_fault=failed[0] if failed else None,
        guard_fault_core_edge=int(guardfault[0][0]) if guardfault else None,
        error_response_offer_count=len(fault_offers),error_response_transfers=sum(x[5]=="1" for x in fault_offers),
        normal_guard_transfers=len(valid_responses),normal_semantic_values_pos_head_kind=successful_values,
        semantic_fault_replies=semantic_faults,layer4_attention_beats=len(out),
        next_layer_position1_write_count=sum(411410<=a<411428 for a in writes),
        second_head_rows=int(events[-1][3])-4019,post_fault_sampled_edges=0 if clean else int(events[-1][-1]))

def main():
    folder=Path(sys.argv[1]).resolve()
    plain=folder.parent/"plain-kv-observation"
    base=rows(plain/"layer4.trace")
    clean=rows(plain/"honest.trace")
    v=[x for x in files_for(base,"KV_RETURN") if 374537<=int(x[1])<=374544]
    assert len(v)==8 and [int(x[1]) for x in v]==list(range(374537,374545))
    ref=dict(original_v=b"".join(word(x[2]) for x in v),changed_v=b"".join(word(x[3]) for x in v),
             query=files_for(base,"L4_QUERY"),attention=[(x[1],x[2]) for x in files_for(clean,"L4_ATTENTION")])
    print(json.dumps({name:analyze(name,folder,ref) for name in CASES},indent=2))

if __name__=="__main__":
    main()
