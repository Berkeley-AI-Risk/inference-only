#!/usr/bin/env python3
"""Executable specification of a PRIVATE K/V guard, not a host API or cycle model.

The unchanged atomic-K/V parent remains responsible for semantic commit and
pending-row bypass. This guard sits below it on its typed DDR channels. Its
prefix counts fully persisted rows, not the parent's committed positions.
"""
from dataclasses import dataclass
import hashlib
import struct

LAYERS, CONTEXT, HEADS, ROW_WORDS, WORD_BYTES = 6, 2048, 2, 9, 32
POSITION_WORDS = HEADS * ROW_WORDS
KV_BASE = 227072


class IntegrityFault(RuntimeError):
    pass


class Busy(RuntimeError):
    pass


@dataclass(frozen=True)
class Transfer:
    serial: int
    epoch: int
    write: bool
    address: int
    data: bytes = b''


def address(layer, position, head, word):
    if not (0 <= layer < LAYERS and 0 <= position < CONTEXT and
            0 <= head < HEADS and 0 <= word < ROW_WORDS):
        raise ValueError('Illegal private K/V coordinate')
    return KV_BASE + POSITION_WORDS * (layer * CONTEXT + position) + ROW_WORDS * head + word


def header(epoch, layer, page, positions, page_positions):
    # Exactly one 64-byte SHA block. Numeric fields use network byte order.
    # Domain, generation, geometry, identity and valid prefix are all bound.
    return struct.pack('>16sQIIIII20x', b'IO-KV-PAGE-v1\0\0\0', epoch,
                       layer, page, positions, page_positions, WORD_BYTES)


def page_digest(epoch, layer, page, positions, page_positions, data):
    if len(data) != positions * POSITION_WORDS * WORD_BYTES:
        raise ValueError('Wrong authenticated prefix length')
    return hashlib.sha256(header(epoch, layer, page, positions, page_positions) + data).digest()


class Memory:
    """Untrusted DDR fixture. Tests may replace, corrupt or defer its contents."""
    def __init__(self):
        self.data = bytearray(LAYERS * CONTEXT * POSITION_WORDS * WORD_BYTES)

    def perform(self, transfer):
        offset = (transfer.address - KV_BASE) * WORD_BYTES
        if not (0 <= offset <= len(self.data) - WORD_BYTES):
            raise ValueError('Outside K/V memory')
        if transfer.write:
            self.data[offset:offset + WORD_BYTES] = transfer.data
            return b''
        return bytes(self.data[offset:offset + WORD_BYTES])


class Guard:
    def __init__(self, page_positions=4):
        if page_positions not in (1, 2, 4, 8, 16):
            raise ValueError('Unsupported fixed geometry')
        self.page_positions = page_positions
        self.epoch = 0
        self.prefix = [0] * LAYERS
        self.partial = [bytearray(page_positions * POSITION_WORDS * WORD_BYTES) for _ in range(LAYERS)]
        self.tags = {}  # Represents unreset on-chip RAM; validity comes from prefix.
        self.cache = None  # Immutable verified on-chip bytes and their identity.
        self.population = None
        self.read = None
        self.response = None
        self.outstanding = None
        self.serial = 0
        self.fault = False
        self.stats = dict(ddr_reads=0, ddr_writes=0, hash_blocks_read=0,
                          hash_blocks_write=0, cache_hits=0, cache_misses=0,
                          discarded_old_completions=0, released_words=0)

    def fail(self, reason):
        self.fault = True
        self.cache = self.response = None
        raise IntegrityFault(reason)

    def live(self):
        if self.fault:
            raise IntegrityFault('Terminal fault; CLEAR does not recover it')

    def idle(self):
        self.live()
        if any(x is not None for x in (self.population, self.read, self.response, self.outstanding)):
            raise Busy('Prior operation or CLEAR drain still owns the channel')

    def clear(self):
        # Retain one already issued transfer until drained. It cannot complete
        # a new operation because new work is barred while it is outstanding.
        if self.epoch == (1 << 64) - 1:
            self.fail('Generation exhausted')
        self.epoch += 1
        self.prefix = [0] * LAYERS
        self.cache = self.population = self.read = self.response = None

    def start_population(self, layer, position):
        self.idle()
        if not (0 <= layer < LAYERS and 0 <= position < CONTEXT and position == self.prefix[layer]):
            self.fail('Nonsequential or out-of-range population')
        self.cache = None
        self.population = dict(layer=layer, position=position, words=[], acknowledged=0)

    def issue_write(self, head, word, data):
        self.live()
        p = self.population
        if p is None or self.outstanding is not None:
            raise Busy('No population or previous write is outstanding')
        if (head * ROW_WORDS + word != len(p['words']) or not 0 <= head < HEADS or
                not 0 <= word < ROW_WORDS or len(data) != WORD_BYTES):
            self.fail('Misordered or malformed population word')
        p['words'].append(bytes(data))
        self.serial += 1
        self.outstanding = Transfer(self.serial, self.epoch, True,
                                    address(p['layer'], p['position'], head, word), bytes(data))
        self.stats['ddr_writes'] += 1
        return self.outstanding

    def complete(self, transfer, data=b'', error=False):
        if self.outstanding != transfer:
            self.fail('Unexpected, duplicate or reordered completion')
        self.outstanding = None
        if transfer.epoch != self.epoch:
            self.stats['discarded_old_completions'] += 1
            return  # An old transfer is drained, never reinterpreted.
        self.live()
        if error:
            self.fail('DDR error')
        if transfer.write:
            p = self.population
            if p is None:
                self.fail('Write lost its population owner')
            p['acknowledged'] += 1
            if p['acknowledged'] == POSITION_WORDS:
                layer, position = p['layer'], p['position']
                offset = position % self.page_positions
                start = offset * POSITION_WORDS * WORD_BYTES
                self.partial[layer][start:start + POSITION_WORDS * WORD_BYTES] = b''.join(p['words'])
                valid = offset + 1
                payload = bytes(self.partial[layer][:valid * POSITION_WORDS * WORD_BYTES])
                self.tags[layer, position // self.page_positions] = page_digest(
                    self.epoch, layer, position // self.page_positions, valid, self.page_positions, payload)
                # RTL must delay the final write completion until this digest
                # is stored. This model is functional, not cycle accurate.
                self.stats['hash_blocks_write'] += 2 + 9 * valid
                self.prefix[layer] += 1
                self.population = None
            return
        if len(data) != WORD_BYTES:
            self.fail('Malformed read word')
        r = self.read
        if r is None:
            self.fail('Read lost its request owner')
        r['staging'].extend(data)
        if len(r['staging']) == r['valid'] * POSITION_WORDS * WORD_BYTES:
            sealed = bytes(r['staging'])
            actual = page_digest(self.epoch, r['layer'], r['page'], r['valid'], self.page_positions, sealed)
            self.stats['hash_blocks_read'] += 2 + 9 * r['valid']
            if actual != self.tags[r['layer'], r['page']]:
                self.fail('Returned page differs from internally populated data')
            self.cache = (self.epoch, r['layer'], r['page'], r['valid'], sealed)
            self.response = (self.epoch, sealed[r['offset']:r['offset'] + WORD_BYTES])
            self.read = None

    def begin_read(self, layer, position, head, word):
        self.idle()
        try:
            address(layer, position, head, word)
        except ValueError:
            self.fail('Illegal read coordinate')
        if position >= self.prefix[layer]:
            self.fail('Read outside persisted current-generation prefix')
        page = position // self.page_positions
        valid = min(self.page_positions, self.prefix[layer] - page * self.page_positions)
        offset = ((position % self.page_positions) * POSITION_WORDS + head * ROW_WORDS + word) * WORD_BYTES
        identity = (self.epoch, layer, page, valid)
        if self.cache is not None and self.cache[:4] == identity:
            self.stats['cache_hits'] += 1
            self.response = (self.epoch, self.cache[4][offset:offset + WORD_BYTES])
        else:
            self.stats['cache_misses'] += 1
            self.read = dict(layer=layer, page=page, valid=valid, offset=offset, staging=bytearray())

    def issue_read(self):
        self.live()
        if self.outstanding is not None or self.read is None:
            raise Busy('No page fill or previous read is outstanding')
        r = self.read
        index = len(r['staging']) // WORD_BYTES
        position = r['page'] * self.page_positions + index // POSITION_WORDS
        row_index = index % POSITION_WORDS
        self.serial += 1
        self.outstanding = Transfer(self.serial, self.epoch, False,
                                    address(r['layer'], position, row_index // ROW_WORDS, row_index % ROW_WORDS))
        self.stats['ddr_reads'] += 1
        return self.outstanding

    def take_response(self):
        self.live()
        if self.response is None:
            return None
        epoch, data = self.response
        self.response = None
        if epoch != self.epoch:
            self.fail('Stale held response')
        self.stats['released_words'] += 1
        return data

    def populate(self, memory, layer, position, payload):
        if len(payload) != POSITION_WORDS * WORD_BYTES:
            raise ValueError('Wrong token-position payload size')
        self.start_population(layer, position)
        for i in range(POSITION_WORDS):
            transfer = self.issue_write(i // ROW_WORDS, i % ROW_WORDS,
                                        payload[i * WORD_BYTES:(i + 1) * WORD_BYTES])
            self.complete(transfer, memory.perform(transfer))

    def read_word(self, memory, layer, position, head, word):
        self.begin_read(layer, position, head, word)
        while self.read is not None:
            transfer = self.issue_read()
            self.complete(transfer, memory.perform(transfer))
        return self.take_response()
