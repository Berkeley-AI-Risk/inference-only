"""Compare the recorded outputs of the combined S-AWIC F2 trial with the reference."""

import hashlib
import json
from pathlib import Path


def check():
    here = Path(__file__).resolve().parent
    record = json.loads((here / "wire-summary.json").read_text())
    reference_bytes = (
        here.parents[1] / "demos/simplestories-v2-5m/tests/reference-cases.json"
    ).read_bytes()
    if hashlib.sha256(reference_bytes).hexdigest() != record["public_reference"]["sha256"]:
        raise ValueError("Reference file digest differs from the recording")
    reference = json.loads(reference_bytes)
    cases = record["cases"]
    names = ["around128", "fox128", "help64", "moon64", "prefix128", "prefix512"]
    if [case["case"] for case in cases] != names:
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


if __name__ == "__main__":
    check()
