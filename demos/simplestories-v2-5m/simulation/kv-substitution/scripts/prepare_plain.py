if not __debug__:
    raise SystemExit("Optimized Python is unsupported; run without -O or -OO")
"""Replay two complete boots and two public STEP operations per run."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

HERE = Path(__file__).resolve().parent.parent / "fixtures/plain"
BASELINE = "01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"
TOP = "tb_board1_booted_shared_semantic"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(package, work):
    source = package / "simulation/model"
    current = json.loads((Path(__file__).resolve().parent.parent / "SOURCE-INPUTS.json").read_text())["files"]
    record = json.loads((source / "expected.json").read_bytes())
    for files, folder in [(record["production_source_sha256"], package / "hardware/project"),
                          (record["test_source_sha256"], source)]:
        for name, digest in files.items():
            contents = (folder / name).read_bytes()
            assert sha(contents) == current["demos/simplestories-v2-5m/"+str((folder / name).relative_to(package))]["sha256"], name
            path = work / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(contents)
    assert len(record["production_compile_order"]) == 64
    assert sha((package / "prebuilt/inference/project/impl/pnr/shared_product.fs").read_bytes()) == BASELINE
    image = (package / "assets/board1-real-semantic-image2048.bin").read_bytes()
    assert sha(image) == record["image_sha256"]
    encoded = b"".join(image[i:i+32][::-1].hex().encode() + b"\n" for i in range(0,len(image),32))
    assert sha(encoded) == record["image_memh_sha256"]
    (work / "image.memh").write_bytes(encoded)
    fixture = work / "tb.sv"
    bench = fixture.read_text()
    a,b = bench.index("    wire [255:0] app_rdata="),bench.index("    wire raw_read_fire=")
    bench = bench[:a] + (HERE / "experiment.sv").read_text() + "\n" + bench[b:]
    a,b = bench.index("        begin : profile_workload"),bench.index("            case(case_id)")
    body = """
        begin
            append_token(12'd378);
            launch_step(); accept_token(12'd200);
            launch_step();
            while (!token_valid_o) begin
                if(fail_closed_o) $fatal(1,"stage/terminal fault");
                @(negedge core_clk_i);
            end
            $display("MEASURED_TOKEN %0d", token_o);
            accept_token(token_o);
            $display("TWO_STEPS_COMPLETE");
            $finish;
        end
    end
    """
    # Replace only the remaining campaign initial body, never any monitor
    # declarations or postamble. Find the end of its original initial block.
    c=bench.index('    `include "query_capture_monitor.inc.sv"',b)
    bench=bench[:a]+body+bench[c:]
    fixture.write_text(bench)
    return record
