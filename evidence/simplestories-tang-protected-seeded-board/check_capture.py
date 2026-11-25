#!/usr/bin/env python3
"""Replay the protected seeded image's saved Tang token and SETTINGS exchanges."""

import hashlib
import json
from pathlib import Path
import runpy


HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
PROTOCOL = REPO / "demos/simplestories-v2-5m/host-app/sampling_protocol.py"


def need(condition, message):
    if not condition:
        raise ValueError(message)


def load(path):
    return json.loads(path.read_bytes())


def sha(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def check_frames(capture, protocol):
    need(set(capture) == {"schema", "phases"} and capture["schema"] == "simplestories-protected-seeded-board-uart-v1",
         "Unexpected capture format")
    codec = protocol["codec"]

    def command(opcode, value, kind, operand=0):
        return codec.encode_legacy(opcode, value), kind, operand

    clear = command(2, 0, 0x82)
    signed_prompt = command(0, 1, 0x80)
    prompt = command(0, 378, 0x80)
    signed = [clear, signed_prompt] + [command(1, 0, 0x81, token) for token in (108, 32)] + [clear]
    greedy_tokens = [200, 15, 103, 200]
    greedy = [clear, prompt] + [command(1, 0, 0x81, token) for token in greedy_tokens[:3]]
    greedy += [clear, prompt, command(1, 0, 0x81, greedy_tokens[3]), clear]
    temperature = codec.temperature_code("1")
    seeded_tokens = list(protocol["SEQUENCES"][temperature])
    accepted = codec.encode_settings(temperature, protocol["SEED_A"]), 0x83, temperature
    rejected = codec.encode_settings(codec.temperature_code("0"), protocol["SEED_B"]), 0xC3, 0
    sampled = [command(1, 0, 0x81, token) for token in seeded_tokens]
    seeded = [accepted, prompt, rejected] + sampled + [clear, prompt] + sampled + [clear]
    expected = {"signed_entry": signed, "protected_greedy_control": greedy, "seeded_image_default": greedy,
                "seeded_image_sample": seeded, "signed_restored": signed}
    need(set(capture["phases"]) == set(expected), "Unexpected phases")
    commands, tx_bytes, rx_bytes = 0, 0, 0
    for phase, script in expected.items():
        observed = capture["phases"][phase]
        need(len(script) == len(observed), f"{phase} has the wrong number of exchanges")
        for index, (event, (tx, kind, operand)) in enumerate(zip(observed, script), 1):
            need(set(event) == {"tx", "rx"}, "Unexpected capture fields")
            raw_tx, raw_rx = bytes.fromhex(event["tx"]), bytes.fromhex(event["rx"])
            need(raw_tx == tx, f"{phase} command {index} changed")
            response = codec.decode_response(raw_rx)
            need((response.kind, response.operand) == (kind, operand), f"{phase} reply {index} changed")
            commands += 1
            tx_bytes += len(raw_tx)
            rx_bytes += len(raw_rx)
    need((commands, tx_bytes, rx_bytes) == (40, 230, 200), "Incorrect wire totals")
    return {"commands_and_replies": commands, "request_bytes": tx_bytes, "reply_bytes": rx_bytes,
            "settings_request_bytes": [len(accepted[0]), len(rejected[0])],
            "accepted_temperature": "1", "accepted_temperature_operand": temperature,
            "nonempty_tape_settings_reply": {"code": 0xC3, "operand": 0},
            "greedy_control": greedy_tokens, "seeded_image_default": greedy_tokens,
            "sample_before_clear": seeded_tokens, "sample_after_clear": seeded_tokens,
            "settings_reissued_after_clear": False, "signed_entry_and_restore": [108, 32]}


def main():
    for line in (HERE / "SHA256SUMS").read_text().splitlines():
        digest, name = line.split("  ", 1)
        need(sha(HERE / name) == digest, f"Changed evidence member {name}")
    identities = load(HERE / "IMAGE-SOURCE.json")
    for relative, pin in identities["public_inputs"].items():
        file = REPO / relative
        need(file.stat().st_size == pin["bytes"] and sha(file) == pin["sha256"], f"Changed public input {relative}")
    result = check_frames(load(HERE / "UART-TRACE.json"), runpy.run_path(str(PROTOCOL)))
    print(json.dumps({"passed": True, "scope": "recorded host UART and source-pinned public fixtures", **result},
                     sort_keys=True, indent=2))


if __name__ == "__main__":
    main()
