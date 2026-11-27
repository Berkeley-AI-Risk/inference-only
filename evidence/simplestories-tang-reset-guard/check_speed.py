"""Verify the two protected greedy UART trials used by the common benchmark."""
from hashlib import sha256
import json
from pathlib import Path
import runpy

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
DEMO = Path("demos/simplestories-v2-5m")


def verify(root, capture, reference):
    release = json.loads((root / DEMO / "prebuilt/kv-protected-reset-guarded/RELEASE.json").read_bytes())
    identity = {"fpga_image_sha256": release["image"]["sha256"],
                "model_image_sha256": release["model"]["sha256"], "clock_hz": 25_000_000}
    if capture["identity"] != identity or capture["physical_fpga"] is not True:
        raise ValueError("Capture does not identify the selected 25 MHz board image")
    if reference["prompt_tokens"] != [378] or len(reference["generated_tokens"]) != 128:
        raise ValueError("Expected the public one-token, 128-output reference")
    uart = runpy.run_path(str(root / DEMO / "host-app/token_machine_uart.py"))
    expected = [("clear", 0, 0), ("append", 378, 0)]
    expected.extend(("step", 0, value) for value in reference["generated_tokens"])
    expected.append(("clear", 0, 0))
    previous = -1
    for name, case in zip(("around1", "around2"), capture["cases"], strict=True):
        file = HERE / "wire" / (name + ".json")
        raw = file.read_bytes()
        if (case["raw_capture"] != "wire/" + file.name or case["raw_capture_sha256"] != sha256(raw).hexdigest()
                or case["name"] != name):
            raise ValueError("Canonical records must identify the two ordered raw captures")
        record = json.loads(raw)
        if record["prompt"] != 378 or record["trial"] != name:
            raise ValueError("Wire capture has a different trial or prompt")
        validated, durations = [], []
        for (op, operand, token), event in zip(expected, record["events"], strict=True):
            if bytes.fromhex(event["tx"]) != uart["request_frame"](op, operand):
                raise ValueError(f"{name}: request differs")
            if uart["decode_response"](bytes.fromhex(event["rx"])) != (uart["EXPECTED_RESULTS"][op], token):
                raise ValueError(f"{name}: reply differs from the public reference")
            start, complete, end = (event[k] for k in ("start_ns", "complete_frame_ns", "validated_ns"))
            if not (all(type(t) is int for t in (start, complete, end)) and previous < start < complete <= end):
                raise ValueError(f"{name}: nonmonotonic wire timestamps")
            previous = end
            if op == "step":
                validated.append(end)
                durations.append((end - start) / 1e9)
        if (case["expected_tokens"] != reference["generated_tokens"] or case["generated_tokens"] != reference["generated_tokens"]
                or case["reply_elapsed_seconds"] != [(end - validated[0]) / 1e9 for end in validated]
                or case["cached_command_seconds"] != durations[1:] or case["first_step_seconds"] != durations[0]
                or case["final_clear_acknowledged"] is not True):
            raise ValueError(f"{name}: canonical timings, tokens or final CLEAR differ from UART")


if __name__ == "__main__":
    capture = json.loads((HERE / "COMMON.json").read_bytes())
    reference = json.loads((ROOT / DEMO / "tests/reference-cases.json").read_bytes())["around128"]
    verify(ROOT, capture, reference)
    print("Two trials matched 256/256 expected tokens, six boundary commands and all timing samples.")
