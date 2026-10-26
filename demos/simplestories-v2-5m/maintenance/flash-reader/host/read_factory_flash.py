#!/usr/bin/env python3
"""Receive a fixed read-only SRAM diagnostic dump. Never programs hardware.

Requires the separately reviewed temporary TFD1 reader already in SRAM.
The only transmitted byte is ASCII R. No arbitrary address, length, or flash
opcode is transmitted. A failed read preserves .partial and its receipt.
"""
from __future__ import annotations

import argparse
import datetime
import fcntl
import hashlib
import json
import os
from pathlib import Path
import select
import stat
import struct
import sys
import termios
import time
import zlib

FLASH_BYTES = 16_777_216
FLASH_ID = bytes.fromhex("0b4018")


def receive_dump(read_exact, output, expected_bytes=FLASH_BYTES,
                 expected_id=FLASH_ID, progress=None):
    """Testable transport-independent decoder; CLI never overrides identity/size."""
    header = read_exact(12)
    if len(header) != 12 or header[:4] != b"TFD1" or header[7] != 0:
        raise ValueError("Invalid TFD1 dump header")
    if header[4:7] != expected_id:
        raise ValueError("Unexpected flash ID: " + header[4:7].hex())
    length = struct.unpack("<I", header[8:12])[0]
    if length != expected_bytes:
        raise ValueError("Unexpected dump length: " + str(length))
    digest, crc, received = hashlib.sha256(), 0, 0
    while received < length:
        chunk = read_exact(min(65536, length - received))
        if not chunk or len(chunk) > length - received:
            raise ValueError("Invalid payload chunk length")
        written = output.write(chunk)
        if written != len(chunk):
            raise OSError("Short output write")
        digest.update(chunk)
        crc = zlib.crc32(chunk, crc)
        received += len(chunk)
        if progress:
            progress(received, length)
    reported_crc = read_exact(4)
    if len(reported_crc) != 4:
        raise ValueError("Truncated CRC trailer")
    if struct.unpack("<I", reported_crc)[0] != crc:
        raise ValueError("Flash dump CRC32 mismatch")
    return {"bytes": received, "jedec_id": header[4:7].hex(),
            "sha256": digest.hexdigest(), "crc32": f"{crc:08x}"}


class SerialReader:
    def __init__(self, fd, total_seconds=3600, idle_seconds=10):
        self.fd = fd
        self.deadline = time.monotonic() + total_seconds
        self.idle_seconds = idle_seconds

    def read_exact(self, count):
        result = bytearray()
        idle_deadline = time.monotonic() + self.idle_seconds
        while len(result) < count:
            remaining = min(self.deadline, idle_deadline) - time.monotonic()
            if remaining <= 0:
                raise TimeoutError("Dump timed out; acceptance is unknown, not retried")
            ready, _, _ = select.select([self.fd], [], [], remaining)
            if not ready:
                continue
            try:
                chunk = os.read(self.fd, count - len(result))
            except BlockingIOError:
                continue
            if not chunk:
                raise EOFError("Serial connection closed during dump")
            result.extend(chunk)
            idle_deadline = time.monotonic() + self.idle_seconds
        return bytes(result)


def open_serial(device):
    fd = os.open(device, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    exclusive = False
    try:
        if not stat.S_ISCHR(os.fstat(fd).st_mode):
            raise ValueError("Device must be a character device")
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        fcntl.ioctl(fd, termios.TIOCEXCL)
        exclusive = True
        attributes = termios.tcgetattr(fd)
        attributes[0] = attributes[1] = attributes[3] = 0
        attributes[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
        attributes[4] = attributes[5] = termios.B115200
        attributes[6][termios.VMIN] = attributes[6][termios.VTIME] = 0
        termios.tcsetattr(fd, termios.TCSANOW, attributes)
        termios.tcflush(fd, termios.TCIOFLUSH)
        return fd
    except BaseException:
        if exclusive:
            fcntl.ioctl(fd, termios.TIOCNXCL)
        os.close(fd)
        raise


def close_serial(fd):
    try:
        fcntl.ioctl(fd, termios.TIOCNXCL)
    finally:
        os.close(fd)


def new_file(path):
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    return os.fdopen(os.open(path, flags, 0o600), "wb")


def record_receipt(stream, result):
    # Append-only JSONL leaves the preflight record intact after a crash.
    stream.write((json.dumps(result, sort_keys=True) + "\n").encode())
    stream.flush()
    os.fsync(stream.fileno())


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    final = args.output.absolute()
    partial = final.with_name(final.name + ".partial")
    receipt_path = final.with_name(final.name + ".jsonl")
    # Reserve all evidence before opening UART or sending a request.
    if os.path.lexists(final):
        raise FileExistsError(str(final))
    with new_file(receipt_path) as receipt:
        result = {"status": "pending", "published": False, "device": args.device,
                  "command_hex": "52", "baud": 115200,
                  "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                  "partial": str(partial), "output": str(final)}
        record_receipt(receipt, result)
        try:
            with new_file(partial) as output:
                fd = open_serial(args.device)
                try:
                    reader = SerialReader(fd)
                    if os.write(fd, b"R") != 1:
                        raise OSError("Dump request was not completely sent")

                    def progress(received, length):
                        if received % 262144 == 0 or received == length:
                            print(f"Read {received}/{length} bytes ({100*received/length:.1f}%)", flush=True)

                    result.update(receive_dump(reader.read_exact, output,
                                               progress=progress))
                    output.flush()
                    os.fsync(output.fileno())
                finally:
                    close_serial(fd)
            # link() is an atomic, no-overwrite publication on the same filesystem.
            os.link(partial, final, follow_symlinks=False)
            result["status"] = "verified_single_read"
            result["published"] = True
            try:
                os.unlink(partial)
            except OSError as error:
                result["cleanup_warning"] = str(error)
        except BaseException as error:
            result["status"] = "failed"
            result["error"] = f"{type(error).__name__}: {error}"
            raise
        finally:
            result["finished_utc"] = datetime.datetime.now(datetime.timezone.utc).isoformat()
            record_receipt(receipt, result)
    print(json.dumps(result, sort_keys=True))
    print("Require an independent second full dump with matching SHA256 before provisioning.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, EOFError, ValueError) as error:
        print(f"Error: {error}", file=sys.stderr)
        raise SystemExit(2)
