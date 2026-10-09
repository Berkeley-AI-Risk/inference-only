"""Re-elaborate and audit the page-bank theorem, boundary and scenario records."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess

TOP = "board1_verified_page_bank"
BANK_SHA = "ced8becfe26c4a733058119f5ec4c88025377973b09411f0ae5141ca9f594aa1"
MONITOR_SHA = "f6d7302e046d4d74c7e849c6e425b2491d62f5ede91fcaf90d67f57b28cb7c9a"
STUB_SHA = "256c5c168a96ce25359705f8e8f2cbdd52010fcd82597f8e07419efce133aa7b"
TB_SHA = "e063f3a6f2f6fbd7dc586b1ebe253cae3d8f1ad13234a931e9a200316e163a54"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def observer_cone(module):
    def bits(value):
        return {bit for bit in value if isinstance(bit, int)}
    cells, nets = module["cells"], module["netnames"]
    selector = bits(nets["f_address"]["bits"])
    constants = [cell for cell in cells.values() if cell["type"] == "$anyconst"]
    assert len(constants) == 1 and bits(constants[0]["connections"]["Y"]) == selector
    assert len(selector) == 7 and int(constants[0]["parameters"]["WIDTH"], 2) == 7
    edges, memory_sinks, observer_ports = [], set(), []
    for name, cell in cells.items():
        ports, directions = cell["connections"], cell["port_directions"]
        if cell["type"] == "$mem_v2":
            params = cell["parameters"]
            width, abits, reads = (int(params[key], 2) for key in ("WIDTH", "ABITS", "RD_PORTS"))
            assert width == 256 and abits == 7 and reads == 2
            assert int(params["SIZE"], 2) == 128 and int(params["WR_PORTS"], 2) == 1
            assert len(params["INIT"]) == 32768 and set(params["INIT"]) == {"x"}
            writes = set().union(*(bits(value) for port, value in ports.items() if port.startswith("WR_")))
            memory_sinks |= writes
            edges.append((name+":writes", writes, bits(ports["RD_DATA"])))
            for index in range(reads):
                addr = ports["RD_ADDR"][abits*index:abits*(index+1)]
                inputs = bits(addr) | set().union(*(bits([ports[port][index]])
                    for port in ("RD_CLK", "RD_EN", "RD_ARST", "RD_SRST")))
                outputs = bits(ports["RD_DATA"][width*index:width*(index+1)])
                if addr == nets["f_address"]["bits"]:
                    observer_ports.append(index)
                    assert ports["RD_EN"][index] == "1" and ports["RD_ARST"][index] == ports["RD_SRST"][index] == "0"
                else:
                    memory_sinks |= inputs
                edges.append((name+":read-"+str(index), inputs, outputs))
        else:
            inputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == "input"))
            outputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == "output"))
            edges.append((name, inputs, outputs))
    assert len(observer_ports) == 1
    reached = set(selector)
    while True:
        new = set().union(*(outputs for _, inputs, outputs in edges if inputs & reached))
        if new <= reached:
            break
        reached |= new
    protected = {name: bits(row["bits"]) for name, row in nets.items()
                 if not row["hide_name"] and not name.startswith("f_")}
    protected.update({name: bits(row["bits"]) for name, row in module["ports"].items()})
    hits = [name for name, value in protected.items() if reached & value]
    assert not hits and not (reached & memory_sinks), hits
    return {"selector_bits": sorted(selector), "reached_bits": sorted(reached),
            "extra_read_only_observer_port": observer_ports[0],
            "production_signal_hits": hits, "production_memory_sink_hits": [],
            "edges": [{"name": name, "inputs": sorted(inputs & reached), "outputs": sorted(outputs)}
                      for name, inputs, outputs in edges if inputs & reached]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("run", "proof", "scenarios", "package"):
        parser.add_argument("--"+name, type=Path, required=True)
    parser.add_argument("--verify-only", action="store_true")
    parser.add_argument("--yosys", default="yosys")
    args = parser.parse_args()
    run, proof, scenarios, package = (getattr(args, name).resolve() for name in ("run", "proof", "scenarios", "package"))
    root = Path(os.path.commonpath([run, proof, scenarios, package]))
    if args.verify_only:
        record = json.loads((run/"FINISHED.json").read_text())
        assert record["passed"]
        for name, value in record["checked_sha256"].items():
            assert sha((root/name).read_bytes()) == value, name
        for name, value in record["outputs_sha256"].items():
            assert sha((run/name).read_bytes()) == value, name
        print("BANK_AUDIT_VERIFY_ONLY PASS")
        return
    checked = {}

    def read(path, expected=None):
        assert not path.is_symlink()
        data = path.read_bytes()
        value = sha(data)
        if expected is not None:
            assert value == expected, path
        checked[str(path.relative_to(root))] = value
        return data

    inputs_raw = read(proof/"INPUTS.json")
    inputs = json.loads(inputs_raw)
    finished = json.loads(read(proof/"FINISHED.json"))
    assert finished["passed"] and finished["inputs_sha256"] == sha(inputs_raw)
    assert finished["assertions"] == inputs["assertions"] == 42 and inputs["induction_length"] == 2
    manifest = json.loads(read(package/"MANIFEST.json", inputs["manifest_sha256"]))["files"]
    bank = read(package/"hardware/project/bank.sv", BANK_SHA)
    assert sha(bank) == manifest["hardware/project/bank.sv"]["sha256"]
    assert read(proof/"production.sv") == bank
    original_sha = read(package/"hardware/project/sha.sv", inputs["sha_source_not_elaborated_sha256"])
    assert sha(original_sha) == manifest["hardware/project/sha.sv"]["sha256"]
    assert read(proof/"production-sha-not-elaborated.sv") == original_sha
    for name, row in inputs["files"].items():
        assert len(read(proof/name, row["sha256"])) == row["bytes"]
    monitor = read(proof/"monitor.inc.sv", MONITOR_SHA)
    read(proof/"sha_boundary.sv", STUB_SHA)
    assert read(proof/"bank.sv") == bank.replace(b"\nendmodule", b"\n"+monitor+b"\nendmodule")
    clean = re.sub(r"//[^\n]*", "", monitor.decode())
    while "assert(" in clean:
        begin = clean.index("assert(")
        end, depth = begin+len("assert("), 1
        while depth:
            depth += (clean[end] == "(") - (clean[end] == ")")
            end += 1
        clean = clean[:begin]+clean[end:]
    assignments = re.findall(r"\b(\w+)\s*(?:\[[^;]*?\])?\s*<=", clean)
    assert assignments and all(name.startswith("f_") for name in assignments)
    assert not re.search(r"\b(assume|force|assign|input|output|module|initial)\b", clean)
    run.mkdir(parents=True, exist_ok=False)
    (run/"auditor.py").write_bytes(Path(__file__).read_bytes())
    replay = run/"elaboration-replay"
    replay.mkdir()
    for name in inputs["files"]:
        (replay/name).write_bytes((proof/name).read_bytes())
    with (replay/"yosys.log").open("w") as output:
        proc = subprocess.run([shutil.which(args.yosys), "-Q", "prove.ys"], cwd=replay,
                              stdout=output, stderr=subprocess.STDOUT, timeout=60)
    assert proc.returncode == 0
    for name in ("design.smt2", "elaborated.json", "elaborated.il"):
        assert read(proof/name) == (replay/name).read_bytes(), name
    design = json.loads((replay/"elaborated.json").read_text())
    assert set(design["modules"]) == {TOP}
    module = design["modules"][TOP]
    kinds = [cell["type"] for cell in module["cells"].values()]
    assert kinds.count("$assert") == 42 and kinds.count("$anyseq") == 3 and kinds.count("$anyconst") == 1
    assert kinds.count("$mem_v2") == 1 and "$assume" not in kinds and all(kind.startswith("$") for kind in kinds)
    cone = observer_cone(module)
    (run/"OBSERVER-CONE.json").write_text(json.dumps(cone, indent=2)+"\n")
    smt = (replay/"design.smt2").read_text()
    for suffix in ("h", "u"):
        assert f"(define-fun |{TOP}_{suffix}| ((state |{TOP}_s|)) Bool true)" in smt
    constants = re.findall(r"^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)", smt, re.M)
    assert len(constants) == 1 and constants[0][1] == "7" and constants[0][2].endswith(" f_address")
    assert f"(= (|{constants[0][0]}| state) (|{constants[0][0]}| next_state))" in smt.split(f"(define-fun |{TOP}_t|", 1)[1]
    assert set(finished["solver_results"]) == {s+"-"+q for s in ("z3", "cvc5") for q in ("base", "induction")}
    for label, row in finished["solver_results"].items():
        assert row["passed"] and row["exit"] == 0
        kind = label.split("-", 1)[1]
        query = read(proof/(kind+".smt2"), row["query_sha256"]).decode()
        log = read(proof/(label+".log"), row["log_sha256"]).decode()
        assert log.splitlines() == (["sat", "unsat"] if kind == "base" else ["unsat"])
        assert query.count(smt) == 1 and query.partition(smt)[0] == "(set-logic ALL)\n(set-option :produce-models true)\n"
        expected = []
        for step in range(3):
            expected += [f"(declare-fun s{step} () {TOP}_s)", f"(assert ({TOP}_h s{step}))",
                         f"(assert ({TOP}_u s{step}))",
                         f"(assert (= ({TOP}_is s{step}) {'true' if kind == 'base' and step == 0 else 'false'}))"]
            if step:
                expected += [f"(assert ({TOP}_t s{step-1} s{step}))"]
        if kind == "base":
            expected += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n| s0)))",
                         f"(assert (not (|{TOP}_n reset_n| s1)))", "(check-sat)",
                         f"(assert (not (and ({TOP}_a s0) ({TOP}_a s1) ({TOP}_a s2))))", "(check-sat)"]
        else:
            expected += [f"(assert ({TOP}_a s0))", f"(assert ({TOP}_a s1))",
                         f"(assert (not ({TOP}_a s2)))", "(check-sat)"]
        assert query.partition(smt)[2].strip().splitlines() == expected
    check_inputs_raw = read(scenarios/"INPUTS.json")
    check_inputs = json.loads(check_inputs_raw)
    check_finished = json.loads(read(scenarios/"FINISHED.json"))
    assert check_finished["passed"] and check_finished["inputs_sha256"] == sha(check_inputs_raw)
    read(scenarios/"runner.py", check_inputs["runner_sha256"])
    tb = read(scenarios/"testbench.sv", TB_SHA)
    assert check_inputs["production_sha256"] == BANK_SHA and check_inputs["testbench_sha256"] == TB_SHA
    names = {"digest-bypass", "early-verified", "sealed-write", "cancel-clears-fault", "wrong-sha-bytes"}
    assert set(check_inputs["mutations"]) == names and set(check_finished["results"]) == names|{"good"}
    for name, row in check_finished["results"].items():
        assert row["passed"] and row["compile_exit"] == 0
        assert read(scenarios/name/"tb.sv") == tb
        source = read(scenarios/name/"bank.sv", row["source_sha256"])
        read(scenarios/name/"compile.log")
        log = read(scenarios/name/"simulation.log", row["log_sha256"]).decode()
        if name == "good":
            assert source == bank and row["simulation_exit"] == 0
            assert log.splitlines()[0] == "BANK_SCENARIOS_PASS scenarios=10 hash_blocks=195" and "FATAL" not in log
        else:
            mutation = check_inputs["mutations"][name]
            old, new = mutation["old"].encode(), mutation["new"].encode()
            assert bank.count(old) == 1 and source == bank.replace(old, new)
            assert row["simulation_exit"] == 1 and row["expected_fault"] == mutation["expected"]
            assert "FATAL:" in log and mutation["expected"] in log and "BANK_SCENARIOS_PASS" not in log
    outputs = {str(path.relative_to(run)): sha(path.read_bytes()) for path in run.rglob("*") if path.is_file()}
    receipt = {"passed": True, "checked_sha256": checked, "outputs_sha256": outputs,
               "assertions": 42, "both_solvers_complete": True, "observer_drives_production": False,
               "real_ram_bits": 32768, "sha_replies_unconstrained_bits": 258,
               "directed_scenarios": 10, "detected_faulty_variants": 5,
               "scope": "Source/query/observer audit of component safety and directed fixture checks, not SHA or whole-machine refinement.",
               "hardware_access": False, "network_access": False}
    (run/"FINISHED.json").write_text(json.dumps(receipt, indent=2)+"\n")
    print("BANK_AUDIT PASS")


if __name__ == "__main__":
    main()
