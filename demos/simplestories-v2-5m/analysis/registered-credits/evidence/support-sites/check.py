"""Source, netlist, codebook, SAT and observed endpoint checks for five mapped support sites."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import gzip
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile
HERE=Path(__file__).resolve().parent
IMAGE="01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"
SITES={"embedding_support","metadata_support","projection_stride_support"}
LAYER="board1_fixed_group_ddr_stream"
META="board1_fixed_projection_metadata_reader"
EMBED="board1_fixed_embedding_lookup"

def sha(b):return hashlib.sha256(b).hexdigest()
def read(p):return json.loads(p.read_bytes())
def y(w,s):
    r=subprocess.run(["yosys","-Q","-T","-p",s],cwd=w,capture_output=True,text=True,timeout=90)
    if r.returncode: raise ValueError(r.stdout[-2350:]+r.stderr[-650:])
    return r.stdout

def native_sites(demo):
    ev=demo/"evidence/current-greedy"
    census=read(ev/"baseline/analysis/mapped-census.json")
    assert census["image_sha256"]==IMAGE and not census["source_to_netlist_equivalence_proved"]
    raw=census["raw_native_products"][".vo"]
    vo=gzip.decompress((ev/"objects"/(raw["sha256"]+".gz")).read_bytes())
    assert sha(vo)==raw["sha256"] and len(vo)==raw["bytes"]
    source=vo.decode()
    instances=[(match[1],match[2]) for match in re.finditer(r"^(MULTALU27X18|MULT12X12) \\(\S+)\s+\(",source,re.M)]
    actual=set(instances)
    recorded={(r["primitive"],r["instance"]) for r in census["mapped_instances"]}
    assert actual==recorded and len(actual)==len(instances)==90
    lines=source.splitlines()
    records=[]
    for r in census["mapped_instances"]:
        if r["group"] not in SITES: continue
        n=r["native_line"]-1
        end=next(i for i in range(n,n+140) if lines[i].strip()==");")
        block="\n".join(lines[n:end+1])
        assert sha(block.encode())==r["cell_text_sha256"]
        get=lambda k:re.search(r"^\s*\."+k+r"\((.*)\),?$",block,re.M)[1]
        A,B=get("A"),get("B")
        assert {"A":A,"B":B}==r["operand_bindings"]
        con=lambda bits:int("".join("1" if x=="VCC" else "0" for x in bits),2)
        operands={k:s.strip("{}").split(", ") for k,s in (("A",A),("B",B))}
        literals={k:con(v) for k,v in operands.items() if all(x in ("GND","VCC") for x in v)}
        records.append(dict(instance=r["instance"],group=r["group"],native_line=n+1,literals=literals,
            primitive=r["primitive"],cell_sha256=r["cell_text_sha256"],output_binding=get("DOUT")))
    assert [v["literals"] for v in records]==[{},{"A":7,"B":304},{"B":11432},{},{"B":304}]
    assert "selected_product [25:0]" in records[0]["output_binding"]
    group=next(c for c in census["mapped_instances"] if c["native_line"]==672429)
    bits=group["operand_bindings"]["B"].strip("{}").split(", ")
    def lut(signal):
        match=re.search(r"^LUT4 (\\\S+)\s+\(\n"+
            r"\s*\.I0\(([^\n]*)\),\n\s*\.I1\(([^\n]*)\),\n\s*\.I2\(([^\n]*)\),\n\s*\.I3\(([^\n]*)\),\n"+
            r"\s*\.F\("+re.escape(signal)+r"\)\n\);\ndefparam \1 \.INIT=16'h([0-9A-Fa-f]+);",source,re.M)
        assert match,signal
        inputs=[int(re.search(r"/u_projection/job_q \[(\d)\]",v)[1]) for v in match.groups()[1:5]]
        values=int(match[6],16)
        return [(values>>sum(((job>>i)&1)<<p for p,i in enumerate(inputs)))&1 for job in range(16)]
    sources={s:lut(s) for s in set(bits)-{"GND","VCC"}}
    decoded=[int("".join(str(sources[s][j]) if s in sources else ("1" if s=="VCC" else "0") for s in bits),2) for j in range(16)]
    assert decoded==[256]*6+[682,256]+[0]*8
    def parents(wire):
        end=source.find(".F("+wire+")")
        if end<0:return []
        start=source.rfind("\nLUT",max(0,end-5000),end)
        return re.findall(r"\.I\d\(([^\n]*)\)",source[start:end])
    left=group["operand_bindings"]["A"].strip("{}").split(", ")
    assert left[:6]==["GND"]*6
    origins={}
    for index,wire in zip(range(5,-1,-1),left[6:]):
        direct=parents(wire)
        local=direct+[v for net in direct for v in parents(net)]
        evidence=[v for v in local if "/u_projection/group_q_0 " in v]
        assert any(v.endswith(f"group_q_0 [{index}]") for v in evidence)
        origins[index]=[v.split("/")[-1] for v in evidence]
    return dict(independently_enumerated=len(actual),vo_sha256=sha(vo),sites=records,
                mapped_group_stride_B_for_jobs_0_to_15=decoded,mapped_group_stride_A_nearby_register_bits=origins)

def inputs(m,name):return m["netnames"][name]["bits"]

def extract(m,roots,out):
    driven={}
    for n,c in m["cells"].items():
        if c["type"].startswith("$") and "ff" not in c["type"]:
            for pin,dr in c["port_directions"].items():
                if dr=="output":
                    for bit in c["connections"][pin]:
                        if isinstance(bit,int):
                            assert bit not in driven
                            driven[bit]=n
    stop=set(sum(roots.values(),[])); todo=sum(out.values(),[]); free=set(); keep={}
    while todo:
        bit=todo.pop()
        if not isinstance(bit,int) or bit in stop:continue
        n=driven.get(bit)
        if n is None: free.add(bit);continue
        if n in keep:continue
        c=keep[n]=m["cells"][n]
        for k,d in c["port_directions"].items():
            if d=="input":todo.extend(c["connections"][k])
    if free:roots["env"]=sorted(free)
    ports={k:dict(direction="input",bits=b) for k,b in roots.items()}
    ports.update({k:dict(direction="output",bits=b) for k,b in out.items()})
    names={k:dict(hide_name=0,bits=p["bits"],attributes={}) for k,p in ports.items()}
    return dict(attributes={},ports=ports,netnames=names,cells=keep)

def expected(layer,job,g):
    counts=[4,2,2,4,11,11,4,63]
    offsets=[0,1024,1536,2048,3072,5888,8704,68592]
    meta=[0,32,48,64,96,184,272,1824]
    c=682 if job==6 else 256
    ok=g<counts[job] and (layer==7 if job==7 else layer<6)
    beat=(0 if job==7 else 11432*layer)+offsets[job]+g*c
    meta=211920+(0 if job==7 else 304*layer)+meta[job]+8*g
    return ok,5*(beat//2),meta

def sat(w,model,roots,outputs,body,checks,alternatives=()):
    cone=extract(model,roots,outputs)
    (w/"cone.json").write_text(json.dumps({"modules":{"cone":cone}}))
    p=[f"input [{len(b)-1}:0] {k}" for k,b in roots.items()]
    p+=[f"input [{len(roots[k])-1}:0] alt_{k}" for k in alternatives]
    lines=["module audit("+",".join(p+["output "+k for k in checks])+");"]
    for version in ["base"]+list(alternatives):
        lines+=[f"wire [{len(b)-1}:0] {version}_{k};" for k,b in outputs.items()]
        pins=[f".{k}({'alt_' if version==k else ''}{k})" for k in roots]
        pins+=[f".{k}({version}_{k})" for k in outputs]
        lines+=["cone c_"+version+"("+",".join(pins)+");"]
    (w/"audit.sv").write_text("\n".join(lines+[body,"endmodule"]))
    prep="read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; "
    for k,expect in checks.items():
        log=y(w,prep+"sat "+("-verify" if expect else "-falsify")+" -prove "+k+" 0")
        assert ("no model found: SUCCESS!" if expect else "model found: FAIL!") in log
    return checks

def descriptor_checks(w,m,meta):
    roots={a:inputs(m,"fixed_"+a+"_i") for a in ("layer","job","group")}
    out={"valid":inputs(m,"descriptor_valid"),
         "address":inputs(m,"descriptor_base_word" if meta else "descriptor_word_base_wide")}
    rows=[]
    for l in range(8):
        for job in range(8):
            for g in range(64):
                yes,wt,md=expected(l,job,g)
                if yes: rows.append((l<<10|job<<6|g,md if meta else wt))
    assert len(rows)==291
    vals=" ".join(f"13'd{k}:begin legal=1; wanted=19'd{v}; end" for k,v in rows)
    body="reg legal; reg [18:0] wanted; always @* begin legal=0;wanted=0;case({layer,job,group}) "+vals+" default:; endcase end\n"
    body+="assign table_error=(base_valid!=legal)||(legal && base_address!=wanted);"
    table=sat(w,m,roots.copy(),out,body,{"table_error":True})
    product_cells=[c for c in m["cells"].values() if c["type"]=="$mul"]
    cuts={"stride":c["connections"]["Y"] for c in product_cells if all(isinstance(v,str) for v in c["connections"]["B"])}
    if not meta:
        (group,)= [c for c in product_cells if c["connections"]["Y"]!=cuts["stride"]]
        cuts["group_offset"]=group["connections"]["Y"]
    assert len(cuts)==len(product_cells)
    bad=" || ".join(k+"_address != base_address" for k in cuts)
    body=f"assign head_influence=job==7 && ({bad});\n"
    check={"head_influence":True}
    for k in cuts:
        body+=f"assign {k}_can_change=base_valid && job!=7 && {k}_address!=base_address;\n"
        check[k+"_can_change"]=False
    return table|sat(w,m,roots|cuts,out,body,check,tuple(cuts))

def embedding_checks(w,m):
    ns=lambda n:inputs(m,n)
    prod=ns("selected_product")
    c=m["cells"]["u_embedding_normalizer"]["connections"]
    assert c["input_raw_i"]==prod+[prod[-1]]*24
    assert m["cells"]["u_tied_group_reader"]["connections"]["fixed_job_i"]==list("1110")
    assert m["cells"]["u_tied_group_reader"]["connections"]["fixed_layer_i"]==list("111")
    touched=set(prod); nets=m["cells"]
    while True:
        old=len(touched)
        for n,cell in nets.items():
            if cell["type"].startswith("$") and "ff" not in cell["type"]:
                if any(touched.intersection(cell["connections"][p]) for p,d in cell["port_directions"].items() if d=="input"):
                    for p,d in cell["port_directions"].items():
                        if d=="output":touched.update(cell["connections"][p])
        if len(touched)==old:break
    sinks=[(k,p) for k,cell in nets.items() if not cell["type"].startswith("$") for p,b in cell["connections"].items() if not p.endswith("_o") and touched.intersection(b)]
    assert sinks==[("u_embedding_normalizer","input_raw_i")]
    assert not any(touched.intersection(v["bits"]) for v in m["ports"].values() if v["direction"]=="output")
    out={"raw":c["input_raw_i"],"take":ns("weight_transfer"),"state":ns("state_q"),
         "external":sum((v["bits"] for v in m["ports"].values() if v["direction"]=="output"),[])}
    checks=sat(w,m,{"product":prod},out,"""
       assign immediate_readout=product_external!=base_external;
       assign changed_accepted_input=base_take && base_state==4 && product_raw!=base_raw;
       """,{"immediate_readout":True,"changed_accepted_input":False},("product",))
    return {"only_immediate_product_sink":sinks,"sat":checks}

def local_metadata(w,prod):
    for name in ("service.sv","metadata192.memh","digests32.memh"):
        (w/name).write_bytes((prod/name).read_bytes())
    y(w,"read_verilog -DSYNTHESIS -sv service.sv; chparam -set BANKS 4 -set ADDR_W 19 board1_verified_ddr_page_service; "+
        "proc -norom; opt; write_json service.json")
    m=read(w/"service.json")["modules"]["board1_verified_ddr_page_service"]
    # The FIFO response tag may take any value for this combinational property.
    # Treat its RAM read as an input, keeping the request decoder and arbitration intact.
    roots={"word":inputs(m,"head_word"),"response_tag":inputs(m,"response_source")}
    out={k:inputs(m,k) for k in ("metadata_head","metadata_read","foreground_scan","bank_read_valid","remembered_scan")}
    return sat(w,m,roots,out,"""
        wire meta=word>=211920 && word<214248;
        assign wrong_decode=base_metadata_head!=meta;
        assign external_priority=meta && (base_foreground_scan || (|base_bank_read_valid));
        assign local_positive=meta && base_metadata_read;
        assign concurrent_prefetch_is_possible=meta && base_metadata_read && base_remembered_scan;
    """,{"wrong_decode":True,"external_priority":True,"local_positive":False,"concurrent_prefetch_is_possible":False})

def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument("repo",type=Path);a=p.parse_args()
    demo=a.repo.resolve()/"demos/simplestories-v2-5m"
    prod=demo/"hardware/project"
    recipe=(prod/"production_sources.f").read_text().splitlines()
    src=[next(s for s in recipe if Path(s).name==n+".sv") for n in (LAYER,META,EMBED)]
    build=read(demo/"prebuilt/inference/BUILD.json"); invhash=build["hardware_inputs_sha256"]
    inv=gzip.decompress((demo/"evidence/current-greedy/objects"/(invhash+".gz")).read_bytes())
    assert sha(inv)==invhash and sha((demo/"prebuilt/inference"/build["image_relative_path"]).read_bytes())==IMAGE
    inv=json.loads(inv)
    relevant=src+["service.sv","shared_token_probe.sv","uart_core.sv","metadata192.memh","digests32.memh","production_sources.f"]
    hashes={s:sha((prod/s).read_bytes()) for s in relevant}
    assert all(inv["project/"+k]==v for k,v in hashes.items())
    with tempfile.TemporaryDirectory() as tmp:
        w=Path(tmp)
        for n in src:(w/Path(n).name).write_bytes((prod/n).read_bytes())
        y(w,"read_verilog -DSYNTHESIS -sv "+" ".join(Path(s).name for s in src)+"; "+
          "".join("chparam -set ADDR_W 19 "+n+"; " for n in (LAYER,META,EMBED))+"proc -norom; opt; write_json local.json")
        modules=read(w/"local.json")["modules"]
        checks={"weight_descriptor":descriptor_checks(w,modules[LAYER],False),
                "metadata_descriptor":descriptor_checks(w,modules[META],True),
                "embedding":embedding_checks(w,modules[EMBED]),"compiled_metadata":local_metadata(w,prod)}
    print(json.dumps({"image":IMAGE,"pinned_sources_sha256":hashes,"mapped":native_sites(demo),"checks":checks},indent=2))
if __name__=="__main__":main()
