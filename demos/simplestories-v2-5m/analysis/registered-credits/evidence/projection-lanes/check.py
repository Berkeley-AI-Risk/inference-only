"""Check the frozen 64-lane engine's per-trace credit invariant, without arithmetic assumptions."""

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

ENGINE = "board1_clustered_projection_scale2"
TILE = "board1_projection_tile16"
LANE = "board1_projection_dsp_accumulator"
REGS = ["state_q", "columns_q", "column_q", "metadata_count_q", "valid_lanes_q"]
IMAGE = "01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"

def sha(b):
    return hashlib.sha256(b).hexdigest()

def read(p):
    return json.loads(p.read_bytes())

def yosys(cmd, wd):
    p=subprocess.run(["yosys","-Q","-T","-p",cmd],cwd=wd,capture_output=True,text=True,timeout=90)
    if p.returncode: raise RuntimeError(p.stdout[-1500:]+p.stderr[-900:])
    return p.stdout

def net(module,name):
    return module["netnames"][name]["bits"]

def clocked(module, name):
    bits=net(module,name)
    (ff,)=[c for c in module["cells"].values() if c["connections"].get("Q")==bits]
    p, c=ff["parameters"],ff["connections"]
    assert ff["type"] in ("$adff","$adffe")
    assert c["ARST"]==net(module,"reset_n") and c["CLK"]==net(module,"clk")
    assert int(p["ARST_POLARITY"],2)==int(p["ARST_VALUE"],2)==0 and int(p["CLK_POLARITY"],2)==1
    if ff["type"]=="$adffe": assert int(p["EN_POLARITY"],2)==1
    return c

def make_comb(module, registers, observations):
    outputs={n:net(module,n) for n in observations}
    inputs={n:net(module,n) for n in registers}
    inputs["reset_n"]=net(module,"reset_n")
    for n in registers:
        ff=clocked(module,n)
        outputs[n+"_d"]=ff["D"]
        outputs[n+"_en"]=ff.get("EN",["1"])
    cells=module["cells"]
    drivers={}
    for name,c in cells.items():
        if c["type"].startswith("$") and "ff" not in c["type"]:
            for p,d in c["port_directions"].items():
                if d=="output":
                    for bit in c["connections"][p]:
                        if isinstance(bit,int):
                            assert bit not in drivers
                            drivers[bit]=name
    pending=sum(outputs.values(), [])
    roots=set(sum(inputs.values(), [])); boundary=set(); keep={}
    while pending:
        bit=pending.pop()
        if not isinstance(bit,int) or bit in roots:continue
        if bit not in drivers:
            boundary.add(bit)
        elif drivers[bit] not in keep:
            name=drivers[bit]; c=keep[name]=cells[name]
            for p,d in c["port_directions"].items():
                if d=="input": pending.extend(c["connections"][p])
    # Make all undetermined inputs, including Yosys don't-care literals, adversarial.
    last=max(x for n in module["netnames"].values() for x in n["bits"] if isinstance(x,int))
    for c in keep.values():
        for p,d in c["port_directions"].items():
            if d=="input":
                bits=c["connections"][p]
                for i,b in enumerate(bits):
                    if b in ("x","z"):
                        last+=1; bits[i]=last; boundary.add(last)
    inputs["env"]=sorted(boundary)
    ports={k:{"bits":v,"direction":"input"} for k,v in inputs.items()}
    ports.update({k:{"bits":v,"direction":"output"} for k,v in outputs.items()})
    nets={k:{"bits":v["bits"],"attributes":{},"hide_name":0} for k,v in ports.items()}
    module={"cells":keep,"ports":ports,"netnames":nets,"attributes":{}}
    return module,inputs,outputs

def harness(regs, inputs, outputs, checks, assertions):
    ports=[f"input [{len(v)-1}:0] {k}" for k,v in inputs.items()]
    lines=["module audit("+",".join(ports+["output "+v for v in checks])+");"]
    for k,v in outputs.items():
        lines.append(f"wire [{len(v)-1}:0] {k};")
    wired=list(inputs)+list(outputs)
    lines.append("cone native("+",".join(f".{k}({k})" for k in wired)+");")
    for k in regs:
        lines.append(f"wire [{len(inputs[k])-1}:0] n_{k}=reset_n ? ({k}_en ? {k}_d : {k}) : 0;")
    return "\n".join(lines+[assertions,"endmodule"])

def check_sat(wd,mod,regs,obs,checks,assertions):
    combo,inputs,outputs=make_comb(mod,regs,obs)
    (wd/"cone.json").write_text(json.dumps({"modules":{"cone":combo}}))
    (wd/"audit.sv").write_text(harness(regs,inputs,outputs,checks,assertions))
    prep="read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; flatten; opt; "
    passed=[]
    for name,expected in checks.items():
        cmd=f"sat {'-verify' if expected else '-falsify'} -prove {name} 0 audit"
        log=yosys(prep+cmd,wd)
        assert ("no model found: SUCCESS!" if expected else "model found: FAIL!") in log
        passed.append(name)
    return passed

def prove_budget(m,wd,skip_metadata_control=False):
    def shape(prefix):
        s,c,j,i,l=(prefix+x for x in REGS)
        allowed=f"(({c}==682 && {l}==64) || ({c}==256 && ({l}==42 || {l}==51 || {l}==64)))"
        return f"(({s}!=1 && {s}!=2) || ({allowed} && ({s}!=1 || ({i}<{l} && {j}==0)) && ({s}!=2 || {j}<{c})))"
    def credit(p):
        s,c,j,i,l=(p+x for x in REGS)
        return f"({s}==1 ? 32'd682*(32'd1+{i}) : ({s}==2 ? 32'd65*(32'd0+{c}-{j}) : 32'd0))"
    properties=f"""
        wire shape={shape('')}, shape_next={shape('n_')};
        wire [31:0] pot={credit('')}, next_pot={credit('n_')};
        wire [31:0] cost=weight_fire ? 32'd747 : 32'd0;
        assign shape_failure=shape && !shape_next;
        assign identity_failure=shape && (weight_fire && state_q!=2);
        assign cap_failure=shape && pot>32'd44330;
        assign budget_failure=shape && cost+next_pot>32'd682+pot;
        assign tight_edge=shape && weight_fire && next_pot+32'd65==pot;
        assign bootstrap_edge=shape && state_q==0 && n_state_q==1 && next_pot==682;
        assign one_credit_less_fails=shape && weight_fire && cost+next_pot>32'd681+pot;
    """
    checks={"shape_failure":True,"identity_failure":True,"cap_failure":True,"budget_failure":True,
            "tight_edge":False,"bootstrap_edge":False,"one_credit_less_fails":False}
    if skip_metadata_control:
        checks={"budget_failure":False}
        properties="\n".join(line for line in properties.splitlines() if "assign " not in line or "assign budget_failure" in line)
    return check_sat(wd,m,REGS,["weight_fire"],checks,properties)

def topology(m, census):
    eng,tile,mac=m[ENGINE],m[TILE],m[LANE]
    tiles=[c for c in eng["cells"].values() if c["type"]==TILE]
    assert len(tiles)==4
    for i in range(4):
        c=eng["cells"][f"g_tile[{i}].u_tile"]["connections"]
        assert c["accept_i"]==net(eng,"weight_fire") and c["clk"]==net(eng,"clk")
        assert c["activation_i"]==net(eng,"activation_i")
        assert c["weights_i"]==net(eng,"weight_data_i")[i*160:(i+1)*160]
    assert len([c for c in tile["cells"].values() if c["type"]==LANE])==16
    for i in range(16):
        c=tile["cells"][f"g_lane[{i}].u_mac"]["connections"]
        for port,n in [("clk","clk"),("multiply_i","op_valid_q"),("accumulate_i","product_valid_q"),
                       ("activation_i","activation_q"),("weight_i",f"weight_q[{i}]")]:
            assert c[port]==net(tile,n)
    native=mac["cells"]["u_signed_product"]
    assert native["type"]=="MULTALU27X18"
    a,b=net(mac,"weight_i"),net(mac,"activation_i")
    c=native["connections"]
    assert c["A"]==a+[a[-1]]*17 and c["B"]==b+[b[-1]]*2
    assert c["CLK"]==net(mac,"clk")+["0"] and c["CE"]==net(mac,"multiply_i")+net(mac,"accumulate_i")
    assert c["DOUT"]==net(mac,"accumulator_o")
    for key,val in dict(PREG_CLK="CLK0",OREG_CLK="CLK0",PREG_CE="CE0",OREG_CE="CE1",MULT12X12_EN="FALSE").items():
        assert native["parameters"][key]==val
    cells=[c for c in census["mapped_instances"] if c["group"]=="projection_lanes"]
    assert len(cells)==64
    pairs=set()
    for c in cells:
        match=re.search(r"g_tile\[(\d+)\].u_tile/g_lane\[(\d+)\].u_mac/u_signed_product$",c["instance"])
        assert match and c["primitive"]=="MULTALU27X18"
        assert c["observed_control_bindings"]["CLK"]=="{GND, core_clk}"
        pairs.add(tuple(map(int,match.groups())))
    assert pairs=={(i,j) for i in range(4) for j in range(16)}

def main(root):
    demo=root/"demos/simplestories-v2-5m"
    build=read(demo/"prebuilt/inference/BUILD.json"); assert build["image_sha256"]==IMAGE
    assert sha((demo/"prebuilt/inference"/build["image_relative_path"]).read_bytes())==IMAGE
    ev=demo/"evidence/current-greedy"; h=build["hardware_inputs_sha256"]
    inventory=gzip.decompress((ev/"objects"/f"{h}.gz").read_bytes())
    assert sha(inventory)==h
    files=json.loads(inventory); project=demo/"hardware/project"
    pin={}
    for name in ("defines.v","production_sources.f","cluster-engine.sv","cluster-tile.sv","cluster-adapter.sv"):
        pin[name]=sha((project/name).read_bytes())
        assert pin[name]==files["project/"+name]
    defines=(project/"defines.v").read_text().splitlines()
    assert defines==["`define SYNTHESIS","`define BOARD1_PROJECTION_MAC_NATIVE"]
    recipe=(project/"production_sources.f").read_text().splitlines()
    assert all(x in recipe for x in ("cluster-engine.sv","cluster-tile.sv","cluster-adapter.sv"))
    census=read(ev/"baseline/analysis/mapped-census.json")
    assert census["image_sha256"]==IMAGE
    with tempfile.TemporaryDirectory() as td:
        wd=Path(td)
        for f in ["defines.v","cluster-engine.sv","cluster-tile.sv"]:
            (wd/f).write_bytes((project/f).read_bytes())
        yosys("read_verilog -sv defines.v cluster-tile.sv cluster-engine.sv; proc -norom; opt; write_json all.json",wd)
        m=read(wd/"all.json")["modules"]
        topology(m,census)
        passes=prove_budget(m[ENGINE],wd)
        regs=["op_valid_q","product_valid_q"]
        ports=["accept_i","kill_i","begin_i"]
        checks={"spurious_product":True,"spurious_accum":True,"allow_advance":False}
        passes+=check_sat(wd,m[TILE],regs,ports,checks,"""
          assign spurious_product=n_op_valid_q != (reset_n && !kill_i && !begin_i && accept_i);
          assign spurious_accum=n_product_valid_q != (reset_n && !kill_i && !begin_i && op_valid_q);
          assign allow_advance=n_product_valid_q && n_op_valid_q;
        """)
        # Mutation only inside the temporary directory. Skip the mandatory metadata phase.
        src=(wd/"cluster-engine.sv").read_text()
        original="scale_valid_q <= 0; state_q <= META;"
        assert src.count(original)==1
        (wd/"mutant.sv").write_text(src.replace(original,"scale_valid_q <= 0; state_q <= WEIGHTS;"))
        yosys("read_verilog -sv defines.v cluster-tile.sv mutant.sv; proc -norom; opt; write_json mutant.json",wd)
        mutant=read(wd/"mutant.json")["modules"][ENGINE]
        assert prove_budget(mutant,wd,skip_metadata_control=True)==["budget_failure"]
    prior=read(Path(__file__).resolve().parents[1]/"attention-accumulators/result.json")
    assert prior["image_sha256"]==IMAGE
    f,R,F,H=[prior[k] for k in ("clock_hz","R_fixed128","F_fixed128","accounting_normalizer_H")]
    T=128*f*682/747
    rows={"head_and_projection_lane_sites":64,"multiplier_input_bits":[10,16],"operations_per_product":2,
          "clock_hz":f,"max_nonnegative_potential":44330,"max_accepted_weight_beats_per_edge_sustained":"682/747",
          "one_second_window_product_upper":64*min(f,(682*f+44330)//747),
          "simple_sites_only_op_credit_per_second":128*f,"sustained_operation_credit_per_second_upper":T,
          "scoped_measured_proxy_upper":T*R/(H*F),"H":H,"F":F,"R":R,"whole_system_upper":None}
    print(json.dumps({"image_sha256":IMAGE,"source_sha256":pin,"native_inventory_sha256":h,
                      "yosys":subprocess.check_output(["yosys","-V"],text=True).strip(),
                      "source_and_mapped_sites_checked":64,"native_SAT_checks":passes,
                      "skip_metadata_defect_rejected":True,**rows},indent=2))
if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("checkout",type=Path)
    main(cli.parse_args().checkout.resolve())
