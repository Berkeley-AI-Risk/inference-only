"""Check the five-layer Tang reader's known answers and two timing boundaries."""
import argparse
from hashlib import sha256
import json
from pathlib import Path
import runpy
import struct

DEMO = Path(__file__).resolve().parents[1]
ROOT = DEMO.parents[1]
PROTECTED_VARIANT = "five-external-kv-zero-hold-50mhz"
BENCHMARK_REFERENCE = ROOT / "benchmarks/fpga-speed/tlm26-overlap-r2-50mhz-v1/golden.json"
CAPACITY_REFERENCE = ROOT / "evidence/tlm26-tang-five-layer-kv-board/REFERENCE.json"
CODEC = runpy.run_path(str(DEMO / "scripts/uart_replay.py"))
request_frame, response_frame = CODEC["request_frame"], CODEC["response_frame"]


CAPTURE = DEMO / "prebuilt" / PROTECTED_VARIANT / "READER-CAPTURE.json"
HELD_SHA256 = "7bb2e98804089773a805dd8b5dfe49154cfa81bfa485542ebcb5ca6304e3dc6f"
BOUNDARIES = ("complete_frame_ns", "validated_ns")


def load(path):
    return json.loads(path.read_bytes())


def require(condition, message):
    if not condition:
        raise ValueError(message)


def expected_workloads():
    short = load(DEMO / "evidence/integer-cpu.json")["results"][0]
    golden = load(BENCHMARK_REFERENCE)
    steps = golden["integer_reference_ids"]
    require(golden["input_ids"] == [1] and len(steps) == golden["output_count"] == 128
            and steps == golden["fp32_checkpoint_ids"] and golden["stop_at_eos"] is False,
            "Reference must encode the fixed BOS plus 128-output workload.")
    return short, steps


def capacity_workload(first_128):
    record = load(CAPACITY_REFERENCE)
    steps = record["expected_step_ids"]
    require(record["prompt_tokens"] == [1] and len(steps) == 255 and steps[:128] == first_128
            and sha256(struct.pack("<255H", *steps)).hexdigest() == record["step_u16le_sha256"],
            "Capacity reference must cover the 255 fixed outputs after BOS.")
    return steps


def check_frames(frames, prompt, expected):
    script = [("clear", 0, 0x82, 0)]
    script.extend(("append", token, 0x80, 0) for token in prompt)
    script.extend(("step", 0, 0x81, token) for token in expected)
    script.append(("clear", 0, 0x82, 0))
    require(len(frames) == len(script), "Wrong number of commands or replies.")
    previous = -1
    timing = []
    for index, (event, (op, operand, kind, token)) in enumerate(zip(frames, script), 1):
        require(event["operation"] == op and event["input_id"] == operand
                and event["tx"] == request_frame(op, operand).hex()
                and event["rx"] == response_frame(kind, token).hex(),
                f"Unexpected command, token or CRC at exchange {index}.")
        launch = event["start_ns"]
        complete, validated = (event[key] for key in BOUNDARIES)
        require(all(type(value) is int for value in (launch, complete, validated))
                and previous < launch < complete <= validated,
                f"Invalid frame and validation timing at exchange {index}.")
        previous = validated
        if op == "step":
            timing.append(event)
    first, last = timing[0], timing[-1]
    return {"generated_outputs": len(timing), "intervals": len(timing) - 1,
            **{key: {"first_step_ns": first[key] - first["start_ns"],
                     "span_ns": last[key] - first[key]} for key in BOUNDARIES}}


def checked_trial(record, assets, expected):
    require(record["complete"] is True and record["variant"] == PROTECTED_VARIANT
            and record["benchmark"] is True and record["already_provisioned"] is True
            and record["acknowledged_pages"] == 0 and record["asset_identity_checked_at_host"] == assets
            and record["prompt_ids"] == [1] and record["generated_ids"] == record["reference_ids"] == expected,
            "The run receipt does not bind the pinned image and BOS reference.")
    return check_frames(record["frames"], [1], expected)


def compare_pair(pair):
    require(len(pair) == 2 and all(row["intervals"] == 127 for row in pair),
            "Require two complete 128-output trials.")
    count = sum(row["intervals"] for row in pair)
    boundaries = {}
    for key in BOUNDARIES:
        spans = [row[key]["span_ns"] for row in pair]
        boundaries[key] = {
            "first_steps_ns": [row[key]["first_step_ns"] for row in pair],
            "cached_trial_spans_ns": spans,
            "cached_trial_tokens_per_second": [127e9 / span for span in spans],
            "pooled_cached_tokens_per_second": count * 1e9 / sum(spans),
        }
    return {"matched_outputs": 256, "cached_intervals": count, **boundaries}


def check_capacity(frames, expected):
    summary = check_frames(frames, [1], expected)
    steps = frames[2:-1]
    for key in BOUNDARIES:
        row = summary[key]
        row["cached_tokens_per_second"] = 254e9 / row["span_ns"]
        row["last_32_cached_tokens_per_second"] = 32e9 / (steps[-1][key] - steps[-33][key])
    return summary


def check_capture(record, assets, short, expected, *, capacity=None):
    require(record["schema"] == "tlm26-five-layer-release-reader-v1"
            and record["asset_identity"] == assets and record["core_clock_hz"] == 50_000_000,
            "Wrong measured image or release-check schema.")
    smoke = record["smoke"]
    require(smoke["acknowledged_pages"] == 768 and smoke["loader_ready"] is True
            and smoke["prompt_ids"] == short["prompt_ids"] and smoke["generated_ids"] == short["generated_ids"]
            and smoke["provision_elapsed_s"] > 0,
            "The cold reader did not provision or match the default prompt.")
    check_frames(smoke["frames"], short["prompt_ids"], short["generated_ids"])
    trials = record["trials"]
    require(len(trials) == 2 and trials[0] != trials[1]
            and all(frames[0]["start_ns"] == 0 for frames in trials),
            "Expected two independent, relative-time wire captures.")
    sentinel = [("clear", 0, 0x82, 0), ("append", 1, 0x80, 0),
                ("step", 0, 0x81, 108), ("step", 0, 0x81, 32), ("clear", 0, 0x82, 0)]
    sentinel_frames = [{"tx": request_frame(op, operand).hex(), "rx": response_frame(kind, token).hex()}
                       for op, operand, kind, token in sentinel]
    restore = record["restoration"]
    require(restore["entry_frames"] == restore["restored_frames"] == sentinel_frames
            and restore["flash_operations"] == 0 and restore["uart_released"] is True,
            "Missing exact entry or restoration reply.")
    summary = {"passed": True, "smoke_expected_outputs": len(short["generated_ids"]),
               "loader_acknowledgments": smoke["acknowledged_pages"], "restored_and_released": True,
               **compare_pair([check_frames(frames, [1], expected) for frames in trials])}
    require(record["reference_sha256"] == sha256(BENCHMARK_REFERENCE.read_bytes()).hexdigest(),
            "The capture lacks the pinned 128-output reference.")
    if capacity is not None:
        require(record["capacity_reference_sha256"] == sha256(CAPACITY_REFERENCE.read_bytes()).hexdigest(),
                "The capture lacks the pinned capacity reference.")
        summary["capacity"] = check_capacity(record["capacity"], capacity)
    return summary


def main():
    from run_prebuilt import check_assets

    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipts", type=Path, nargs=2,
                        help="check two RESULT.json files produced by the benchmark reader")
    parser.add_argument("--capacity-receipt", type=Path,
                        help="also check a RESULT.json produced with --capacity")
    args = parser.parse_args()
    assets = check_assets(PROTECTED_VARIANT)
    short, expected = expected_workloads()
    capacity = capacity_workload(expected)
    if args.receipts is None:
        if args.capacity_receipt is not None:
            parser.error("--capacity-receipt requires the two --receipts")
        result = check_capture(load(CAPTURE), assets, short, expected, capacity=capacity)
        held = load(CAPTURE.with_name("HELD-READER-CAPTURE.json"))
        held_assets = held["asset_identity"]
        require(held_assets["tlm26.fs"]["sha256"] == HELD_SHA256
                and all(held_assets[name] == assets[name] for name in ("model.bin", "tok512.model")),
                "The control does not bind the older five-layer image and same model.")
        result["held_control"] = check_capture(held, held_assets, short, expected)
    else:
        trial1, trial2 = (load(path) for path in args.receipts)
        require(trial1["frames"][-1]["validated_ns"] < trial2["frames"][0]["start_ns"],
                "Trial receipts overlap or are out of capture order.")
        result = {"passed": True, **compare_pair([checked_trial(record, assets, expected)
                                                  for record in (trial1, trial2)])}
        if args.capacity_receipt is not None:
            full = load(args.capacity_receipt)
            require(full["complete"] is True and full["variant"] == PROTECTED_VARIANT
                    and full["capacity"] is True and full["already_provisioned"] is True
                    and full["asset_identity_checked_at_host"] == assets and full["prompt_ids"] == [1]
                    and full["generated_ids"] == full["reference_ids"] == capacity,
                    "The capacity receipt differs from the released image or reference.")
            require(trial2["frames"][-1]["validated_ns"] < full["frames"][0]["start_ns"],
                    "Capacity receipt overlaps the paired trials.")
            result["capacity"] = check_capacity(full["frames"], capacity)
    print(json.dumps(result, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
