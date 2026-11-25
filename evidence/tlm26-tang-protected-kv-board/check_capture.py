#!/usr/bin/env python3
"""Replay the saved TLM26 UART exchanges and compute matched host throughput."""

import hashlib
import json
from pathlib import Path
import runpy


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
CODEC = REPO / "demos/tlm26-moe/scripts/uart_replay.py"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load(path):
    return json.loads(path.read_bytes())


def matches(events, script, codec, message):
    need(len(events) == len(script), message + " has the wrong exchange count")
    for index, (event, (opcode, value, status, token)) in enumerate(zip(events, script), 1):
        expected_tx = codec["frame"](0xA5, opcode, value).hex()
        expected_rx = codec["frame"](0x5A, status, token).hex()
        need((event["tx"], event["rx"]) == (expected_tx, expected_rx), f"{message} UART exchange {index} differs")


def trial(events, expected, codec, label):
    script = [(2, 0, 0x82, 0), (0, 1, 0x80, 0)]
    script += [(1, 0, 0x81, token) for token in expected] + [(2, 0, 0x82, 0)]
    matches(events, script, codec, label)
    for event in events:
        need(set(event) == {"tx", "rx", "start_ns", "validated_ns"}, label + " has unexpected capture fields")
        start, end = event["start_ns"], event["validated_ns"]
        need(type(start) is type(end) is int and start >= 0 and end > start, label + " has invalid host timing")
    need(all(b["start_ns"] >= a["validated_ns"] for a, b in zip(events, events[1:])),
         label + " has overlapping exchanges")
    steps = events[2:-1]
    intervals = len(steps) - 1
    span = steps[-1]["validated_ns"] - steps[0]["validated_ns"]
    first = steps[0]["validated_ns"] - steps[0]["start_ns"]
    return {"exchanges": len(events), "matched_ids": len(steps), "cached_intervals": intervals, "cached_span_ns": span,
            "first_step_ns": first, "cached_tokens_per_second": intervals * 1e9 / span}


def check_capture(capture, control, golden, codec):
    expected = golden["integer_reference_ids"]
    need(golden["input_ids"] == [1] and len(expected) == 128 and expected == golden["fp32_checkpoint_ids"],
         "The two reference sequences must agree for BOS and 128 generated IDs")
    need(golden["stop_at_eos"] is False, "The reference must retain all 128 output positions")
    need(set(capture) == {"schema", "protected_trials", "signed_entry", "signed_restored"} and
         capture["schema"] == "tlm26-protected-matched-board-uart-v1", "Unexpected capture format")
    sentinel = [(2, 0, 0x82, 0), (0, 1, 0x80, 0), (1, 0, 0x81, 108), (1, 0, 0x81, 32), (2, 0, 0x82, 0)]
    for arm in ("signed_entry", "signed_restored"):
        events = capture[arm]
        need(all(set(row) == {"tx", "rx"} for row in events), "Unexpected sentinel data fields")
        matches(events, sentinel, codec, arm)
    results = {}
    for label, trials in (("protected", capture["protected_trials"]), ("on_chip_control", control)):
        need(len(trials) == 2 and trials[0] != trials[1], label + " must contain two separate captures")
        review = [trial(events, expected, codec, f"{label} trial {index}") for index, events in enumerate(trials, 1)]
        cached = sum(row["cached_intervals"] for row in review)
        span = sum(row["cached_span_ns"] for row in review)
        results[label] = {"trials": review, "total_intervals": cached, "total_span_ns": span,
                          "matched_ids": sum(row["matched_ids"] for row in review),
                          "exchanges": sum(row["exchanges"] for row in review),
                          "pooled_cached_tokens_per_second": cached * 1e9 / span}
    protected = results["protected"]["pooled_cached_tokens_per_second"]
    control = results["on_chip_control"]["pooled_cached_tokens_per_second"]
    return {**results, "protected_rate_percent_of_control": protected * 100 / control,
            "signed_entry_and_restore_tokens": [108, 32]}


def main():
    for line in (HERE / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        need(sha(HERE / name) == digest, f"Changed evidence member {name}")
    identity = load(HERE / "IMAGE-SOURCE.json")
    need(sha(CODEC) == identity["host_protocol"]["codec_sha256"], "Wrong committed UART codec")
    codec = runpy.run_path(str(CODEC))
    public = identity["on_chip_control"]["public_records"]
    for name, pin in public.items():
        need(sha(REPO / name) == pin["sha256"], f"Wrong public control file {name}")
    golden = load(REPO / identity["host_protocol"]["public_golden"])
    need(golden["checkpoint_sha256"] == identity["model"]["checkpoint_sha256"] and
         golden["staged_int16_image_sha256"] == identity["model"]["image"]["sha256"], "Wrong model reference")
    paths = identity["on_chip_control"]["public_trials_in_order"]
    control = [load(REPO / path)["uart_events"] for path in paths]
    review = check_capture(load(HERE / "UART-TRACE.json"), control, golden, codec)
    expected_rates = {"protected": 9.022929586310914, "on_chip_control": 9.077744452657152}
    for label, expected in expected_rates.items():
        actual = review[label]["pooled_cached_tokens_per_second"]
        need(abs(actual - expected) < 1e-12, f"{label} pooled rate changed")
    print(json.dumps({"passed": True, "scope": "recorded host UART and host-validated reply timing", **review},
                     sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
