"""Verify the paired codebook, the three authenticated runs and the combined native credit arithmetic."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import hashlib
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
def read(p):return json.loads(p.read_bytes())

def codebook(demo):
    image=(demo/"assets/board1-real-semantic-image2048.bin").read_bytes()
    identity=hashlib.sha256(image).hexdigest()
    assert identity=="cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0"
    local=[int(s,16) for s in (demo/"hardware/project/metadata192.memh").read_text().splitlines()]
    scales=[];rows={}
    weights_by_scale={}
    for group in range(63):
        beats=[]
        for j in range(256):
            offset=32*(171480+640*group)+80*j
            beats.append(int.from_bytes(image[offset:offset+80],"little"))
        for lane in range(min(64,4019-64*group)):
            token=64*group+lane
            md_word=213744+8*group+lane//8
            record=(local[md_word-211920]>>(24*(lane%8)))&0xffffff
            pointer=32*md_word+4*(lane%8)
            assert record==int.from_bytes(image[pointer:pointer+4],"little")
            m=record>>8
            assert 0<m<32768
            scales.append(m)
            def signed(beat):
                x=beat>>(10*lane)&1023
                return x-1024 if x>=512 else x
            row=[signed(b) for b in beats]
            assert min(row)>-512
            weights_by_scale.setdefault(m,set()).update(row)
            rows[token]=(row[0],m,row[255])
    first_pairs={(w,m) for w,m,_ in rows.values()}
    first_w={w for w,_,_ in rows.values()}
    example=None
    for t,(w,_,_) in rows.items():
        for u,(_,m,_) in rows.items():
            if w not in weights_by_scale[m]:
                example=dict(coefficient_from_token=t,coefficient=w,scale_from_token=u,scale=m)
                break
        if example:break
    assert example
    return rows,dict(image_sha256=identity,eligible_tokens=len(rows),coordinates_per_token=256,
        distinct_first_coordinate_coefficients=len(first_w),distinct_scales=len(set(scales)),
        distinct_first_coordinate_pairs=len(first_pairs),cartesian_first_coordinate_pairs=len(first_w)*len(set(scales)),
        distinct_pairs_any_coordinate=sum(map(len,weights_by_scale.values())),unavailable_pair_even_over_all_columns=example)

def analyze(token,folder,rows):
    lines=[s.split() for s in (folder/f"token-{token}.trace").read_text().splitlines()]
    assert lines[0][:2]==["BOOT_AUTHENTICATED","words=227062"] and "real_sha=1" in lines[0]
    interesting=lambda name:[[int(s) for s in line[1:]] for line in lines if line[0]==name]
    hi,scale,lo=rows[token]
    group,lane=divmod(token,64)
    (header,)=interesting("HEADER")
    assert header[1:]==[token,group,lane,scale]
    embed=interesting("EMBED")
    assert [v[1:] for v in embed]==[[token,0,hi,scale,hi*scale],[token,255,lo,scale,lo*scale]]
    eb_addresses=interesting("EMB_ADDR")
    assert [v[1:] for v in eb_addresses]==[[2,213744+8*group],[4,171480+640*group]]
    pub=interesting("PUBLIC_TOKEN")
    assert pub==[[token,{0:15,1:108,64:60}[token]]]
    physical=interesting("RAM_PAGE")
    # Physical refill log counts the first observed read of each aligned page; cache hits do not reappear.
    pages={w:c for c,w in physical}
    first_page=171392+640*group
    assert physical[0][1]==first_page
    assert not any(211920<=w and w+127<214248 for w in pages)
    desc=interesting("PROJ_DESC"); addrs=interesting("PROJ_ADDR")
    wanted={ (0,0,0):(256,0,0,211920),(0,6,0):(682,8704,21760,212192),
             (0,6,1):(682,9386,23465,212200),(1,0,0):(256,11432,28580,212224) }
    assert len(desc)==4 and len(addrs)==8
    for row in desc:
        l,j,g=row[1:4]; c,beat,w,meta=wanted[l,j,g]
        assert row[4:]==[c,beat,w]
        assert [v[4:] for v in addrs if v[1:4]==[l,j,g]]==[[2,meta],[4,w]]
        assert (w//128)*128 in pages
    return dict(token=token,result_token=pub[0][1],embedding_internal_first_product=embed[0][3:],
        embedding_internal_last_product=embed[1][3:],embedding_private_metadata_weight_words=[x[2] for x in eb_addresses],
        first_external_page_word=first_page,first_external_read_phy_edge=physical[0][0],
        external_first_seen_page_count=len(pages),target_projection_descriptors=desc,
        private_projection_addresses=addrs,external_selected_page_first_seen_phy_edges={w:pages[w] for w in (0,21760,23424,28544)})

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("repo",type=Path);p.add_argument("records",type=Path,nargs="?",default=HERE)
    a=p.parse_args();d=a.repo.resolve()/"demos/simplestories-v2-5m";wd=a.records.resolve()
    rows,book=codebook(d)
    trials={t:analyze(t,wd,rows) for t in [0,1,64]}
    owners=read(wd/"owners-result.json"); native=read(wd/"native-result.json")
    earlier=read(HERE.parent/"remaining-datapath/result.json")
    assert earlier["image"]==owners["image"]==native["image"]
    assert native["mapped"]["independently_enumerated"]==90 and len(native["mapped"]["sites"])==5
    for check in ("address","embedding"):assert "Property proved" in owners["pdr"][check]
    for cover in ("cover_embed","cover_address"):assert "was asserted" in owners["pdr"][cover]
    prior=earlier["ledger"]; n=prior["clock_hz"]
    values={}
    for convention,u in (("semantic_postscale",29),("physical_postscale",31)):
        def gross(n,a,c):
            return 128*min(n-a,(682*(n-a)+c)//747)+u*a
        values[convention]={"smaller_route_credits_per_union_edge":u,
            "25M_edge_arbitrary":max(gross(n,a,44330) for a in (0,1)),
            "25M_edge_reset":max(gross(n,a,0) for a in (0,1))}
    print(json.dumps({"codebook":book,"booted_runs":trials,"joint":values,
       "sustained_ops_s":128*682*n/747,"gross_proxy_at_fixed_context128":prior["joint_scoped_proxy"],
       "covered_mapped_sites":90,"unclassified_mapped_sites":0,"demonstrated_generic_training_ops_s":None,
       "whole_device_certified_training_factor":None},indent=2))
if __name__=="__main__":main()
