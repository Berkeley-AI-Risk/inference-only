"""Targeted induction-sensitivity tests on formal-only faulty model copies.

These are counterexamples to induction, NOT claims of reset-reachable FPGA
attacks. Positive source/model/query audits must pass separately. No hardware.

Every target is already proved for the unmutated model. These controls use
the full conjunction of earlier-state invariants; where the positive proof
uses a subset, adding hypotheses cannot make its UNSAT query satisfiable.
Thus that proof supplies the unmutated baseline without another solver run.
The raw-read-data control is the exception: it removes a wire lemma as well
as changing a connection. It is explicitly a two-change sensitivity test.
"""
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


# Each replacement is applied exactly once to a regenerated positive model.
# The raw-data case additionally removes the direct wire assertion, to check
# that the new accumulated-row assertion detects the wrong payload itself.
CASES = {
    "guard-epoch": ("history", "guard.sv", [("epoch_q<=epoch_q+1'b1;", "epoch_q<=epoch_q;")],
        "assert(epoch_q == f_epoch_before + 64'd1);"),
    "guard-clear": ("parent", "parent.sv", [(".clear_i(clear_i),", ".clear_i(1'b0),")],
        "assert(g_epoch_q == f_guard_epoch_before + 64'd1);"),
    "raw-read-data": ("parent", "parent.sv", [
        (".kv_read_rsp_data_i(kv_read_rsp_data),", ".kv_read_rsp_data_i(guard_rd_data),"),
        ("assert(a_kv_read_rsp_data_i == kv_read_rsp_data);", "// Direct wire lemma omitted in this fault-control model only.")],
        "assert((a_f_read_expected & a_f_read_bitmask) == (f_guard_row & a_f_read_bitmask));"),
    "aligner-group": ("attention", "attention.sv", [
        (".request_vector_i(captured_cache_vector_q[coordinate_q[5:3]*128 +: 128]),",
         ".request_vector_i(captured_cache_vector_q[(coordinate_q[5:3] ^ 3'd1)*128 +: 128]),")],
        "assert(f_att_aligner_vector == f_att_vector[coordinate_q[5:3]*128 +:128]);"),
    "aligner-zero": ("attention", "attention.sv", [
        (".request_vector_i(captured_cache_vector_q[coordinate_q[5:3]*128 +: 128]),", ".request_vector_i(128'd0),")],
        "assert(f_att_aligner_vector == f_att_vector[coordinate_q[5:3]*128 +:128]);"),
    "aligner-shift": ("attention", "attention.sv", [
        (".request_shift_i((state_q == ST_VALUE_EXP_SCAN) ? 9'sd0 : align8_shift),", ".request_shift_i(9'sd0),")],
        "assert(f_att_aligner_shift == f_att_expected_shift);"),
    "key-exponent": ("attention", "attention.sv", [("raw_score_exponent_comb[7:0];", "8'd0;")],
        "assert(pending_score_exponent_q == f_att_score_exponent);"),
    "stored-exponent": ("parent", "atomic.sv", [
        ("pending_key_exponents_q[7:0],", "8'd0,")],
        "assert(a_kv_write_req_data_o[15:0] == {a_f_value_exponents[a_write_head_q*8 +:8], a_f_key_exponents[a_write_head_q*8 +:8]});"),
    "pending-exponent": ("parent", "atomic.sv", [
        ("pending_key_exponents_q[7:0],", "8'd0,")],
        "assert(attention_cache_key_exp == a_f_key_exponents[a_response_head_q*8 +:8]);"),
    "clear-history-sticky": ("history", "guard.sv", [
        ("clear_seen_q<=clear_i;", "clear_seen_q<=clear_seen_q||clear_i;")],
        "assert(clear_seen_q == f_previous_clear);"),
    "clear-history-high": ("history", "guard.sv", [
        ("clear_seen_q<=clear_i;", "clear_seen_q<=1'b1;")],
        "assert(clear_seen_q == f_previous_clear);"),
    "digest-comparison": ("history", "guard.sv", [
        ("else if(hash_digest==expected_q) begin", "else if(1'b1) begin")],
        "if (f_previous_mismatch) assert(fault_o);"),
    "sealed-copy-return": ("history", "guard.sv", [
        ("if(live && state_q==OCAP) assembly_q[chunk_q*32 +:32]<=stage_data_q;",
         "if(live && state_q==OCAP) assembly_q[chunk_q*32 +:32]<=word_q[chunk_q*32 +:32];")],
        "assert(s_rd_rsp_data[f_stage_chunk*32 +:32] == f_stage_hash_value);"),
    "early-tag-publication": ("history", "guard.sv", [
        ("if(group_head_q && role_q) begin", "if(1'b1) begin")],
        "if (head_q && row_word_q == 8) assert(f_wr_published && f_wr_row_tags == 4);"),
    "read-beyond-prefix": ("history", "guard.sv", [
        ("!population_q && s_rd_position<prefix_q[s_rd_layer];", "!population_q;")],
        "assert(read_positions >= 1 && read_positions <= 16);"),
    "write-hash-provenance": ("history", "guard.sv", [
        ("assembly_q[chunk_q*32 +:32]<=hash_write_q ? partial_data_q : stage_data_q;",
         "assembly_q[chunk_q*32 +:32]<=stage_data_q;")],
        "if (state_q == HWORD) assert(assembly_q[f_partial_chunk*32 +:32] == f_partial_value);"),
    "cache-role": ("history", "guard.sv", [
        ("wire cache_hit=cache_identity && cache_role_q==read_role;", "wire cache_hit=cache_identity;")],
        "role_q == cache_role_q);"),
    "hash-layer": ("history", "page_hash.sv", [("29'd0,layer_i,", "29'd0,3'd0,")],
        "assert(header_q[319:288] == {29'd0,f_layer});"),
    "hash-length": ("history", "page_hash.sv", [("27'd0,positions_i,", "27'd0,5'd16,")],
        "assert(header_q[191:160] == {27'd0,f_positions});"),
    "key-raw-reply": ("attention", "attention.sv", [
        ("score_key_coordinate_q <= $signed(\n                captured_cache_vector_q[score_prefetch_coordinate*16 +: 16]);",
         "score_key_coordinate_q <= $signed(\n                private_cache_response_key_vector_i[score_prefetch_coordinate*16 +: 16]);")],
        "assert(score_key_coordinate_q == f_att_vector[coordinate_q*16 +:16]);"),
    "key-coordinate": ("attention", "attention.sv", [
        ("score_key_coordinate_q <= $signed(\n                captured_cache_vector_q[score_prefetch_coordinate*16 +: 16]);",
         "score_key_coordinate_q <= $signed(\n                captured_cache_vector_q[(score_prefetch_coordinate ^ 6'd1)*16 +: 16]);")],
        "assert(score_key_coordinate_q == f_att_vector[coordinate_q*16 +:16]);"),
    "attention-clear-live": ("attention", "attention.sv", [
        ("wire interface_live = rst_n && !clear_i && model_lock_i &&",
         "wire interface_live = rst_n && model_lock_i &&")],
        "assert(!private_cache_request_valid_o && !result_valid_o && !done_valid_o);"),
    "value-coordinate": ("attention", "attention.sv", [
        ("wire signed [15:0] lane_dynamic_operand = aligned_value_at_coordinate;",
         "wire signed [15:0] lane_dynamic_operand = $signed(aligned_value_selected_group[(coordinate_q[2:0] ^ 3'd1)*16 +: 16]);")],
        "assert(lane_dynamic_operand == f_att_aligned_value);"),
}
TOPS = {"history": "board1_kv_integrity_guard", "parent": "kv_parent_composition", "attention": "board1_context2048_attention"}


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def model_files(work, name):
    """Reconstruct one exact faulty source model from checked positive inputs."""
    stage, changed_name, replacements, needle = CASES[name]
    source = work / stage
    inp = json.loads((source / "INPUTS.json").read_bytes())
    completed = json.loads((source / "FINISHED.json").read_bytes())
    assert completed["passed"] and all(row["passed"] for row in completed["solver_results"].values())
    files = {}
    for filename, record in inp["files"].items():
        assert Path(filename).name == filename
        raw = (source / filename).read_bytes()
        assert sha(raw) == record["sha256"] and len(raw) == record["bytes"]
        if filename.endswith(".sv") or filename == "prove.ys":
            files[filename] = raw
    text = files[changed_name].decode()
    for old, new in replacements:
        assert text.count(old) == 1, (name, old)
        text = text.replace(old, new)
    files[changed_name] = text.encode()
    removed = int(name == "raw-read-data")
    count = inp["assertions"] - removed
    old = f"select -assert-count {inp['assertions']} t:$assert".encode()
    assert files["prove.ys"].count(old) == 1
    files["prove.ys"] = files["prove.ys"].replace(old, f"select -assert-count {count} t:$assert".encode())
    return files, {"stage": stage, "mutation": replacements, "target": needle,
                  "positive_inputs_sha256": sha((source / "INPUTS.json").read_bytes()),
                  "files": {n: sha(raw) for n, raw in files.items()},
                  "reset_reachable_claim": False, "hardware_access": False}


def target_index(smt, filename, source, needle):
    lines = [i for i, line in enumerate(source.splitlines(), 1) if line.strip() == needle]
    assert len(lines) == 1, (filename, needle, lines)
    targets = []
    for index, locations in re.findall(r"^; yosys-smt2-assert (\d+) \S+ (.*)$", smt, re.M):
        ranges = re.findall(r"(?:^|[|\s])" + re.escape(filename) + r":(\d+)\.\d+-(\d+)\.\d+(?=$|[|\s])", locations)
        if any(int(end) == lines[0] for _, end in ranges):
            targets.append(int(index))
    assert len(targets) == 1, (filename, needle, targets)
    return targets[0]


def target_query(smt, top, target):
    rows = ["(set-logic ALL)", smt]
    for i in range(3):
        rows += [f"(declare-fun s{i} () {top}_s)", f"(assert ({top}_h s{i}))", f"(assert ({top}_u s{i}))",
                 f"(assert (not ({top}_is s{i})))"]
        if i:
            rows += [f"(assert ({top}_t s{i-1} s{i}))"]
        if i < 2:
            rows += [f"(assert ({top}_a s{i}))"]
    rows += [f"(assert (not (|{top}_a {target}| s2)))", "(check-sat)"]
    return ("\n".join(rows) + "\n").encode()


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--work", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--jobs", type=int, default=4)
    ap.add_argument("--timeout", type=int, default=300)
    args = ap.parse_args()
    assert 1 <= args.jobs <= 16 and 1 <= args.timeout <= 600
    out = args.out.resolve()
    out.mkdir(parents=True, exist_ok=False)

    def check(item):
        name, (stage, changed_name, replacements, needle) = item
        source, run = args.work / stage, out / name
        run.mkdir()
        files, inputs = model_files(args.work, name)
        for filename, raw in files.items():
            (run / filename).write_bytes(raw)
        (run / "INPUTS.json").write_text(json.dumps(inputs, indent=2) + "\n")
        with (run / "yosys.log").open("w") as log:
            p = subprocess.run([shutil.which("yosys"), "-Q", "prove.ys"], cwd=run, stdout=log, stderr=subprocess.STDOUT)
        assert p.returncode == 0, name
        top, smt = TOPS[stage], (run / "design.smt2").read_text()
        target_file = "parent.sv" if stage == "parent" else changed_name
        target = target_index(smt, target_file, files[target_file].decode(), needle)
        query = target_query(smt, top, target)
        (run / "target.smt2").write_bytes(query)
        results = {}
        for solver in ("z3", "cvc5"):
            argv = ([shutil.which(solver), f"-T:{args.timeout}", "-smt2"] if solver == "z3" else
                    [shutil.which(solver), f"--tlimit={args.timeout*1000}", "--lang=smt2"])
            try:
                result = subprocess.run(argv + [str(run / "target.smt2")], capture_output=True, timeout=args.timeout+15)
                raw, code = result.stdout + result.stderr, result.returncode
            except subprocess.TimeoutExpired as exc:
                raw, code = (exc.stdout or b"") + (exc.stderr or b""), None
            (run / (solver + ".log")).write_bytes(raw)
            results[solver] = {"passed": code == 0 and raw.strip() == b"sat", "exit": code, "log_sha256": sha(raw)}
        result = {"passed": all(r["passed"] for r in results.values()), "target_assertion": target,
                  "model_sha256": sha(smt.encode()),
                  "query_sha256": sha(query), "solvers": results, "reset_reachable_claim": False}
        (run / "FINISHED.json").write_text(json.dumps(result, indent=2) + "\n")
        print("FAULT_CONTROL", name, result["passed"], flush=True)
        return name, result

    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        results = dict(pool.map(check, CASES.items()))
    passed = set(results) == set(CASES) and all(row["passed"] for row in results.values())
    (out / "FINISHED.json").write_text(json.dumps({"passed": passed, "cases": results,
        "reset_reachable_claim": False, "hardware_access": False, "network_access": False}, indent=2) + "\n")
    raise SystemExit(0 if passed else 1)

if __name__ == "__main__":
    main()
