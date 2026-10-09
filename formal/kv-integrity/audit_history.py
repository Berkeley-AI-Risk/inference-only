"""Audit the combined guard history proof without trusting its runner's verdict.

This checks exact source instrumentation, unchanged full RAMs, non-driving
observers, unrestricted boundaries, complete induction queries and raw answers.
It does not certify SHA correctness, parent composition or physical security.
"""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

TOP = "board1_kv_integrity_guard"
GUARD_SHA = "4a90d4233f628c3ca69e42266c0a9064c5ffd766b45e2e403389696a0a2d2299"
HASH_SHA = "3ee9a8a716916dcaba6d3434f722b301b3e4fb6b258ee429a457bb246191faba"
COUNTS = {"control_monitor.inc.sv": 33, "staging_monitor.inc.sv": 47,
          "write_history_monitor.inc.sv": 38, "partial_history_monitor.inc.sv": 20,
          "tag_history_monitor.inc.sv": 25, "hash_connection_monitor.inc.sv": 7,
          "write_hash_connection_monitor.inc.sv": 6, "hash_monitor.inc.sv": 45}
MUTATIONS = {
    "clear-fault": (b"if(clear_i) begin\n                if(!clear_seen_q",
                    b"if(clear_i) begin\n                fault_q<=0;\n                if(!clear_seen_q"),
    "untrusted-write": (b"if(write_fire) word_q<=s_wr_data;", b"if(write_fire) word_q<=m_rd_rsp_data;"),
}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def helper(name):
    path = Path(__file__).with_name(name + ".py")
    spec = importlib.util.spec_from_file_location("history_" + name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return path, module


def validate_support(support, count):
    assert set(support) == {str(i) for i in range(count)}
    for row in support.values():
        assert row and row == sorted(set(row)) and all(type(i) is int and 0 <= i < count for i in row)


def readonly_monitor(raw, name):
    text = re.sub(r"//[^\n]*", "", raw.decode())
    assert "`" not in text and "/*" not in text
    count = 0
    while "assert(" in text:
        start = text.index("assert(")
        end, depth = start + 7, 1
        while depth:
            depth += (text[end] == "(") - (text[end] == ")")
            end += 1
        text = text[:start] + text[end:]
        count += 1
    assert count == COUNTS[name], (name, count)
    constants = set(re.findall(r"\(\* anyconst \*\)\s+reg\s+\[[^\]]+\]\s+(f_\w+)\s*;", text))
    assert text.count("(* anyconst *)") == len(constants)
    text = text.replace("(* anyconst *)", "")
    declarations = re.findall(r"\breg\s+(?:\[[^\]]+\]\s+)?([^;]+);", text)
    registers = {name.strip() for row in declarations for name in row.split(",")}
    assert all(re.fullmatch(r"f_\w+", name) for name in registers)
    wires = re.findall(r"\bwire\s+(?:\[[^\]]+\]\s+)?(f_\w+)\s*=[^;]*;", text)
    assert len(wires) == len(set(wires)) and not (set(wires) & registers)
    text = re.sub(r"\bwire\s+(?:\[[^\]]+\]\s+)?f_\w+\s*=[^;]*;", "", text)
    assignments = set(re.findall(r"\b(\w+)\s*<=", text))
    assert assignments == registers - constants
    assert not re.search(r"(?<![<>=!])=(?!=)", text)
    assert not re.search(r"\b(assume|force|assign|input|output|inout|wire|logic|module|initial|function|"
                         r"task|defparam|bind|always_latch|always)\b", text)
    assert text.count("always_comb") == 1
    assert text.count("always_ff") == int(bool(registers - constants))
    return {"assertions": count, "constants": sorted(constants),
            "ghost_registers": sorted(registers), "production_assignment_targets": []}


def observer_audit(module, flags, instrumented_guard):
    """Trace all arbitrary observation selectors, including the new RAM ports."""
    def bits(value):
        return {bit for bit in value if isinstance(bit, int)}

    names = {}
    expected_ports = {}
    if flags["staging_observer"]:
        names["f_stage_address"] = 10
        expected_ports["stage_memory"] = "f_stage_address"
    if flags["partial_history"]:
        names["f_partial_select"] = 15
        expected_ports["partial_memory"] = "f_partial_address"
    if flags["tag_history"]:
        names["f_tag_select"] = 15
        expected_ports.update({f"g_tags[{i}].memory": "f_tag_address" for i in range(6)})
    if flags["composed_page_hash"]:
        names["u_hash.f_byte"] = 5
    nets, cells = module["netnames"], module["cells"]
    selectors = set()
    outputs = [tuple(c["connections"]["Y"]) for c in cells.values() if c["type"] == "$anyconst"]
    assert len(outputs) == len(names)
    assert set(outputs) == {tuple(nets[name]["bits"]) for name in names}
    for name, width in names.items():
        assert len(nets[name]["bits"]) == len(bits(nets[name]["bits"])) == width
        selectors |= bits(nets[name]["bits"])
    assert len(selectors) == sum(names.values())
    edges, sinks, observed = [], set(), {}
    for name, cell in cells.items():
        ports, directions = cell["connections"], cell["port_directions"]
        if cell["type"] == "$mem_v2":
            params = cell["parameters"]
            width, abits, reads = (int(params[key], 2) for key in ("WIDTH", "ABITS", "RD_PORTS"))
            assert width == 32 and reads == 1 + int(name in expected_ports)
            assert int(params["WR_PORTS"], 2) == 1 and set(params["INIT"]) == {"x"}
            writes = set().union(*(bits(v) for p, v in ports.items() if p.startswith("WR_")))
            sinks |= writes
            edges.append((name + ":write", writes, bits(ports["RD_DATA"])))
            for i in range(reads):
                address = ports["RD_ADDR"][i*abits:(i+1)*abits]
                inputs = bits(address) | set().union(*(bits([ports[p][i]]) for p in ("RD_CLK", "RD_EN", "RD_ARST", "RD_SRST")))
                result = bits(ports["RD_DATA"][i*width:(i+1)*width])
                if name in expected_ports and address == nets[expected_ports[name]]["bits"]:
                    assert name not in observed
                    assert ports["RD_EN"][i] == "1" and ports["RD_ARST"][i] == ports["RD_SRST"][i] == "0"
                    observed[name] = i
                else:
                    sinks |= inputs
                edges.append((name + ":read-" + str(i), inputs, result))
        else:
            inputs = set().union(*(bits(v) for p, v in ports.items() if directions[p] == "input"))
            result = set().union(*(bits(v) for p, v in ports.items() if directions[p] == "output"))
            edges.append((name, inputs, result))
    assert set(observed) == set(expected_ports)
    reached = set(selectors)
    while True:
        new = set().union(*(result for _, inputs, result in edges if inputs & reached))
        if new <= reached:
            break
        reached |= new
    # Yosys retains named temporaries for calls to production pure functions.
    # Exempt only the exact calls in the read-only observer declarations, not
    # similarly named function temporaries used by the production circuit.
    observer_calls = {}
    if flags["partial_history"]:
        for function, declaration in (
            ("layer_base", "    wire [13:0] f_partial_address = layer_base(f_partial_layer) + {2'd0,f_partial_slot,f_partial_chunk};"),
            ("partial_slot_for", "    wire [8:0] f_partial_slot = partial_slot_for(f_partial_position,f_partial_head,f_partial_word);")):
            matches = [i for i, line in enumerate(instrumented_guard.decode().splitlines(), 1) if line == declaration]
            assert len(matches) == 1
            observer_calls[function] = matches[0]
    ghost_temporaries = set()
    for name in nets:
        match = re.fullmatch(r"(layer_base|partial_slot_for)\$func\$guard\.sv:(\d+)\$\d+\.(\$result|layer|head|position_mod|word_index)", name)
        if match and observer_calls.get(match[1]) == int(match[2]):
            ghost_temporaries.add(name)
    protected = {name: bits(row["bits"]) for name, row in nets.items()
                 if not row["hide_name"] and name not in ghost_temporaries and
                 not (name.startswith("f_") or name.startswith("u_hash.f_"))}
    protected.update({name: bits(row["bits"]) for name, row in module["ports"].items()})
    hits = [name for name, value in protected.items() if value & reached]
    assert not hits and not (sinks & reached), hits
    return {"selectors": names, "observation_ports": observed,
            "observer_function_temporaries": sorted(ghost_temporaries),
            "production_signal_hits": [], "production_memory_sink_hits": [],
            "reached_bits": sorted(reached)}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "proof", "out"):
        ap.add_argument("--" + name, type=Path, required=True)
    ap.add_argument("--negative", type=Path, required=True, action="append")
    args = ap.parse_args()
    package, proof, out = (getattr(args, name).resolve() for name in ("package", "proof", "out"))
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
    guard_path = "variants/kv-protected/hardware/project/kv_integrity_guard.sv"
    hash_path = "variants/kv-protected/hardware/project/kv_page_hash.sv"
    guard, page_hash = read(package / guard_path, GUARD_SHA), read(package / hash_path, HASH_SHA)
    assert manifest[guard_path]["sha256"] == GUARD_SHA and manifest[hash_path]["sha256"] == HASH_SHA
    assert not re.search(rb"\bf_\w*\b", guard + page_hash)
    out.mkdir(parents=True, exist_ok=False)
    (out / "auditor.py").write_bytes(Path(__file__).read_bytes())
    control_path, control = helper("audit_control")
    hash_path, hash_audit = helper("audit_hash")
    (out / control_path.name).write_bytes(control_path.read_bytes())
    (out / hash_path.name).write_bytes(hash_path.read_bytes())
    common = None
    reports = {}
    _, contract = helper("audit_contract")
    negatives = contract.distinct_negative_paths(proof, args.negative)
    directories = [("production", proof)] + [("negative-" + str(i), p) for i, p in enumerate(negatives)]
    seen_mutations = set()
    for label, directory in directories:
        negative = label != "production"
        raw_inputs = read(directory / "INPUTS.json")
        inputs, finished = json.loads(raw_inputs), json.loads(read(directory / "FINISHED.json"))
        assert finished["passed"] and finished["inputs_sha256"] == sha(raw_inputs)
        assert finished["production_proof"] == (not negative) and finished["expected_negative_detected"] == negative
        assert inputs["manifest_sha256"] == sha(manifest_raw) and inputs["induction_length"] == 2
        assert inputs["geometry_reduced"] is False and inputs["timeout_reduced"] is False
        flags = {name: inputs.get(name, False) for name in
                 ("staging_observer", "write_history", "partial_history", "tag_history", "composed_page_hash")}
        assert flags["write_history"]
        assert not flags["composed_page_hash"] or flags["staging_observer"]
        for name, row in inputs["files"].items():
            assert len(read(directory / name, row["sha256"])) == row["bytes"]
        assert read(directory / "production.sv") == guard
        hash_name = "production-page-hash.sv" if flags["composed_page_hash"] else "production-page-hash-not-elaborated.sv"
        assert read(directory / hash_name) == page_hash
        selected = ["control_monitor.inc.sv"]
        for flag, name in (("staging_observer", "staging_monitor.inc.sv"), ("write_history", "write_history_monitor.inc.sv"),
                           ("partial_history", "partial_history_monitor.inc.sv"), ("tag_history", "tag_history_monitor.inc.sv")):
            if flags[flag]:
                selected.append(name)
        if flags["composed_page_hash"]:
            selected += ["hash_connection_monitor.inc.sv", "write_hash_connection_monitor.inc.sv"]
        components = {name: read(directory / name) for name in selected}
        instrumentation = {name: readonly_monitor(raw, name) for name, raw in components.items()}
        monitor = b"\n".join(components.values())
        assert read(directory / "monitor.inc.sv") == monitor
        tested = guard
        mutation_name = None
        if negative:
            mutation = inputs["mutation"]
            chosen = [(key, old, new) for key, (old, new) in MUTATIONS.items()
                      if mutation["old"] == old.decode() and mutation["new"] == new.decode()]
            assert len(chosen) == 1
            mutation_name, old, new = chosen[0]
            assert mutation_name not in seen_mutations
            seen_mutations.add(mutation_name)
            assert guard.count(old) == 1
            tested = guard.replace(old, new)
        else:
            assert inputs["mutation"] is None
        assert read(directory / "tested.sv") == tested
        expected_guard = tested.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
        if flags["tag_history"]:
            seam = b"    wire [31:0] tag_data[0:5];"
            expected_guard = expected_guard.replace(seam, seam + b"\n    wire [31:0] f_tag_memory[0:5];")
            seam = b"        assign tag_data[bank]=read_q;"
            expected_guard = expected_guard.replace(seam, seam + b"\n        assign f_tag_memory[bank]=memory[f_tag_address];")
        count = sum(COUNTS[name] for name in selected)
        constants = sum(len(row["constants"]) for row in instrumentation.values())
        if flags["composed_page_hash"]:
            hm = read(directory / "hash_monitor.inc.sv")
            hash_audit.monitor_check(hm, page_hash)
            count += 45
            constants += 1
            seam = b"    output wire fault_o\n);"
            replacement = (b"    output wire fault_o,\n    output wire [511:0] f_link_header_q_o,\n"
                           b"    output wire [6:0] f_link_words_q_o,\n    output wire [3:0] f_link_state_q_o\n);")
            taps = (b"    assign f_link_header_q_o = header_q;\n    assign f_link_words_q_o = words_q;\n"
                    b"    assign f_link_state_q_o = state_q;\n")
            boundary = page_hash.replace(seam, replacement).replace(b"\nendmodule", b"\n" + taps + hm + b"\nendmodule")
            component_name = "page_hash.sv"
            assert read(directory / component_name) == boundary
            seam = b"    kv_page_hash u_hash("
            taps = b"    wire [511:0] f_hash_header;\n    wire [6:0] f_hash_words;\n    wire [3:0] f_hash_state;\n"
            expected_guard = expected_guard.replace(seam, taps + seam)
            seam = b".digest_o(hash_digest),.fault_o(hash_fault));"
            replacement = (b".digest_o(hash_digest),.fault_o(hash_fault),\n"
                           b"        .f_link_header_q_o(f_hash_header),.f_link_words_q_o(f_hash_words),\n"
                           b"        .f_link_state_q_o(f_hash_state));")
            expected_guard = expected_guard.replace(seam, replacement)
            boundary_files = boundary, read(directory / "compress_boundary.sv")
        else:
            component_name = "hash_boundary.sv"
            boundary_files = (read(directory / component_name),)
        assert read(directory / "guard.sv") == expected_guard
        signature = flags, monitor, boundary_files
        if common is None:
            common = signature
        else:
            assert common == signature
        assert inputs["assertions"] == finished["assertions"] == count
        commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS guard.sv " + component_name +
                    (" compress_boundary.sv" if flags["composed_page_hash"] else ""),
                    f"prep -top {TOP} -flatten", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                    f"select -assert-count {count} t:$assert", "select -assert-none t:$assume",
                    "select -assert-count 2 t:$anyseq" if flags["composed_page_hash"] else "select -assert-count 5 t:$anyseq",
                    f"select -assert-count {constants} t:$anyconst", "select -assert-count 8 t:$mem_v2", "check -assert",
                    "write_json elaborated.json", "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
        assert read(directory / "prove.ys") == ("\n".join(commands) + "\n").encode()
        replay = out / (label + "-elaboration")
        replay.mkdir()
        for name in inputs["files"]:
            (replay / name).write_bytes((directory / name).read_bytes())
        with (replay / "yosys.log").open("w") as output:
            process = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=replay,
                                     stdout=output, stderr=subprocess.STDOUT, timeout=60)
        assert process.returncode == 0
        for name in ("elaborated.json", "elaborated.il", "design.smt2"):
            assert read(directory / name) == (replay / name).read_bytes()
        modules = json.loads((replay / "elaborated.json").read_text())["modules"]
        assert set(modules) == {TOP}
        module = modules[TOP]
        cells = list(module["cells"].values())
        types = [c["type"] for c in cells]
        assert all(kind.startswith("$") for kind in types) and "$assume" not in types
        assert types.count("$assert") == count and types.count("$anyconst") == constants
        memories = [c for c in cells if c["type"] == "$mem_v2"]
        assert sorted((int(c["parameters"]["SIZE"], 2), int(c["parameters"]["WIDTH"], 2)) for c in memories) == (
            [(640, 32)] + [(4096, 32)] * 6 + [(13824, 32)])
        for name, width in (("epoch_q", 64), ("cache_epoch_q", 64), ("watchdog_q", 26)):
            assert len(module["netnames"][name]["bits"]) == width
        observed = observer_audit(module, flags, expected_guard)
        (out / (label + "-OBSERVERS.json")).write_text(json.dumps(observed, indent=2) + "\n")
        if flags["composed_page_hash"]:
            hash_audit.arbitrary_compressor_outputs(module, prefix="u_hash.")
        else:
            outputs = [tuple(c["connections"]["Y"]) for c in cells if c["type"] == "$anyseq"]
            replies = [tuple(module["netnames"]["u_hash." + name]["bits"]) for name in
                       ("begin_ready_o", "word_ready_o", "digest_valid_o", "digest_o", "fault_o")]
            assert len(outputs) == 5 and set(outputs) == set(replies)
            assert [len(bits) for bits in replies] == [1, 1, 1, 256, 1]
            assert len(set(bit for bits in replies for bit in bits if isinstance(bit, int))) == 260
        smt = (replay / "design.smt2").read_text()
        for suffix in ("i", "h", "u"):
            assert f"(define-fun |{TOP}_{suffix}| ((state |{TOP}_s|)) Bool true)" in smt
        symbolic = re.findall(r"^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)", smt, re.M)
        assert len(symbolic) == constants
        for wire, _, _ in symbolic:
            assert f"(= (|{wire}| state) (|{wire}| next_state))" in smt.split(f"(define-fun |{TOP}_t|", 1)[1]
        split = inputs.get("split_induction", False)
        assert not negative or not split
        support = None
        if inputs.get("component_hypotheses", False):
            assert split and not negative
            support_record = json.loads(read(directory / "INDUCTION-SUPPORT.json"))
            support = support_record["earlier_state_assertions"]
            validate_support(support, count)
            # Any subset of the same proved invariant set is sound here:
            # it gives the induction step fewer hypotheses, not more. Every
            # conclusion remains mandatory, and the reset base checks all.
        queries = (["base"] if negative else ["base", "fault-clear-witness"] +
                   ([f"induction-{i:02d}" for i in range(count)] if split else ["induction"]))
        assert set(finished["solver_results"]) == {s + "-" + q for s in ("z3", "cvc5") for q in queries}
        for kind in queries:
            generic = "induction" if kind.startswith("induction-") else kind
            query = control.expected_query(smt, generic, negative)
            if kind.startswith("induction-"):
                index = int(kind.split("-")[1])
                query = query.replace(f"(assert (not ({TOP}_a s2)))", f"(assert (not (|{TOP}_a {index}| s2)))")
                if support is not None:
                    for i in range(2):
                        query = query.replace(f"(assert ({TOP}_a s{i}))", "(assert (and " + " ".join(
                            f"(|{TOP}_a {j}| s{i})" for j in support[str(index)]) + "))")
            assert read(directory / (kind + ".smt2")).decode() == query
            expected = (["sat", "sat" if negative else "unsat"] if kind == "base" else
                        ["sat"] if kind == "fault-clear-witness" else ["unsat"])
            for solver in ("z3", "cvc5"):
                row = finished["solver_results"][solver + "-" + kind]
                assert row["passed"] and row["exit"] == 0 and not row["timed_out"]
                assert row["answers"] == row["expected"] == expected and row["query_sha256"] == sha(query.encode())
                assert read(directory / (solver + "-" + kind + ".log"), row["log_sha256"]).decode().splitlines() == expected
        reports[label] = {"assertions": count, "queries_both_solvers": len(queries) * 2,
                          "geometry_bits": 1249280, "source_and_elaboration_identical": True,
                          "mutation": mutation_name, "reset_reachable_negative": negative,
                          "scope_flags": flags, "instrumentation": instrumentation}
    assert seen_mutations == set(MUTATIONS)
    result = {"passed": True, "checks": reports, "checked_sha256": checked,
              "scope": "Source-bound guard history safety, not SHA correctness, attention-parent composition or a physical-security rating.",
              "independent_human_or_agent_review": False, "hardware_access": False, "network_access": False}
    result["outputs_sha256"] = {str(p.relative_to(out)): sha(p.read_bytes()) for p in out.rglob("*") if p.is_file()}
    (out / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
    print("KV_HISTORY_AUDIT PASS")


if __name__ == "__main__":
    main()
