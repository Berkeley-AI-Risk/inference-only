#!/usr/bin/env python3
"""Generate token IDs with the experimental seeded SRAM image.

Dry-run default. --execute opens only the explicit POSIX serial device; no
programming, discovery, installation, model/flash write or network path exists.
Each invocation starts CLEAR, discarding the current conversation. The owner
must first load the intended image and allow its authenticated boot to finish.
"""
import argparse
import datetime
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import sys
import time

HERE = Path(__file__).resolve().parent
PACKAGE = HERE.parents[2]
TRANSPORT_SHA256 = '00d18e9411d52f7d7414b96cbf28d29db38d1c5008705dfb4194f268cbb11cbf'
IMAGE_SHA256 = '0e6d30b68bd8757657bc1c3b949ac5b9571a0a8d1f8bb1a6e6018b241f733033'


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


codec = load_module('_seeded_settings_codec', HERE / 'settings_codec.py')


def released_transport():
    path = PACKAGE / 'host-app/token_machine_uart.py'
    if hashlib.sha256(path.read_bytes()).hexdigest() != TRANSPORT_SHA256:
        raise ValueError('released exclusive-TTY transport changed; refusing to open a device')
    return load_module('_seeded_released_uart_transport', path)


class Reporter:
    def __init__(self, path=None):
        self.stream = None
        self.sequence = 0
        if path is not None:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL |
                         getattr(os, 'O_NOFOLLOW', 0), 0o600)
            self.stream = os.fdopen(fd, 'w', encoding='utf-8', newline='\n')

    def __call__(self, event, **fields):
        self.sequence += 1
        record = dict(sequence=self.sequence, event=event,
                      utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      monotonic_ns=time.monotonic_ns(), **fields)
        line = json.dumps(record, sort_keys=True)
        if self.stream is not None:
            self.stream.write(line + '\n')
            self.stream.flush()
            os.fsync(self.stream.fileno())
        print(line, flush=True)

    def close(self):
        if self.stream is not None:
            self.stream.close()


class WireClient:
    def __init__(self, session, report, timeout):
        self.session, self.report, self.timeout = session, report, timeout
        self.label = None
        reader = session.reader
        previous_observer = reader._frame_observer

        def observe(frame):
            report('raw_rx', operation=self.label, frame_hex=frame.hex())
            if previous_observer is not None:
                previous_observer(frame)

        reader._frame_observer = observe
        if hasattr(reader, '_extract'):
            original_extract = reader._extract

            def strict_extract():
                if reader._pending and reader._pending[0] != 0x5a:
                    report('wire_noise', operation=self.label,
                           buffered_hex=bytes(reader._pending).hex())
                    raise ValueError('unexpected non-magic response bytes')
                return original_extract()

            reader._extract = strict_extract

    def receive(self, operation, timeout=None):
        self.label = operation
        try:
            frame = self.session.reader.read_frame(self.timeout if timeout is None else timeout)
        except (TimeoutError, ValueError, OSError) as error:
            self.report('receive_error', operation=operation, error_type=type(error).__name__,
                        error=str(error), buffered_hex=bytes(self.session.reader._pending).hex())
            raise
        return codec.decode_response(frame)

    def quiet(self, operation):
        try:
            response = self.receive(operation, 0.1)
        except TimeoutError:
            if self.session.reader.buffered_bytes:
                raise ValueError('incomplete trailing response; acceptance is unknown')
            return
        raise ValueError(f'unexpected extra response kind=0x{response.kind:02x}')

    def exchange(self, operation, frame, expected_kind, expected_operand=None):
        started = time.monotonic()
        self.report('tx_attempt', operation=operation, frame_hex=frame.hex())
        self.session._send(frame)
        response = self.receive(operation)
        if operation == 'clear' and response.kind == 0x81:
            # One earlier STEP may have completed before recovery CLEAR won.
            self.report('previous_step_before_clear', token=response.operand)
            response = self.receive(operation)
        if (response.kind != expected_kind or
                (expected_operand is not None and response.operand != expected_operand)):
            raise ValueError(f'{operation}: expected 0x{expected_kind:02x}/{expected_operand}, '
                             f'received 0x{response.kind:02x}/{response.operand}; stopped without retry')
        seconds = time.monotonic() - started
        self.report('operation', operation=operation, response_kind=response.kind,
                    operand=response.operand, seconds=seconds)
        return response.operand, seconds


def generate(session, report, *, code, seed, tokens, steps, timeout):
    client = WireClient(session, report, timeout)
    client.exchange('clear', codec.encode_legacy(2), 0x82, 0)
    client.quiet('clear-drain')
    client.exchange('settings', codec.encode_settings(code, seed), 0x83, code)
    for index, token in enumerate(tokens):
        client.exchange(f'append-{index + 1}', codec.encode_legacy(0, token), 0x80, 0)
    generated, durations = [], []
    for index in range(steps):
        token, seconds = client.exchange(f'step-{index + 1}', codec.encode_legacy(1), 0x81)
        generated.append(token)
        durations.append(seconds)
        report('token', ordinal=index + 1, token=token, seconds=seconds)
    client.quiet('final-drain')
    return dict(generated_tokens=generated, first_step_seconds=durations[0],
                cached_steps=max(0, steps - 1), cached_command_seconds=sum(durations[1:]),
                cached_command_tokens_per_second=((steps - 1) / sum(durations[1:]) if steps > 1 else None),
                timing_scope='Host STEP/reply wall time including JSON/evidence recording; first STEP separate.')


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--temperature', choices=('0', '0.5', '1', '2'), default='0')
    parser.add_argument('--seed', type=lambda value: int(value, 0))
    parser.add_argument('--tokens', type=int, nargs='+', default=[378])
    parser.add_argument('--steps', type=int, default=8)
    parser.add_argument('--timeout', type=float, default=3600, help='one-reply deadline in seconds, at most 3600')
    parser.add_argument('--device', help='exact POSIX /dev/ serial device; no automatic discovery')
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--record', type=Path, help='optional exclusive new JSONL receipt; never overwrites')
    args = parser.parse_args(argv)
    if (not 1 <= args.steps <= 2047 or not 1 <= len(args.tokens) <= 2047
            or len(args.tokens) + args.steps > 2048
            or any(not 0 <= token < 4019 for token in args.tokens)):
        parser.error('require 1..2047 prompt/generated tokens, IDs 0..4018, and total tape length <=2048')
    if not math.isfinite(args.timeout) or not 0 < args.timeout <= 3600:
        parser.error('--timeout must be finite, positive and at most 3600 seconds')
    code = codec.temperature_code(args.temperature)
    try:
        seed = codec.choose_seed(args.seed) if code or args.seed is not None else 0
    except ValueError as error:
        parser.error(str(error))
    if args.execute and (not args.device or not args.device.startswith('/dev/')
                         or any(ord(char) < 32 for char in args.device)):
        parser.error('--execute requires the exact owner-selected /dev/ serial device')
    if args.record is not None and not args.execute:
        parser.error('--record is available with --execute; dry runs write only stdout')
    report = Reporter(args.record)
    try:
        report('generation', variant='seeded-sampling', dry_run=not args.execute,
               hardware_access=args.execute, programming=False,
               temperature=args.temperature, seed=f'0x{seed:032x}', seed_used=code != 0,
               prompt_tokens=args.tokens, steps=args.steps,
               intended_image_sha256=IMAGE_SHA256, live_configuration_attested=False)
        if not args.execute:
            operations = [('clear', codec.encode_legacy(2)),
                          ('settings', codec.encode_settings(code, seed))]
            operations.extend(('append', codec.encode_legacy(0, token)) for token in args.tokens)
            operations.extend(('step', codec.encode_legacy(1)) for _ in range(args.steps))
            report('dry_run_frames', frames=[dict(operation=name, frame_hex=frame.hex())
                                             for name, frame in operations])
            return 0
        transport = released_transport()
        report('transport_verified', sha256=TRANSPORT_SHA256)
        with transport.TokenMachineSession(args.device, timeout_seconds=args.timeout) as session:
            result = generate(session, report, code=code, seed=seed, tokens=args.tokens,
                              steps=args.steps, timeout=args.timeout)
        report('finished', passed=True, **result)
        return 0
    except BaseException as error:
        report('failed', passed=False, error_type=type(error).__name__, error=str(error),
               command_retried=False, automatic_programming=False)
        if isinstance(error, (KeyboardInterrupt, SystemExit)):
            raise
        return 1
    finally:
        report.close()


if __name__ == '__main__':
    raise SystemExit(main())
