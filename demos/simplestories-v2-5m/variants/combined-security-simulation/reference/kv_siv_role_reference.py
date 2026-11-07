"""Fixed 130-byte K/V-role codec, software reference only.

Map each logical five-word role (including its shared two-exponent tail)
to five encrypted physical words. Two roles use ten physical words.
"""
import hashlib
from pathlib import Path
import struct

from kv_siv_reference import OpenSSL, MODEL_ID, PUBLIC_TEST_KEY, AuthenticationError, encrypt, decrypt

PARENT_SHA = '03dd85d5830f097785014ba19334404f37a6c1117338f88cad884ebb9cb338c5'
if hashlib.sha256(Path(__file__).with_name('kv_siv_reference.py').read_bytes()).hexdigest() != PARENT_SHA:
    raise ValueError('Checked RFC5297 reference changed; review before reuse')
DOMAIN = b'IO-KV-ROLE-SIV1'.ljust(16, b'\0')
KV_BASE_WORD = 227072
PLAIN_BYTES, RECORD_BYTES = 130, 160
ROLE_WORDS = ((0, 1, 2, 3, 8), (4, 5, 6, 7, 8))


def context(epoch, layer, position, head, role, model_id=MODEL_ID):
    if not (0 <= epoch < 2**64 and 0 <= layer < 6 and 0 <= position < 2048
            and head in (0, 1) and role in (0, 1) and len(model_id) == 32):
        raise ValueError('Invalid fixed role identity')
    return [DOMAIN, model_id, struct.pack('>QBBBBHH', epoch, layer, head, role, 0, position, PLAIN_BYTES)]


def physical_address(layer, position, head, role, slot):
    context(0, layer, position, head, role)
    if not 0 <= slot < 5:
        raise ValueError('Invalid role slot')
    return KV_BASE_WORD + 20*(layer*2048 + position) + 10*head + 5*role + slot


def role_plaintext(row, role):
    if len(row) != 288 or any(row[258:]) or role not in (0, 1):
        raise ValueError('Noncanonical logical nine-word K/V row')
    return row[role*128:(role+1)*128] + row[256:258]


def seal_role(aes, key, associated, logical_five_words):
    if len(key) != 64 or len(logical_five_words) != 160 or any(logical_five_words[130:]):
        raise ValueError('Expected fixed role and AES256-SIV key pair')
    tag, cipher = encrypt(aes, key, associated, logical_five_words[:130])
    return cipher + tag + bytes(14)


def open_role(aes, key, associated, record):
    if len(key) != 64 or len(record) != 160 or any(record[146:]):
        raise AuthenticationError('Wrong encrypted role geometry/padding')
    plain = decrypt(aes, key, associated, record[130:146], record[:130])
    return plain + bytes(30)


def logical_five_words(row, role):
    return role_plaintext(row, role) + bytes(30)
