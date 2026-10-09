#!/usr/bin/env python3
"""Dependency-free macOS/POSIX client for the fixed token-only UART."""

from __future__ import annotations

import argparse
import datetime
import errno
import fcntl
import json
import os
import select
import stat
import sys
import termios
import time
from typing import Callable, NamedTuple, Optional, TextIO, Tuple

REQUEST_MAGIC = 0xA5
RESPONSE_MAGIC = 0x5A
OPCODES = {"append": 0x00, "step": 0x01, "clear": 0x02}
EXPECTED_RESULTS = {"append": 0x80, "step": 0x81, "clear": 0x82}
VOCAB_SIZE = 4019
FRAME_BYTES = 5
TRANSCRIPT_SCHEMA = "token-only-model0-uart-raw-frames-v1"


def utc_now() -> str:
    return (
        datetime.datetime.now(datetime.timezone.utc)
        .isoformat(timespec="microseconds")
        .replace("+00:00", "Z")
    )


class RawFrameTranscript:
    """Exclusive-create JSONL evidence for exact transmitted/received frames."""

    def __init__(self, path: str, device: str) -> None:
        if not path:
            raise ValueError("transcript path must not be empty")
        flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
        flags |= getattr(os, "O_CLOEXEC", 0)
        flags |= getattr(os, "O_NOFOLLOW", 0)
        fd = os.open(path, flags, 0o600)
        try:
            if not stat.S_ISREG(os.fstat(fd).st_mode):
                raise OSError("transcript destination is not a regular file")
            os.fchmod(fd, 0o600)
        except BaseException:
            os.close(fd)
            raise
        try:
            self._stream: TextIO = os.fdopen(
                fd, "w", encoding="utf-8", newline="\n"
            )
        except BaseException:
            os.close(fd)
            raise
        self._sequence = 0
        try:
            self._write({
                "device": device,
                "event": "session",
                "monotonic_ns": time.monotonic_ns(),
                "schema": TRANSCRIPT_SCHEMA,
                "utc": utc_now(),
            })
        except BaseException:
            self._stream.close()
            raise

    def _write(self, record: dict) -> None:
        self._stream.write(
            json.dumps(record, sort_keys=True, separators=(",", ":")) + "\n"
        )
        self._stream.flush()
        os.fsync(self._stream.fileno())

    def record_frame(self, direction: str, frame: bytes) -> None:
        if direction not in ("tx", "rx"):
            raise ValueError("transcript direction must be tx or rx")
        if len(frame) != FRAME_BYTES:
            raise ValueError("transcript records only complete five-byte frames")
        self._sequence += 1
        self._write({
            "direction": direction,
            "event": "frame",
            "frame_hex": frame.hex(),
            "monotonic_ns": time.monotonic_ns(),
            "sequence": self._sequence,
            "utc": utc_now(),
        })

    def close(self) -> None:
        if not self._stream.closed:
            self._stream.close()


class CommandRejected(RuntimeError):
    """The FPGA explicitly reported that a command was not accepted."""

    def __init__(self, operation: str, kind: int, attempts: int) -> None:
        self.operation = operation
        self.kind = kind
        self.attempts = attempts
        super().__init__(
            f"{operation} rejected (response 0x{kind:02x}, "
            f"attempts={attempts})"
        )


class CommandResult(NamedTuple):
    operation: str
    token: Optional[int]
    completed_before_clear: Tuple[int, ...]
    attempts: int


class BatchCommand(NamedTuple):
    operation: str
    token: int


def crc8(payload: bytes) -> int:
    value = 0
    for item in payload:
        value ^= item
        for _ in range(8):
            value = ((value << 1) ^ 0x07) & 0xFF if value & 0x80 else (
                value << 1
            ) & 0xFF
    return value


def request_frame(operation: str, token: int = 0) -> bytes:
    if operation not in OPCODES:
        raise ValueError(f"unsupported operation: {operation}")
    if operation == "append":
        if not 0 <= token < VOCAB_SIZE:
            raise ValueError(f"token must be in 0..{VOCAB_SIZE - 1}")
    elif token != 0:
        raise ValueError(f"{operation} has no token operand")
    prefix = bytes((REQUEST_MAGIC, OPCODES[operation], token & 0xFF,
                    (token >> 8) & 0x0F))
    return prefix + bytes((crc8(prefix),))


def decode_response(frame: bytes) -> Tuple[int, int]:
    if len(frame) != FRAME_BYTES or frame[0] != RESPONSE_MAGIC:
        raise ValueError("malformed response frame")
    if crc8(frame[:4]) != frame[4]:
        raise ValueError("response CRC mismatch")
    if frame[3] & 0xF0:
        raise ValueError("noncanonical response token")
    return frame[1], frame[2] | ((frame[3] & 0x0F) << 8)


def response_frame(kind: int, token: int = 0) -> bytes:
    """Build a response for the offline self-test and pseudo-terminal tests."""
    if not 0 <= kind <= 0xFF or not 0 <= token <= 0xFFF:
        raise ValueError("response field out of range")
    prefix = bytes((RESPONSE_MAGIC, kind, token & 0xFF, token >> 8))
    return prefix + bytes((crc8(prefix),))


def claim_exclusive_uart(fd: int, device: str) -> None:
    """Fail quickly unless this process can exclusively own the serial path."""
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError as error:
        if error.errno in (errno.EACCES, errno.EAGAIN, errno.EWOULDBLOCK):
            raise OSError(
                error.errno,
                f"serial device is already locked: {device}",
            ) from error
        raise OSError(
            error.errno,
            f"could not lock serial device {device}: {error.strerror}",
        ) from error

    tioc_exclusive = getattr(termios, "TIOCEXCL", None)
    if tioc_exclusive is None:
        return
    try:
        fcntl.ioctl(fd, tioc_exclusive)
    except OSError as error:
        fcntl.flock(fd, fcntl.LOCK_UN)
        raise OSError(
            error.errno,
            f"could not claim exclusive tty access to {device}: "
            f"{error.strerror}",
        ) from error


def release_exclusive_uart(fd: int) -> None:
    tioc_nonexclusive = getattr(termios, "TIOCNXCL", None)
    if tioc_nonexclusive is not None:
        try:
            fcntl.ioctl(fd, tioc_nonexclusive)
        except OSError:
            pass
    try:
        fcntl.flock(fd, fcntl.LOCK_UN)
    except OSError:
        pass


def configure_uart(fd: int) -> None:
    attributes = termios.tcgetattr(fd)
    attributes[0] = 0
    attributes[1] = 0
    attributes[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
    attributes[3] = 0
    attributes[4] = termios.B115200
    attributes[5] = termios.B115200
    attributes[6][termios.VMIN] = 0
    attributes[6][termios.VTIME] = 0
    termios.tcsetattr(fd, termios.TCSANOW, attributes)
    termios.tcflush(fd, termios.TCIOFLUSH)


class ResponseFrameReader:
    """Incremental decoder that preserves bytes following the first frame."""

    def __init__(
        self,
        fd: int,
        frame_observer: Optional[Callable[[bytes], None]] = None,
    ) -> None:
        self.fd = fd
        self._pending = bytearray()
        self._frame_observer = frame_observer

    @property
    def buffered_bytes(self) -> int:
        return len(self._pending)

    def _extract(self) -> Optional[bytes]:
        try:
            magic_index = self._pending.index(RESPONSE_MAGIC)
        except ValueError:
            self._pending.clear()
            return None

        if magic_index:
            del self._pending[:magic_index]
        if len(self._pending) < FRAME_BYTES:
            return None

        candidate = bytes(self._pending[:FRAME_BYTES])
        if self._frame_observer is not None:
            self._frame_observer(candidate)
        try:
            decode_response(candidate)
        except ValueError:
            # Consume the bad magic byte so a subsequent read can resynchronize.
            # The current call still reports the corrupt/noncanonical frame.
            del self._pending[0]
            raise
        del self._pending[:FRAME_BYTES]
        return candidate

    def read_frame(self, timeout_seconds: float) -> bytes:
        if timeout_seconds <= 0:
            raise ValueError("timeout must be positive")
        deadline = time.monotonic() + timeout_seconds
        while True:
            candidate = self._extract()
            if candidate is not None:
                return candidate

            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            readable, _, _ = select.select((self.fd,), (), (), remaining)
            if not readable:
                break
            try:
                chunk = os.read(self.fd, 4096)
            except BlockingIOError:
                continue
            if not chunk:
                raise OSError("UART closed while waiting for a response")
            self._pending.extend(chunk)
        raise TimeoutError(
            f"no complete response within {timeout_seconds:g} seconds"
        )


class TokenMachineSession:
    """One open UART transaction stream with a persistent receive buffer."""

    def __init__(self, device: str, timeout_seconds: float = 3600.0,
                 not_ready_retries: int = 0,
                 retry_interval_seconds: float = 0.25,
                 transcript_path: Optional[str] = None) -> None:
        if timeout_seconds <= 0:
            raise ValueError("timeout must be positive")
        if not_ready_retries < 0:
            raise ValueError("not-ready retries must be nonnegative")
        if retry_interval_seconds < 0:
            raise ValueError("retry interval must be nonnegative")
        self.device = device
        self.timeout_seconds = timeout_seconds
        self.not_ready_retries = not_ready_retries
        self.retry_interval_seconds = retry_interval_seconds
        self.transcript_path = transcript_path
        self.fd: Optional[int] = None
        self.reader: Optional[ResponseFrameReader] = None
        self.transcript: Optional[RawFrameTranscript] = None

    def open(self) -> "TokenMachineSession":
        if self.fd is not None:
            return self
        transcript = None
        if self.transcript_path is not None:
            transcript = RawFrameTranscript(
                self.transcript_path, self.device
            )
        fd = None
        exclusive_claimed = False
        try:
            open_flags = (
                os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK |
                getattr(os, "O_CLOEXEC", 0) |
                # macOS/BSD can take the advisory lock atomically with open;
                # flock below provides the same check on other POSIX hosts.
                getattr(os, "O_EXLOCK", 0)
            )
            try:
                fd = os.open(self.device, open_flags)
            except OSError as error:
                if (getattr(os, "O_EXLOCK", 0) and error.errno in
                        (errno.EACCES, errno.EAGAIN, errno.EBUSY,
                         errno.EWOULDBLOCK)):
                    raise OSError(
                        error.errno,
                        f"serial device is already locked: {self.device}",
                    ) from error
                raise
            if not stat.S_ISCHR(os.fstat(fd).st_mode):
                raise OSError(
                    errno.ENOTTY,
                    f"serial device is not a character device: {self.device}",
                )
            claim_exclusive_uart(fd, self.device)
            exclusive_claimed = True
            configure_uart(fd)
        except BaseException:
            if fd is not None:
                if exclusive_claimed:
                    release_exclusive_uart(fd)
                os.close(fd)
            if transcript is not None:
                transcript.close()
            raise
        self.fd = fd
        self.transcript = transcript
        self.reader = ResponseFrameReader(fd, self._record_received_frame)
        return self

    def close(self) -> None:
        fd = self.fd
        transcript = self.transcript
        self.fd = None
        self.reader = None
        self.transcript = None
        try:
            if fd is not None:
                release_exclusive_uart(fd)
                os.close(fd)
        finally:
            if transcript is not None:
                transcript.close()

    def __enter__(self) -> "TokenMachineSession":
        return self.open()

    def __exit__(self, exc_type: object, exc_value: object,
                 traceback: object) -> None:
        self.close()

    def _require_open(self) -> Tuple[int, ResponseFrameReader]:
        if self.fd is None or self.reader is None:
            raise RuntimeError("UART session is not open")
        return self.fd, self.reader

    def _record_received_frame(self, frame: bytes) -> None:
        if self.transcript is not None:
            self.transcript.record_frame("rx", frame)

    def _send(self, frame: bytes) -> None:
        fd, _ = self._require_open()
        offset = 0
        deadline = time.monotonic() + self.timeout_seconds
        while offset < len(frame):
            try:
                written = os.write(fd, frame[offset:])
            except BlockingIOError:
                written = 0
            if written:
                offset += written
                continue
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("UART write timed out before command framing")
            _, writable, _ = select.select((), (fd,), (), remaining)
            if not writable:
                raise TimeoutError("UART write timed out before command framing")
        if self.transcript is not None:
            try:
                self.transcript.record_frame("tx", frame)
            except OSError as error:
                raise OSError(
                    "UART frame was queued but transcript recording failed; "
                    "command acceptance is unknown"
                ) from error
        # Do not call tcdrain here.  The complete frame is already queued in
        # order, and on macOS a pseudo-terminal tcdrain can wait for its peer
        # while retaining the Python interpreter lock.  Waiting for the framed
        # response provides the required request/response ordering.

    @staticmethod
    def _validate_response_token(kind: int, token: int) -> None:
        if kind == EXPECTED_RESULTS["step"]:
            if token >= VOCAB_SIZE:
                raise RuntimeError(
                    f"generated token {token} is outside the fixed vocabulary"
                )
        elif token != 0:
            raise RuntimeError(
                f"response 0x{kind:02x} carried unexpected token {token}"
            )

    def _receive(self) -> Tuple[int, int]:
        _, reader = self._require_open()
        kind, token = decode_response(
            reader.read_frame(self.timeout_seconds)
        )
        self._validate_response_token(kind, token)
        return kind, token

    def command(self, operation: str, token: int = 0,
                not_ready_retries: Optional[int] = None,
                retry_interval_seconds: Optional[float] = None
                ) -> CommandResult:
        frame = request_frame(operation, token)
        retries = (self.not_ready_retries if not_ready_retries is None
                   else not_ready_retries)
        interval = (self.retry_interval_seconds
                    if retry_interval_seconds is None
                    else retry_interval_seconds)
        if retries < 0:
            raise ValueError("not-ready retries must be nonnegative")
        if interval < 0:
            raise ValueError("retry interval must be nonnegative")

        expected = EXPECTED_RESULTS[operation]
        explicit_not_ready = 0xC0 | OPCODES[operation]
        attempts = 0
        completed_before_clear = []
        while True:
            attempts += 1
            self._send(frame)
            while True:
                try:
                    kind, result_token = self._receive()
                except TimeoutError as error:
                    # A timeout does not tell us whether the command crossed the
                    # ready/valid seam, so replaying it could duplicate APPEND.
                    raise TimeoutError(
                        f"{operation} response timed out; command acceptance is "
                        "unknown and the command was not retried"
                    ) from error

                if kind == expected:
                    return CommandResult(
                        operation,
                        result_token if operation == "step" else None,
                        tuple(completed_before_clear),
                        attempts,
                    )
                if (operation == "clear" and
                        kind == EXPECTED_RESULTS["step"]):
                    completed_before_clear.append(result_token)
                    continue
                if 0xC0 <= kind <= 0xCF:
                    if kind == explicit_not_ready and attempts <= retries:
                        if interval:
                            time.sleep(interval)
                        break
                    raise CommandRejected(operation, kind, attempts)
                raise RuntimeError(
                    f"unexpected response 0x{kind:02x} to {operation}"
                )

    def step_then_clear(self) -> CommandResult:
        """Issue only STEP and CLEAR, then resolve their permitted race."""
        self._send(request_frame("step"))
        self._send(request_frame("clear"))
        completed = []
        while True:
            try:
                kind, token = self._receive()
            except TimeoutError as error:
                raise TimeoutError(
                    "STEP/CLEAR response timed out; command acceptance is "
                    "unknown and neither command was retried"
                ) from error
            if kind == EXPECTED_RESULTS["step"]:
                completed.append(token)
                continue
            if kind == EXPECTED_RESULTS["clear"]:
                return CommandResult(
                    "step-clear", None, tuple(completed), 1
                )
            if 0xC0 <= kind <= 0xCF:
                raise CommandRejected("step-clear", kind, 1)
            raise RuntimeError(
                f"unexpected response 0x{kind:02x} to STEP/CLEAR"
            )


def transact(device: str, operation: str, token: int,
             timeout_seconds: float) -> Optional[int]:
    """Backward-compatible single-command helper."""
    with TokenMachineSession(device, timeout_seconds) as session:
        return session.command(operation, token).token


def parse_batch_item(item: str) -> BatchCommand:
    if item == "step" or item == "clear" or item == "step-clear":
        return BatchCommand(item, 0)
    if item.startswith("append:"):
        fields = item.split(":")
        if len(fields) != 2 or not fields[1]:
            raise ValueError(f"invalid batch command: {item}")
        try:
            token = int(fields[1], 0)
        except ValueError as error:
            raise ValueError(f"invalid APPEND token in: {item}") from error
        request_frame("append", token)
        return BatchCommand("append", token)
    raise ValueError(f"invalid batch command: {item}")


def run_batch(session: TokenMachineSession,
              commands: Tuple[BatchCommand, ...]) -> Tuple[CommandResult, ...]:
    results = []
    for command in commands:
        if command.operation == "step-clear":
            results.append(session.step_then_clear())
        else:
            results.append(session.command(command.operation, command.token))
    return tuple(results)


def run_known_answer_test(session: TokenMachineSession) -> Tuple[int, ...]:
    """Run Board1 generation, cached continuation, and CLEAR/replay KAT."""
    sequence = (
        BatchCommand("clear", 0),
        BatchCommand("append", 378),
        BatchCommand("step", 0),
        # STEP commits its generated token to the tape.  A second STEP is the
        # continuation operation; explicitly appending 200 here would
        # duplicate the already committed generated token.
        BatchCommand("step", 0),
        BatchCommand("clear", 0),
        BatchCommand("append", 378),
        BatchCommand("step", 0),
    )
    expected_tokens = (200, 15, 200)
    results = run_batch(session, sequence)
    actual_tokens = tuple(
        result.token for result in results if result.operation == "step"
    )
    if actual_tokens != expected_tokens:
        raise RuntimeError(
            f"Board1 KAT mismatch: expected {expected_tokens}, got "
            f"{actual_tokens}"
        )
    return actual_tokens


def self_test() -> None:
    assert request_frame("append", 378) == bytes.fromhex("a5007a0196")
    assert request_frame("step") == bytes.fromhex("a5010000da")
    assert request_frame("clear") == bytes.fromhex("a502000067")
    response = response_frame(0x81, 200)
    assert decode_response(response) == (0x81, 200)
    assert parse_batch_item("append:0x17a") == BatchCommand("append", 378)
    try:
        decode_response(response[:-1] + bytes((response[-1] ^ 1,)))
    except ValueError:
        pass
    else:
        raise AssertionError("corrupted response CRC was accepted")
    print(
        "PASS mac-uart-client frames=4 crc8=07 token=200 "
        "persistent_session=available dependencies=stdlib"
    )


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Operate the fixed token-only FPGA over a POSIX UART"
    )
    parser.add_argument("--device", help="for example /dev/cu.usbserial-XXXX")
    parser.add_argument("--timeout", type=float, default=3600.0)
    parser.add_argument("--not-ready-retries", type=int, default=0,
                        help="retry only explicit matching C0/C1/C2 rejects")
    parser.add_argument("--retry-interval", type=float, default=0.25)
    parser.add_argument(
        "--transcript",
        help=(
            "write timestamped exact TX/RX frames as JSONL to a new file; "
            "an existing path is never overwritten"
        ),
    )
    parser.add_argument("--self-test", action="store_true")
    subparsers = parser.add_subparsers(dest="operation")
    append_parser = subparsers.add_parser("append")
    append_parser.add_argument("token", type=int)
    subparsers.add_parser("step")
    subparsers.add_parser("clear")
    subparsers.add_parser(
        "step-clear", help="send STEP then CLEAR and resolve either race order"
    )
    batch_parser = subparsers.add_parser(
        "batch", help="run one persistent sequence"
    )
    batch_parser.add_argument(
        "commands", nargs="+",
        help="append:TOKEN, step, clear, or the STEP/CLEAR macro step-clear",
    )
    subparsers.add_parser("kat", help="run the fixed Board1 known-answer test")
    return parser.parse_args(argv)


def print_result(index: Optional[int], result: CommandResult) -> None:
    prefix = "" if index is None else f"{index}: "
    if result.operation == "step":
        print(f"{prefix}{result.token}")
    elif result.operation == "step-clear":
        tokens = ",".join(str(token) for token in
                          result.completed_before_clear) or "none"
        print(f"{prefix}accepted completed_before_clear={tokens}")
    else:
        suffix = ""
        if result.completed_before_clear:
            values = ",".join(
                str(token) for token in result.completed_before_clear
            )
            suffix = f" completed_before_clear={values}"
        print(f"{prefix}accepted{suffix}")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    if args.self_test:
        self_test()
        return 0
    if args.operation is None or args.device is None:
        raise SystemExit(
            "--device and one of append/step/clear/step-clear/batch/kat "
            "are required"
        )

    with TokenMachineSession(
        args.device,
        args.timeout,
        args.not_ready_retries,
        args.retry_interval,
        args.transcript,
    ) as session:
        if args.operation == "batch":
            commands = tuple(parse_batch_item(item) for item in args.commands)
            for index, result in enumerate(run_batch(session, commands), 1):
                print_result(index, result)
        elif args.operation == "kat":
            tokens = run_known_answer_test(session)
            print(
                "PASS board1-uart-kat tokens=" +
                ",".join(str(token) for token in tokens) +
                " clear_replay=1 operations=7"
            )
        elif args.operation == "step-clear":
            print_result(None, session.step_then_clear())
        else:
            token = args.token if args.operation == "append" else 0
            print_result(None, session.command(args.operation, token))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv[1:]))
    except (OSError, TimeoutError, ValueError, RuntimeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(2)
