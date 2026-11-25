#!/usr/bin/env python3
"""Verify the recorded five- and two-layer Tang UART traces off-device."""

import hashlib
import json
from pathlib import Path
import runpy
import struct


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PRIOR = HERE.parent / "tlm26-tang-protected-kv-board"
CODEC = REPO / "demos/tlm26-moe/scripts/uart_replay.py"


def load(path):
    return json.loads(path.read_bytes())


def need(predicate, message):
    if not predicate:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def rate(steps, intervals, start_index=0):
    span = steps[start_index + intervals]["validated_ns"] - steps[start_index]["validated_ns"]
    return {"intervals": intervals, "span_ns": span, "tokens_per_second": intervals * 1e9 / span}


def capacity(events, expected, codec, prior, label):
    script = [(2, 0, 0x82, 0), (0, 1, 0x80, 0)]
    script.extend((1, 0, 0x81, token) for token in expected)
    script.extend([(2, 0, 0x82, 0), (0, 1, 0x80, 0)])
    script.extend((1, 0, 0x81, token) for token in expected[:5])
    script.append((2, 0, 0x82, 0))
    prior["matches"](events, script, codec, label)
    previous_end = -1
    for row in events:
        need(set(row) == {"tx", "rx", "start_ns", "validated_ns"}, label + " has unexpected capture fields")
        start, end = row["start_ns"], row["validated_ns"]
        need(type(start) is type(end) is int and previous_end < start < end, label + " has invalid host timing")
        previous_end = end
    need(events[0]["start_ns"] == 0, label + " must use relative timestamps")
    steps = events[2:2 + len(expected)]
    return {"exchanges": len(events), "matched_STEP_ids": len(steps), "positions_filled": len(steps) + 1,
            "matched_after_CLEAR": 5, "after_CLEAR_ids": expected[:5],
            "first_128": rate(steps, 127), "whole_cached": rate(steps, 254),
            "last_32_intervals": rate(steps, 32, 222),
            "first_step_ns": steps[0]["validated_ns"] - steps[0]["start_ns"],
            "last_step_ns": steps[-1]["validated_ns"] - steps[-1]["start_ns"]}


def standard(trials, expected, codec, prior, label):
    need(len(trials) == 2 and trials[0] != trials[1], label + " must contain two distinct captures")
    checked = [prior["trial"](events, expected[:128], codec, f"{label} trial {index}")
               for index, events in enumerate(trials, 1)]
    intervals = sum(row["cached_intervals"] for row in checked)
    span = sum(row["cached_span_ns"] for row in checked)
    return {"trials": checked, "matched_STEP_ids": sum(row["matched_ids"] for row in checked),
            "exchanges": sum(row["exchanges"] for row in checked), "intervals": intervals, "span_ns": span,
            "pooled_tokens_per_second": intervals * 1e9 / span}


def check(capture, reference, public_golden, control_trace, codec, prior):
    need(set(capture) == {"schema", "five_layer_standard", "five_layer_capacity", "two_layer_capacity", "sentinels"}
         and capture["schema"] == "tlm26-tang-five-layer-board-uart-v1", "Unexpected board capture format")
    expected = reference["expected_step_ids"]
    need(reference["prompt_tokens"] == public_golden["input_ids"] == [1], "The benchmark appends BOS token 1")
    need(len(expected) == 255 and all(type(token) is int and 0 <= token < 512 for token in expected),
         "The reference must have 255 legal STEP IDs")
    need(hashlib.sha256(struct.pack("<255H", *expected)).hexdigest() == reference["step_u16le_sha256"],
         "Recorded integer STEP reference changed")
    need(expected[:128] == public_golden["integer_reference_ids"] == public_golden["fp32_checkpoint_ids"]
         and public_golden["stop_at_eos"] is False, "The capacity reference differs from the public 128-output prefix")
    sentinel = [(2, 0, 0x82, 0), (0, 1, 0x80, 0), (1, 0, 0x81, 108), (1, 0, 0x81, 32), (2, 0, 0x82, 0)]
    need(set(capture["sentinels"]) == {"five_layer_entry", "five_layer_restored", "two_layer_entry", "two_layer_restored"},
         "Expected an entry and restoration sentinel for each full-context session")
    for label, events in capture["sentinels"].items():
        need(all(set(row) == {"tx", "rx"} for row in events), label + " has unexpected data fields")
        prior["matches"](events, sentinel, codec, label)
    need(all(events and events[0]["start_ns"] == 0 for events in capture["five_layer_standard"]),
         "Five-layer standard trials must use relative timestamps")
    five_trial = standard(capture["five_layer_standard"], expected, codec, prior, "Five-layer")
    control_trial = standard(control_trace["protected_trials"], expected, codec, prior, "Earlier two-layer")
    five_full = capacity(capture["five_layer_capacity"], expected, codec, prior, "Five-layer capacity")
    control_full = capacity(capture["two_layer_capacity"], expected, codec, prior, "Two-layer capacity")
    return {"passed": True, "scope": "recorded host UART and reply timing",
            "five_layer_exchanges": five_trial["exchanges"] + five_full["exchanges"],
            "signed_entry_and_restore_tokens": [108, 32],
            "five_layer": {"standard": five_trial, "capacity": five_full},
            "two_layer": {"standard": control_trial, "capacity": control_full}}


def main():
    expected = {"README.md", "IMAGE-SOURCE.json", "REFERENCE.json", "UART-TRACE.json", "check_capture.py"}
    for line in (HERE / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        need(name in expected and sha(HERE / name) == digest, f"Unexpected or changed evidence member {name}")
        expected.remove(name)
    need(not expected, "Missing evidence member hashes")
    identity = load(HERE / "IMAGE-SOURCE.json")
    reference = load(HERE / "REFERENCE.json")
    need(sha(CODEC) == identity["codec_sha256"], "Unexpected public UART codec")
    for name, digest in identity["reviewed_public_files"].items():
        need(sha(REPO / name) == digest, f"Unexpected public input {name}")
    prior_identity = load(PRIOR / "IMAGE-SOURCE.json")
    public_golden = load(REPO / prior_identity["host_protocol"]["public_golden"])
    need(reference["model_sha256"] == identity["model"]["image"]["sha256"] == public_golden["staged_int16_image_sha256"]
         and public_golden["checkpoint_sha256"] == identity["model"]["checkpoint_sha256"], "Model identity differs")
    review = check(load(HERE / "UART-TRACE.json"), reference, public_golden, load(PRIOR / "UART-TRACE.json"),
                   runpy.run_path(str(CODEC)), runpy.run_path(str(PRIOR / "check_capture.py")))
    print(json.dumps(review, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
