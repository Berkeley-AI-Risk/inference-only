#!/usr/bin/env python3
"""Fault injection and lifecycle tests for the private guard specification."""
import hashlib
from pathlib import Path
import struct
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from kv_integrity_model import (Guard, Memory, Transfer, Busy, IntegrityFault,
                                CONTEXT, KV_BASE, POSITION_WORDS, WORD_BYTES, address, header)


def payload(layer=0, position=0, salt=0):
    # Legal int16 coordinates, exponents zero, unused row tail zero.
    rows = []
    for head in range(2):
        values = [((layer * 391 + position * 17 + head * 991 + i + salt) % 65535) - 32767
                  for i in range(128)]
        rows.append(struct.pack('<128h', *values) + bytes(32))
    return b''.join(rows)


class GuardTests(unittest.TestCase):
    def setUp(self):
        self.guard, self.memory = Guard(), Memory()

    def put(self, n=5, layer=0, salt=0):
        for p in range(n):
            self.guard.populate(self.memory, layer, p, payload(layer, p, salt))

    def test_hash_header_shape(self):
        h = header(1, 2, 3, 4, 4)
        self.assertEqual(len(h), 64)
        self.assertNotEqual(h, header(2, 2, 3, 4, 4))
        self.assertNotEqual(h, header(1, 3, 3, 4, 4))
        self.assertNotEqual(h, header(1, 2, 4, 4, 4))
        self.assertNotEqual(h, header(1, 2, 3, 3, 4))

    def test_exact_words_all_layers_partial_and_full_pages(self):
        for layer in range(6):
            self.put(9, layer)
            for position in range(9):
                for head in range(2):
                    for word in range(9):
                        start = (head * 9 + word) * 32
                        self.assertEqual(self.guard.read_word(self.memory, layer, position, head, word),
                                         payload(layer, position)[start:start + 32])

    def test_all_page_sizes_and_last_context_slot(self):
        for size in (1, 2, 4, 8, 16):
            guard, memory = Guard(size), Memory()
            for position in range(CONTEXT):
                guard.populate(memory, 5, position, payload(5, position))
            self.assertEqual(guard.prefix[5], CONTEXT)
            for p in (0, 1, size - 1, size, 1023, 2047):
                self.assertEqual(guard.read_word(memory, 5, p, 1, 8), bytes(32))
            with self.assertRaises(IntegrityFault):
                guard.start_population(5, 2048)

    def test_every_bit_in_returned_word_is_detected(self):
        for bit in range(256):
            guard, memory = Guard(), Memory()
            guard.populate(memory, 0, 0, payload())
            memory.data[bit // 8] ^= 1 << (bit % 8)
            with self.assertRaises(IntegrityFault):
                guard.read_word(memory, 0, 0, 0, 0)
            self.assertEqual(guard.stats['released_words'], 0)

    def test_corruption_any_word_of_full_page(self):
        for word in range(72):
            guard, memory = Guard(), Memory()
            for p in range(4):
                guard.populate(memory, 0, p, payload(0, p))
            memory.data[word * 32] ^= 1
            with self.assertRaises(IntegrityFault):
                guard.read_word(memory, 0, 0, 0, 0)
            self.assertEqual(guard.stats['released_words'], 0)

    def test_no_release_before_last_word_and_digest(self):
        self.put(4)
        self.guard.begin_read(0, 0, 0, 0)
        for i in range(72):
            self.assertIsNone(self.guard.take_response())
            t = self.guard.issue_read()
            self.guard.complete(t, self.memory.perform(t))
            if i < 71:
                self.assertIsNone(self.guard.cache)
        self.assertEqual(self.guard.take_response(), payload()[:32])

    def test_replayed_older_partial_page_rejected(self):
        self.put(1)
        old = bytes(self.memory.data[:2304])
        self.guard.populate(self.memory, 0, 1, payload(0, 1))
        self.memory.data[:2304] = old
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_replayed_previous_clear_generation_rejected(self):
        self.put(4)
        old = bytes(self.memory.data[:2304])
        self.guard.clear()
        self.put(4, salt=7)
        self.memory.data[:2304] = old
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_clear_invalidates_unwritten_prefix(self):
        self.put(4)
        self.guard.clear()
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_swapped_pages_rejected(self):
        self.put(8)
        self.memory.data[:2304] = self.memory.data[2304:4608]
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_swapped_layers_rejected(self):
        self.put(4, layer=0)
        self.put(4, layer=1)
        start = (address(1, 0, 0, 0) - KV_BASE) * 32
        self.memory.data[:2304] = self.memory.data[start:start + 2304]
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_trusted_tag_cannot_be_derived_from_old_ddr(self):
        self.put(1)
        self.memory.data[0] ^= 1
        # Adding the next position hashes the earlier trusted on-chip bytes,
        # not a corrupted DDR reread.
        self.guard.populate(self.memory, 0, 1, payload(0, 1))
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_tamper_after_check_does_not_change_sealed_response(self):
        self.put(1)
        good = self.guard.read_word(self.memory, 0, 0, 0, 0)
        self.memory.data[0] ^= 1
        self.assertEqual(self.guard.read_word(self.memory, 0, 0, 0, 0), good)
        self.guard.cache = None  # Test-only forced eviction, not a device input.
        with self.assertRaises(IntegrityFault):
            self.guard.read_word(self.memory, 0, 0, 0, 0)

    def test_page_growth_invalidates_cache(self):
        self.put(1)
        self.guard.read_word(self.memory, 0, 0, 0, 0)
        self.guard.populate(self.memory, 0, 1, payload(0, 1))
        self.assertIsNone(self.guard.cache)
        self.assertEqual(self.guard.read_word(self.memory, 0, 1, 0, 0), payload(0, 1)[:32])

    def test_clear_during_each_read_word_drains_before_reuse(self):
        for at in range(72):
            guard, memory = Guard(), Memory()
            for p in range(4):
                guard.populate(memory, 0, p, payload(0, p))
            guard.begin_read(0, 0, 0, 0)
            for i in range(at):
                t = guard.issue_read()
                guard.complete(t, memory.perform(t))
            t = guard.issue_read()
            guard.clear()
            with self.assertRaises(Busy):
                guard.start_population(0, 0)
            guard.complete(t, memory.perform(t))
            self.assertIsNone(guard.take_response())
            guard.populate(memory, 0, 0, payload(salt=3))
            self.assertEqual(guard.read_word(memory, 0, 0, 0, 0), payload(salt=3)[:32])

    def test_clear_during_each_write_ack_drains_before_reuse(self):
        for at in range(18):
            guard, memory = Guard(), Memory()
            guard.start_population(0, 0)
            for i in range(at + 1):
                t = guard.issue_write(i // 9, i % 9, payload()[i * 32:(i + 1) * 32])
                if i != at:
                    guard.complete(t, memory.perform(t))
            guard.clear()
            with self.assertRaises(Busy):
                guard.start_population(0, 0)
            guard.complete(t, memory.perform(t))
            self.assertEqual(guard.prefix, [0] * 6)
            guard.populate(memory, 0, 0, payload(salt=4))
            self.assertEqual(guard.read_word(memory, 0, 0, 0, 0), payload(salt=4)[:32])

    def test_clear_revokes_held_response(self):
        self.put(1)
        self.guard.begin_read(0, 0, 0, 0)
        while self.guard.read is not None:
            t = self.guard.issue_read()
            self.guard.complete(t, self.memory.perform(t))
        self.guard.clear()
        self.assertIsNone(self.guard.take_response())

    def test_duplicate_response_faults(self):
        self.put(1)
        self.guard.begin_read(0, 0, 0, 0)
        t = self.guard.issue_read()
        data = self.memory.perform(t)
        self.guard.complete(t, data)
        with self.assertRaises(IntegrityFault):
            self.guard.complete(t, data)

    def test_wrong_response_owner_faults(self):
        self.put(1)
        self.guard.begin_read(0, 0, 0, 0)
        t = self.guard.issue_read()
        with self.assertRaises(IntegrityFault):
            self.guard.complete(Transfer(t.serial + 1, t.epoch, False, t.address), bytes(32))

    def test_stale_transfer_cannot_complete_new_request(self):
        self.put(1)
        self.guard.begin_read(0, 0, 0, 0)
        old = self.guard.issue_read()
        self.guard.clear()
        self.guard.complete(old, self.memory.perform(old))
        self.put(1, salt=8)
        self.guard.begin_read(0, 0, 0, 0)
        self.guard.issue_read()
        with self.assertRaises(IntegrityFault):
            self.guard.complete(old, bytes(32))

    def test_ddr_error_and_fault_stickiness(self):
        self.put(1)
        self.guard.begin_read(0, 0, 0, 0)
        t = self.guard.issue_read()
        with self.assertRaises(IntegrityFault):
            self.guard.complete(t, bytes(32), error=True)
        self.guard.clear()
        with self.assertRaises(IntegrityFault):
            self.guard.start_population(0, 0)

    def test_misordered_population_faults(self):
        self.guard.start_population(0, 0)
        with self.assertRaises(IntegrityFault):
            self.guard.issue_write(0, 1, bytes(32))

    def test_partial_population_not_readable(self):
        self.guard.start_population(0, 0)
        t = self.guard.issue_write(0, 0, bytes(32))
        self.guard.complete(t, self.memory.perform(t))
        with self.assertRaises(Busy):
            self.guard.begin_read(0, 0, 0, 0)
        self.assertEqual(self.guard.prefix[0], 0)

    def test_generation_wrap_fails_closed(self):
        self.guard.epoch = (1 << 64) - 1
        with self.assertRaises(IntegrityFault):
            self.guard.clear()


if __name__ == '__main__':
    unittest.main(verbosity=2)
