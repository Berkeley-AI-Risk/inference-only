"""Reconstruct the checked RTL deck and regenerate the four K/V record books."""

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import shutil
import subprocess
import sys


HERE = Path(__file__).resolve().parent
PARENT = "kv-joined-book-checked-sat"
RECORD = "kv-write-record"
CONTROLLER = (
    "fpga/token_only_model0_ddr_board1/context2048_gowin_portability0/rtl/"
    "board1_context2048_atomic_kv_typed_clear_consistent.sv"
)
WRONG_CONTROLLER_SHA256 = "c65adc9ba58678b9c420eae431ce9a8dff07d24fe67c9579c074831d6432f58e"
STOCK_TRANSLATOR_SHA256 = "264b13524d49ead3427f791f53cdc0b672729636cf5b03790b67ad4a70963735"
CORRECTED_TRANSLATOR_SHA256 = "99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c"
BOOKS = (
    "kv-write-record-step.lisp",
    "kv-write-record-lift.lisp",
    "kv-write-record.lisp",
    "kv-write-record-mismatched-rows.lisp",
)


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def verify_candidate():
    manifest = read_json(HERE / "MANIFEST.json")["members"]
    for name, pin in manifest.items():
        relative = PurePosixPath(name)
        source = HERE / relative
        if (relative.is_absolute() or ".." in relative.parts or relative.as_posix() != name
                or not source.is_file() or source.is_symlink()
                or source.stat().st_size != pin["bytes"] or sha256(source) != pin["sha256"]):
            raise ValueError(f"Candidate member does not match its manifest: {name}")
    return manifest


def apply_patch(original, target, patch, expected_sha256):
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("xb") as stream:
        stream.write(original.read_bytes())
    subprocess.run(["patch", "-s", "-f", str(target), str(patch)],
                   cwd=target.parent, stdin=subprocess.DEVNULL, check=True)
    if sha256(target) != expected_sha256:
        raise ValueError(f"Patched bytes do not match the recorded hash: {target.name}")


def reproduce(repo, out, stock_translator):
    manifest = verify_candidate()
    if stock_translator is not None and sha256(stock_translator) != STOCK_TRANSLATOR_SHA256:
        raise ValueError("Expected the pinned stock ACL2 8.7 svstmt-compile.lisp")

    out.mkdir(mode=0o700)
    python = [sys.executable, "-I", "-S", "-B"]
    subprocess.run(python + [str(HERE / "reconstruction/reconstruct_sources.py"),
                              "--public-git", str(repo), "--out", str(out / "public-deck")],
                   cwd=out, check=True)
    reconstruction = read_json(out / "public-deck/RECONSTRUCTION.json")
    (out / "public-deck/deck").rename(out / PARENT)

    reference_books = {f"{RECORD}/{book}" for book in BOOKS}
    for name in manifest:
        relative = name.removeprefix("proof/")
        if name.startswith("proof/") and relative not in reference_books:
            dest = out / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            with dest.open("xb") as stream:
                stream.write((HERE / name).read_bytes())

    record = out / RECORD
    apply_patch(out / PARENT / "rtl" / CONTROLLER,
                record / "rtl-mismatched-rows" / CONTROLLER,
                record / "mismatched-rows.patch", WRONG_CONTROLLER_SHA256)
    if any((record / book).exists() for book in BOOKS):
        raise ValueError("The four record books must be absent before generation")
    subprocess.run(python + ["make_record_book.py"], cwd=record, check=True)

    books = {}
    for name in BOOKS:
        path = record / name
        if path.read_bytes() != (HERE / "proof" / RECORD / name).read_bytes():
            raise ValueError(f"Regenerated book differs from the certified source: {name}")
        books[name] = sha256(path)

    translator = None
    if stock_translator is not None:
        target = out / "translator/svstmt-compile.lisp"
        apply_patch(stock_translator, target, HERE / "translator/svstmt-compile.patch",
                    CORRECTED_TRANSLATOR_SHA256)
        translator = {"stock_sha256": STOCK_TRANSLATOR_SHA256, "corrected_sha256": sha256(target)}

    for name, pin in reconstruction["members"].items():
        if sha256(out / PARENT / name) != pin["expected_sha256"]:
            raise ValueError(f"Reconstructed input changed during generation: {name}")

    receipt = {
        "public_commit": reconstruction["public_commit"],
        "public_tree": reconstruction["public_tree"],
        "verified_rtl_names": reconstruction["reconstructed_member_count"],
        "rtl_manifest_sha256": sha256(out / PARENT / "SOURCES.sha256"),
        "elaboration_order_sha256": sha256(out / PARENT / "rtl/FILES.txt"),
        "wrong_position_controller_sha256": WRONG_CONTROLLER_SHA256,
        "regenerated_books_sha256": books,
        "translator_source_check": translator,
        "certificate_operation": "none",
    }
    (out / "REPRODUCTION.json").write_text(json.dumps(receipt, indent=2, sort_keys=True) + "\n",
                                           encoding="utf-8")
    print(f"Verified {receipt['verified_rtl_names']} RTL names and regenerated {len(books)} exact book sources.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-git", required=True, type=Path, help="Local clone with the pinned public Git objects")
    parser.add_argument("--out", required=True, type=Path, help="Fresh output directory with an existing parent")
    parser.add_argument("--stock-translator", type=Path,
                        help="Optional stock ACL2 8.7 svstmt-compile.lisp to verify the published correction")
    args = parser.parse_args()
    try:
        reproduce(args.public_git.resolve(), args.out.absolute(), args.stock_translator)
    except (OSError, ValueError, subprocess.CalledProcessError) as exc:
        parser.exit(1, f"Reproduction failed. {exc}\n")


if __name__ == "__main__":
    main()
