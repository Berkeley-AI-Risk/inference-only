"""Audit source binding, read-only instrumentation, elaboration and SMT queries.

This audit is separate from the runner. It does not extend the theorem's scope.
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


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def check_monitor(raw, production, staging=False, composed=False):
    """Restrict added code to ghost declarations/assignments and assertions."""
    text = re.sub(r"//[^\n]*", "", raw.decode())
    assert "`" not in text and "/*" not in text
    assert not re.search(r"\bf_\w*\b", production.decode())
    assertion_count = 0
    while "assert(" in text:
        start = text.index("assert(")
        end, depth = start + len("assert("), 1
        while depth:
            depth += (text[end] == "(") - (text[end] == ")")
            end += 1
        text = text[:start] + text[end:]
        assertion_count += 1
    assert assertion_count == (87 if composed else 80 if staging else 33)
    declarations = re.findall(r"\breg\s+(?:\[[^\]]+\]\s+)?([^;]+);", text)
    declared = {name.strip() for row in declarations for name in row.split(",")}
    assert declared and all(re.fullmatch(r"f_\w+", name) for name in declared)
    assignments = re.findall(r"\b(\w+)\s*<=", text)
    constants = {"f_stage_address"} if staging else set()
    assert assignments and set(assignments) == declared - constants
    if staging:
        assert text.count("(* anyconst *)") == 1
        text = text.replace("(* anyconst *)", "")
        wires = re.findall(r"\bwire\s+(?:\[[^\]]+\]\s+)?(f_\w+)\s*=[^;]*;", text)
        assert len(wires) == (9 if composed else 7) and len(set(wires)) == len(wires)
        text = re.sub(r"\bwire\s+(?:\[[^\]]+\]\s+)?f_\w+\s*=[^;]*;", "", text)
    assert not re.search(r"(?<![<>=!])=(?!=)", text)
    assert not re.search(r"\b(assume|force|assign|input|output|inout|wire|module|initial|"
                         r"function|task|defparam|bind|always_latch)\b", text)
    assert text.count("always_ff") == (2 if staging else 1)
    assert text.count("always_comb") == (3 if composed else 2 if staging else 1)
    return {"assertions": assertion_count, "ghost_registers": sorted(declared),
            "production_assignment_targets": [],
            "method": ("Exact production bytes plus read-only ghosts and one audited observation port." if staging else
                       "Exact production bytes plus restricted read-only ghost/assertion text; no added RAM ports.")}


def observer_cone(module, composed=False):
    """The arbitrary address and its observation cannot drive production."""
    def bits(value):
        return {bit for bit in value if isinstance(bit, int)}

    cells, nets = module["cells"], module["netnames"]
    selector = bits(nets["f_stage_address"]["bits"])
    constants = [cell for cell in cells.values() if cell["type"] == "$anyconst"]
    selected = [c for c in constants if bits(c["connections"]["Y"]) == selector]
    assert len(constants) == (2 if composed else 1) and len(selected) == 1
    assert len(selector) == 10 and int(selected[0]["parameters"]["WIDTH"], 2) == 10
    edges, memory_sinks, observer_ports = [], set(), []
    for name, cell in cells.items():
        ports, directions = cell["connections"], cell["port_directions"]
        if cell["type"] == "$mem_v2":
            params = cell["parameters"]
            width, abits, reads = (int(params[key], 2) for key in ("WIDTH", "ABITS", "RD_PORTS"))
            assert width == 32 and reads == (2 if name == "stage_memory" else 1)
            assert int(params["WR_PORTS"], 2) == 1
            writes = set().union(*(bits(value) for port, value in ports.items() if port.startswith("WR_")))
            memory_sinks |= writes
            edges.append((name + ":writes", writes, bits(ports["RD_DATA"])))
            for index in range(reads):
                address = ports["RD_ADDR"][abits*index:abits*(index+1)]
                inputs = bits(address) | set().union(*(bits([ports[port][index]])
                    for port in ("RD_CLK", "RD_EN", "RD_ARST", "RD_SRST")))
                outputs = bits(ports["RD_DATA"][width*index:width*(index+1)])
                if address == nets["f_stage_address"]["bits"]:
                    assert name == "stage_memory" and abits == 10
                    assert ports["RD_EN"][index] == "1"
                    assert ports["RD_ARST"][index] == ports["RD_SRST"][index] == "0"
                    observer_ports.append(index)
                else:
                    memory_sinks |= inputs
                edges.append((name + ":read-" + str(index), inputs, outputs))
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
                 if not row["hide_name"] and not (name.startswith("f_") or name.startswith("u_hash.f_"))}
    protected.update({name: bits(row["bits"]) for name, row in module["ports"].items()})
    hits = [name for name, value in protected.items() if reached & value]
    assert not hits and not (reached & memory_sinks), hits
    return {"selector_bits": sorted(selector), "reached_bits": sorted(reached),
            "extra_read_only_observer_port": observer_ports[0],
            "production_signal_hits": [], "production_memory_sink_hits": [],
            "edges": [{"name": name, "inputs": sorted(inputs & reached), "outputs": sorted(outputs)}
                      for name, inputs, outputs in edges if inputs & reached]}


def expected_query(smt, kind, negative):
    length = 4 if negative or kind == "fault-clear-witness" else 2
    initial = kind != "induction"
    lines = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(length + 1):
        lines += [f"(declare-fun s{i} () {TOP}_s)", f"(assert ({TOP}_h s{i}))",
                  f"(assert ({TOP}_u s{i}))",
                  f"(assert (= ({TOP}_is s{i}) {'true' if initial and i == 0 else 'false'}))"]
        if i:
            lines.append(f"(assert ({TOP}_t s{i-1} s{i}))")
    if initial:
        lines += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n| s0)))",
                  f"(assert (not (|{TOP}_n reset_n| s1)))"]
    if kind == "base":
        lines += ["(check-sat)", "(assert (not (and " +
                  " ".join(f"({TOP}_a s{i})" for i in range(length + 1)) + ")))", "(check-sat)"]
    elif kind == "induction":
        lines += [f"(assert ({TOP}_a s0))", f"(assert ({TOP}_a s1))",
                  f"(assert (not ({TOP}_a s2)))", "(check-sat)"]
    else:
        assert kind == "fault-clear-witness" and not negative
        lines += [f"(assert (|{TOP}_n reset_n| s4))", f"(assert (|{TOP}_n f_previous_fault| s4))",
                  f"(assert (|{TOP}_n clear_i| s4))", f"(assert (|{TOP}_n fault_o| s4))", "(check-sat)"]
    return "\n".join(lines) + "\n"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "proof", "negative", "out"):
        parser.add_argument("--" + name, type=Path, required=True)
    parser.add_argument("--staging", action="store_true")
    parser.add_argument("--compose-hash", action="store_true")
    args = parser.parse_args()
    assert not args.compose_hash or args.staging
    count = 132 if args.compose_hash else 80 if args.staging else 33
    package, proof, negative, out = (getattr(args, name).resolve()
                                    for name in ("package", "proof", "negative", "out"))
    checked = {}

    def read(path, expected=None):
        assert not path.is_symlink(), path
        raw = path.read_bytes()
        value = sha(raw)
        if expected:
            assert value == expected, path
        checked[str(path)] = value
        return raw

    manifest_raw = read(package / "MANIFEST.json")
    manifest = json.loads(manifest_raw)["files"]
    guard_name = "variants/kv-protected/hardware/project/kv_integrity_guard.sv"
    hash_name = "variants/kv-protected/hardware/project/kv_page_hash.sv"
    guard = read(package / guard_name, GUARD_SHA)
    hash_source = read(package / hash_name, HASH_SHA)
    assert manifest[guard_name]["sha256"] == GUARD_SHA and manifest[hash_name]["sha256"] == HASH_SHA
    out.mkdir(parents=True, exist_ok=False)
    (out / "auditor.py").write_bytes(Path(__file__).read_bytes())
    hash_audit = None
    if args.compose_hash:
        helper = Path(__file__).with_name("audit_hash.py")
        (out / "hash-audit-helpers.py").write_bytes(helper.read_bytes())
        spec = importlib.util.spec_from_file_location("kv_hash_audit_helpers", helper)
        hash_audit = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(hash_audit)
    monitor_report = None
    summaries = {}
    common_monitor, common_boundary = None, None
    for directory, is_negative in ((proof, False), (negative, True)):
        label = "negative" if is_negative else "production"
        inputs_raw = read(directory / "INPUTS.json")
        inputs = json.loads(inputs_raw)
        finished = json.loads(read(directory / "FINISHED.json"))
        assert finished["passed"] and finished["inputs_sha256"] == sha(inputs_raw)
        assert finished["production_proof"] == (not is_negative)
        assert finished["expected_negative_detected"] == is_negative
        assert inputs["assertions"] == finished["assertions"] == count
        assert inputs.get("staging_observer", False) == args.staging
        assert inputs.get("split_induction", False) is False
        assert inputs.get("composed_page_hash", False) == args.compose_hash
        assert inputs["induction_length"] == 2 and inputs["manifest_sha256"] == sha(manifest_raw)
        assert inputs["geometry_reduced"] is False and inputs["timeout_reduced"] is False
        for name, row in inputs["files"].items():
            assert len(read(directory / name, row["sha256"])) == row["bytes"]
        assert read(directory / "production.sv") == guard
        raw_hash_name = "production-page-hash.sv" if args.compose_hash else "production-page-hash-not-elaborated.sv"
        component_name = "page_hash.sv" if args.compose_hash else "hash_boundary.sv"
        assert read(directory / raw_hash_name) == hash_source
        monitor, boundary = read(directory / "monitor.inc.sv"), read(directory / component_name)
        monitor_report = check_monitor(monitor, guard, args.staging, args.compose_hash)
        if args.compose_hash:
            hash_monitor = read(directory / "hash_monitor.inc.sv")
            hash_audit.monitor_check(hash_monitor, hash_source)
            connection_monitor = read(directory / "hash_connection_monitor.inc.sv")
            assert monitor.endswith(b"\n" + connection_monitor)
            assert inputs["read_only_hash_register_taps"] == {"header_q": 512, "words_q": 7, "state_q": 4}
            header_seam = b"    output wire fault_o\n);"
            header_extra = (b"    output wire fault_o,\n    output wire [511:0] f_link_header_q_o,\n"
                            b"    output wire [6:0] f_link_words_q_o,\n    output wire [3:0] f_link_state_q_o\n);")
            tap_assignments = (b"    assign f_link_header_q_o = header_q;\n"
                               b"    assign f_link_words_q_o = words_q;\n"
                               b"    assign f_link_state_q_o = state_q;\n")
            assert hash_source.count(header_seam) == 1
            assert boundary == hash_source.replace(header_seam, header_extra).replace(
                b"\nendmodule", b"\n" + tap_assignments + hash_monitor + b"\nendmodule")
            read(directory / "compress_boundary.sv")
        if common_monitor is None:
            common_monitor, common_boundary = monitor, boundary
        else:
            assert (monitor, boundary) == (common_monitor, common_boundary)
        tested = guard
        if is_negative:
            old = b"if(clear_i) begin\n                if(!clear_seen_q"
            new = b"if(clear_i) begin\n                fault_q<=0;\n                if(!clear_seen_q"
            assert inputs["mutation"]["old"] == old.decode() and inputs["mutation"]["new"] == new.decode()
            assert guard.count(old) == 1
            tested = guard.replace(old, new)
        else:
            assert inputs["mutation"] is None
        assert read(directory / "tested.sv") == tested
        expected_guard = tested.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
        if args.compose_hash:
            declaration_seam = b"    kv_page_hash u_hash("
            tap_declarations = (b"    wire [511:0] f_hash_header;\n    wire [6:0] f_hash_words;\n"
                                b"    wire [3:0] f_hash_state;\n")
            connection_seam = b".digest_o(hash_digest),.fault_o(hash_fault));"
            connection_extra = (b".digest_o(hash_digest),.fault_o(hash_fault),\n"
                                b"        .f_link_header_q_o(f_hash_header),.f_link_words_q_o(f_hash_words),\n"
                                b"        .f_link_state_q_o(f_hash_state));")
            assert expected_guard.count(declaration_seam) == expected_guard.count(connection_seam) == 1
            expected_guard = expected_guard.replace(declaration_seam, tap_declarations + declaration_seam).replace(
                connection_seam, connection_extra)
        assert read(directory / "guard.sv") == expected_guard
        replay = out / (label + "-elaboration")
        replay.mkdir()
        for name in inputs["files"]:
            (replay / name).write_bytes((directory / name).read_bytes())
        with (replay / "yosys.log").open("w") as output:
            proc = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=replay,
                                  stdout=output, stderr=subprocess.STDOUT, timeout=60)
        assert proc.returncode == 0
        for name in ("elaborated.json", "elaborated.il", "design.smt2"):
            assert read(directory / name) == (replay / name).read_bytes(), name
        elaborated = json.loads((replay / "elaborated.json").read_text())
        assert set(elaborated["modules"]) == {TOP}
        module = elaborated["modules"][TOP]
        cells = list(module["cells"].values())
        types = [cell["type"] for cell in cells]
        assert all(kind.startswith("$") for kind in types)
        assert types.count("$assert") == count and types.count("$anyseq") == (2 if args.compose_hash else 5)
        assert "$assume" not in types and types.count("$anyconst") == (2 if args.compose_hash else int(args.staging))
        if args.staging:
            (out / (label + "-OBSERVER-CONE.json")).write_text(json.dumps(observer_cone(module, args.compose_hash), indent=2) + "\n")
        if args.compose_hash:
            hash_audit.arbitrary_compressor_outputs(module, prefix="u_hash.")
            (out / (label + "-HASH-OBSERVER-CONE.json")).write_text(json.dumps(
                hash_audit.byte_observer_cone(module, prefix="u_hash.", total_constants=2), indent=2) + "\n")
        else:
            arbitrary_outputs = [tuple(c["connections"]["Y"]) for c in cells if c["type"] == "$anyseq"]
            reply_names = ("begin_ready_o", "word_ready_o", "digest_valid_o", "digest_o", "fault_o")
            replies = [tuple(module["netnames"]["u_hash." + name]["bits"]) for name in reply_names]
            assert [len(bits) for bits in replies] == [1, 1, 1, 256, 1]
            assert all(isinstance(bit, int) for bits in replies for bit in bits)
            assert len(set(bit for bits in replies for bit in bits)) == 260
            assert len(arbitrary_outputs) == 5 and set(arbitrary_outputs) == set(replies)
        memories = [cell for cell in cells if cell["type"] == "$mem_v2"]
        assert sorted((int(c["parameters"]["SIZE"], 2), int(c["parameters"]["WIDTH"], 2))
                      for c in memories) == [(640, 32)] + [(4096, 32)] * 6 + [(13824, 32)]
        for c in memories:
            assert set(c["parameters"]["INIT"]) == {"x"}
        widths = sorted(int(c["parameters"]["WIDTH"], 2) for c in cells if c["type"] == "$anyseq")
        assert widths == ([1, 256] if args.compose_hash else [1, 1, 1, 1, 256])
        for name, width in (("epoch_q", 64), ("cache_epoch_q", 64), ("watchdog_q", 26)):
            assert len(module["netnames"][name]["bits"]) == width
        smt = (replay / "design.smt2").read_text()
        for suffix in ("i", "h", "u"):
            assert f"(define-fun |{TOP}_{suffix}| ((state |{TOP}_s|)) Bool true)" in smt
        if args.staging:
            constants = re.findall(r"^; yosys-smt2-anyconst (\S+) (\d+) ([^\n]+)", smt, re.M)
            assert len(constants) == (2 if args.compose_hash else 1)
            assert sorted((width, desc.split()[-1]) for _, width, desc in constants) == (
                [("10", "f_stage_address"), ("5", "f_byte")] if args.compose_hash else [("10", "f_stage_address")])
            for wire, _, _ in constants:
                assert f"(= (|{wire}| state) (|{wire}| next_state))" in smt.split(f"(define-fun |{TOP}_t|", 1)[1]
        queries = ("base",) if is_negative else ("base", "induction", "fault-clear-witness")
        assert set(finished["solver_results"]) == {solver + "-" + kind
                                                  for solver in ("z3", "cvc5") for kind in queries}
        for kind in queries:
            query = read(directory / (kind + ".smt2")).decode()
            assert query == expected_query(smt, kind, is_negative)
            expected = (["sat", "sat" if is_negative else "unsat"] if kind == "base" else
                        ["sat"] if kind == "fault-clear-witness" else ["unsat"])
            for solver in ("z3", "cvc5"):
                record = finished["solver_results"][solver + "-" + kind]
                assert record["passed"] and record["exit"] == 0 and not record["timed_out"]
                assert record["answers"] == record["expected"] == expected
                assert record["query_sha256"] == sha(query.encode())
                log = read(directory / (solver + "-" + kind + ".log"), record["log_sha256"])
                assert log.decode().splitlines() == expected
        summaries[label] = {"reelaboration_identical": True, "assertions": count,
                            "memory_bits": 1249280, "unrestricted_hash_reply_bits": 257 if args.compose_hash else 260,
                            "solver_queries": len(queries) * 2}
    report = {"passed": True, "checks": summaries, "instrumentation": monitor_report,
              "checked_sha256": checked, "production_source_sha256": GUARD_SHA,
              "scope": ("Audited composition of the real guard and page-hash wrapper with non-driving observers and arbitrary SHA replies; not expected-tag provenance or attention-parent composition."
                        if args.compose_hash else "Audited control and full staging-RAM correspondence induction with a non-driving arbitrary observer; not cryptography or parent composition."
                        if args.staging else "Audited control/cache-admission induction, not RAM/hash-byte correspondence, cryptography or parent composition."),
              "independent_human_or_agent_review": False,
              "hardware_access": False, "network_access": False}
    report["outputs_sha256"] = {str(path.relative_to(out)): sha(path.read_bytes())
                               for path in out.rglob("*") if path.is_file()}
    (out / "FINISHED.json").write_text(json.dumps(report, indent=2) + "\n")
    print("KV_CONTROL_AUDIT PASS")


if __name__ == "__main__":
    main()
