"""Verify and run the measured TLM26 Tang Mega image through its ordinary UART."""

import argparse
from contextlib import contextmanager
from hashlib import file_digest, sha256
import json
import os
from pathlib import Path
import stat
import termios
import time

from uart_replay import claim_exclusive_uart, configure_uart, read_bytes, release_exclusive_uart
from uart_replay import request_frame, response_frame, write_bytes


DEMO = Path(__file__).resolve().parents[1]
DEFAULT_VARIANT = "overlap-r2-50mhz"
PROTECTED_VARIANT = "five-external-kv-zero-hold-50mhz"
VARIANTS = (DEFAULT_VARIANT, PROTECTED_VARIANT)
BENCHMARK_REFERENCE = (DEMO.parents[1] / "benchmarks/fpga-speed"
                       / "tlm26-overlap-r2-50mhz-v1/golden.json")
MODEL_BYTES = 768 * 4096
VOCABULARY = 512
CONTEXT = 256


def asset_path(variant, name):
    directory = variant if name == "tlm26.fs" else DEFAULT_VARIANT
    return DEMO / "prebuilt" / directory / name


def check_assets(variant=DEFAULT_VARIANT):
    record = json.loads((DEMO / "prebuilt" / variant / "IMAGE.json").read_bytes())
    assets = record["files"]
    if set(assets) != {"tlm26.fs", "model.bin", "tok512.model"}:
        raise ValueError("Wrong TLM26 image inventory")
    for name, expected in assets.items():
        path = asset_path(variant, name)
        with path.open("rb") as stream:
            observed = {"bytes": os.fstat(stream.fileno()).st_size,
                        "sha256": file_digest(stream, "sha256").hexdigest()}
        if observed != expected:
            raise ValueError(f"Shipped file differs from its recorded identity: {name}")
    return assets


def exact_input(name, assets, variant):
    content = asset_path(variant, name).read_bytes()
    if {"bytes": len(content), "sha256": sha256(content).hexdigest()} != assets[name]:
        raise ValueError(f"{name} changed after verification")
    return content


@contextmanager
def opened_uart(port):
    fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode) or not os.isatty(fd):
            raise ValueError("Choose the board's UART device")
        claim_exclusive_uart(fd, port)
        try:
            configure_uart(fd)
            yield fd
        finally:
            release_exclusive_uart(fd)
    finally:
        os.close(fd)


def upload(fd, model, result):
    if len(model) != MODEL_BYTES:
        raise ValueError("Wrong provisioned model size")
    start = time.monotonic()
    write_bytes(fd, b"TLM1")
    if read_bytes(fd, 1, 12) != b"B":
        raise RuntimeError("Missing TLM1 loader acknowledgment. Check the SRAM image and UART selection.")
    result["loader_ready"] = True
    for offset in range(0, len(model), 4096):
        write_bytes(fd, model[offset:offset + 4096])
        if read_bytes(fd, 1, 6) != b"y":
            raise RuntimeError(f"Missing model-page acknowledgment at page {offset // 4096}")
        pages = offset // 4096 + 1
        result["acknowledged_pages"] = pages
        if pages % 128 == 0:
            print(f"Uploaded {pages}/768 pages", flush=True)
    result["provision_elapsed_s"] = time.monotonic() - start
    # The existing transport grants the loader one post-ACK handover interval.
    time.sleep(0.02)


def transact(fd, result, operation, token=0, *, expected_token=None):
    raw = request_frame(operation, token)
    record = {"operation": operation, "input_id": token, "tx": raw.hex()}
    result["frames"].append(record)
    launched = time.monotonic_ns()
    write_bytes(fd, raw)
    reply = read_bytes(fd, 5, 10)
    complete_frame = time.monotonic_ns()
    record.update(rx=reply.hex(), start_ns=launched, complete_frame_ns=complete_frame,
                  elapsed_ns=complete_frame - launched)
    reply_token = int.from_bytes(reply[2:4], "little")
    expected_kind = {"clear": 0x82, "append": 0x80, "step": 0x81}[operation]
    if reply_token >= VOCABULARY or reply != response_frame(expected_kind, reply_token):
        raise RuntimeError(f"{operation} returned {reply.hex()}, expected opcode {expected_kind:02x} and a valid CRC")
    if operation != "step" and reply_token:
        raise RuntimeError(f"{operation} acknowledged unexpected value {reply_token}")
    if expected_token is not None and reply_token != expected_token:
        raise RuntimeError(f"Reference mismatch at STEP {len(result['generated_ids']) + 1}: "
                           f"received {reply_token}, expected {expected_token}")
    record["validated_ns"] = time.monotonic_ns()
    return reply_token


def prompt_options(args, assets):
    if args.capacity:
        if args.new_tokens is not None:
            raise ValueError("The capacity test requires exactly 255 outputs.")
        reference = json.loads((DEMO.parents[1] / "evidence/tlm26-tang-five-layer-kv-board/REFERENCE.json").read_bytes())
        if reference["prompt_tokens"] != [1] or len(reference["expected_step_ids"]) != 255:
            raise ValueError("The capacity reference must cover BOS and 255 outputs.")
        return [1], 255, reference["expected_step_ids"], None
    if args.benchmark:
        if args.new_tokens is not None:
            raise ValueError("The benchmark requires exactly 128 outputs.")
        reference = json.loads(BENCHMARK_REFERENCE.read_bytes())
        if (reference["input_ids"] != [1] or reference["output_count"] != 128
                or reference["stop_at_eos"] is not False
                or len(reference["integer_reference_ids"]) != 128):
            raise ValueError("The saved BOS benchmark reference has the wrong workload.")
        return [1], 128, reference["integer_reference_ids"], None
    if args.prompt is not None:
        try:
            import sentencepiece
        except ModuleNotFoundError as error:
            raise ValueError("Install SentencePiece before using --prompt. The default smoke check needs only Python.") from error
        tokenizer = sentencepiece.SentencePieceProcessor(model_proto=exact_input("tok512.model", assets, args.variant))
        if tokenizer.bos_id() != 1 or tokenizer.vocab_size() != VOCABULARY:
            raise ValueError("Wrong tokenizer vocabulary")
        ids = [1, *tokenizer.encode(args.prompt, out_type=int)]
        return ids, (12 if args.new_tokens is None else args.new_tokens), None, tokenizer
    if args.ids is not None:
        return args.ids, (12 if args.new_tokens is None else args.new_tokens), None, None
    if args.new_tokens is not None:
        raise ValueError("The reference smoke check has a fixed continuation. Pass --prompt or --ids to set a count.")
    reference = json.loads((DEMO / "evidence/integer-cpu.json").read_bytes())["results"][0]
    return reference["prompt_ids"], len(reference["generated_ids"]), reference["generated_ids"], None


def generate(args, assets):
    prompt, count, reference, tokenizer = prompt_options(args, assets)
    if count < 1 or len(prompt) + count > CONTEXT or any(not 0 <= value < VOCABULARY for value in prompt):
        raise ValueError(f"Use IDs in 0–511 and keep the prefix plus new tokens within {CONTEXT} positions")
    model = None if args.already_provisioned else exact_input("model.bin", assets, args.variant)
    args.out.mkdir()
    result = {"variant": args.variant, "benchmark": args.benchmark,
              "capacity": args.capacity, "asset_identity_checked_at_host": assets, "loader_ready": False, "acknowledged_pages": 0,
              "already_provisioned": args.already_provisioned, "prompt_ids": prompt, "generated_ids": [],
              "reference_ids": reference, "frames": [], "complete": False}
    try:
        with opened_uart(args.uart) as fd:
            if model is not None:
                upload(fd, model, result)
            transact(fd, result, "clear")
            for token in prompt:
                transact(fd, result, "append", token)
            for index in range(count):
                expected = None if reference is None else reference[index]
                token = transact(fd, result, "step", expected_token=expected)
                result["generated_ids"].append(token)
            transact(fd, result, "clear")
        if tokenizer is not None:
            result["continuation"] = tokenizer.decode(result["generated_ids"])
        result["complete"] = True
    except (OSError, ValueError, RuntimeError, termios.error) as error:
        result["error"] = str(error)
        raise
    finally:
        with (args.out / "RESULT.json").open("x") as stream:
            json.dump(result, stream, indent=2, sort_keys=True)
            stream.write("\n")
    print(json.dumps({"generated_ids": result["generated_ids"], "continuation": result.get("continuation"),
                      "reference_match": reference is not None, "receipt": str(args.out / "RESULT.json")}))


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    modes = cli.add_subparsers(dest="mode", required=True)
    verify = modes.add_parser("verify", help="verify the ready-to-load assets without opening a UART")
    run = modes.add_parser("run", help="load the DDR model and check the reference prompt by default")
    for mode in (verify, run):
        mode.add_argument("--variant", choices=VARIANTS, default=DEFAULT_VARIANT)
    run.add_argument("--uart", required=True)
    run.add_argument("--out", type=Path, required=True, help="new directory for the session receipt")
    run.add_argument("--already-provisioned", action="store_true")
    options = run.add_mutually_exclusive_group()
    options.add_argument("--prompt", help="text to tokenize with the shipped tokenizer")
    options.add_argument("--ids", type=int, nargs="+", help="exact input IDs, including any BOS")
    options.add_argument("--benchmark", action="store_true", help="check the fixed BOS plus 128-output reference")
    options.add_argument("--capacity", action="store_true", help="check all 255 saved capacity IDs")
    run.add_argument("--new-tokens", type=int)
    args = cli.parse_args()
    try:
        assets = check_assets(args.variant)
        if args.mode == "verify":
            print(json.dumps({"verified": assets}, indent=2, sort_keys=True))
        else:
            generate(args, assets)
    except (OSError, ValueError, RuntimeError, termios.error) as error:
        cli.exit(1, f"{error}\n")


if __name__ == "__main__":
    main()
