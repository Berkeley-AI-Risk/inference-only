"""Joint credit audit of the pinned SimpleStories RTL, using a free-environment control cone."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import gzip
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile

HERE = Path(__file__).resolve().parent
TOP = "board1_context2048_semantic_datapath"
J = "u_projection."
S = J + "u_group_stream."
A = J + "u_shared_engine."
E = A + "u_engine."
SOURCES = [
    TOP + ".sv", "board1_context2048_attention.sv", "board1_fixed_group_projection_scale_job.sv",
    "board1_fixed_group_ddr_stream.sv", "cluster-adapter.sv", "cluster-tile.sv", "cluster-engine.sv"
]
REGS = {
    "parent": "engine_state_q", "fault": "fault_q", "started": "service_start_seen_q",
    "done_seen": "service_done_seen_q", "att": "u_attention.state_q", "attfail":"u_attention.range_fault_o",
    "job": J+"state_q", "jobfail": J+"fail_q", "stream_done_seen": J+"stream_done_seen_q",
    "engine_done_seen": J+"engine_done_seen_q", "stream": S+"state_q", "streamfail": S+"fail_closed_q",
}
OBS = {"header": S+"group_valid_o", "weight": S+"weight_valid_o",
       "engine_start": E+"start_fire", "engine_meta": E+"metadata_fire", "engine_weight": E+"weight_fire"}
COMMON = {"clear":"clear_i","lock":"model_lock_i","upfault":"upstream_fault_i","rst_n":"rst_n"}
IMAGE="01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"

def digest(b):
    return hashlib.sha256(b).hexdigest()

def read(path):
    return json.loads(path.read_bytes())

def run(command, wd, timeout=120):
    p=subprocess.run(command,cwd=wd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=timeout)
    if p.returncode:
        raise RuntimeError(p.stdout[-4000:])
    return p.stdout

def yosys(script, wd):
    return run(["yosys","-Q","-T","-p",script],wd)

def elaborate(wd):
    yosys("read_verilog -sv defines.v "+" ".join(SOURCES)+"; hierarchy -top "+TOP+
          "; proc -norom; flatten; opt; write_json full.json",wd)
    return read(wd/"full.json")["modules"][TOP]

def pin_files(repo, wd):
    demo=repo/"demos/simplestories-v2-5m"
    project=demo/"hardware/project"
    build=read(demo/"prebuilt/inference/BUILD.json")
    image=demo/"prebuilt/inference"/build["image_relative_path"]
    assert digest(image.read_bytes())==build["image_sha256"]==IMAGE
    h=build["hardware_inputs_sha256"]
    inv=gzip.decompress((demo/"evidence/current-greedy/objects"/(h+".gz")).read_bytes())
    assert digest(inv)==h
    inv=json.loads(inv)
    recipe=(project/"production_sources.f").read_text().splitlines()
    paths={Path(name).name:name for name in recipe}
    source_hash={}
    for name in SOURCES+["defines.v","production_sources.f"]:
        path=paths.get(name,name)
        data=(project/path).read_bytes()
        assert digest(data)==inv["project/"+path]
        (wd/name).write_bytes(data)
        source_hash[path]=digest(data)
    assert (wd/"defines.v").read_text().splitlines()==["`define SYNTHESIS","`define BOARD1_PROJECTION_MAC_NATIVE"]
    census=read(demo/"evidence/current-greedy/baseline/analysis/mapped-census.json")
    assert census["image_sha256"]==IMAGE and census["total_multiplier_instances"]==90
    assert census["functional_group_counts"]==dict(projection_lanes=64, attention_score=8, attention_value=8,
        projection_scaling=2, rmsnorm=2, feed_forward=1, metadata_support=3, embedding_support=1, projection_stride_support=1)
    remainder={group:[v["instance"] for v in census["mapped_instances"] if v["group"]==group]
               for group in ("projection_scaling","rmsnorm","feed_forward","metadata_support","embedding_support","projection_stride_support")}
    assert all(len(v)==census["functional_group_counts"][k] for k,v in remainder.items())
    return source_hash,remainder,census

def net(m,name):
    return m["netnames"][name]["bits"]

def cone(m, wd):
    data={key:net(m,name) for key,name in (REGS|COMMON).items()}
    outputs={key:net(m,name) for key,name in OBS.items()}
    drivers={}
    for name,c in m["cells"].items():
        for pin,d in c.get("port_directions",{}).items():
            if d=="output":
                for bit in c["connections"][pin]:
                    if isinstance(bit,int):
                        assert bit not in drivers
                        drivers[bit]=(name,pin)
    for k in REGS:
        b=data[k]
        name,pin=drivers[b[0]]
        c=m["cells"][name]
        ff=c["connections"]
        assert pin=="Q" and ff["Q"]==b and c["type"] in ("$adffe","$adff")
        assert ff["ARST"]==net(m,"rst_n") and ff["CLK"]==net(m,"clk")
        p=c["parameters"]
        assert int(p["ARST_VALUE"],2)==int(p["ARST_POLARITY"],2)==0 and int(p["CLK_POLARITY"],2)==1
        if "EN_POLARITY" in p: assert int(p["EN_POLARITY"],2)==1
        outputs[k+"_d"]=ff["D"]
        outputs[k+"_en"]=ff.get("EN",["1"])
    # Unknown child outputs and untracked FF contents are independent on every edge.
    # Also abstract large arithmetic/selector cells. Keep the actual clocked controls.
    root=set(sum(data.values(),[]))
    def inputs(cell):
        return [bit for pin,d in cell["port_directions"].items() if d=="input" for bit in cell["connections"][pin]]
    def control_cell(bit):
        if bit not in drivers:
            return None
        name,pin=drivers[bit]
        c=m["cells"][name]
        if c["type"] not in ("$mux","$pmux","$eq","$ne","$and","$logic_and","$logic_or","$reduce_and",
                              "$reduce_or","$reduce_bool","$not","$logic_not","$or","$eqx","$nex"):
            return None
        if len(c["connections"][pin])>16:
            return None
        return name
    frontier=set()
    cells={}
    todo=sum(outputs.values(),[])
    while todo:
        bit=todo.pop()
        if not isinstance(bit,int) or bit in root:
            continue
        name=control_cell(bit)
        if name is None:
            frontier.add(bit)
        elif name not in cells:
            c=cells[name]=m["cells"][name]
            todo.extend(inputs(c))
    fresh=max(bit for nn in m["netnames"].values() for bit in nn["bits"] if isinstance(bit,int))
    for c in cells.values():
        for pin,d in c["port_directions"].items():
            if d=="input":
                b=c["connections"][pin]
                for i,s in enumerate(b):
                    if s in ("x","z"):
                        fresh+=1; b[i]=fresh; frontier.add(fresh)
    assert not root & frontier
    assert not any(b in ("x","z") for v in outputs.values() for b in v)
    data["env"]=sorted(frontier)
    ports={k:dict(direction="input",bits=v) for k,v in data.items()}
    ports.update({k:dict(direction="output",bits=v) for k,v in outputs.items()})
    names={k:dict(hide_name=0,bits=v["bits"],attributes={}) for k,v in ports.items()}
    (wd/"cone.json").write_text(json.dumps(dict(modules={"cone":dict(attributes={},ports=ports,cells=cells,netnames=names)})))
    return data,outputs,len(cells)

def make_model(data,outputs,kind):
    if kind=="gates":
        ports=[f"input [{len(bits)-1}:0] {k}" for k,bits in data.items()]
        lines=["module audit("+",".join(ports+["output violation"])+");"]
        lines+=[f"wire {k};" for k in OBS]
        lines+=["cone native("+",".join(f".{k}({k})" for k in list(data)+list(OBS))+");",
                "assign violation=((engine_start || engine_meta) && !header) || (engine_weight && !weight);","endmodule"]
        return "\n".join(lines)
    ports=["input clk,reset_before,reset_after","output violation"]
    for k in list(COMMON)+["env"]:
        if k!="rst_n": ports.append(f"input [{len(data[k])-1}:0] {k}")
    lines=["module audit("+",".join(ports)+");","wire rst_n=!reset_before;"]
    for k in REGS:
        width=len(data[k])
        lines.extend([f"reg [{width-1}:0] q_{k}=0;",
                      f"wire [{width-1}:0] {k}=reset_before ? 0 : q_{k};",
                      f"always @(posedge clk) q_{k} <= (reset_before || reset_after) ? 0 : ({k}_en ? {k}_d : {k});"])
    lines += [f"wire [{len(bits)-1}:0] {k};" for k,bits in outputs.items()]
    lines+=["cone native("+",".join(f".{k}({k})" for k in list(data)+list(outputs))+");",
            "wire charged=(att==6'd33 || att==6'd24);",
            "wire money=header || weight;",
            "reg [1:0] h=0; always @(posedge clk) h<={h[0],money};"]
    # Independent of how many of those four state transitions/credit sites are enabled.
    props={"joint":"charged && (money || (|h))",
           "wrong_all_attention_states":"(att==0) && engine_weight",
           "attention_reachable":"charged", "mutant_overlap":"charged && engine_weight"}
    return "\n".join(lines+["assign violation="+props[kind]+";","endmodule"])

def prove(wd,data,outputs,kind):
    (wd/"audit.sv").write_text(make_model(data,outputs,kind))
    if kind=="gates":
        log=yosys("read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; sat -verify -prove violation 0",wd)
        assert "no model found: SUCCESS!" in log
        return "SAT: no model found for any simultaneous gate violation"
    yosys("read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; techmap; opt; abc -g AND; opt_clean; aigmap; dffunmap; aigmap; write_aiger -zinit model.aig",wd)
    log=run(["yosys-abc","-c","read_aiger model.aig; pdr -T 60"],wd,75)
    return log

def potential_check(wd,census):
    spec=importlib.util.spec_from_file_location("projection_proof",HERE.parent/"projection-lanes/check.py")
    prior=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(prior)
    yosys("read_verilog -sv defines.v cluster-tile.sv cluster-engine.sv; proc -norom; opt; write_json local.json",wd)
    m=read(wd/"local.json")["modules"]
    prior.topology(m,census)
    prior.check_sat(wd,m[prior.TILE],["op_valid_q","product_valid_q"],["accept_i","kill_i","begin_i"],
        {"multiply_tag_error":True,"accumulate_tag_error":True,"uninterrupted_tags":False},"""
        assign multiply_tag_error=n_op_valid_q != (reset_n && !kill_i && !begin_i && accept_i);
        assign accumulate_tag_error=n_product_valid_q != (reset_n && !kill_i && !begin_i && op_valid_q);
        assign uninterrupted_tags=n_op_valid_q && n_product_valid_q;
        """)
    # Re-run the frozen projection budget theorem as well as the new conditional lemma.
    assert "budget_failure" in prior.prove_budget(m[prior.ENGINE],wd)
    template="""({p}state_q==1 ? 32'd682*(32'd1+{p}metadata_count_q) :
        ({p}state_q==2 ? 32'd65*(32'd0+{p}columns_q-{p}column_q) : 32'd0))"""
    expression="wire [31:0] p="+template.format(p="")+",p_next="+template.format(p="n_")+";"
    # Counters need not be reachable for a held phase, but subtracting at illegal values
    # could underflow. Use exactly the old reachable descriptor and counter shape.
    expression+="""
    wire sizes=(columns_q==682 && valid_lanes_q==64) ||
        (columns_q==256 && (valid_lanes_q==42 || valid_lanes_q==51 || valid_lanes_q==64));
    wire shape=(state_q!=1 && state_q!=2) || (sizes &&
        (state_q!=1 || (metadata_count_q<valid_lanes_q && column_q==0)) &&
        (state_q!=2 || column_q<columns_q));
    assign gain=shape && !(start_fire || metadata_fire || weight_fire) && p_next>p;
    assign bad_strengthening=shape && start_fire && p_next>p;
    """
    checks={"gain":True,"bad_strengthening":False}
    prior.check_sat(wd,m[prior.ENGINE],prior.REGS,["start_fire","metadata_fire","weight_fire"],checks,expression)
    return {"gross_budget_reproduced":True,"native_topology_64_sites_rechecked":True,
            "exact_two_stage_credit_propagation_rechecked":True,"no_gain_without_fires":True,"start_can_gain":True}

def bound():
    proj=read(HERE.parent/"projection-lanes/result.json")
    att=read(HERE.parent/"attention-accumulators/result.json")
    cadence=read(HERE.parent/"attention-accumulators/cadence-result.json")
    assert proj["image_sha256"]==att["image_sha256"]==cadence["image_sha256"]==IMAGE
    assert att["operations_per_product"]==2 and att["max_product_contributions_per_edge"]==8
    assert proj["head_and_projection_lane_sites"]==64 and proj["max_nonnegative_potential"]==44330
    assert att["clock_hz"]==proj["clock_hz"]==25_000_000 and cadence["max_charged_edges_in_nine"]==8
    n=att["clock_hz"]
    def credit(a,carry):
        return 128*min(n-a,(682*(n-a)+carry)//747)+16*a
    # Increasing a by two reduces the projection beat bound by at least one.
    gross=128*682*n/747
    proxy=gross*proj["R"]/(proj["H"]*proj["F"])
    return dict(clock_hz=n,reference={"H":proj["H"],"R":proj["R"],"F":proj["F"]},projection_lane_sites=64,
                attention_score_sites=8,attention_value_sites=8,admission_to_multiply_edges=1,
                admission_to_accumulate_edges=2,potential_max=44330,asymptotic_gross_ops_per_second=gross,
                proxy=proxy,old_separate_sum=proj["scoped_measured_proxy_upper"]+cadence["asymptotic_channel_proxy_upper"],
                arbitrary_reachable_one_second_window_ops=max(credit(a,44330) for a in (0,1)),
                one_second_from_reset_ops=max(credit(a,0) for a in (0,1)),demonstrated_useful_training_rate=None)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("checkout",type=Path)
    a=parser.parse_args()
    with tempfile.TemporaryDirectory() as temp:
        wd=Path(temp)
        hashes,remainder,census=pin_files(a.checkout.resolve(),wd)
        local=potential_check(wd,census)
        m=elaborate(wd)
        data,outputs,ncells=cone(m,wd)
        report={}
        for check in ("gates","joint","wrong_all_attention_states","attention_reachable"):
            log=prove(wd,data,outputs,check)
            report[check]=log
            print(check,log.splitlines()[-1], file=sys.stderr,flush=True)
            assert ({"joint":"Property proved","gates":"no model found"}.get(check,"was asserted")) in log
        # Defect control: an idle attention service can start score work without an owner.
        src=wd/"board1_context2048_attention.sv"
        original=src.read_text()
        snippet="range_fault_o <= 1'b0;\n                    if (start_valid_i && start_ready_o) begin"
        assert original.count(snippet)==1
        src.write_text(original.replace(snippet,"range_fault_o <= 1'b0;\n                    "+
                                        "if (!start_valid_i && fixed_position_i[0]) state_q <= ST_SCORE_QUERY_USE;\n"+
                                        "                    else if (start_valid_i && start_ready_o) begin"))
        mutated=elaborate(wd)
        data2,outputs2,_=cone(mutated,wd)
        for check in ("joint","mutant_overlap"):
            log=prove(wd,data2,outputs2,check)
            assert "was asserted" in log
            report["unscheduled_score_"+check]=log
        print(json.dumps({"source_commit":"159528e36d46fc803326758b160aa5e84aebd72b","image":IMAGE,
                          "yosys":run(["yosys","-V"],wd).strip(),"source_sha256":hashes,"tracked_registers":REGS,"control_cells":ncells,
                          "free_environment_bits":len(data["env"]),"pdr_and_controls":report,
                          "projection_potential":local,"bound":bound(),"remaining_mapped_instances":remainder},indent=2))

if __name__=="__main__":
    main()
