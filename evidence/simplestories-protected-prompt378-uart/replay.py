"""Compare the public fixed-point model to six ordinary STEP replies in a protected RTL trace."""
import argparse
from bisect import bisect_right
from collections import defaultdict
from contextlib import redirect_stdout
import gzip
from hashlib import sha256
from io import StringIO
import json
from pathlib import Path
import runpy
import subprocess
import sys
from tempfile import TemporaryDirectory

COMMIT = "b12eadcffd05a6052d648ec23869bc369c4cd16a"
DEMO = "demos/simplestories-v2-5m"
FILES = (
    "assets/board1-real-semantic-image2048.bin",
    "tools/materialize_image.py", "reference/evidence/q0-receipt.json",
    "reference/quantization/__init__.py", "reference/quantization/artifacts.py",
    "reference/quantization/oracle.py", "reference/seeded-sampling/reconstruct_rom.py",
    "reference/seeded-sampling/rom-manifest.json", "reference/seeded-sampling/context2048.py",
    "reference/seeded-sampling/model.py", "variants/seeded-sampling/tools/sampler_oracle.py",
)
# Commands are fixed independently of the recorded simulation.
COMMANDS = [(0, 378), (1, 0), (1, 0), (1, 0), (1, 0), (2, 0), (0, 378), (1, 0), (1, 0)]
STEP_NUMBERS = [2, 3, 4, 5, 8, 9]
HEAD_COUNTS = {"STEP": 3, "NF": 5, "ROW": 8, "WIN": 3, "CLEAR": 3}
UART_COUNTS = {"UART_CMD": 4, "UART_PIN": 5, "UART_TOKEN": 3, "UART_CLEAR_READY": 2}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def checksum(data):
    return sha256(data).hexdigest()


def canonical(data):
    return json.dumps(data, separators=(",", ":")).encode("ascii")


def reference(repo):
    with TemporaryDirectory(prefix="simplestories-prompt-replay-") as temp:
        root = Path(temp)
        public_inputs = {}
        for name in FILES:
            data = subprocess.check_output(["git", "-C", str(repo), "show", f"{COMMIT}:{DEMO}/{name}"])
            target = root / DEMO / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(data)
            public_inputs[name] = checksum(data)
        seeded = root / DEMO / "reference/seeded-sampling"
        rom = root / "rom"
        raw = subprocess.check_output([sys.executable, "-I", "-B", str(seeded / "reconstruct_rom.py"),
                                       "--output", str(rom)], text=True)
        reconstruction = json.loads(raw)
        require(reconstruction["all_canonical_rom_hashes_match"] and reconstruction["image_roundtrip_matches"],
                "public ROM reconstruction failed")
        api = runpy.run_path(str(seeded / "model.py"))
        with redirect_stdout(StringIO()):
            loaded = api["load"](rom, engine="scalar")

        # Observe one unmodified public function's input. All input to the model comes from COMMANDS
        # and its own greedy outputs. No data in the RTL trace are inputs to this calculation.
        class Capture(loaded["Model"]):
            def raw_head(self, hidden):
                self.final_vector = [(int(v), int(hidden.exponent)) for v in hidden.value]
                return super().raw_head(hidden)

        model = Capture(loaded["data"])
        token = None
        frames = {}
        for number, (op, argument) in enumerate(COMMANDS, 1):
            if op == 0:
                token = argument
            elif op == 2:
                model.clear()
                require(model.position == 0 and all(not c for c in (*model.keys, *model.values)),
                        "public model CLEAR did not reset the session")
                token = None
            else:
                require(token is not None, "missing prompt token")
                input_token = token
                rows = model.consume(token)
                token, _ = loaded["sampler"].sample(rows, 0, loaded["sampler"].initial_state(0))
                frames[number] = dict(input=input_token, vector=model.final_vector, scores=rows,
                                      winner=token, position=model.position - 1)
        require(frames[2] == frames[8] and frames[3] == frames[9], "public replay after CLEAR changed")
        return frames, reconstruction, public_inputs, loaded["np"].__version__


def parse(lines):
    commands = []
    events = []
    boot = done = 0
    for line in lines:
        fields = line.split()
        if not fields:
            continue
        if fields[0] == "HEAD_JOIN":
            label = fields[1]
            require(label in HEAD_COUNTS, "unexpected head record")
            epoch, cycle, *data = map(int, fields[2:])
            require(epoch == 1 and len(data) == HEAD_COUNTS[label], f"invalid {label} record")
            events.append((cycle, label, data))
        elif fields[0] in UART_COUNTS:
            label = fields[0]
            data = list(map(int, fields[1:]))
            require(len(data) == UART_COUNTS[label], f"invalid {label} record")
            if label == "UART_CMD":
                commands.append(data)
            else:
                events.append((data[0], label, data[1:]))
        elif fields[0] == "BOOT_AUTHENTICATED":
            require("real_sha=1" in fields and "handoff_drained=1" in fields and "words=227062" in fields,
                    "original boot receipt is missing fields")
            boot += 1
        elif fields[0] == "PASS_C070_UART":
            require(fields[1:] == ["boot_words=227062", "frames=9", "primary_tokens=4", "replay_tokens=2"],
                    "original simulation terminal receipt differs")
            done += 1
        else:
            raise ValueError("unexpected record in reduced trace")
    require((boot, done) == (1, 1), "missing or duplicate boot or terminal receipt")
    starts = [c[0] for c in commands]
    require(starts == sorted(set(starts)) and [c[1] for c in commands] == list(range(1, 10)),
            "wrong command ordering")
    require([tuple(c[2:]) for c in commands] == COMMANDS, "command schedule differs")
    by_number = {i: defaultdict(list) for i in range(1, 10)}
    for cycle, label, data in events:
        number = bisect_right(starts, cycle)
        require(number > 0 and (not label.startswith("UART_") or data[0] == number),
                f"{label} outside its command at cycle {cycle}")
        by_number[number][label].append((cycle, data))
    return starts, by_number


def crc8(values):
    crc = 0
    for value in values:
        crc ^= value
        for _ in range(8):
            crc = ((crc << 1) ^ (7 if crc & 128 else 0)) & 255
    return crc


def uart_bytes(pins):
    require(len(pins) == 50, "a five-byte reply must supply fifty pin samples")
    frame = bytearray()
    for byte_index in range(5):
        symbols = []
        group = pins[byte_index * 10 : (byte_index + 1) * 10]
        for i, (cycle, (_, address, index, bit)) in enumerate(group):
            require((address, index) == (byte_index, i) and bit in (0, 1), "pin sample address or bit")
            if i:
                require(cycle == group[i - 1][0] + 217, "UART pin sampling period")
            symbols.append(bit)
        require(symbols[0] == 0 and symbols[9] == 1, "invalid UART start or stop symbol")
        if byte_index:
            require(group[0][0] > pins[byte_index * 10 - 1][0], "UART byte ordering")
        frame.append(sum(bit << i for i, bit in enumerate(symbols[1:9])))
    require(crc8(frame[:4]) == frame[4], "UART CRC")
    return bytes(frame)


def compare(starts, observed, expected):
    steps = []
    wire = []
    for number, (op, _) in enumerate(COMMANDS, 1):
        obs = observed[number]
        start = starts[number - 1]
        pins = obs["UART_PIN"]
        result = uart_bytes(pins)
        token = expected[number]["winner"] if op == 1 else 0
        require(result[:4] == bytes((0x5A, 0x80 + op, token & 255, token >> 8)),
                f"command {number} reply disagrees with independent model")
        wire.append(result.hex())
        if op != 1:
            require(all(not obs[key] for key in ("STEP", "NF", "ROW", "WIN", "UART_TOKEN")),
                    f"unexpected decoder output on command {number}")
            if op == 2:
                require(obs["CLEAR"] == [(start, [1, 1, 1])] and len(obs["UART_CLEAR_READY"]) == 1
                        and obs["UART_CLEAR_READY"][0][0] > start, "CLEAR not accepted and drained")
            else:
                require(not obs["CLEAR"] and not obs["UART_CLEAR_READY"], "unexpected CLEAR")
            continue
        exp = expected[number]
        require(not obs["CLEAR"] and not obs["UART_CLEAR_READY"] and obs["STEP"] == [(start, [1, 1, 1])],
                f"command {number} STEP or CLEAR acceptance")
        require(len(obs["NF"]) == len(exp["vector"]) == 256, "final vector count")
        prior = start
        for i, ((cycle, data), (value, exponent)) in enumerate(zip(obs["NF"], exp["vector"])):
            require(cycle > prior and data == [i, value, exponent, int(i == 255), 1],
                    f"command {number} normalized lane {i}")
            prior = cycle
        require(len(obs["ROW"]) == len(exp["scores"]) == 4019, "selector row count")
        for i, ((cycle, data), (score, exponent)) in enumerate(zip(obs["ROW"], exp["scores"])):
            require(cycle > prior and data == [1, 1, 1, i, score, exponent, int(i == 4018), 1],
                    f"command {number} score row {i}")
            prior = cycle
        require(len(obs["WIN"]) == 1, "winner count")
        won_at, winner = obs["WIN"][0]
        require(won_at > prior and winner == [token, *exp["scores"][token]], "winner tuple")
        require(obs["UART_TOKEN"] == [(won_at + 1, [number, token])] and pins[0][0] > won_at, "token handoff")
        steps.append(dict(command=number, position=exp["position"], input_token=exp["input"],
                          winner=token, accepted_step_cycle=start, winner_cycle=won_at,
                          vector_sha256=checksum(canonical(exp["vector"])),
                          score_pairs_sha256=checksum(canonical(exp["scores"])), pin_frame=result.hex()))
    return steps, wire


def controls(starts, observed, expected):
    # Select a non-winning row in the third generation and a data bit in the first replayed reply.
    cases = [(4, "ROW", 77, 4, "command 4 score row 77"),
             (5, "NF", 91, 2, "command 5 normalized lane 91"),
             (8, "UART_PIN", 21, 3, "UART CRC")]
    failures = []
    for number, kind, offset, field, why in cases:
        data = observed[number][kind][offset][1]
        saved = data[field]
        data[field] = saved ^ 1
        try:
            compare(starts, observed, expected)
        except ValueError as exc:
            require(str(exc) == why, f"control failed for a different reason: {exc}")
            failures.append(why)
        else:
            raise ValueError(f"changed observation passed: {why}")
        finally:
            data[field] = saved
    return failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--public-git", required=True, type=Path, help="Local public checkout containing the pinned commit")
    parser.add_argument("--trace", type=Path, default=Path(__file__).with_name("trace.txt.gz"))
    args = parser.parse_args()
    expected, rebuilt, public, numpy_version = reference(args.public_git)
    raw = gzip.decompress(args.trace.read_bytes())
    starts, observed = parse(raw.decode("ascii").splitlines())
    steps, wire = compare(starts, observed, expected)
    rejects = controls(starts, observed, expected)
    print(json.dumps(dict(public_commit=COMMIT, public_files_sha256=public, numpy_version=numpy_version,
                          model_reconstruction=rebuilt, reduced_trace_sha256=checksum(raw),
                          step_replies=len(steps), matched_score_pairs=sum(len(v["scores"]) for v in expected.values()),
                          matched_final_activations=sum(len(v["vector"]) for v in expected.values()),
                          uart_frames=wire, pin_samples=sum(len(v["UART_PIN"]) for v in observed.values()),
                          steps=steps, negative_controls=rejects), indent=2))


if __name__ == "__main__":
    main()
