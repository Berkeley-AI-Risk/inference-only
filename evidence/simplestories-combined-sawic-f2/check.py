"""Compare both combined S-AWIC F2 board captures with the public reference."""

import hashlib
import json
from pathlib import Path


PROMPTS = ["around128", "fox128", "help64", "moon64", "prefix128", "prefix512"]


def check_first_image(record, reference):
    cases = record["cases"]
    if [case["case"] for case in cases] != PROMPTS:
        raise ValueError("Recorded prompt order differs from the trial")
    total = 0
    for case in cases:
        name = case["case"]
        complete = name != "prefix512"
        if case["pass"] != 1 or case["finished"] != complete:
            raise ValueError(f"{name}: trial completion differs")
        if case["prompt_tokens"] != reference[name]["prompt_tokens"]:
            raise ValueError(f"{name}: prompt tokens differ")
        expected = reference[name]["generated_tokens"] if complete else []
        if case["generated_tokens"] != expected:
            raise ValueError(f"{name}: output tokens differ")
        total += len(expected)
    pending = record["pending_at_end"]
    if (pending["case"], pending["operation"], pending["observed_result"]) != (
        "prefix512", "STEP", None
    ):
        raise ValueError("Final unread STEP differs")
    if record["smoke"] != {"APPEND": 1, "STEP": 108, "status": 0}:
        raise ValueError("Initial token differs")
    if total != 512 or total != record["verified_generated_tokens_excluding_smoke"]:
        raise ValueError("Generated token count differs")
    print("Five prompts matched all 512 generated tokens. The sixth STEP was unread.")


def check_two_pass_image(record, reference):
    cases = record["cases"]
    expected_order = [(n, name) for n in (1, 2) for name in PROMPTS]
    if [(case["pass_number"], case["name"]) for case in cases] != expected_order:
        raise ValueError("Expected two ordered passes of the six prompts")
    total = 0
    command_replies = 2  # Initial APPEND and STEP.
    for case in cases:
        name = case["name"]
        expected = reference[name]
        if case["clear_acks"] != 1 or case["appended_tokens"] != expected["prompt_tokens"]:
            raise ValueError(f"Pass {case['pass_number']}, {name}: CLEAR or prompt differs")
        outputs = case["generated_tokens"]
        if outputs != expected["generated_tokens"]:
            raise ValueError(f"Pass {case['pass_number']}, {name}: output tokens differ")
        total += len(outputs)
        command_replies += 1 + len(case["appended_tokens"]) + len(outputs)
    if total != 1026 or total != record["verified_generated_tokens_excluding_smoke"]:
        raise ValueError("Two-pass generated-token count differs")
    if record["first_token"] != 108 or command_replies != record["successful_command_replies_including_smoke"]:
        raise ValueError("Initial token or total command replies differs")
    print("Two passes matched all 1,026 output tokens, including both 512-token-prefix STEPs.")


def check():
    here = Path(__file__).resolve().parent
    reference_bytes = (
        here.parents[1] / "demos/simplestories-v2-5m/tests/reference-cases.json"
    ).read_bytes()
    digest = hashlib.sha256(reference_bytes).hexdigest()
    reference = json.loads(reference_bytes)
    for filename, compare in [
        ("wire-summary.json", check_first_image),
        ("two-pass-wire-summary.json", check_two_pass_image),
    ]:
        record = json.loads((here / filename).read_text())
        if record["public_reference"]["sha256"] != digest:
            raise ValueError(f"{filename}: reference file digest differs")
        compare(record, reference)


if __name__ == "__main__":
    check()
