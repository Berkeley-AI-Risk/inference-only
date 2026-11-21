"""Reconstruct the checked-parent SimpleStories source deck from local public Git objects."""

from argparse import ArgumentParser
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import subprocess


COMMIT = "470b836cbe94ecebc117fe7cfa2b9008d14951f4"
TREE = "35a5bf972a45eef735e43b2fd2c9dfdfa64074f1"
PROJECT = "demos/simplestories-v2-5m/hardware/project"
MANIFEST_SHA256 = "fe76cc67599c1bb4c4b9dcb33b8080fedf7e5526a35c84d8ba902c88201209ac"
ORDER_SHA256 = "45b0b8862c0e3c7b5928efa57fb63f3a6e40e93f25b857077f3d8a7206816354"
FPGA = "fpga/token_only_model0_ddr_board1"
CONTROLLER = f"{FPGA}/context2048_gowin_portability0/rtl/board1_context2048_atomic_kv_typed_clear_consistent.sv"
EXP_LUT = f"{FPGA}/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv"
ROM_IMAGE = f"{PROJECT}/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh"
ROM_BLOB = "606ba66e796d38c77335dc925bc8c9c2b5d00a67"
ROM_SHA256 = "c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f"
SPECIAL_EDITS = {
    "rtl/defines.v": "select_behavioral_projection",
    f"rtl/{CONTROLLER}": "qualify_busy_clear_completion_fault",
    f"rtl/{EXP_LUT}": "materialize_fixed_exp_rom_image",
    "rtl/shared_token_probe.sv": "declare_probe_signals_before_use",
}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def pinned_manifest(path):
    data = path.read_bytes()
    if sha256(data) != MANIFEST_SHA256:
        raise ValueError("Expected the exact historical SOURCES.sha256")
    entries = {}
    for line in data.decode("ascii").splitlines():
        digest, name = line.split("  ", 1)
        source = PurePosixPath(name)
        if (source.is_absolute() or ".." in source.parts or source.as_posix() != name
                or len(source.parts) < 2 or name in entries or not re.fullmatch("[0-9a-f]{64}", digest)):
            raise ValueError(f"Invalid manifest entry {name}")
        entries[name] = digest
    original = [name for name in entries if not name.startswith("rtl/")]
    if len(entries) != 77 or original != [f"rtl-original/{CONTROLLER}"]:
        raise ValueError("Expected the 76 ordered elaboration inputs and the historical controller")
    return data, entries


def git(repo, *args):
    return subprocess.check_output(
        ["git", "--no-replace-objects", "-c", "protocol.allow=never", "-C", str(repo), *args],
        env={**os.environ, "GIT_NO_LAZY_FETCH": "1", "GIT_TERMINAL_PROMPT": "0", "GIT_OPTIONAL_LOCKS": "0"},
    )


def local_blobs(repo):
    if git(repo, "rev-parse", "--verify", f"{COMMIT}^{{tree}}").decode().strip() != TREE:
        raise ValueError("Unexpected public commit tree")
    entries = {}
    for row in git(repo, "ls-tree", "-r", "-z", COMMIT, "--", PROJECT).split(b"\0"):
        if row:
            fields, name = row.decode("ascii").split("\t", 1)
            mode, kind, blob = fields.split()
            if kind == "blob" and mode in {"100644", "100755"}:
                entries[name] = blob
    return entries


def read_blob(repo, blob):
    raw = git(repo, "cat-file", "blob", blob)
    header = f"blob {len(raw)}\0".encode("ascii")
    if hashlib.sha1(header + raw).hexdigest() != blob:
        raise ValueError(f"Bytes disagree with the public Git blob {blob}")
    return raw


def replace_once(raw, before, after):
    if raw.count(before) != 1:
        raise ValueError(f"Expected one source anchor {before!r}")
    return raw.replace(before, after, 1)


def inline_rom(raw, words):
    start = b"    initial begin : load_complete_image\n"
    end = b"    end\n\n    // Read/selection"
    _, found, tail = raw.partition(start)
    loader, end_found, _ = tail.partition(end)
    if not found or not end_found or b"        $readmemh(FILE, initialization_image);\n" not in loader:
        raise ValueError("Expected the public parameterized initialization block")
    # The public loop initializes offsets 0, 1024, 2048 and 3072 on every
    # iteration. Retain that assignment order and keep the endpoint separate.
    assignments = []
    for address in range(1024):
        for offset in (0, 1024, 2048, 3072):
            index = address + offset
            assignments.append(f"        value_mem[{index}] = 32'h{words[index]};\n")
    assignments.append(f"        endpoint_value = 32'h{words[4096]};\n")
    return replace_once(raw, start + loader + end, start + "".join(assignments).encode("ascii") + end)


def edit_source(name, raw, words):
    if name == "rtl/defines.v":
        return replace_once(raw, b"\x60define BOARD1_PROJECTION_MAC_NATIVE\n", b"\n")
    if name == f"rtl/{CONTROLLER}":
        return replace_once(
            raw,
            b"                            if (!write_aborted_q &&\n"
            b"                                kv_write_cpl_fault_i)\n",
            b"                            // While CLEAR is active the typed boundary\n"
            b"                            // marks every completion as faulted.  A\n"
            b"                            // completion consumed on the CLEAR edge is a\n"
            b"                            // cancelled acknowledgement, not an endpoint\n"
            b"                            // failure.  This mirrors the read path's\n"
            b"                            // \x60!clear_i && !read_aborted_q\x60 guard below.\n"
            b"                            if (!clear_i && !write_aborted_q &&\n"
            b"                                kv_write_cpl_fault_i)\n",
        )
    if name == "rtl/shared_token_probe.sv":
        raw = replace_once(raw, b"    logic core_fault_to_boundary_q;\n", b"\n")
        raw = replace_once(raw, b"    wire auth_fault;\n", b"\n")
        return replace_once(
            raw,
            b"    end\n\n    board1_private_model_ddr_cdc u_model_cdc (\n",
            b"    end\n    logic core_fault_to_boundary_q; wire auth_fault;\n"
            b"    board1_private_model_ddr_cdc u_model_cdc (\n",
        )
    if name == f"rtl/{EXP_LUT}":
        return inline_rom(raw, words)
    return raw


def reconstruct(repo, manifest, out):
    manifest_data, expected = pinned_manifest(manifest)
    blobs = local_blobs(repo)
    if blobs[ROM_IMAGE] != ROM_BLOB:
        raise ValueError("Wrong public exponent image blob")
    image = read_blob(repo, ROM_BLOB)
    words = image.decode("ascii").splitlines()
    if sha256(image) != ROM_SHA256 or len(words) != 4097 or any(not re.fullmatch("[0-9a-f]{8}", word) for word in words):
        raise ValueError("Expected 4,096 low words and the separate endpoint from the public image")

    raw_matches, blanked_matches, generated, checks, raw_cache = [], [], {}, {}, {}
    for name, digest in expected.items():
        public_path = f"{PROJECT}/{name.split('/', 1)[1]}"
        blob = blobs[public_path]
        if blob not in raw_cache:
            raw_cache[blob] = read_blob(repo, blob)
        raw = raw_cache[blob]
        blanked, count = re.subn(rb"(?m)^\x60default_nettype (?:none|wire)\n", b"\n", raw)
        updated = edit_source(name, blanked, words)
        if sha256(raw) == digest:
            raw_matches.append(name)
        if sha256(blanked) == digest:
            blanked_matches.append(name)
        if sha256(updated) != digest:
            raise ValueError(f"Reconstructed bytes disagree with SOURCES.sha256 for {name}")
        generated[name] = updated
        checks[name] = {
            "expected_sha256": digest,
            "public_path": public_path,
            "public_git_blob": blob,
            "public_sha256": sha256(raw),
            "public_bytes": len(raw),
            "blanked_nettype_lines": count,
            "specific_edit": SPECIAL_EDITS.get(name),
            "reconstructed_bytes": len(updated),
        }

    blanked_mismatches = set(expected) - set(blanked_matches)
    if blanked_mismatches != SPECIAL_EDITS.keys():
        raise ValueError("Unexpected source deltas after blanking the historical directives")
    if len(raw_matches) != 1 or len(blanked_matches) != 73:
        raise ValueError("Unexpected raw or directive-only reconstruction counts")
    order = "".join(name.removeprefix("rtl/") + "\n" for name in expected if name.startswith("rtl/")).encode("ascii")
    if sha256(order) != ORDER_SHA256:
        raise ValueError("The manifest order does not reproduce the historical rtl/FILES.txt")

    # Create a fresh private output only when every derivation already agrees.
    out.mkdir(mode=0o700)
    deck = out / "deck"
    (deck / "rtl").mkdir(parents=True)
    (deck / "SOURCES.sha256").write_bytes(manifest_data)
    (deck / "rtl/FILES.txt").write_bytes(order)
    for name, data in generated.items():
        target = deck / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
    for name, digest in expected.items():
        if sha256((deck / name).read_bytes()) != digest:
            raise ValueError(f"Written bytes disagree with SOURCES.sha256 for {name}")
    receipt = {
        "checked_utc": datetime.now(timezone.utc).isoformat(),
        "public_commit": COMMIT,
        "public_tree": TREE,
        "public_subtree": PROJECT,
        "local_git_repository": str(repo),
        "historical_manifest_sha256": MANIFEST_SHA256,
        "reconstructed_elaboration_order_sha256": ORDER_SHA256,
        "source_manifest_member_order": list(expected),
        "reconstructed_member_count": len(checks),
        "raw_public_matches_in_manifest": raw_matches,
        "matches_after_nettype_blanking": len(blanked_matches),
        "mismatches_after_nettype_blanking": sorted(blanked_mismatches),
        "member_private_source_inputs_needed": [],
        "blanked_nettype_line_counts_across_manifest": dict(Counter(row["blanked_nettype_lines"] for row in checks.values())),
        "exp_rom": {"public_path": ROM_IMAGE, "public_git_blob": ROM_BLOB, "public_sha256": ROM_SHA256,
                    "initialized_low_words": 4096, "separate_endpoint_words": 1, "endpoint_hex": words[4096]},
        "members": checks,
    }
    (out / "RECONSTRUCTION.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n")
    print(f"Verified {len(checks)} source-manifest names and SHA-256 digests.")


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument("--public-git", type=Path, required=True, help="Local Git repository containing the pinned commit")
    parser.add_argument("--manifest", type=Path, default=Path(__file__).with_name("SOURCES.sha256"))
    parser.add_argument("--out", type=Path, required=True, help="Fresh private output directory")
    args = parser.parse_args()
    reconstruct(args.public_git.resolve(), args.manifest, args.out.absolute())


if __name__ == "__main__":
    main()
