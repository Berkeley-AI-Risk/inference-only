if not __debug__:
    raise SystemExit("Optimized Python is unsupported; run without -O or -OO")
"""Check the native transcripts against each other and the canonical integer reference."""
import hashlib
import json
from pathlib import Path
import sys


def signed(x, width):
    sign = 1 << (width-1)
    return (x ^ sign) - sign


def data_words(words, byte_width):
    return b"".join(int(x,16).to_bytes(byte_width,"little") for x in words)


def s16(word):
    return signed(int(word,16) & 65535,16)


def same_frame(expected, raw, exponent):
    assert hashlib.sha256(raw).hexdigest() == expected["sha256"]
    assert exponent == expected["exponent"]
    return dict(exponent=exponent, first_mantissa=int.from_bytes(raw[:2],"little",signed=True),
                all_mantissas_sha256=expected["sha256"])


def check_derived_frames(lines, reference, layer, channel):
    items=[x for x in lines if x[0]==f"L{layer}_{channel}"]
    assert [int(x[1]) for x in items]==list(range(4))
    assert len({x[2] for x in items})==1
    return same_frame(reference[f"layer{layer}"][channel.lower()],
                      data_words([x[3] for x in items],128),int(items[0][2]))


def address(layer,position,role,word):
    return 227072 + 9 * (2 * (2048*layer+position) + role) + word


def load_case(folder, name):
    lines=[line.split() for line in (folder/(name+".trace")).read_text().splitlines()]
    assert lines[0][0]=="BOOT_AUTHENTICATED" and lines[-1][0]=="TWO_STEPS_COMPLETE"
    assert "words=227062" in lines[0] and "real_sha=1" in lines[0]
    rd=[x for x in lines if x[0]=="KV_RETURN"]
    wr=[x for x in lines if x[0]=="KV_WRITE"]
    assert len(wr)==216
    assert [int(x[2]) for x in wr]==[address(l,p,r,i) for p in range(2) for l in range(6)
                                     for r in range(2) for i in range(9)]
    physical={}
    for fields in lines:
        if fields[0]=="KV_WRITE":
            _,cycle,addr,word=fields
            physical[int(addr)]=(int(cycle),word)
        if fields[0]=="KV_RETURN":
            _,cycle,addr,ordinary,offered=fields
            written,data=physical[int(addr)]
            assert int(cycle)>written and ordinary==data
    return lines,rd,wr


def main():
    folder=Path(sys.argv[1])
    refs=json.loads((folder/"reference.json").read_text())
    original,base_reads,base_writes=load_case(folder,"honest")
    report={}
    for name,layer in [("honest",0),("negated",0),("layer4",4)]:
        lines,reads,writes=load_case(folder,name)
        query=check_derived_frames(lines,refs[name],layer,"QUERY")
        attention=check_derived_frames(lines,refs[name],layer,"ATTENTION")
        basequery=check_derived_frames(original,refs["honest"],layer,"QUERY")
        assert query==basequery
        token=int(next(x[1] for x in lines if x[0]=="MEASURED_TOKEN"))
        assert token==refs[name]["second_token"]
        # All read return addresses/order agree even if later traffic timing changes.
        assert [x[2] for x in base_reads]==[x[2] for x in reads]
        base=address(layer,0,1,0)
        selected=[x for x in reads if base<=int(x[2])<base+9]
        assert [int(x[2]) for x in selected]==list(range(base,base+9))
        assert selected[-1][3]==selected[-1][4]
        for _,_,addr,truth,supplied in reads:
            if name=="honest" or not(base<=int(addr)<base+8):
                assert supplied==truth
            else:
                data=int(truth,16)
                flipped=sum(((-signed((data>>(16*i))&65535,16))&65535)<<(16*i) for i in range(16))
                assert flipped==int(supplied,16)
        footer=int(selected[-1][4],16)
        assert (footer>>16)==0 and footer>>8==(footer&255)
        returned=same_frame(refs[name]["returned_v"],data_words([x[4] for x in selected[:8]],32),
                            signed(footer&255,8))
        subsequent={}
        for r,label in [(0,"k"),(1,"v")]:
            outbase=address(layer+1,1,r,0)
            output=[x for x in writes if outbase<=int(x[2])<outbase+9]
            assert len(output)==9
            exponent=signed(int(output[-1][3],16)&255,8)
            subsequent[label]=same_frame(refs[name][f"layer{layer+1}_{label}"],
                                         data_words([x[3] for x in output[:8]],32),exponent)
        br=[x for x in original if x[0] in ("KV_WRITE","KV_RETURN")]
        nr=[x for x in lines if x[0] in ("KV_WRITE","KV_RETURN")]
        assert [(x[0],x[2]) for x in br]==[(x[0],x[2]) for x in nr]
        first_write=next(((a,b) for a,b in zip(base_writes,writes) if a[3]!=b[3]),None)
        first_timing=next(((a,b) for a,b in zip(br,nr) if a[1]!=b[1]),None)
        pv=[x for x in lines if x[0]==f"L{layer}_PV" and int(x[1])==0]
        assert [int(x[2]) for x in pv]==[0,1]
        # The monitored signed lane slice is exactly 16 bits. This Verilator
        # build can display neighbouring packed bits above bit 15 on %0d.
        old,pending=([int(x[3]),signed(int(x[4]) & 65535,16)] for x in pv)
        numeric=refs[name][f"layer{layer}"]
        assert [old[0],pending[0]]==numeric["probabilities"]
        assert [old[1],pending[1]]==numeric["aligned_v0"]
        report[name]=dict(layer=layer,token=token,second_step_query=query,returned_old_v=returned,
            read_order=[int(x[2]) for x in selected],read_cycle=[int(x[1]) for x in selected],
            total_kv_writes=len(writes),total_kv_returns=len(reads),same_address_order=True,
            pv_head0_coordinate0=dict(old_probability=old[0],old_aligned_v=old[1],
                current_probability=pending[0],current_aligned_v=pending[1],
                old_product=old[0]*old[1],sum_of_products=old[0]*old[1]+pending[0]*pending[1]),
            layer_attention=attention,next_layer_kv_written=subsequent,
            first_changed_write=(dict(address=int(first_write[1][2]),honest_cycle=int(first_write[0][1]),
                case_cycle=int(first_write[1][1]),honest_first_mantissa=s16(first_write[0][3]),
                case_first_mantissa=s16(first_write[1][3])) if first_write else None),
            first_changed_kv_event_time=(dict(kind=first_timing[0][0],address=int(first_timing[0][2]),
                honest=int(first_timing[0][1]),case=int(first_timing[1][1])) if first_timing else None))
    print(json.dumps(report,indent=2))


if __name__=="__main__":
    main()
