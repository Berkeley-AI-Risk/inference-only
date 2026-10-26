"""Exact integer numerical reference for the fixed finite CDF sampler.

No hardware access. Reads the same immutable Q30 table as RTL rather than
recomputing exponentials in host floating point. The UART accepts neither these
rows nor host probabilities: this reference is for offline inspection/tests.
"""
from functools import lru_cache
import hashlib
from pathlib import Path

MASK = (1 << 64) - 1
ROWS = 4019
TEMPERATURE = {1: 0.5, 2: 1.0, 3: 2.0}
TABLE = Path(__file__).resolve().parents[1] / 'hardware/project/model_rtl_evidence/attention_sublayer/exp_neg_q30.memh'
TABLE_SHA256 = 'c3e491c6abcd545f73dce0fabb37f86d2eed31a0334268da1e035a75f4c62a3f'


def unsigned(value, bits, name):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < 1 << bits:
        raise ValueError(name + ' outside unsigned' + str(bits))
    return value


def rotl(value, count):
    return ((value << count) | (value >> (64 - count))) & MASK


def initial_state(seed):
    unsigned(seed, 128, 'seed')
    return (seed & MASK, seed >> 64) if seed else (1, 0)


def draw(state):
    if len(state) != 2:
        raise ValueError('two unsigned64 state words required')
    lo, hi = state
    unsigned(lo, 64, 'state low')
    unsigned(hi, 64, 'state high')
    if lo == hi == 0:
        raise ValueError('all-zero PRNG state is forbidden')
    result = (rotl((lo + hi) & MASK, 17) + lo) & MASK
    hi ^= lo
    return result, (rotl(lo, 49) ^ hi ^ ((hi << 21) & MASK), rotl(hi, 28))


@lru_cache(maxsize=1)
def exponential_table():
    data = TABLE.read_bytes()
    if hashlib.sha256(data).hexdigest() != TABLE_SHA256:
        raise ValueError('immutable exponential table changed')
    table = tuple(int(line, 16) for line in data.decode('ascii').splitlines())
    if len(table) != 4097 or table[0] != 1 << 30:
        raise ValueError('unexpected fixed table format')
    return table


def aligned_rows(rows):
    if len(rows) != ROWS:
        raise ValueError('fixed vocabulary required')
    common = rows[0][1] - 2
    values = []
    for raw, exponent in rows:
        if isinstance(raw, bool) or not isinstance(raw, int) or not -(1 << 49) <= raw < (1 << 49):
            raise ValueError('raw logit exceeds signed50')
        if (isinstance(exponent, bool) or not isinstance(exponent, int)
                or not -128 <= exponent <= 127 or exponent - common not in (0, 1, 2)):
            raise ValueError('illegal exponent schedule')
        values.append(raw << (exponent - common))
    return values, common


def weights(rows, temperature):
    if isinstance(temperature, bool) or temperature not in TEMPERATURE:
        raise ValueError('positive temperature code required')
    values, common = aligned_rows(rows)
    shift = common + 8 + {1: 1, 2: 0, 3: -1}[temperature]
    maximum = max(values)
    table = exponential_table()
    mass = []
    for value in values:
        gap = maximum - value
        index = gap << shift if shift >= 0 else gap >> -shift
        mass.append(table[index] if index < 4096 else 0)
    return mass


def select_mass(mass, random):
    unsigned(random, 64, 'random word')
    if (not mass or len(mass) > ROWS or
            any(isinstance(value, bool) or not isinstance(value, int)
                or not 0 <= value <= 1 << 30 for value in mass)):
        raise ValueError('bounded nonnegative Q30 masses required')
    total = sum(mass)
    if total == 0:
        raise ValueError('positive total mass required')
    target = (random * total) >> 64
    cumulative = 0
    for index, value in enumerate(mass):
        cumulative += value
        if cumulative > target:
            return index
    raise ArithmeticError('CDF target escaped positive bounded mass')


def sample(rows, temperature, state):
    if isinstance(temperature, bool) or temperature not in (0, 1, 2, 3):
        raise ValueError('supported temperature code required')
    if temperature == 0:
        values, _ = aligned_rows(rows)
        return max(range(ROWS), key=values.__getitem__), state
    mass = weights(rows, temperature)
    random, next_state = draw(state)
    return select_mass(mass, random), next_state
