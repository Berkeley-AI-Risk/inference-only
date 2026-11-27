"""Reconstruct the guarded board datapath and replay its two RAM-port controls."""
from hashlib import sha256
from pathlib import Path
import shutil
import subprocess
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
RTL = (HERE.parents[1] / "demos/simplestories-v2-5m/variants/kv-protected/hardware"
       / "project/fpga/token_only_model0_ddr_board1")
DATAPATH = RTL / "context2048_token_machine0/rtl/board1_context2048_semantic_datapath.sv"
RAM = RTL / "fixed_semantic_layer0/rtl/board1_fixed_semantic_vector128_ram.sv"


def verify(path, digest):
    if sha256(path.read_bytes()).hexdigest() != digest:
        raise ValueError(f"SHA-256 mismatch for {path.name}")


def simulate(work, guarded):
    result = subprocess.run(
        ["iverilog", "-g2012", "-i", "-DSYNTHESIS", "-s", "port_tb", "-o", "sim",
         DATAPATH.name, RAM.name, str(HERE / "port_tb.sv")],
        cwd=work, stderr=subprocess.PIPE, text=True,
    )
    if result.returncode:
        raise RuntimeError(result.stderr)
    for word in ("0000", "ffff"):
        mode = ["+guarded"] if guarded else []
        subprocess.run(["vvp", "./sim", f"+word={word}", *mode], check=True, cwd=work)


def main():
    verify(DATAPATH, "fd7b6ade26e99db09999709954630b6d358b2d6cd7fae1f7f18c878fefec0dc3")
    verify(RAM, "9282e788fc641f15f225986738a8a9d605c892b210e060763622026a5b05310a")
    with TemporaryDirectory() as temp:
        work = Path(temp)
        shutil.copyfile(DATAPATH, work / DATAPATH.name)
        shutil.copyfile(RAM, work / RAM.name)
        simulate(work, guarded=False)
        with (HERE / "kv-read-reset.patch").open("rb") as patch:
            subprocess.run(["patch", "-p1"], stdin=patch, cwd=work, check=True)
        verify(work / DATAPATH.name, "1aa05c713d12dc767885dfa99c3c2d56a35874dded5ab398946e3f57962b794b")
        simulate(work, guarded=True)


if __name__ == "__main__":
    main()
