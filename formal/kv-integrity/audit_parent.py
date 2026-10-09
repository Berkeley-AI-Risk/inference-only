"""Reconstruct the projected integration and check every retained proof query.

Uses parent_model.py for source projection, so this is not an independent
review of that projection. Query, memory and non-driving checks are separate
from the proof runner. Does not certify the abstracted attention arithmetic.
"""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess

TOP = "kv_parent_composition"


def load(path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def monitor_check(raw):
    text = re.sub(r"//[^\n]*", "", raw.decode())
    count = 0
    while "assert(" in text:
        start = text.index("assert(")
        end, depth = start + 7, 1
        while depth:
            depth += (text[end] == "(") - (text[end] == ")")
            end += 1
        text = text[:start] + text[end:]
        count += 1
    constants = set(re.findall(r"\(\* anyconst \*\)\s+reg\s+\[[^\]]+\]\s+(f_\w+)\s*;", text))
    assert text.count("(* anyconst *)") == len(constants)
    text = text.replace("(* anyconst *)", "")
    declarations = re.findall(r"\breg\s+(?:\[[^\]]+\]\s*)?([^;]+);", text)
    registers = {s.strip() for row in declarations for s in row.split(",")}
    assert registers and all(re.fullmatch(r"f_\w+", r) for r in registers)
    text = re.sub(r"\bwire\s+(?:\[[^\]]+\]\s*)?f_\w+\s*=[^;]*;", "", text)
    # An index may itself contain an indexed expression, as in mask[x[5:3]].
    # Do not silently omit that assignment from the production-write check.
    assignment_targets = re.findall(r"\b(\w+)\s*(?:\[(?:[^\[\]]|\[[^\[\]]*\])*\]\s*)*<=", text)
    assert len(assignment_targets) == text.count("<=")
    targets = set(assignment_targets)
    assert targets == registers - constants, targets - registers
    assert not re.search(r"(?<![<>=!])=(?!=)", text)
    assert not re.search(r"\b(assume|force|assign|input|output|inout|wire|logic|module|initial|function|task|defparam|bind)\b", text)
    assert "`" not in text and "/*" not in text and "(*" not in text
    assert text.count("always_ff") == text.count("always_comb") == 1
    return count


def check_guard_sources(files, model, history, hash_audit):
    # Reconstruct the prior guard instrumentation rather than trusting its
    # saved PASS receipt or the checksums in its own input record.
    guard, page_hash = files["production-guard.sv"], files["production-page_hash.sv"]
    assert model.sha(guard) == history.GUARD_SHA and model.sha(page_hash) == history.HASH_SHA
    names = ["control_monitor.inc.sv", "staging_monitor.inc.sv", "write_history_monitor.inc.sv",
             "partial_history_monitor.inc.sv", "tag_history_monitor.inc.sv",
             "hash_connection_monitor.inc.sv", "write_hash_connection_monitor.inc.sv"]
    for name in names:
        history.readonly_monitor(files[name], name)
    monitor = b"\n".join(files[name] for name in names)
    assert files["monitor.inc.sv"] == monitor
    expected = guard.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
    seam = b"    wire [31:0] tag_data[0:5];"
    expected = expected.replace(seam, seam + b"\n    wire [31:0] f_tag_memory[0:5];")
    seam = b"        assign tag_data[bank]=read_q;"
    expected = expected.replace(seam, seam + b"\n        assign f_tag_memory[bank]=memory[f_tag_address];")
    seam = b"    kv_page_hash u_hash("
    expected = expected.replace(seam, b"    wire [511:0] f_hash_header;\n    wire [6:0] f_hash_words;\n    wire [3:0] f_hash_state;\n" + seam)
    expected = expected.replace(b".digest_o(hash_digest),.fault_o(hash_fault));",
        b".digest_o(hash_digest),.fault_o(hash_fault),\n        .f_link_header_q_o(f_hash_header),.f_link_words_q_o(f_hash_words),\n        .f_link_state_q_o(f_hash_state));")
    assert files["guard.sv"] == model.add_taps(expected.decode(), model.GUARD_TAPS).encode()
    hash_audit.monitor_check(files["hash_monitor.inc.sv"], page_hash)
    page_hash = page_hash.replace(b"    output wire fault_o\n);",
        b"    output wire fault_o,\n    output wire [511:0] f_link_header_q_o,\n    output wire [6:0] f_link_words_q_o,\n    output wire [3:0] f_link_state_q_o\n);")
    page_hash = page_hash.replace(b"\nendmodule",
        b"\n    assign f_link_header_q_o = header_q;\n    assign f_link_words_q_o = words_q;\n    assign f_link_state_q_o = state_q;\n" +
        files["hash_monitor.inc.sv"] + b"\nendmodule")
    assert files["page_hash.sv"] == page_hash
    assert monitor_check(files["epoch_monitor.inc.sv"]) == 59


def observer_check(module, guard_source):
    def bits(xs):
        return {b for b in xs if isinstance(b, int)}
    nets, cells = module["netnames"], module["cells"]
    expected = {"u_guard.f_stage_address": 10, "u_guard.f_partial_select": 15,
                "u_guard.f_tag_select": 15, "u_guard.u_hash.f_byte": 5, "u_atomic.f_coordinate": 7}
    outputs = [tuple(c["connections"]["Y"]) for c in cells.values() if c["type"] == "$anyconst"]
    assert len(outputs) == 5 and set(outputs) == {tuple(nets[n]["bits"]) for n in expected}
    reached = set()
    for name, width in expected.items():
        assert len(nets[name]["bits"]) == len(bits(nets[name]["bits"])) == width
        reached |= bits(nets[name]["bits"])
    selectors = set(reached)
    assert len(selectors) == 52
    memory_observers = {"u_guard.stage_memory": "u_guard.f_stage_address",
                        "u_guard.partial_memory": "u_guard.f_partial_address"}
    memory_observers.update({f"u_guard.g_tags[{i}].memory": "u_guard.f_tag_address" for i in range(6)})
    edges, sinks, seen, geometry = [], set(), set(), []
    for name, cell in cells.items():
        ports, directions = cell["connections"], cell["port_directions"]
        if cell["type"] == "$mem_v2":
            p = cell["parameters"]
            width, abits, reads, size = (int(p[k], 2) for k in ("WIDTH", "ABITS", "RD_PORTS", "SIZE"))
            assert name in memory_observers and width == 32 and reads == 2
            assert int(p["WR_PORTS"], 2) == 1 and set(p["INIT"]) == {"x"}
            geometry.append((size, width))
            writes = set().union(*(bits(v) for key, v in ports.items() if key.startswith("WR_")))
            sinks |= writes
            edges.append((writes, bits(ports["RD_DATA"])))
            for i in range(reads):
                address = ports["RD_ADDR"][i*abits:(i+1)*abits]
                rd_inputs = bits(address) | set().union(*(bits([ports[key][i]]) for key in ("RD_CLK", "RD_EN", "RD_ARST", "RD_SRST")))
                if address == nets[memory_observers[name]]["bits"]:
                    assert name not in seen
                    seen.add(name)
                    assert ports["RD_EN"][i] == "1" and ports["RD_ARST"][i] == ports["RD_SRST"][i] == "0"
                else:
                    sinks |= rd_inputs
                edges.append((rd_inputs, bits(ports["RD_DATA"][i*width:(i+1)*width])))
        else:
            inputs = set().union(*(bits(v) for key, v in ports.items() if directions[key] == "input"))
            outputs = set().union(*(bits(v) for key, v in ports.items() if directions[key] == "output"))
            edges.append((inputs, outputs))
    assert seen == set(memory_observers)
    assert sorted(geometry) == [(640, 32)] + [(4096, 32)] * 6 + [(13824, 32)]
    while True:
        more = set().union(*(output for source, output in edges if source & reached))
        if more <= reached:
            break
        reached |= more
    calls = {}
    for fn, declaration in (
        ("layer_base", "    wire [13:0] f_partial_address = layer_base(f_partial_layer) + {2'd0,f_partial_slot,f_partial_chunk};"),
        ("partial_slot_for", "    wire [8:0] f_partial_slot = partial_slot_for(f_partial_position,f_partial_head,f_partial_word);")):
        lines = [i for i, line in enumerate(guard_source.decode().splitlines(), 1) if line == declaration]
        assert len(lines) == 1
        calls[fn] = lines[0]
    exempt = set()
    for name in nets:
        m = re.fullmatch(r"u_guard\.(layer_base|partial_slot_for)\$func\$guard\.sv:(\d+)\$\d+\.(\$result|layer|head|position_mod|word_index)", name)
        if m and calls.get(m[1]) == int(m[2]):
            exempt.add(name)
    def ghost(name):
        return name.startswith(("f_", "g_f_", "a_f_")) or any(s.startswith("f_") for s in name.split("."))
    protected = {name: bits(row["bits"]) for name, row in nets.items()
                 if not row["hide_name"] and name not in exempt and not ghost(name)}
    protected.update({name: bits(row["bits"]) for name, row in module["ports"].items()})
    hits = [name for name, value in protected.items() if value & reached]
    assert not hits and not (sinks & reached), hits
    return {"selectors": expected, "memory_bits": sum(size*width for size, width in geometry),
            "production_signal_hits": [], "production_memory_sink_hits": [], "observer_temporaries": sorted(exempt)}


def query_prefix(smt, initial, depth):
    rows = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
    for i in range(depth + 1):
        rows.extend([f"(declare-fun s{i} () {TOP}_s)", f"(assert ({TOP}_h s{i}))", f"(assert ({TOP}_u s{i}))",
                     f"(assert (= ({TOP}_is s{i}) {'true' if initial and i == 0 else 'false'}))"])
        if i:
            rows.append(f"(assert ({TOP}_t s{i-1} s{i}))")
    if initial:
        rows.extend([f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n_i| s0)))", f"(assert (not (|{TOP}_n reset_n_i| s1)))"])
    return rows


def check_queries(directory, count, negative, sha):
    inputs_raw = (directory / "INPUTS.json").read_bytes()
    finished = json.loads((directory / "FINISHED.json").read_bytes())
    assert finished["inputs_sha256"] == sha(inputs_raw)
    assert finished["passed"] and finished["source_unchanged"] and finished["yosys_exit"] == 0
    assert finished["production_proof"] == (not negative)
    assert finished["expected_negative_detected"] == negative
    smt = (directory / "design.smt2").read_text()
    contract = load(Path(__file__).with_name("audit_contract.py"))
    contract.unrestricted_state_predicates(smt, TOP)
    assert len(re.findall(r"^; yosys-smt2-assert ", smt, re.M)) == count
    assert "; yosys-smt2-assume " not in smt
    record = json.loads((directory / "INDUCTION-SUPPORT.json").read_text())
    labels, support = record["conclusion_sources"], record["earlier_state_assertions"]
    assert set(labels) == set(support) == {str(i) for i in range(count)}
    for indices in support.values():
        assert indices and indices == sorted(set(indices)) and all(type(i) is int and 0 <= i < count for i in indices)
    queries = {}
    if negative:
        witness = json.loads((directory / "NEGATIVE-WITNESS.json").read_text())
        ports = json.loads((directory / "elaborated.json").read_text())["modules"][TOP]["ports"]
        assert set(witness["inputs"]) == {str(i) for i in range(7)}
        target = witness["target_assertion"]
        assert type(target) is int and 0 <= target < count
        mutation = json.loads(inputs_raw)["mutation"]
        needle = ("assert(!clear_i || layer_clear || !child_reset_n);" if mutation == "lost-clear" else
                  "assert(a_kv_read_rsp_data_i == kv_read_rsp_data);")
        line = re.search(r"^; yosys-smt2-assert " + str(target) + r" \S+ parent\.sv:(\d+)\.", smt, re.M)
        assert line and (directory / "parent.sv").read_text().splitlines()[int(line[1])-1].strip() == needle
        rows = query_prefix(smt, True, 6)
        for step in range(7):
            assert set(witness["inputs"][str(step)]) == set(ports)
            for name, port in ports.items():
                width, value = len(port["bits"]), witness["inputs"][str(step)][name]
                assert type(value) is int and 0 <= value < 2**width
                literal = ("true" if value else "false") if width == 1 else f"(_ bv{value} {width})"
                rows.append(f"(assert (= (|{TOP}_n {name}| s{step}) {literal}))")
        rows += [f"(assert (not (|{TOP}_a {target}| s6)))"]
        queries["base"] = (rows, ["sat"])
    else:
        queries["reset-witness"] = (query_prefix(smt, True, 2), ["sat"])
        coverage = []
        for component in sorted(set(labels.values())):
            indices = sorted(int(i) for i, name in labels.items() if name == component)
            coverage.extend(indices)
            rows = query_prefix(smt, True, 2) + ["(assert (not (and " + " ".join(
                f"(|{TOP}_a {j}| s{i})" for i in range(3) for j in indices) + ")))"]
            queries["base-" + component.removesuffix("_monitor.inc.sv")] = (rows, ["unsat"])
        assert sorted(coverage) == list(range(count))
        for i in range(count):
            rows = query_prefix(smt, False, 2)
            rows += ["(assert (and " + " ".join(f"(|{TOP}_a {j}| s{k})" for j in support[str(i)]) + "))" for k in range(2)]
            rows += [f"(assert (not (|{TOP}_a {i}| s2)))"]
            queries[f"induction-{i:03d}"] = (rows, ["unsat"])
    assert set(finished["solver_results"]) == {s + "-" + n for s in ("z3", "cvc5") for n in queries}
    for name, (rows, answers) in queries.items():
        raw = ("\n".join(rows + ["(check-sat)"]) + "\n").encode()
        assert (directory / (name + ".smt2")).read_bytes() == raw, name
        for solver in ("z3", "cvc5"):
            row = finished["solver_results"][solver + "-" + name]
            log = (directory / (solver + "-" + name + ".log")).read_bytes()
            actual = contract.exact_answers(log, answers)
            assert row["passed"] and row["exit"] == 0 and row["query_sha256"] == sha(raw) and row["log_sha256"] == sha(log)
            assert actual == row["answers"] == row["expected"] == answers and b"(error " not in log
    return len(queries) * 2


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    for name in ("package", "prior", "proof", "out"):
        ap.add_argument("--" + name, type=Path, required=True)
    ap.add_argument("--negative", type=Path, action="append", required=True)
    args = ap.parse_args()
    here = Path(__file__).resolve().parent
    model, hash_audit, history = (load(here / name) for name in ("parent_model.py", "audit_hash.py", "audit_history.py"))
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)
    reports = {}
    contract = load(here / "audit_contract.py")
    negatives = contract.distinct_negative_paths(args.proof, args.negative)
    seen_mutations = set()
    for directory in [args.proof.resolve()] + negatives:
        inputs = json.loads((directory / "INPUTS.json").read_bytes())
        mutation = inputs["mutation"]
        assert (mutation is None) == (directory == args.proof.resolve())
        assert mutation not in seen_mutations
        seen_mutations.add(mutation)
        files, binding = model.derive(args.package.resolve(), args.prior.resolve(), here, mutation)
        for key, value in binding.items():
            # JSON converts tuple values to lists.
            assert inputs[key] == json.loads(json.dumps(value)), key
        for name, raw in files.items():
            assert (directory / name).read_bytes() == raw, name
        for name, record in inputs["files"].items():
            raw = (directory / name).read_bytes()
            assert len(raw) == record["bytes"] and model.sha(raw) == record["sha256"], name
        count = 280 + monitor_check(files["parent_monitor.inc.sv"])
        check_guard_sources(files, model, history, hash_audit)
        assert inputs["assertions"] == count
        commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS guard.sv page_hash.sv compress_boundary.sv atomic.sv mapper.sv parent.sv",
                    f"prep -top {TOP} -flatten", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                    f"select -assert-count {count} t:$assert", "select -assert-none t:$assume", "select -assert-count 2 t:$anyseq",
                    "select -assert-count 5 t:$anyconst", "select -assert-count 8 t:$mem_v2", "check -assert",
                    "write_json elaborated.json", "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
        assert (directory / "prove.ys").read_text() == "\n".join(commands) + "\n"
        module = json.loads((directory / "elaborated.json").read_text())["modules"][TOP]
        def width(shape):
            match = re.fullmatch(r"\s*(?:signed\s+)?(?:\[(\d+):(\d+)\]\s*)?", shape)
            assert match, shape
            return abs(int(match[1]) - int(match[2])) + 1 if match[1] else 1
        assert {n: len(p["bits"]) for n, p in module["ports"].items()} == {
            n: width(shape) for n, shape in binding["parent_private_boundary_inputs"].items()}
        assert {n: bool(p.get("signed", 0)) for n, p in module["ports"].items()} == {
            n: shape.lstrip().startswith("signed ") for n, shape in binding["parent_private_boundary_inputs"].items()}
        assert all(p["direction"] == "input" for p in module["ports"].values())
        assert not any(c["type"] in ("$assume", "$anyinit") for c in module["cells"].values())
        observers = observer_check(module, files["guard.sv"])
        replies = hash_audit.arbitrary_compressor_outputs(module, "u_guard.u_hash.")
        queries = check_queries(directory, count, bool(mutation), model.sha)
        replay = out / directory.name
        replay.mkdir()
        for name in ("guard.sv", "page_hash.sv", "compress_boundary.sv", "atomic.sv", "mapper.sv", "parent.sv", "prove.ys"):
            (replay / name).write_bytes((directory / name).read_bytes())
        with (replay / "yosys.log").open("w") as log:
            result = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=replay, stdout=log, stderr=subprocess.STDOUT)
        assert result.returncode == 0
        for name in ("elaborated.json", "elaborated.il", "design.smt2"):
            assert (replay / name).read_bytes() == (directory / name).read_bytes(), name
        reports[directory.name] = {"assertions": count, "queries_checked": queries, "mutation": mutation,
                                   "observers": observers, "arbitrary_sha_replies": replies, "byte_identical_elaboration": True}
    assert seen_mutations == {None, "lost-clear", "raw-read-bypass"}
    for name in ("audit_parent.py", "parent_model.py", "audit_hash.py", "audit_history.py", "parent_monitor.inc.sv"):
        (out / name).write_bytes((here / name).read_bytes())
    (out / "FINISHED.json").write_text(json.dumps({"passed": True, "reports": reports, "hardware_access": False,
        "network_access": False, "independent_projection_review": False, "projection_generator_shared_with_runner": True}, indent=2) + "\n")
    print("PARENT_AUDIT_PASSED", flush=True)


if __name__ == "__main__":
    main()
