"""Separate source/query/observer audit for the page-hash component theorem."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess

TOP = "kv_page_hash"
SOURCE_SHA = "3ee9a8a716916dcaba6d3434f722b301b3e4fb6b258ee429a457bb246191faba"
MUTATIONS = {
    "drop-epoch": ("128'h494f2d4b562d524f4c452d7632000000,epoch_i,",
                   "128'h494f2d4b562d524f4c452d7632000000,64'd0,"),
    "wrong-byte-order": ("byte_order[255-8*i -:8]=value[8*i +:8];",
                         "byte_order[255-8*i -:8]=value[255-8*i -:8];"),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def arbitrary_compressor_outputs(module, prefix=""):
    """Check that actual compressor replies are direct, distinct anyseq bits."""
    cells, nets = module["cells"], module["netnames"]
    outputs = [tuple(c["connections"]["Y"]) for c in cells.values() if c["type"] == "$anyseq"]
    expected = [tuple(nets[prefix + name]["bits"]) for name in ("sha_done", "sha_state")]
    assert [len(bits) for bits in expected] == [1, 256]
    assert all(isinstance(bit, int) for bits in expected for bit in bits)
    assert len(set(expected[0] + expected[1])) == 257
    assert len(outputs) == 2 and set(outputs) == set(expected)
    for local, port in (("sha_done", "done_o"), ("sha_state", "state_o")):
        assert nets[prefix + local]["bits"] == nets[prefix + "u_sha." + port]["bits"]
    return {"direct_arbitrary_reply_bits": 257, "gating_or_coupling": False}


def monitor_check(raw, production):
    text = re.sub(r"//[^\n]*", "", raw.decode())
    assert "`" not in text and "/*" not in text and not re.search(r"\bf_\w*\b", production.decode())
    count = 0
    while "assert(" in text:
        first = text.index("assert(")
        end, depth = first + len("assert("), 1
        while depth:
            depth += (text[end] == "(") - (text[end] == ")")
            end += 1
        text = text[:first] + text[end:]
        count += 1
    assert count == 45 and text.count("(* anyconst *)") == 1
    text = text.replace("(* anyconst *)", "")
    declarations = re.findall(r"\breg\s+(?:\[[^\]]+\]\s+)?([^;]+);", text)
    names = {name.strip() for row in declarations for name in row.split(",")}
    assert names and all(re.fullmatch(r"f_\w+", name) for name in names)
    wires = re.findall(r"\bwire\s+(f_\w+)\s*=[^;]*;", text)
    assert set(wires) == {"f_shape", "f_waiting"} and len(wires) == 2
    text = re.sub(r"\bwire\s+f_\w+\s*=[^;]*;", "", text)
    assignments = set(re.findall(r"\b(\w+)\s*<=", text))
    assert assignments == names - {"f_byte"}
    assert not re.search(r"(?<![<>=!])=(?!=)", text)
    assert not re.search(r"\b(assume|force|assign|input|output|inout|wire|module|initial|function|task|defparam|bind)\b", text)
    assert text.count("always_ff") == text.count("always_comb") == 1
    return {"assertions": count, "ghost_registers": sorted(names), "production_assignment_targets": []}


def byte_observer_cone(module, prefix="", total_constants=1):
    def bits(value):
        return {bit for bit in value if isinstance(bit, int)}

    nets, cells = module["netnames"], module["cells"]
    selector = bits(nets[prefix + "f_byte"]["bits"])
    constants = [c for c in cells.values() if c["type"] == "$anyconst"]
    selected = [c for c in constants if bits(c["connections"]["Y"]) == selector]
    assert len(constants) == total_constants and len(selected) == 1
    assert len(selector) == 5 and int(selected[0]["parameters"]["WIDTH"], 2) == 5
    edges = []
    for name, cell in cells.items():
        directions, ports = cell["port_directions"], cell["connections"]
        inputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == "input"))
        outputs = set().union(*(bits(value) for port, value in ports.items() if directions[port] == "output"))
        edges.append((name, inputs, outputs))
    reached = set(selector)
    while True:
        new = set().union(*(outputs for _, inputs, outputs in edges if inputs & reached))
        if new <= reached:
            break
        reached |= new
    protected = {name: bits(row["bits"]) for name, row in nets.items()
                 if not row["hide_name"] and not (name.startswith("f_") or name.startswith(prefix + "f_"))}
    protected.update({name: bits(row["bits"]) for name, row in module["ports"].items()})
    hits = [name for name, value in protected.items() if value & reached]
    assert not hits, hits
    return {"selector_bits": sorted(selector), "reached_bits": sorted(reached), "production_signal_hits": [],
            "edges": [{"name": name, "inputs": sorted(inputs & reached), "outputs": sorted(outputs)}
                      for name, inputs, outputs in edges if inputs & reached]}


def expected_query(smt, kind, depth):
    initial = kind == "base"
    assert initial or (kind == "induction" and depth == 2)
    lines = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(depth + 1):
        lines += [f"(declare-fun s{i} () {TOP}_s)", f"(assert ({TOP}_h s{i}))",
                  f"(assert ({TOP}_u s{i}))",
                  f"(assert (= ({TOP}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
        if i:
            lines.append(f"(assert ({TOP}_t s{i-1} s{i}))")
    if initial:
        lines += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n| s0)))",
                  f"(assert (not (|{TOP}_n reset_n| s1)))", "(check-sat)",
                  "(assert (not (and " + " ".join(f"({TOP}_a s{i})" for i in range(depth+1)) + ")))",
                  "(check-sat)"]
    else:
        lines += [f"(assert ({TOP}_a s0))", f"(assert ({TOP}_a s1))",
                  f"(assert (not ({TOP}_a s2)))", "(check-sat)"]
    return "\n".join(lines) + "\n"


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "proof", "drop-epoch", "wrong-byte-order", "out"):
        ap.add_argument("--" + name, type=Path, required=True)
    args = ap.parse_args()
    package, proof, epoch, order, out = (getattr(args, name).resolve()
        for name in ("package", "proof", "drop_epoch", "wrong_byte_order", "out"))
    checked = {}

    def read(path, expected=None):
        assert not path.is_symlink(), path
        raw = path.read_bytes()
        digest = sha(raw)
        if expected:
            assert digest == expected, path
        checked[str(path)] = digest
        return raw

    manifest_raw = read(package / "MANIFEST.json")
    manifest = json.loads(manifest_raw)["files"]
    source_path = "variants/kv-protected/hardware/project/kv_page_hash.sv"
    source = read(package / source_path, SOURCE_SHA)
    assert manifest[source_path]["sha256"] == SOURCE_SHA
    compressor_path = "variants/kv-protected/hardware/project/sha.sv"
    compressor = read(package / compressor_path, manifest[compressor_path]["sha256"])
    out.mkdir(parents=True, exist_ok=False)
    (out / "auditor.py").write_bytes(Path(__file__).read_bytes())
    summaries, common = {}, None
    for label, directory, depth in (("production", proof, 2), ("drop-epoch", epoch, 4), ("wrong-byte-order", order, 8)):
        negative = label != "production"
        inputs_raw = read(directory / "INPUTS.json")
        inputs = json.loads(inputs_raw)
        finished = json.loads(read(directory / "FINISHED.json"))
        assert finished["passed"] and finished["inputs_sha256"] == sha(inputs_raw)
        assert finished["production_proof"] == (not negative)
        assert finished["expected_negative_detected"] == negative
        assert inputs["assertions"] == finished["assertions"] == 45 and inputs["depth"] == depth
        assert inputs["manifest_sha256"] == sha(manifest_raw)
        for name, row in inputs["files"].items():
            assert len(read(directory / name, row["sha256"])) == row["bytes"]
        assert read(directory / "production.sv") == source
        assert read(directory / "production-compressor-not-elaborated.sv") == compressor
        monitor, boundary = read(directory / "monitor.inc.sv"), read(directory / "compress_boundary.sv")
        monitor_check(monitor, source)
        if common is None:
            common = monitor, boundary
        else:
            assert common == (monitor, boundary)
        tested = source
        if negative:
            old, new = (text.encode() for text in MUTATIONS[label])
            assert source.count(old) == 1
            assert inputs["mutation"]["old"] == old.decode() and inputs["mutation"]["new"] == new.decode()
            tested = source.replace(old, new)
        else:
            assert inputs["mutation"] is None
        assert read(directory / "tested.sv") == tested
        assert read(directory / "page_hash.sv") == tested.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
        replay = out / (label + "-elaboration")
        replay.mkdir()
        for name in inputs["files"]:
            (replay / name).write_bytes((directory / name).read_bytes())
        with (replay / "yosys.log").open("w") as output:
            result = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=replay,
                                    stdout=output, stderr=subprocess.STDOUT, timeout=60)
        assert result.returncode == 0
        for name in ("elaborated.json", "elaborated.il", "design.smt2"):
            assert read(directory / name) == (replay / name).read_bytes()
        design = json.loads((replay / "elaborated.json").read_text())
        assert set(design["modules"]) == {TOP}
        module = design["modules"][TOP]
        cells = list(module["cells"].values())
        types = [c["type"] for c in cells]
        assert all(kind.startswith("$") for kind in types)
        assert types.count("$assert") == 45 and types.count("$anyseq") == 2 and types.count("$anyconst") == 1
        assert "$assume" not in types and "$mem_v2" not in types
        assert sorted(int(c["parameters"]["WIDTH"], 2) for c in cells if c["type"] == "$anyseq") == [1, 256]
        arbitrary_compressor_outputs(module)
        (out / (label + "-OBSERVER-CONE.json")).write_text(json.dumps(byte_observer_cone(module), indent=2) + "\n")
        smt = (replay / "design.smt2").read_text()
        for suffix in ("i", "h", "u"):
            assert f"(define-fun |{TOP}_{suffix}| ((state |{TOP}_s|)) Bool true)" in smt
        constants = re.findall(r"^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)", smt, re.M)
        assert len(constants) == 1 and constants[0][1] == "5" and constants[0][2].endswith(" f_byte")
        assert f"(= (|{constants[0][0]}| state) (|{constants[0][0]}| next_state))" in smt.split(f"(define-fun |{TOP}_t|", 1)[1]
        queries = ("base",) if negative else ("base", "induction")
        assert set(finished["solver_results"]) == {s + "-" + q for s in ("z3", "cvc5") for q in queries}
        for kind in queries:
            query = read(directory / (kind + ".smt2")).decode()
            assert query == expected_query(smt, kind, depth)
            expected = ["sat", "sat" if negative else "unsat"] if kind == "base" else ["unsat"]
            for solver in ("z3", "cvc5"):
                row = finished["solver_results"][solver + "-" + kind]
                assert row["passed"] and row["exit"] == 0 and row["answers"] == row["expected"] == expected
                assert row["query_sha256"] == sha(query.encode())
                log = read(directory / (solver + "-" + kind + ".log"), row["log_sha256"])
                assert log.decode().splitlines() == expected
        summaries[label] = {"reelaboration_identical": True, "assertions": 45, "both_solvers_checked": True,
                            "reset_reachable_negative": negative, "observer_drives_production": False}
    result = {"passed": True, "checks": summaries, "checked_sha256": checked,
              "scope": "Page-hash framing and sequencing with arbitrary SHA replies; not SHA correctness, expected-tag provenance or attention composition.",
              "independent_human_or_agent_review": False, "hardware_access": False, "network_access": False}
    result["outputs_sha256"] = {str(p.relative_to(out)): sha(p.read_bytes()) for p in out.rglob("*") if p.is_file()}
    (out / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("KV_HASH_AUDIT PASS")


if __name__ == "__main__":
    main()
