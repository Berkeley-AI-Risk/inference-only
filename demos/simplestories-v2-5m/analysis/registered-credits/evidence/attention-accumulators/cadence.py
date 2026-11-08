"""Prove a nine-edge occupancy bound on the baseline attention controller."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import gzip
import json
from pathlib import Path
import subprocess
import sys
import tempfile
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check import MODULE, IMAGE, RTL, read, sha, yosys

REGS = ["state_q", "coordinate_q", "workspace_read_return_q", "output_read_return_q", "shift_client_q"]

def control_cone(top):
    cells = top["cells"]
    ports = {}
    current, next_ports, reset = {}, {}, {}
    for name in REGS:
        bits = top["netnames"][name]["bits"]
        current[name] = bits
        (ff,) = [c for c in cells.values() if c["connections"].get("Q") == bits]
        assert ff["type"] == "$adffe"
        p, con = ff["parameters"], ff["connections"]
        assert [int(p[k],2) for k in ["EN_POLARITY","ARST_POLARITY","CLK_POLARITY"]] == [1,0,1]
        assert con["CLK"] == top["netnames"]["clk"]["bits"] and con["ARST"] == top["netnames"]["rst_n"]["bits"]
        reset[name] = int(p["ARST_VALUE"],2)
        next_ports[name+"_d"] = con["D"]
        next_ports[name+"_en"] = con["EN"]
    # Traverse the actual combinational next-state logic backwards to its inputs.
    # Untracked register and child outputs are independent on every edge.
    drivers = {}
    for name,c in cells.items():
        if not c["type"].startswith("$") or "ff" in c["type"]:
            continue
        for p,direction in c["port_directions"].items():
            if direction == "output":
                for bit in c["connections"][p]:
                    if isinstance(bit,int):
                        drivers[bit] = name
    current_bits = set(sum(current.values(), []))
    kept, frontier = {}, set()
    pending = sum(next_ports.values(), [])
    while pending:
        bit = pending.pop()
        if not isinstance(bit,int) or bit in current_bits:
            continue
        if bit not in drivers:
            frontier.add(bit)
            continue
        n = drivers[bit]
        if n not in kept:
            c = kept[n] = cells[n]
            for k,p in c["port_directions"].items():
                if p == "input":
                    pending.extend(c["connections"][k])
    # Give synthesis don't-care literals arbitrary fresh values each edge.
    # The proof must survive every concretization of these unspecified bits.
    last_bit=max(bit for wire in top["netnames"].values() for bit in wire["bits"] if isinstance(bit,int))
    unknowns=[]
    for c in kept.values():
        for p,direction in c["port_directions"].items():
            if direction=="input":
                bits=c["connections"][p]
                for i,bit in enumerate(bits):
                    if bit in ("x","z"):
                        last_bit+=1
                        bits[i]=last_bit
                        unknowns.append(last_bit)
    assert not any(bit in ("x","z") for bits in next_ports.values() for bit in bits)
    current["env"] = sorted(frontier) + unknowns
    for k, bits in current.items():
        ports[k] = {"direction":"input", "bits":bits}
    for k, bits in next_ports.items():
        ports[k] = {"direction":"output", "bits":bits}
    nets = {k:{"hide_name":0, "bits":v["bits"], "attributes":{}} for k,v in ports.items()}
    return {"attributes":{}, "ports":ports,"netnames":nets,"cells":kept}, current, reset

def wrapper(current, reset, window):
    lines=[f"module audit(input clk,reset_before,reset_after,input [{len(current['env'])-1}:0] env,output violation);"]
    connect=[".env(env)"]
    for name in REGS:
        w=len(current[name])
        lines += [f"reg [{w-1}:0] stored_{name}={w}'d{reset[name]};",
                  f"wire [{w-1}:0] {name}=reset_before ? {w}'d{reset[name]} : stored_{name};",
                  f"wire [{w-1}:0] {name}_d; wire {name}_en;",
                  f"always @(posedge clk) stored_{name} <= reset_after ? {w}'d{reset[name]} : ({name}_en ? {name}_d : {name});"]
        for k in [name, name+"_d", name+"_en"]:
            connect.append(f".{k}({k})")
    lines += ["cone native("+",".join(connect)+");",
              "wire charged = state_q==6'd33 || state_q==6'd24;",
              f"reg [{window-2}:0] history=0;",
              "always @(posedge clk) history <= (history<<1) | charged;",
              "assign violation=charged && (&history);","endmodule"]
    return "\n".join(lines)

def main(repo):
    demo=repo/"demos/simplestories-v2-5m"
    build=read(demo/"prebuilt/inference/BUILD.json")
    invhash=build["hardware_inputs_sha256"]
    assert build["image_sha256"]==IMAGE
    inv=gzip.decompress((demo/"evidence/current-greedy/objects"/f"{invhash}.gz").read_bytes())
    assert sha(inv)==invhash
    rtl=(demo/"hardware"/RTL).read_bytes()
    assert sha(rtl)==json.loads(inv)[RTL]
    with tempfile.TemporaryDirectory() as tmp:
        wd=Path(tmp); (wd/"attention.sv").write_bytes(rtl)
        yosys("read_verilog -DSYNTHESIS -sv attention.sv; proc; opt; write_json full.json",wd)
        cone, current, reset=control_cone(read(wd/"full.json")["modules"][MODULE])
        (wd/"cone.json").write_text(json.dumps({"modules":{"cone":cone}}))
        records={}
        for window in [9,8]:
            (wd/"audit.sv").write_text(wrapper(current,reset,window))
            cmd="read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; techmap; opt; abc -g AND; opt_clean; aigmap; dffunmap; aigmap; write_aiger -zinit model.aig"
            yosys(cmd,wd)
            run=subprocess.run(["yosys-abc","-c","read_aiger model.aig; pdr -T 60"],cwd=wd,text=True,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,timeout=75)
            if run.returncode or ("Property proved" if window==9 else "was asserted") not in run.stdout:
                raise RuntimeError(f"window={window}\n{run.stdout}")
            records[str(window)]=run.stdout.strip()
        previous=read(Path(__file__).resolve().with_name("result.json"))
        assert previous["source_sha256"]==sha(rtl) and previous["image_sha256"]==IMAGE
        f=previous["clock_hz"]
        edge_credit=previous["max_product_contributions_per_edge"]*previous["operations_per_product"]
        average_ceiling=f*edge_credit*8/9
        print(json.dumps({"source_sha256":sha(rtl),"image_sha256":IMAGE,"control_registers":REGS,
                          "control_cells":len(cone["cells"]),"arbitrary_environment_bits":len(current["env"]),
                          "max_charged_edges_in_nine":8,"one_second_25_million_edge_credit_upper":edge_credit*(f-f//9),
                          "asymptotic_operation_credit_per_second_upper":average_ceiling,
                          "asymptotic_channel_proxy_upper":average_ceiling*previous["R_fixed128"]/
                          (previous["accounting_normalizer_H"]*previous["F_fixed128"]),
                          "inductive_check":records},indent=2))
if __name__=="__main__":
    cli=argparse.ArgumentParser(description=__doc__)
    cli.add_argument("checkout",type=Path)
    main(cli.parse_args().checkout.resolve())
