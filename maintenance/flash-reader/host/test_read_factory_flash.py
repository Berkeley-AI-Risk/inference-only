import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import pty
import struct
import tempfile
import threading
import unittest
from unittest import mock
import zlib

import read_factory_flash as reader


def packet(data, chip_id=reader.FLASH_ID, length=None, crc=None):
    return (b"TFD1" + chip_id + b"\0" +
            struct.pack("<I", len(data) if length is None else length) + data +
            struct.pack("<I", zlib.crc32(data) if crc is None else crc))


class ReceiverTests(unittest.TestCase):
    def test_correct_size_id_sha_crc_and_data(self):
        data = bytes(range(256)) * 257
        stream, output = io.BytesIO(packet(data)), io.BytesIO()
        result = reader.receive_dump(stream.read, output, expected_bytes=len(data))
        self.assertEqual(output.getvalue(), data)
        self.assertEqual(result["sha256"], hashlib.sha256(data).hexdigest())
        self.assertEqual(result["crc32"], f"{zlib.crc32(data):08x}")
        self.assertEqual(result["bytes"], len(data))

    def test_bad_headers_rejected_before_payload(self):
        for raw in (b"bad", b"FAIL" + bytes(8),
                    packet(b"x", chip_id=b"\xff\xff\xff"),
                    packet(b"x", length=0),
                    b"TFD1" + reader.FLASH_ID + b"\x01" + struct.pack("<I", 1)):
            output = io.BytesIO()
            with self.subTest(raw=raw[:12]), self.assertRaises(ValueError):
                reader.receive_dump(io.BytesIO(raw).read, output, expected_bytes=1)
            self.assertEqual(output.getvalue(), b"")

    def test_bad_crc_preserves_payload_but_rejects(self):
        output = io.BytesIO()
        with self.assertRaisesRegex(ValueError, "CRC32"):
            reader.receive_dump(io.BytesIO(packet(b"abcd", crc=0)).read,
                                output, expected_bytes=4)
        self.assertEqual(output.getvalue(), b"abcd")

    def test_truncation_rejected(self):
        wire = packet(b"abcd")
        for stop in (0, 11, 12, 14, 16, 18):
            with self.subTest(stop=stop), self.assertRaises(ValueError):
                reader.receive_dump(io.BytesIO(wire[:stop]).read, io.BytesIO(),
                                    expected_bytes=4)

    def test_existing_final_or_partial_never_opens_uart(self):
        for suffix in ("", ".partial", ".jsonl"):
            with tempfile.TemporaryDirectory() as directory:
                target = Path(directory) / "dump.bin"
                occupied = Path(str(target) + suffix)
                occupied.write_bytes(b"sentinel")
                with mock.patch.object(reader, "open_serial") as open_uart:
                    with self.assertRaises(FileExistsError):
                        reader.main(["--device", "/dev/unused", "--output", str(target)])
                    open_uart.assert_not_called()
                self.assertEqual(occupied.read_bytes(), b"sentinel")

    def test_complete_cli_fixed_request_and_atomic_publication(self):
        data = bytes(range(256)) * (reader.FLASH_BYTES // 256)
        source = io.BytesIO(packet(data))
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "dump.bin"
            fake_transport = mock.Mock(read_exact=source.read)
            with mock.patch.object(reader, "open_serial", return_value=91), \
                 mock.patch.object(reader, "close_serial") as close_uart, \
                 mock.patch.object(reader, "SerialReader", return_value=fake_transport), \
                 mock.patch.object(reader.os, "write", return_value=1) as write_uart, \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(reader.main(["--device", "/dev/mock",
                                              "--output", str(target)]), 0)
            write_uart.assert_called_once_with(91, b"R")
            close_uart.assert_called_once_with(91)
            self.assertEqual(target.stat().st_size, reader.FLASH_BYTES)
            self.assertEqual(hashlib.sha256(target.read_bytes()).digest(),
                             hashlib.sha256(data).digest())
            self.assertFalse(Path(str(target) + ".partial").exists())
            records = [json.loads(line) for line in Path(str(target) + ".jsonl").read_text().splitlines()]
            self.assertEqual(records[0]["status"], "pending")
            receipt = records[-1]
            self.assertEqual(receipt["status"], "verified_single_read")
            self.assertTrue(receipt["published"])

    def test_failure_receipt_and_partial_are_retained(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "dump.bin"
            with mock.patch.object(reader, "open_serial", side_effect=OSError("offline")):
                with self.assertRaises(OSError):
                    reader.main(["--device", "/dev/mock", "--output", str(target)])
            self.assertFalse(target.exists())
            self.assertTrue(Path(str(target) + ".partial").exists())
            result = json.loads(Path(str(target) + ".jsonl").read_text().splitlines()[-1])
            self.assertEqual(result["status"], "failed")
            self.assertIn("offline", result["error"])

    def test_partial_cleanup_failure_does_not_mislabel_published_dump(self):
        data = b"\xa5" * reader.FLASH_BYTES
        source = io.BytesIO(packet(data))
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "dump.bin"
            with mock.patch.object(reader, "open_serial", return_value=91), \
                 mock.patch.object(reader, "close_serial"), \
                 mock.patch.object(reader, "SerialReader", return_value=mock.Mock(read_exact=source.read)), \
                 mock.patch.object(reader.os, "write", return_value=1), \
                 mock.patch.object(reader.os, "unlink", side_effect=OSError("cleanup unavailable")), \
                 contextlib.redirect_stdout(io.StringIO()):
                self.assertEqual(reader.main(["--device", "/dev/mock",
                                              "--output", str(target)]), 0)
            self.assertEqual(target.stat().st_size, reader.FLASH_BYTES)
            self.assertTrue(Path(str(target) + ".partial").exists())
            result = json.loads(Path(str(target) + ".jsonl").read_text().splitlines()[-1])
            self.assertTrue(result["published"])
            self.assertEqual(result["status"], "verified_single_read")
            self.assertIn("cleanup unavailable", result["cleanup_warning"])

    def test_actual_pty_fragmented_transport(self):
        master, slave = pty.openpty()
        fd = None
        errors = []
        payload = bytes(range(256)) * 4
        try:
            fd = reader.open_serial(os.ttyname(slave))

            def peer():
                try:
                    wire = packet(payload)
                    for offset in range(0, len(wire), 7):
                        chunk = wire[offset:offset + 7]
                        self.assertEqual(os.write(master, chunk), len(chunk))
                except BaseException as error:
                    errors.append(error)

            thread = threading.Thread(target=peer)
            thread.start()
            result = reader.receive_dump(reader.SerialReader(fd, 5, 1).read_exact,
                                         io.BytesIO(), expected_bytes=len(payload))
            thread.join(2)
            self.assertFalse(thread.is_alive())
            self.assertFalse(errors)
            self.assertEqual(result["bytes"], len(payload))
        finally:
            if fd is not None:
                reader.close_serial(fd)
            os.close(master)
            os.close(slave)

    def test_actual_pty_timeout(self):
        master, slave = pty.openpty()
        fd = None
        try:
            fd = reader.open_serial(os.ttyname(slave))
            with self.assertRaises(TimeoutError):
                reader.SerialReader(fd, 1, 0.02).read_exact(1)
        finally:
            if fd is not None:
                reader.close_serial(fd)
            os.close(master)
            os.close(slave)


if __name__ == "__main__":
    unittest.main(verbosity=2)
