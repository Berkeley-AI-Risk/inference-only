"""Bounded SETTINGS/legacy packet codec. No device access."""
from dataclasses import dataclass
import secrets

VOCABULARY = 4019
TEMPERATURE_CODES = {'0': 0, '0.5': 1, '1': 2, '2': 3}


def crc8(data):
    remainder = 0
    for byte in data:
        remainder ^= byte
        for _ in range(8):
            remainder = ((remainder << 1) ^ 0x07) & 255 if remainder & 128 else (remainder << 1) & 255
    return remainder


def checked_integer(value, upper, name):
    if isinstance(value, bool) or not isinstance(value, int) or not 0 <= value < upper:
        raise ValueError(name + ' outside fixed supported domain')
    return value


def temperature_code(text):
    try:
        return TEMPERATURE_CODES[text]
    except (KeyError, TypeError):
        raise ValueError('temperature must be exactly 0, 0.5, 1 or 2')


def choose_seed(value=None):
    return secrets.randbits(128) if value is None else checked_integer(value, 1 << 128, 'seed')


def encode_settings(code, seed):
    checked_integer(code, 4, 'temperature code')
    checked_integer(seed, 1 << 128, 'seed')
    body = bytes((0xa5, 3, code)) + seed.to_bytes(16, 'little')
    return body + bytes((crc8(body),))


def encode_legacy(opcode, token=0):
    checked_integer(opcode, 3, 'legacy opcode')
    checked_integer(token, VOCABULARY, 'token')
    if opcode != 0 and token != 0:
        raise ValueError('STEP/CLEAR require zero operand')
    body = bytes((0xa5, opcode, token & 255, token >> 8))
    return body + bytes((crc8(body),))


@dataclass(frozen=True)
class Response:
    kind: int
    operand: int


def decode_response(packet):
    if not isinstance(packet, bytes) or len(packet) != 5:
        raise ValueError('one complete five-byte response required')
    if packet[0] != 0x5a or packet[3] & 0xf0 or crc8(packet[:-1]) != packet[-1]:
        raise ValueError('malformed response or bad CRC')
    kind = packet[1]
    operand = packet[2] | (packet[3] << 8)
    if kind == 0x81:
        if operand >= VOCABULARY:
            raise ValueError('token outside vocabulary')
    elif kind == 0x83:
        if operand > 3:
            raise ValueError('unsupported acknowledged temperature')
    elif kind in (0x80, 0x82, 0xc0, 0xc1, 0xc2, 0xc3, 0xcf):
        if operand != 0:
            raise ValueError('unexpected acknowledgement/rejection operand')
    else:
        raise ValueError('unknown response kind')
    return Response(kind, operand)
