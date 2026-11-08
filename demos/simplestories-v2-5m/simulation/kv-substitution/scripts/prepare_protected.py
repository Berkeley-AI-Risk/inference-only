if not __debug__:
    raise SystemExit("Optimized Python is unsupported; run without -O or -OO")
"""Two ordinary token STEPs, with a clean control and two external-memory histories."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import tempfile

HERE=Path(__file__).resolve().parent.parent / "fixtures/protected"
CAPSULE_SHA="73e530fee2f22d0bd8ee1afa370435533c31c2723f825589e90e7b1daecdeecf"
IMAGE_SHA="cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0"
FS_SHA="90ac68150d0c297b666bc1963d05e32d1d2d0d7d69706593e58d48d5ab2e79e2"
TOP="tb_board1_booted_shared_semantic"

def sha(data):
    return hashlib.sha256(data).hexdigest()

def prepare(package, work):
    capsule=(package/"evidence/current-greedy/kv-protected-CAPSULE.json").read_bytes()
    assert sha(capsule)==CAPSULE_SHA
    spec=json.loads(capsule)
    selector="/protected-model-v15-compact-prefix/packet/optimized/"
    members={k.split(selector)[1]:v for k,v in spec["bindings"].items() if selector in k}
    assert len(members)==96 and sha((package/"prebuilt/kv-protected/project/impl/pnr/shared_product.fs").read_bytes())==FS_SHA
    for name, record in members.items():
        temp=Path(name)
        assert not temp.is_absolute() and ".." not in temp.parts
        z=(package/record["portable"]["path"]).read_bytes()
        assert sha(z)==record["portable"]["sha256"]
        raw=gzip.decompress(z)
        assert sha(raw)==record["original"]["sha256"]
        destination=work/temp
        destination.parent.mkdir(exist_ok=True,parents=True)
        destination.write_bytes(raw)
    rtls=(work/"production_sources.f").read_text().splitlines()
    project=package/"variants/kv-protected/hardware/project"
    assert len(rtls)==len(set(rtls))==66
    for name in rtls:
        assert (work/name).read_bytes()==(project/name).read_bytes(),name
    binary=b"".join(bytes.fromhex(x)[::-1] for x in (work/"image.memh").read_text().splitlines())
    assert sha(binary)==IMAGE_SHA and binary==(package/"assets/board1-real-semantic-image2048.bin").read_bytes()
    fixture=work/"tb.sv"
    bench=fixture.read_text()
    start=bench.index("    wire [255:0] app_rdata=")
    end=bench.index("    wire raw_read_fire",start)
    bench=bench[:start]+(HERE/"fixture.sv").read_text()+"\n"+bench[end:]
    start=bench.index('        `include "integration_campaign.inc.sv"')
    end=bench.index('    `include "query_capture_monitor.inc.sv"',start)
    fixture.write_text(bench[:start]+(HERE/"campaign.sv").read_text()+"\n"+bench[end:])
    return json.loads((work/"expected.json").read_bytes())["reference_sources"]
