"""Record ordinary token and external page observations on the booted pinned baseline."""

if __name__ == "__main__" and not __debug__:
    raise SystemExit("Assertions required: run without -O or -OO")

import argparse
from concurrent.futures import ThreadPoolExecutor
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import shlex
import subprocess
import sys
import uuid
import tempfile

HERE=Path(__file__).resolve().parent
TOP = "tb_board1_booted_shared_semantic"
IMAGE = "01b040cb830cd4c5343f0666568213d433442c6937e711751a79847d492b4a57"
MANIFEST = "11f2706bee3e07515d534a42f06e312eb1def2f278abd0315f79756280e2bb9c"
INVENTORY = "4f4cbc54676e9d976af7358386c19d8befdab34d819de30e4fb3e42beb3362fd"


def sha(data):
    return hashlib.sha256(data).hexdigest()


def prepare(project, work):
    fixture = project / "simulation/model"
    release = (project / "MANIFEST.json").read_bytes()
    assert sha(release) == MANIFEST
    manifest = json.loads(release)["files"]
    record_bytes = (fixture / "expected.json").read_bytes()
    assert sha(record_bytes) == manifest["simulation/model/expected.json"]["sha256"]
    record = json.loads(record_bytes)
    archived = (project / "evidence/current-greedy/objects" / (INVENTORY + ".gz")).read_bytes()
    native_bytes = gzip.decompress(archived)
    assert sha(native_bytes) == INVENTORY
    native = json.loads(native_bytes)
    assert len(record["production_compile_order"]) == 64
    for role, directory in (("production", project / "hardware/project"), ("test", fixture)):
        for name, old_hash in record[role + "_source_sha256"].items():
            path = directory / name
            contents = path.read_bytes()
            digest = sha(contents)
            assert digest == manifest[str(path.relative_to(project))]["sha256"]
            assert digest == (native["project/" + name] if role == "production" else old_hash)
            target = work / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(contents)
    bitstream = project / "prebuilt/inference/project/impl/pnr/shared_product.fs"
    assert sha(bitstream.read_bytes()) == IMAGE
    image = (project / "assets/board1-real-semantic-image2048.bin").read_bytes()
    assert sha(image) == record["image_sha256"]
    encoded = "".join(image[i:i+32][::-1].hex() + "\n" for i in range(0, len(image), 32)).encode()
    assert sha(encoded) == record["image_memh_sha256"]
    (work / "image.memh").write_bytes(encoded)
    return record


def file_hash(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def save_json(path, value):
    pending = path.with_name(path.name + ".tmp")
    pending.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n")
    pending.replace(path)


def record_command(args, work, logs, label, timeout, env=None):
    """Write the request before launch, stream both outputs, then record the exit."""
    logs.mkdir(parents=True, exist_ok=True)
    log = logs / (label + ".log")
    receipt = logs / (label + ".json")
    argv = list(map(str, args))
    seq_digest = sha(json.dumps(argv, ensure_ascii=True, separators=(",", ":")).encode())
    rec = {"argv": argv, "argv_sha256": seq_digest, "cwd": str(work),
           "merged_log": log.name, "status": "starting", "returncode": None}
    save_json(receipt, rec)
    result = None
    try:
        with log.open("wb", buffering=0) as stream:
            resolved = shutil.which(argv[0], path=(env or os.environ).get("PATH"))
            if resolved:
                rec["executable_path"] = str(Path(resolved).absolute())
                rec["executable_sha256"] = file_hash(Path(resolved))
            proc = subprocess.Popen(argv, cwd=work, env=env, stdout=stream, stderr=subprocess.STDOUT)
            rec.update(pid=proc.pid, status="running")
            save_json(receipt, rec)
            try:
                result = proc.wait(timeout=timeout)
            except BaseException:
                proc.kill()
                rec["returncode"] = proc.wait()
                raise
            rec.update(returncode=result, status="exited")
    except BaseException as error:
        rec.update(status="error", error=f"{type(error).__name__}: {error}")
        raise
    finally:
        if log.exists():
            rec.update(merged_log_sha256=file_hash(log), merged_log_bytes=log.stat().st_size)
        save_json(receipt, rec)
    if result:
        raise RuntimeError(f"{label} exited {result}. {log}\n" + log.read_text(errors="replace")[-4500:])
    return receipt, log


def compiler_invocation(args):
    logs = Path(os.environ["SIMPLESTORIES_CXX_LOGS"])
    driver = os.environ["SIMPLESTORIES_CXX_DRIVER"]
    label = "cxx-" + uuid.uuid4().hex
    try:
        record_command([driver, *args], Path.cwd(), logs, label, 1800)
    except Exception:
        if (logs / (label + ".log")).is_file():
            sys.stderr.buffer.write((logs / (label + ".log")).read_bytes())
        details = json.loads((logs / (label + ".json")).read_bytes())
        return details.get("returncode") or 1
    sys.stdout.buffer.write((logs / (label + ".log")).read_bytes())
    return 0


TRACE_LINE = re.compile(rb"^(BOOT_AUTHENTICATED|HEADER|EMBED|EMB_ADDR|PROJ_DESC|PROJ_ADDR|RAM_PAGE|PUBLIC_TOKEN)\b")


def extract_trace(log):
    selected = [line for line in log.read_bytes().splitlines() if TRACE_LINE.match(line)]
    if not selected or not selected[0].startswith(b"BOOT_AUTHENTICATED ") or not selected[-1].startswith(b"PUBLIC_TOKEN "):
        raise ValueError(f"incomplete boot or public token in {log}")
    return b"\n".join(selected) + b"\n"


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument("repo",type=Path)
    p.add_argument("output",type=Path)
    a=p.parse_args()
    project=a.repo.resolve()/"demos/simplestories-v2-5m"
    out=a.output.resolve()
    out.mkdir(parents=True,exist_ok=True)
    logs = out / "native-runs"
    logs.mkdir(exist_ok=False)
    with tempfile.TemporaryDirectory(prefix="support-site-") as temp:
        w=Path(temp)
        receipt=prepare(project,w)
        tb=(project/"simulation/model/tb.sv").read_text()
        begin=tb.index('        begin : profile_workload')
        end=tb.index('    `include "query_capture_monitor.inc.sv"',begin)
        tb=tb[:begin]+'''
        if (!$value$plusargs("TOKEN=%d",requested_token)) $fatal(1,"TOKEN required");
        trace_active=1;
        append_token(12'(requested_token));
        launch_step();
        while (!token_valid_o) begin
            if (fail_closed_o) $fatal(1,"unexpected terminal fault");
            @(negedge core_clk_i);
        end
        $display("PUBLIC_TOKEN %0d %0d",requested_token,token_o);
        accept_token(token_o);
        $finish;
    end
'''+tb[end:]
        insert=tb.index("    wire raw_read_fire=")
        tb=tb[:insert]+(HERE/"observe.sv").read_text()+"\n"+tb[insert:]
        (w/"tb.sv").write_text(tb)
        # Make invokes this transparent driver for each compile and link. Shell quoting
        # protects the interpreter and script paths even when the checkout contains spaces.
        compiler = shutil.which("c++")
        if compiler is None:
            raise FileNotFoundError("c++ is required")
        wrapper = w / "record-cxx"
        wrapper.write_text("#!/bin/sh\nexec " + shlex.join([sys.executable, "-I", "-S", "-B", str(Path(__file__).resolve()), "--capture-cxx"]) + ' "$@"\n')
        wrapper.chmod(0o755)
        env = os.environ.copy()
        env.update(SIMPLESTORIES_CXX_DRIVER=compiler, SIMPLESTORIES_CXX_LOGS=str(logs / "compiler"))
        make_flags = f"CURDIR={w}/obj OPT_FAST=-O3 OPT_SLOW=-O3 CXX={wrapper} LINK={wrapper}"
        flags = ["--binary", "--timing", "--build-jobs", "6", "-MAKEFLAGS", make_flags,
                 "-Wno-fatal", "-Wno-WIDTHEXPAND", "-Wno-WIDTHTRUNC", "-Wno-TIMESCALEMOD",
                 "-DSYNTHESIS", "-GAUTH_BANKS=4", "--top-module", TOP, "--Mdir", str(w / "obj"),
                 "-f", "production_sources.f"]
        binary = w / "obj" / ("V" + TOP)
        build, _ = record_command([shutil.which("verilator") or "verilator", *flags, *receipt["reference_sources"],
                                   "tb.sv", "-CFLAGS", "-O3"], w, logs, "build", 1800, env)
        build_info = json.loads(build.read_bytes())
        build_info.update(generated_tb_sha256=file_hash(w / "tb.sv"), image_memh_sha256=file_hash(w / "image.memh"),
                          model_binary_sha256=file_hash(binary), compiler_path=compiler,
                          compiler_receipts=sorted(str(path.relative_to(logs)) for path in (logs / "compiler").glob("*.json")))
        save_json(build, build_info)
        if not build_info["compiler_receipts"]:
            raise RuntimeError("no actual C++ driver receipts from build")

        def one(token):
            args = [str(binary), "+IMAGE_MEMH=image.memh", "+ZERO_STALL", f"+TOKEN={token}"]
            rec_path, log = record_command(args, w, logs, f"token-{token}", 1800)
            trace = extract_trace(log)
            path = out / f"token-{token}.trace"
            path.write_bytes(trace)
            rec = json.loads(rec_path.read_bytes())
            rec.update(trace_sha256=sha(trace), trace_bytes=len(trace), trace_file=path.name)
            save_json(rec_path, rec)
            print(trace.splitlines()[-1].decode(), flush=True)

        with ThreadPoolExecutor(max_workers=3) as pool:
            list(pool.map(one, [0, 1, 64]))


if __name__ == "__main__":
    if sys.argv[1:2] == ["--capture-cxx"]:
        raise SystemExit(compiler_invocation(sys.argv[2:]))
    main()
