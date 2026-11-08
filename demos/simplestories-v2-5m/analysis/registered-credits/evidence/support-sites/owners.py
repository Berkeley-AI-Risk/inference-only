"""Composition checks for additional support routes on the frozen token core."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
import importlib.util
import json
from pathlib import Path
import sys
import tempfile
HERE=Path(__file__).resolve().parent
spec=importlib.util.spec_from_file_location("rest",HERE.parent/"remaining-datapath/check.py")
rest=importlib.util.module_from_spec(spec)
spec.loader.exec_module(rest)
j=rest.joint
S=rest.DP+j.S
EB="u_token_shell.u_fixed_embedding."
ES=EB+"u_tied_group_reader."

def run(w, flags):
    m=j.elaborate(w)
    m["netnames"]["rst_n"]=m["netnames"]["child_reset_n"]
    data,out,n=j.cone(m,w)
    records={}
    for name in flags:
        parts=rest.wrapper(data,out,"final").split("assign violation=")
        expr={"embedding":"(embed_payload || embed_meta) && competing",
              "address":"(proj_desc || proj_meta) && competing",
              "cover_embed":"embed_payload","cover_address":"proj_desc || proj_meta",
              "weaker_address":"(proj_desc || proj_meta) && spend",
              "weaker_embedding":"(embed_payload || embed_meta) && spend"}[name]
        (w/"audit.sv").write_text(parts[0]+"assign violation="+expr+";\nendmodule")
        j.yosys("read_json cone.json; read_verilog -sv audit.sv; hierarchy -top audit; proc; flatten; opt; "+
                "techmap; opt; abc -g AND; opt_clean; aigmap; dffunmap; aigmap; write_aiger -zinit site.aig",w)
        log=j.run(["yosys-abc","-c","read_aiger site.aig; pdr -t -T 130"],w,145)
        print(name,log.splitlines()[-1],file=sys.stderr,flush=True)
        assert ("was asserted" if name.startswith("cover_") else "Property proved") in log
        records[name]=log
    return records,{"registers":j.REGS,"free_bits":len(data["env"]),"control_cells":n}

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("checkout",type=Path);p.add_argument("--scratch",type=Path)
    p.add_argument("--flags",nargs="+",default=["address","embedding","cover_embed","cover_address"])
    a=p.parse_args()
    rest.configure()
    j.SOURCES+=["board1_fixed_embedding_lookup.sv","board1_fixed_projection_metadata_reader.sv"]
    j.REGS.update(embedding=EB+"state_q",ebstream=ES+"state_q")
    j.OBS.update(embed_payload=EB+"norm_input_valid",embed_meta=ES+"meta_start_valid",
                 proj_desc=S+"descriptor_transfer",proj_meta=S+"meta_start_valid")
    with tempfile.TemporaryDirectory() as tmp:
        w=a.scratch or Path(tmp);hashes,_,_=j.pin_files(a.checkout.resolve(),w)
        logs,cut=run(w,a.flags)
        print(json.dumps({"source_sha256":hashes,"image":j.IMAGE,"pdr":logs,"cut":cut},indent=2))
if __name__=="__main__":main()
