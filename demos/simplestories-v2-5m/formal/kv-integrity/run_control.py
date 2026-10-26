"""Source-bound guard/staging/hash-wrapper checks; not a full K/V integrity theorem."""
if not __debug__:
    raise SystemExit("Proof checks require assertions; do not use Python -O or -OO.")

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import time

TOP = "board1_kv_integrity_guard"
GUARD_PATH = "variants/kv-protected/hardware/project/kv_integrity_guard.sv"
HASH_PATH = "variants/kv-protected/hardware/project/kv_page_hash.sv"
GUARD_SHA = "4a90d4233f628c3ca69e42266c0a9064c5ffd766b45e2e403389696a0a2d2299"
HASH_SHA = "3ee9a8a716916dcaba6d3434f722b301b3e4fb6b258ee429a457bb246191faba"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--run", type=Path, required=True)
    parser.add_argument("--induction", type=int, default=2)
    parser.add_argument("--timeout", type=int, default=120)
    parser.add_argument("--negative-clear", action="store_true")
    parser.add_argument("--negative-write-data", action="store_true", help="Formal-only faulty copy taking write payload from untrusted DDR replies.")
    parser.add_argument("--write-history", action="store_true", help="Also prove accepted-write and tag-publication history.")
    parser.add_argument("--partial-history", action="store_true", help="Also track an arbitrary partial-RAM word back to an accepted internal write.")
    parser.add_argument("--tag-history", action="store_true", help="Also trace arbitrary expected-tag RAM chunks to current-generation write hashes.")
    parser.add_argument("--staging", action="store_true", help="Also prove full staging-RAM correspondence.")
    parser.add_argument("--compose-hash", action="store_true", help="Use the real page-hash wrapper with its own monitor; abstract only the SHA compressor.")
    parser.add_argument("--split", action="store_true", help="Split induction conclusions; hypotheses still contain every assertion.")
    parser.add_argument("--component-hypotheses", action="store_true", help="Use only relevant component invariants at earlier induction states; never add assumptions.")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--quiet", action="store_true", help="Print start, failures and final status; retain every raw query and answer.")
    args = parser.parse_args()
    assert 2 <= args.induction <= 8 and 1 <= args.timeout <= 600
    negative = args.negative_clear or args.negative_write_data
    assert not (args.negative_clear and args.negative_write_data)
    assert not args.negative_write_data or args.write_history
    assert not args.partial_history or args.write_history
    assert not args.tag_history or args.write_history
    assert 1 <= args.jobs <= 16 and not (args.split and negative)
    assert not args.component_hypotheses or args.split
    assert not args.compose_hash or args.staging
    here, package, run = Path(__file__).resolve().parent, args.package.resolve(), args.run.resolve()
    manifest_raw = (package / "MANIFEST.json").read_bytes()
    manifest = json.loads(manifest_raw)["files"]
    production = (package / GUARD_PATH).read_bytes()
    hash_source = (package / HASH_PATH).read_bytes()
    assert sha(production) == GUARD_SHA == manifest[GUARD_PATH]["sha256"]
    assert sha(hash_source) == HASH_SHA == manifest[HASH_PATH]["sha256"]
    components = {"control_monitor.inc.sv": (here / "control_monitor.inc.sv").read_bytes()}
    monitor = components["control_monitor.inc.sv"]
    if args.staging:
        components["staging_monitor.inc.sv"] = (here / "staging_monitor.inc.sv").read_bytes()
        monitor += b"\n" + components["staging_monitor.inc.sv"]
    if args.write_history:
        components["write_history_monitor.inc.sv"] = (here / "write_history_monitor.inc.sv").read_bytes()
        monitor += b"\n" + components["write_history_monitor.inc.sv"]
    if args.partial_history:
        components["partial_history_monitor.inc.sv"] = (here / "partial_history_monitor.inc.sv").read_bytes()
        monitor += b"\n" + components["partial_history_monitor.inc.sv"]
    if args.tag_history:
        components["tag_history_monitor.inc.sv"] = (here / "tag_history_monitor.inc.sv").read_bytes()
        monitor += b"\n" + components["tag_history_monitor.inc.sv"]
    boundary = (here / "hash_boundary.sv").read_bytes()
    hash_monitor = b""
    connection_monitor = b""
    if args.compose_hash:
        hash_monitor = (here / "hash_monitor.inc.sv").read_bytes()
        connection_monitor = (here / "hash_connection_monitor.inc.sv").read_bytes()
        monitor += b"\n" + connection_monitor
        components["hash_connection_monitor.inc.sv"] = connection_monitor
        if args.write_history:
            components["write_hash_connection_monitor.inc.sv"] = (here / "write_hash_connection_monitor.inc.sv").read_bytes()
            monitor += b"\n" + components["write_hash_connection_monitor.inc.sv"]
        assert hash_source.count(b"\nendmodule") == 1
        header_seam = b"    output wire fault_o\n);"
        header_extra = (b"    output wire fault_o,\n    output wire [511:0] f_link_header_q_o,\n"
                        b"    output wire [6:0] f_link_words_q_o,\n    output wire [3:0] f_link_state_q_o\n);")
        tap_assignments = (b"    assign f_link_header_q_o = header_q;\n"
                           b"    assign f_link_words_q_o = words_q;\n"
                           b"    assign f_link_state_q_o = state_q;\n")
        assert hash_source.count(header_seam) == 1
        boundary = hash_source.replace(header_seam, header_extra).replace(
            b"\nendmodule", b"\n" + tap_assignments + hash_monitor + b"\nendmodule")
    assert b"assume(" not in monitor + boundary
    assert production.count(b"\nendmodule") == 1
    tested = production
    mutation = None
    if negative:
        if args.negative_clear:
            old = b"if(clear_i) begin\n                if(!clear_seen_q"
            new = b"if(clear_i) begin\n                fault_q<=0;\n                if(!clear_seen_q"
        else:
            old = b"if(write_fire) word_q<=s_wr_data;"
            new = b"if(write_fire) word_q<=m_rd_rsp_data;"
        assert production.count(old) == 1
        tested = production.replace(old, new)
        mutation = {"old": old.decode(), "new": new.decode(),
                    "scope": "Deliberately faulty formal-only copy; never programmed or released."}
    instrumented = tested.replace(b"\nendmodule", b"\n" + monitor + b"\nendmodule")
    if args.tag_history:
        tag_declaration = b"    wire [31:0] tag_data[0:5];"
        tag_read_seam = b"        assign tag_data[bank]=read_q;"
        assert instrumented.count(tag_declaration) == instrumented.count(tag_read_seam) == 1
        instrumented = instrumented.replace(tag_declaration, tag_declaration + b"\n    wire [31:0] f_tag_memory[0:5];")
        instrumented = instrumented.replace(tag_read_seam,
            tag_read_seam + b"\n        assign f_tag_memory[bank]=memory[f_tag_address];")
    if args.compose_hash:
        declaration_seam = b"    kv_page_hash u_hash("
        tap_declarations = (b"    wire [511:0] f_hash_header;\n    wire [6:0] f_hash_words;\n"
                            b"    wire [3:0] f_hash_state;\n")
        connection_seam = b".digest_o(hash_digest),.fault_o(hash_fault));"
        connection_extra = (b".digest_o(hash_digest),.fault_o(hash_fault),\n"
                            b"        .f_link_header_q_o(f_hash_header),.f_link_words_q_o(f_hash_words),\n"
                            b"        .f_link_state_q_o(f_hash_state));")
        assert instrumented.count(declaration_seam) == instrumented.count(connection_seam) == 1
        instrumented = instrumented.replace(declaration_seam, tap_declarations + declaration_seam).replace(
            connection_seam, connection_extra)
    count = monitor.count(b"assert(") + hash_monitor.count(b"assert(")
    constants = monitor.count(b"(* anyconst *)") + hash_monitor.count(b"(* anyconst *)")
    hash_component_name = "page_hash.sv" if args.compose_hash else "hash_boundary.sv"
    production_hash_name = "production-page-hash.sv" if args.compose_hash else "production-page-hash-not-elaborated.sv"
    files = {"production.sv": production, "tested.sv": tested,
             production_hash_name: hash_source,
             "guard.sv": instrumented, "monitor.inc.sv": monitor,
             hash_component_name: boundary, "runner.py": Path(__file__).read_bytes()}
    files.update(components)
    if args.compose_hash:
        files["hash_monitor.inc.sv"] = hash_monitor
        files["hash_connection_monitor.inc.sv"] = connection_monitor
        files["compress_boundary.sv"] = (here / "compress_boundary.sv").read_bytes()
    commands = ["read_verilog -formal -sv -nosynthesis -D SYNTHESIS guard.sv " + hash_component_name +
                (" compress_boundary.sv" if args.compose_hash else ""),
                f"prep -top {TOP} -flatten", "async2sync", "chformal -lower", "opt_clean", "dffunmap",
                f"select -assert-count {count} t:$assert", "select -assert-none t:$assume",
                "select -assert-count 2 t:$anyseq" if args.compose_hash else "select -assert-count 5 t:$anyseq",
                f"select -assert-count {constants} t:$anyconst",
                "select -assert-count 8 t:$mem_v2", "check -assert",
                "write_json elaborated.json", "write_rtlil elaborated.il", "write_smt2 -wires design.smt2"]
    files["prove.ys"] = ("\n".join(commands) + "\n").encode()
    run.mkdir(parents=True, exist_ok=False)
    for name, data in files.items():
        (run / name).write_bytes(data)
    inputs = {"manifest_sha256": sha(manifest_raw), "production_guard_sha256": GUARD_SHA,
              ("page_hash_source_sha256" if args.compose_hash else "page_hash_source_not_elaborated_sha256"): HASH_SHA,
              "assertions": count, "induction_length": args.induction,
              "timeout_seconds": args.timeout, "mutation": mutation,
              "staging_observer": args.staging, "split_induction": args.split,
              "write_history": args.write_history,
              "partial_history": args.partial_history,
              "tag_history": args.tag_history,
              "composed_page_hash": args.compose_hash,
              "component_hypotheses": args.component_hypotheses,
              "read_only_hash_register_taps": {"header_q": 512, "words_q": 7, "state_q": 4} if args.compose_hash else {},
              "files": {name: {"sha256": sha(data), "bytes": len(data)} for name, data in files.items()},
              "hash_boundary": ({"sha_done": 1, "sha_state": 256, "unused_busy_bits_optimized_away": 1} if args.compose_hash else
                                {"begin_ready": 1, "word_ready": 1, "digest_valid": 1, "digest": 256, "fault": 1}),
              "environment": ("Base reset at states 0 and 1; other guard inputs and SHA compressor replies unrestricted." if args.compose_hash else
                              "Base reset at states 0 and 1; other inputs and page-hash replies unrestricted."),
              "geometry_reduced": False, "timeout_reduced": False,
              "hardware_access": False, "network_access": False}
    (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2) + "\n")
    started = time.monotonic()
    print(f"KV_CONTROL_STARTED assertions={count} run={run}", flush=True)
    with (run / "yosys.log").open("w") as output:
        proc = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=run,
                              stdout=output, stderr=subprocess.STDOUT)
    records, memories = {}, {}
    if proc.returncode == 0:
        module = json.loads((run / "elaborated.json").read_text())["modules"][TOP]
        memories = {name: {key: int(cell["parameters"][key], 2) for key in ("SIZE", "WIDTH")}
                    for name, cell in module["cells"].items() if cell["type"] == "$mem_v2"}
        assert sorted((r["SIZE"], r["WIDTH"]) for r in memories.values()) == (
            [(640, 32)] + [(4096, 32)] * 6 + [(13824, 32)])
        smt = (run / "design.smt2").read_text()
        assert len(re.findall(r"^; yosys-smt2-assert ", smt, re.M)) == count
        k = max(args.induction, 4) if negative else args.induction

        def chain(initial, length):
            parts = ["(set-logic ALL)", "(set-option :produce-models true)", smt]
            for step in range(length + 1):
                parts += [f"(declare-fun s{step} () {TOP}_s)", f"(assert ({TOP}_h s{step}))",
                          f"(assert ({TOP}_u s{step}))",
                          f"(assert (= ({TOP}_is s{step}) {'true' if initial and step == 0 else 'false'}))"]
                if step:
                    parts += [f"(assert ({TOP}_t s{step-1} s{step}))"]
            if initial:
                parts += [f"(assert ({TOP}_i s0))", f"(assert (not (|{TOP}_n reset_n| s0)))",
                          f"(assert (not (|{TOP}_n reset_n| s1)))"]
            return parts

        queries = {"base": "\n".join(chain(True, k) + ["(check-sat)",
            "(assert (not (and " + " ".join(f"({TOP}_a s{i})" for i in range(k + 1)) + ")))",
            "(check-sat)"]) + "\n"}
        if not negative:
            prefix = chain(False, k) + [f"(assert ({TOP}_a s{i}))" for i in range(k)]
            if args.split:
                support = None
                if args.component_hypotheses:
                    groups = {}
                    for component, raw in components.items():
                        assert instrumented.count(raw) == 1
                        first = instrumented[:instrumented.index(raw)].count(b"\n") + 1
                        groups[component] = (first, first + raw.count(b"\n"))
                    labels = {}
                    for index, filename, line in re.findall(
                        r"^; yosys-smt2-assert (\d+) \S+ (guard\.sv|page_hash\.sv):(\d+)\.", smt, re.M):
                        matches = (["hash_monitor.inc.sv"] if filename == "page_hash.sv" else
                                   [name for name, (first, last) in groups.items() if first <= int(line) <= last])
                        assert len(matches) == 1
                        labels[int(index)] = matches[0]
                    assert set(labels) == set(range(count))
                    needed = {
                        "control_monitor.inc.sv": ["control_monitor.inc.sv"],
                        "staging_monitor.inc.sv": ["control_monitor.inc.sv", "staging_monitor.inc.sv"],
                        "write_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv"],
                        "partial_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "partial_history_monitor.inc.sv"],
                        "tag_history_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "tag_history_monitor.inc.sv"],
                        "hash_monitor.inc.sv": ["hash_monitor.inc.sv"],
                        "hash_connection_monitor.inc.sv": ["control_monitor.inc.sv", "staging_monitor.inc.sv", "hash_monitor.inc.sv", "hash_connection_monitor.inc.sv"],
                        "write_hash_connection_monitor.inc.sv": ["control_monitor.inc.sv", "write_history_monitor.inc.sv", "hash_monitor.inc.sv", "write_hash_connection_monitor.inc.sv"],
                    }
                    support = {str(i): sorted(j for j, name in labels.items() if name in needed[labels[i]]) for i in range(count)}
                    (run / "INDUCTION-SUPPORT.json").write_text(json.dumps(
                        {"conclusion_sources": labels, "earlier_state_assertions": support}, indent=2) + "\n")
                for index in range(count):
                    local_prefix = prefix
                    if support is not None:
                        local_prefix = chain(False, k) + ["(assert (and " + " ".join(
                            f"(|{TOP}_a {j}| s{i})" for j in support[str(index)]) + "))" for i in range(k)]
                    queries[f"induction-{index:02d}"] = "\n".join(local_prefix + [
                        f"(assert (not (|{TOP}_a {index}| s{k})))", "(check-sat)"]) + "\n"
            else:
                queries["induction"] = "\n".join(prefix + [
                    f"(assert (not ({TOP}_a s{k})))", "(check-sat)"]) + "\n"
            queries["fault-clear-witness"] = "\n".join(chain(True, 4) + [
                f"(assert (|{TOP}_n reset_n| s4))", f"(assert (|{TOP}_n f_previous_fault| s4))",
                f"(assert (|{TOP}_n clear_i| s4))", f"(assert (|{TOP}_n fault_o| s4))",
                "(check-sat)"]) + "\n"
        for name, query in queries.items():
            (run / (name + ".smt2")).write_text(query)

        def solve(item):
            solver, name = item
            begin = time.monotonic()
            argv = ([shutil.which("z3"), f"-T:{args.timeout}", "-smt2"] if solver == "z3" else
                    [shutil.which("cvc5"), f"--tlimit={args.timeout * 1000}", "--lang=smt2", "--incremental"])
            label = solver + "-" + name
            timed_out = False
            with (run / (label + ".log")).open("w") as output:
                try:
                    result = subprocess.run(argv + [str(run / (name + ".smt2"))], stdout=output,
                                            stderr=subprocess.STDOUT, timeout=args.timeout + 30)
                    status = result.returncode
                except subprocess.TimeoutExpired:
                    status, timed_out = None, True
            log = (run / (label + ".log")).read_text()
            answers = [line for line in log.splitlines() if line in ("sat", "unsat", "unknown")]
            expected = (["sat", "sat" if negative else "unsat"] if name == "base" else
                        ["sat"] if name == "fault-clear-witness" else ["unsat"])
            row = {"passed": status == 0 and answers == expected and "(error " not in log,
                   "exit": status, "timed_out": timed_out, "answers": answers, "expected": expected,
                   "seconds": time.monotonic() - begin, "query_sha256": sha(queries[name].encode()),
                   "log_sha256": sha(log.encode())}
            if solver == "z3" and answers and answers[-1] == "sat" and name != "fault-clear-witness":
                names = ["reset_n", "clear_i", "model_locked_i", "state_q", "owner_q", "fault_q",
                         "fault_o", "terminal_now", "aborted_q", "f_previous_fault", "f_previous_clear",
                         "cache_valid_q", "f_verified", "hash_write_q", "hash_digest_valid", "hash_fault",
                         "read_fire", "write_fire", "upstream_fault_i"]
                if args.staging:
                    names += ["f_stage_address", "f_stage_active", "f_stage_written", "f_stage_hashed",
                              "f_stage_total", "f_stage_value", "f_stage_hash_value", "f_stage_read_seen",
                              "f_stage_read_target", "f_stage_fill", "f_stage_hash", "f_stage_miss",
                              "positions_q", "total_slots_q", "target_slot_q", "scan_slot_q", "hash_slot_q",
                              "chunk_q", "stage_data_q", "stage_address", "cache_positions_q", "assembly_q"]
                if args.write_history:
                    names += [name for name in module["netnames"] if name.startswith("f_wr_")]
                    names += ["population_q", "population_layer_q", "population_position_q", "next_head_q", "next_word_q",
                              "layer_q", "position_q", "head_q", "row_word_q", "page_q", "group_head_q", "role_q",
                              "positions_q", "chunk_q", "total_slots_q", "hash_slot_q", "hash_position_q", "hash_group_word_q"]
                    names += [f"prefix_q[{i}]" for i in range(6)]
                if args.partial_history:
                    names += [name for name in module["netnames"] if name.startswith("f_partial_")]
                    names += ["partial_address", "partial_data_q", "assembly_q", "word_q"]
                if args.tag_history:
                    names += [name for name in module["netnames"] if name.startswith("f_tag_")]
                    names += ["tag_address", "expected_q", "digest_q", "cache_hit", "rd_legal"]
                names = list(dict.fromkeys(names))
                diagnostic = queries[name] + "(get-value (" + " ".join(
                    f"(|{TOP}_n {wire}| s{i})" for i in range(k + 1) for wire in names) + " " + " ".join(
                    f"(|{TOP}_a {i}| s{k})" for i in range(count)) + "))\n"
                (run / (label + "-countermodel.smt2")).write_text(diagnostic)
                with (run / (label + "-countermodel.log")).open("w") as output:
                    subprocess.run(argv + [str(run / (label + "-countermodel.smt2"))], stdout=output,
                                   stderr=subprocess.STDOUT, timeout=args.timeout + 30)
            if not args.quiet or not row["passed"]:
                print("KV_CONTROL_" + label + " " + json.dumps(row), flush=True)
            return label, row

        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            records = dict(pool.map(solve, [(solver, name) for solver in ("z3", "cvc5") for name in queries]))
    unchanged = all(sha((run / name).read_bytes()) == sha(data) for name, data in files.items())
    expected_records = 2 if negative else 2 * (count + 2 if args.split else 3)
    passed = proc.returncode == 0 and len(records) == expected_records and unchanged and all(
        row["passed"] for row in records.values())
    receipt = {"passed": passed, "assertions": count, "yosys_exit": proc.returncode,
               "seconds": time.monotonic() - started, "inputs_sha256": sha((run / "INPUTS.json").read_bytes()),
               "source_unchanged": unchanged, "solver_results": records, "memories": memories,
               "production_proof": passed and not negative,
               "expected_negative_detected": passed and negative,
               "scope": ("Expected-tag RAM/hash-reply provenance and publication, with other monitors selected in INPUTS; not attention-parent composition or cryptographic correctness."
                         if args.tag_history else "Accepted internal-write and full partial-RAM/hash-input history, with other monitors selected in INPUTS; not yet expected-tag RAM provenance or attention-parent composition."
                         if args.partial_history else "Accepted internal-write history and four-tag publication control, with other monitors selected in INPUTS; not yet tag/partial-RAM content history or attention-parent composition."
                         if args.write_history else "Real guard plus real page-hash wrapper: staging/read correspondence, identity header, framing and sequencing with arbitrary SHA replies; not expected-tag provenance or attention-parent composition."
                         if args.compose_hash else "Guard control and staging/hash-input/read-output correspondence with arbitrary page-hash replies; not cryptography or parent composition."
                         if args.staging else "Guard control/cache-admission safety with arbitrary page-hash replies; not data/hash correspondence or composition."),
               "hardware_access": False, "network_access": False}
    (run / "FINISHED.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print("KV_CONTROL_FINISHED passed=" + str(passed), flush=True)
    raise SystemExit(0 if passed else 1)


if __name__ == "__main__":
    main()
