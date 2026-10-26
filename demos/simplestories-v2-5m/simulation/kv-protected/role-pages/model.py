"""Functional reference for fixed 16-position, head/role-specific K/V tags.

Not cycle-accurate and not a public memory API. The unchanged parent guard
model supplies transfer ownership, sequential population and CLEAR draining.
"""
import hashlib
import importlib.util
from pathlib import Path
import struct

BASE_PATH = Path(__file__).resolve().parents[1] / 'kv_integrity_model.py'
BASE_SHA = '7bfc6552528c7e56cb03918b770264c63d20cd1db6021ccbb6f75ea9ec3e1151'
if hashlib.sha256(BASE_PATH.read_bytes()).hexdigest() != BASE_SHA:
    raise ValueError('Baseline ownership model changed; review before reuse')
spec = importlib.util.spec_from_file_location('role_baseline', BASE_PATH)
base = importlib.util.module_from_spec(spec)
import sys
sys.modules[spec.name] = base
spec.loader.exec_module(base)

PAGE_POSITIONS = 16
ROLE_WORDS = ((0, 1, 2, 3, 8), (4, 5, 6, 7, 8))
address, Memory, IntegrityFault, Busy = base.address, base.Memory, base.IntegrityFault, base.Busy
Transfer = base.Transfer
CONTEXT, KV_BASE, POSITION_WORDS, WORD_BYTES = 2048, 227072, 18, 32


def header(epoch, layer, page, head, role, positions):
    if not (0 <= epoch < 2**64 and 0 <= layer < 6 and 0 <= page < 128 and
            head in (0, 1) and role in (0, 1) and 1 <= positions <= 16):
        raise ValueError('Invalid fixed role-page identity')
    return struct.pack('>16sQIIIIIII12x', b'IO-KV-ROLE-v2', epoch, layer,
                       page, head, role, positions, PAGE_POSITIONS, 32)


def digest(epoch, layer, page, head, role, positions, payload):
    if len(payload) != positions * 5 * 32:
        raise ValueError('Wrong role-page payload length')
    return hashlib.sha256(header(epoch, layer, page, head, role, positions) + payload).digest()


def hash_blocks(positions):
    # Full 64-byte header, payload, 0x80 and eight-byte bit count.
    return (64 + positions * 5 * 32 + 9 + 63) // 64


class Guard(base.Guard):
    def __init__(self):
        super().__init__(page_positions=PAGE_POSITIONS)

    def complete(self, transfer, data=b'', error=False):
        if self.outstanding != transfer:
            self.fail('Unexpected, duplicate or reordered completion')
        self.outstanding = None
        if transfer.epoch != self.epoch:
            self.stats['discarded_old_completions'] += 1
            return
        self.live()
        if error:
            self.fail('DDR error')
        if transfer.write:
            p = self.population
            if p is None:
                self.fail('Write lost its population owner')
            p['acknowledged'] += 1
            if p['acknowledged'] == 18:
                layer, position = p['layer'], p['position']
                valid, page = position % 16 + 1, position // 16
                start = (valid - 1) * 576
                self.partial[layer][start:start + 576] = b''.join(p['words'])
                for head in range(2):
                    for role in range(2):
                        payload = b''.join(
                            self.partial[layer][(pos * 18 + head * 9 + word) * 32:
                                                (pos * 18 + head * 9 + word + 1) * 32]
                            for pos in range(valid) for word in ROLE_WORDS[role])
                        self.tags[layer, page, head, role] = digest(
                            self.epoch, layer, page, head, role, valid, payload)
                        self.stats['hash_blocks_write'] += hash_blocks(valid)
                self.prefix[layer] += 1
                self.population = None
            return
        if len(data) != 32:
            self.fail('Malformed read word')
        r = self.read
        if r is None:
            self.fail('Read lost its request owner')
        r['staging'].extend(data)
        if len(r['staging']) == r['valid'] * 5 * 32:
            sealed = bytes(r['staging'])
            actual = digest(self.epoch, r['layer'], r['page'], r['head'], r['role'], r['valid'], sealed)
            self.stats['hash_blocks_read'] += hash_blocks(r['valid'])
            if actual != self.tags[r['layer'], r['page'], r['head'], r['role']]:
                self.fail('Returned role page differs from internally populated data')
            self.cache = (self.epoch, r['layer'], r['page'], r['head'], r['role'], r['valid'], sealed)
            self.response = (self.epoch, sealed[r['offset']:r['offset'] + 32])
            self.read = None

    def begin_read(self, layer, position, head, word):
        self.idle()
        try:
            address(layer, position, head, word)
        except ValueError:
            self.fail('Illegal read coordinate')
        if position >= self.prefix[layer]:
            self.fail('Read outside persisted current-generation prefix')
        page, valid = position // 16, min(16, self.prefix[layer] - position // 16 * 16)
        role = int(4 <= word < 8)
        if (word == 8 and self.cache is not None and
                self.cache[:4] == (self.epoch, layer, page, head) and self.cache[5] == valid):
            role = self.cache[4]
        offset = (position % 16 * 5 + ROLE_WORDS[role].index(word)) * 32
        identity = (self.epoch, layer, page, head, role, valid)
        if self.cache is not None and self.cache[:6] == identity:
            self.stats['cache_hits'] += 1
            self.response = (self.epoch, self.cache[6][offset:offset + 32])
        else:
            self.stats['cache_misses'] += 1
            self.read = dict(layer=layer, page=page, head=head, role=role, valid=valid,
                             offset=offset, staging=bytearray())

    def issue_read(self):
        self.live()
        if self.outstanding is not None or self.read is None:
            raise Busy('No role-page fill or previous read is outstanding')
        r = self.read
        index = len(r['staging']) // 32
        position = r['page'] * 16 + index // 5
        self.serial += 1
        self.outstanding = base.Transfer(self.serial, self.epoch, False,
            address(r['layer'], position, r['head'], ROLE_WORDS[r['role']][index % 5]))
        self.stats['ddr_reads'] += 1
        return self.outstanding
