"""Bound the remaining arithmetic sites through the frozen token-machine controllers."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile

HERE=Path(__file__).resolve().parent

def import_proof(name, filename):
    spec=importlib.util.spec_from_file_location(name,filename)
    mod=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod

joint=import_proof("joint_credit",HERE.parent/"joint-cadence/check.py")
DP="u_six_layers.u_datapath."
E=DP+joint.E
EL=DP+"u_elementwise_lane.u_fixed_elementwise_product_compact_lane."
RMS=DP+"u_rmsnorm."
FINAL="u_token_shell.u_final_rmsnorm."
ADD_SOURCES=["board1_context2048_token_machine_core.sv","board1_context2048_token_shell.sv",
    "board1_context2048_semantic_layer.sv","board1_context2048_semantic_sequence.sv",
    "board1_fixed_vector_rmsnorm_service.sv","board1_fixed_elementwise_lane_core.sv",
    "board1_fixed_elementwise_product_compact_lane.sv","normalizer_pipeline.sv"]
ORIGINAL_REGS=joint.REGS.copy()

def configure():
    joint.TOP="board1_context2048_token_machine_core"
    joint.SOURCES+=ADD_SOURCES
    joint.REGS={k:DP+v for k,v in ORIGINAL_REGS.items()}
    joint.REGS.update({"shell":"u_token_shell.state_q","sequence":"u_six_layers.u_sequence.state_q",
        "shell_fails":"u_token_shell.fail_q","head_seen":"u_token_shell.head_done_seen_q",
        "winner_seen":"u_token_shell.winner_seen_q","elem_phase":DP+"elem_phase_q","rope_phase":DP+"rope_phase_q",
        "norm_phase":DP+"u_normalizer.state_q","norm_done":DP+"norm_done_seen_q","output_done":DP+"output_done_q",
        "seqfault":"u_six_layers.u_sequence.fault_q","rms":RMS+"state_q","final_rms":FINAL+"state_q",
        "elem":EL+"state_q","engine":E+"state_q","scale_tags":E+"scale_valid_q"})
    joint.OBS={"engine_start":E+"start_fire","engine_meta":E+"metadata_fire","engine_weight":E+"weight_fire",
               "advance":E+"advance","issue":E+"issue"}
    joint.COMMON={"clear":"u_token_shell.clear_i","lock":"model_locked_i","rst_n":"child_reset_n"}

def wrapper(data,outputs,kind):
    ports=["input clk,reset_before,reset_after","output violation"]
    for k in list(joint.COMMON)+["env"]:
        if k!="rst_n": ports.append(f"input [{len(data[k])-1}:0] {k}")
    lines=["module audit("+",".join(ports)+");","wire rst_n=!reset_before;"]
    for k in joint.REGS:
        width=len(data[k])
        lines.extend([f"reg [{width-1}:0] q_{k}=0;",
                      f"wire [{width-1}:0] {k}=reset_before ? 0 : q_{k};",
                      f"always @(posedge clk) q_{k} <= (reset_before || reset_after) ? 0 : ({k}_en ? {k}_d : {k});"])
    lines += [f"wire [{len(bits)-1}:0] {k};" for k,bits in outputs.items()]
    lines+=["cone native("+",".join(f".{k}({k})" for k in list(data)+list(outputs))+");",
            "wire att_use=att==33 || att==24;",
            "wire rms_use=rms==3 || rms==11 || rms==12;",
            "wire final_use=final_rms==3 || final_rms==11 || final_rms==12;",
            "wire elem_use=(elem>=1 && elem<=4) || elem==7;",
            "wire partial_use=advance && scale_tags[1];",
            "wire merge_use=advance && scale_tags[2];",
            "wire spend=engine_start || engine_meta || engine_weight;",
            "reg [1:0] h=0; always @(posedge clk) h<={h[0],spend};",
            "wire competing=spend || (|h);"]
    props={"rms":"rms_use && competing","final":"final_use && competing","elem":"elem_use && competing",
           "cover_rms":"rms_use","cover_final":"final_use","cover_elem":"elem_use",
           "cover_post":"partial_use && merge_use","cover_weight":"engine_weight"}
    return "\n".join(lines+["assign violation="+props[kind]+";","endmodule"])

def run_owners(wd,names):
    m=joint.elaborate(wd)
    m["netnames"]["rst_n"]=m["netnames"]["child_reset_n"]
    data,outputs,size=joint.cone(m,wd)
    results={}
    for name in names:
        (wd/"audit.sv").write_text(wrapper(data,outputs,name))
        joint.yosys("read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; "+
                    "techmap; opt; abc -g AND; opt_clean; aigmap; dffunmap; aigmap; write_aiger -zinit site.aig",wd)
        # ABC's internal abstraction/refinement option supplies a shorter invariant for final RMS.
        command="read_aiger site.aig; pdr "+("-t " if name=="final" else "")+"-T 135"
        log=joint.run(["yosys-abc","-c",command],wd,150)
        expect="was asserted" if name.startswith("cover_") else "Property proved"
        print(name,log.splitlines()[-1],file=sys.stderr,flush=True)
        assert expect in log
        results[name]=log
    return results,dict(tracked_registers=joint.REGS.copy(),free_bits=len(data["env"]),control_cells=size)

def local_sites(wd):
    prior=import_proof("projection_proof",HERE.parent/"projection-lanes/check.py")
    site=import_proof("site_checks",HERE/"site_checks.py")
    sources="defines.v cluster-tile.sv cluster-engine.sv board1_fixed_vector_rmsnorm_service.sv "+\
            "board1_fixed_elementwise_product_compact_lane.sv board1_fixed_elementwise_dsp_lane.sv board1_fixed_elementwise_product_dsp.sv"
    joint.yosys("read_verilog -sv "+sources+"; proc -norom; opt; write_json local.json",wd)
    m=joint.read(wd/"local.json")["modules"]
    tests={"postscale":site.postscale(prior,m,wd),
           "each_rms":site.service(prior,m["board1_fixed_vector_rmsnorm_service"],wd,"rms"),
           "elementwise":site.service(prior,m["board1_fixed_elementwise_product_compact_lane"],wd,"elem")}
    # Pin each of the five physical multiply sites to the selected signed product and port widths.
    def product(module,pins):
        assert all(len(module["ports"][k]["bits"])==width for k,width in pins.items())
        (mul,)=[c for c in module["cells"].values() if c["type"]=="$mul"]
        assert int(mul["parameters"]["A_SIGNED"],2)==int(mul["parameters"]["B_SIGNED"],2)==1
        return {k:len(v) for k,v in mul["connections"].items()}
    widths={"each_postscale":product(m["board1_projection_postscale_mul"],{"a_i":27,"b_i":18,"product_o":48}),
            "each_rms":product(m["board1_fixed_elementwise_dsp_lane"],{"activation_i":16,"dynamic_operand_i":16,
                "direct_weight_i":10,"wide_operand_i":26,"scale_operand_i":16,"product0_o":32,"wide_product_o":48}),
            "elementwise":product(m["board1_fixed_elementwise_product_dsp"],{"first_i":16,"second_i":16,"product_o":32})}
    # Temporary mutation moves both product captures one valid tag too early.
    src=wd/"cluster-engine.sv"
    original=src.read_text()
    clause="if (scale_valid_q[1]) begin\n                low_product_q <= low_product;"
    assert original.count(clause)==1
    (wd/"mutant.sv").write_text(original.replace(clause,clause.replace("[1]","[0]")))
    joint.yosys("read_verilog -sv defines.v cluster-tile.sv mutant.sv; proc -norom; opt; write_json mutant.json",wd)
    tests["wrong_postscale_tag_mutant"]=site.postscale(prior,joint.read(wd/"mutant.json")["modules"],wd,mutant=True)
    return tests,widths

def ledger():
    previous=joint.read(HERE.parent/"joint-cadence/result.json")
    assert previous["image"]==joint.IMAGE
    b=previous["bound"]
    n=b["clock_hz"]
    assert n==25_000_000 and b["potential_max"]==44330
    def standalone(carry):
        issues=(n+(320 if carry else 0))//6
        partials=issues+(2 if carry else 0)
        merges=issues+(3 if carry else 0)
        rms_product=(n+(2 if carry else 0))//2
        rms_ops=n+int(carry)
        el_product=(4*n+(4 if carry else 0))//5
        el_ops=(6*n+(9 if carry else 0))//5
        return dict(postscale_row_issues=issues,postscale_partial_pairs=partials,postscale_merges=merges,
                    postscale_physical_product_and_add_ops=2*partials+merges,
                    postscale_semantic_row_multiplications=merges,each_rms_products=rms_product,
                    each_rms_product_and_square_add_ops=rms_ops,elementwise_products=el_product,
                    elementwise_product_and_rope_add_ops=el_ops)
    def full(carry,physical):
        secondary=16+2+2+3+(3 if physical else 1)
        def window(a):
            return 128*min(n-a,(682*(n-a)+carry)//747)+secondary*a
        return {"secondary_ops_per_union_edge":secondary,"max_25M_edge_window":max(window(0),window(1))}
    return {"coverage":{"projection":64,"attention_score":8,"attention_value":8,"postscale":2,"rms":2,"elementwise":1,
                        "datapath_total":85,"support_separate":5},
            "standalone_25M_edges_arbitrary_start":standalone(True),"standalone_25M_edges_reset":standalone(False),
            "standalone_sustained_ops_per_second":{"postscale_partial_products":2*n/6,"postscale_merge_adds":n/6,
                "postscale_row_scales":n/6,"each_rms_products":n/2,"each_rms_including_square_add":n,
                "elementwise_products":4*n/5,"elementwise_including_rope_adds":6*n/5},
            "joint_semantic_scale":{"arbitrary":full(44330,False),"reset":full(0,False)},
            "joint_physical_scale":{"arbitrary":full(44330,True),"reset":full(0,True)},
            "measured_reference":b["reference"],"clock_hz":n,
            "joint_sustained_scalar_ops_per_second":128*682*n/747,"joint_scoped_proxy":b["proxy"],
            "demonstrated_generic_training_rate":None,"whole_device_factor":None}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("checkout",type=Path)
    args=p.parse_args()
    configure()
    with tempfile.TemporaryDirectory() as temp:
        wd=Path(temp)
        pin_only=["board1_fixed_elementwise_dsp_lane.sv","board1_fixed_elementwise_product_dsp.sv"]
        joint.SOURCES+=pin_only
        hashes,remaining,census=joint.pin_files(args.checkout.resolve(),wd)
        del joint.SOURCES[-len(pin_only):]
        groups={"projection_scaling","rmsnorm","feed_forward"}
        assert sum(1 for c in census["mapped_instances"] if c["group"] in groups)==5
        local,widths=local_sites(wd)
        full_regs=joint.REGS.copy()
        full_sources=joint.SOURCES.copy()
        # The basic, more permissive control cone already proves the layer RMS exclusion.
        # Its smaller state vector finds a short inductive invariant for this particular role.
        extra={"shell_fails","head_seen","winner_seen","elem_phase","rope_phase","norm_phase","norm_done","output_done"}
        joint.REGS={k:v for k,v in full_regs.items() if k not in extra}
        joint.SOURCES=[s for s in full_sources if s!="normalizer_pipeline.sv"]
        rms,small=run_owners(wd,("rms","cover_rms"))
        joint.REGS=full_regs
        joint.SOURCES=full_sources
        other,wide=run_owners(wd,("elem","final","cover_elem","cover_final","cover_post","cover_weight"))
        print(json.dumps({"source_commit":"159528e36d46fc803326758b160aa5e84aebd72b","image":joint.IMAGE,
               "yosys":joint.run(["yosys","-V"],wd).strip(),"source_sha256":hashes,
               "source_multiplier_widths":widths,"local_step_checks_expected_prove_zero":local,
               "owner_models":{"layer_rms":small,"other_sites":wide},
               "owner_proofs_and_covers":rms|other,"ledger":ledger(),"additional_and_support_mapped_instances":remaining},indent=2))
if __name__=="__main__":
    main()
