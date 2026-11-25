"""Replay flash sampling and loader ordering on the released four-bank RTL."""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent
PROJECT = HERE.parents[1] / "demos/simplestories-v2-5m/variants/kv-protected/hardware/project"
BOARD = "fpga/token_only_model0_ddr_board1/"
FILES = {
    BOARD + "product_top4/rtl/board1_context2048_qspi_read03_master.sv": "e395d0c11e16182ab1273c30c3097b03e82bc099",
    BOARD + "product8_timing_successor2/rtl/board1_context2048_qspi_image_stream.sv": "9e4dfc08cdd6e2bd6a9730718f36ec00f6a9c6d2",
    BOARD + "product8_timing_successor2/rtl/board1_qspi_async_word_fifo4.sv": "370e5b9194817c3ac3a469262a3c072b390d9dd3",
    "top.sv": "42bc2539fe36b99a5648eada301ed34612634c58",
    "product.gprj": "50777fb3240e7aacd350d2b157f35f6256c769e2",
    "production_sources.f": "13cc617f0a32d88f33bc57f8961cf38ddad8f469",
}
CASES = (
    ("pin_fifo_tb", ["+wrongbit=0"], True, ["PASS 7 pin-derived words", "PASS boundary word", "PASS 14 stores"]),
    ("pin_fifo_tb", ["+wrongbit=1"], False, ["sampled DQ1 disagrees with RAM slot 0"]),
    ("boot_loader_order_tb", ["+schedule=0", "+wrongorder=0"], True, ["PASS epoch=0 schedule=0", "PASS epoch=1 schedule=0", "PASS common reset"]),
    ("boot_loader_order_tb", ["+schedule=1", "+wrongorder=0"], True, ["PASS epoch=0 schedule=1", "PASS epoch=1 schedule=1", "PASS common reset"]),
    ("boot_loader_order_tb", ["+schedule=0", "+wrongorder=1"], False, ["loader order mismatch at word 6"]),
)


def source_files():
    for name, oid in FILES.items():
        data = (PROJECT / name).read_bytes()
        if hashlib.sha1(f"blob {len(data)}\0".encode() + data).hexdigest() != oid:
            raise ValueError(f"Public project file differs from the proof input: {name}")
    enabled = [f.get("path") for f in ET.parse(PROJECT / "product.gprj").iter("File") if f.get("enable") == "1"]
    compiled = (PROJECT / "production_sources.f").read_text().splitlines()
    for name in FILES:
        if name.endswith(".sv") and (enabled.count(name) != 1 or compiled.count(name) != 1):
            raise ValueError(f"Unexpected production RTL membership: {name}")
    return [PROJECT / name for name in FILES if name.startswith(BOARD)]


def native(work, sources):
    for top in ("pin_fifo_tb", "boot_loader_order_tb"):
        subprocess.run(["iverilog", "-g2012", "-DSYNTHESIS", "-s", top, "-o", work / top,
                        *sources, HERE / (top + ".sv")], check=True)
    for top, args, success, markers in CASES:
        run = subprocess.run(["vvp", work / top, *args], stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT, text=True)
        if (run.returncode == 0) != success or any(m not in run.stdout for m in markers):
            raise ValueError(run.stdout)
        print(f"PASS {top} {' '.join(args)}")


def certify(work, sources):
    acl2 = Path(os.environ["ACL2"]).resolve(strict=True)
    books = Path(os.environ["ACL2_SYSTEM_BOOKS"]).resolve(strict=True)
    compiler = books / "centaur/sv/vl/svstmt-compile.lisp"
    if hashlib.sha256(compiler.read_bytes()).hexdigest() != "99f4a19521edf7aa657744c3865bec70f05ffd4135696b7c04f0dc3a6c46486c":
        raise ValueError("Use ACL2 8.7 with the corrected VL translator documented in the README")
    work.mkdir()
    for pattern in ("*.lisp", "*.lsp", "cert.acl2"):
        for source in HERE.glob(pattern):
            shutil.copyfile(source, work / source.name)
    for source in sources:
        lines = source.read_bytes().splitlines(keepends=True)
        directives = [b"`default_nettype none\n", b"`default_nettype wire\n"]
        if [line for line in lines if line.startswith(b"`default_nettype")] != directives:
            raise ValueError(f"Unexpected directives in {source}")
        (work / source.name).write_bytes(b"".join(b"\n" if line in directives else line for line in lines))
    shutil.copyfile(work / sources[0].name, work / "reader-vl.sv")
    subprocess.run([books / "build/cert.pl", "-j", "2", "--acl2", acl2,
                    "pin-reset-history.lisp", "order-reset.lisp"], cwd=work, check=True)
    for name, assertions, marker, theorem in (
        ("pin", 9, ":PIN-FIFO-READBACK-PASSED", "EVERY-BOOT-FIFO-WRITE-CONTAINS-ITS-SAMPLED-DQ1-BITS"),
        ("order", 8, ":BOOT-LOADER-ORDER-READBACK-PASSED", "EVERY-BOOT-LOADER-ACCEPTANCE-AFTER-COMMON-RESET-IS-AN-IN-ORDER-STORAGE-WRITE"),
    ):
        log = work / (name + "-readback.log")
        with (work / (name + "-readback.lsp")).open("rb") as inp, log.open("wb") as out:
            subprocess.run([acl2], cwd=work, stdin=inp, stdout=out, stderr=subprocess.STDOUT, check=True)
        text = log.read_text()
        if (any(x in text for x in ("ACL2 Error", "HARD ACL2 ERROR", "******** FAILED"))
                or theorem not in text or marker not in text
                or len(re.findall(r"^SV !> :PASSED$", text, re.M)) != assertions):
            raise ValueError(f"Fresh theorem readback failed; see {log}")
        print(f"PASS {name} certified and {assertions} readback checks")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--certify", type=Path, help="new scratch directory for ACL2 certificates and readbacks")
    args = parser.parse_args()
    inputs = source_files()
    with tempfile.TemporaryDirectory() as directory:
        native(Path(directory), inputs)
    if args.certify:
        certify(args.certify.resolve(), inputs)
