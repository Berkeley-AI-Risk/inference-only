"""Check the Tang board UART capture against the public integer model."""
from pathlib import Path
import runpy
import subprocess
import sys
from tempfile import TemporaryDirectory

HERE = Path(__file__).resolve().parent
DEMO = HERE.parents[1] / "demos/simplestories-v2-5m"
REFERENCE = DEMO / "reference/seeded-sampling"


def compare(frames, expected, uart):
    for n, (line, (operation, operand, result)) in enumerate(zip(frames, expected, strict=True), 1):
        tx, rx = (bytes.fromhex(field) for field in line.split())
        if tx != uart["request_frame"](operation, operand):
            raise ValueError(f"Exchange {n} has an unexpected request")
        if uart["decode_response"](rx) != (uart["EXPECTED_RESULTS"][operation], result):
            raise ValueError(f"Exchange {n} has an unexpected reply")


def main():
    uart = runpy.run_path(str(DEMO / "host-app/token_machine_uart.py"))
    reference = runpy.run_path(str(REFERENCE / "model.py"))
    frames = (HERE / "uart-frames.txt").read_text().splitlines()
    with TemporaryDirectory() as temp:
        rom = Path(temp) / "rom"
        subprocess.run([sys.executable, "-I", "-B", str(REFERENCE / "reconstruct_rom.py"),
                        "--output", str(rom)], check=True, stdout=subprocess.DEVNULL)
        loaded = reference["load"](rom, engine="scalar")
        expected = []
        for prompt, count in ((378, 8), (27, 2), (378, 8)):
            model = loaded["Model"](loaded["data"])
            tokens = reference["generate"](model, model.consume(prompt), loaded["sampler"],
                                           temperature=0, seed=0, count=count)["generated_tokens"]
            expected.extend([("clear", 0, 0), ("append", prompt, 0)])
            expected.extend(("step", 0, token) for token in tokens)
            expected.append(("clear", 0, 0))
            print(f"Prompt {prompt}: {' '.join(map(str, tokens))}")
    compare(frames, expected, uart)
    print(f"Matched all {len(expected)} UART exchanges, including 18 dependent STEP replies.")


if __name__ == "__main__":
    main()
