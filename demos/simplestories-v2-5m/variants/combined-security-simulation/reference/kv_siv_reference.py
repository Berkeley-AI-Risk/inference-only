"""Software reference for RFC5297 deterministic AES-SIV K/V rows.

Not production cryptographic code, RTL, a provisioning utility, or a host API.
Uses installed OpenSSL AES-ECB for the block primitive; the independent oracle
uses OpenSSL's complete native AES-SIV implementation, not this composition.
All repository tests use explicitly public keys. No nonce or RNG is assumed.
"""
import ctypes as C
import ctypes.util
import hmac
from pathlib import Path
import struct

LIBCRYPTO = C.util.find_library('crypto')
if not LIBCRYPTO: raise RuntimeError('OpenSSL 3 libcrypto was not found')
DOMAIN = b'IO-KV-ROW-SIV-v1'
MODEL_ID = bytes.fromhex('cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0')
PUBLIC_TEST_KEY = bytes(range(0x40, 0x80))
PLAIN_BYTES, RECORD_BYTES = 258, 288


class AuthenticationError(ValueError):
    pass


class OpenSSL:
    """Minimal explicit EVP binding. Failed decryptions never return plaintext."""
    def __init__(self):
        self.lib = C.CDLL(str(LIBCRYPTO))
        ptr = C.c_void_p; integer = C.c_int; iptr = C.POINTER(integer)
        signatures = {
            'EVP_CIPHER_fetch': (ptr, [ptr, C.c_char_p, C.c_char_p]),
            'EVP_CIPHER_free': (None, [ptr]),
            'EVP_CIPHER_CTX_new': (ptr, []), 'EVP_CIPHER_CTX_free': (None, [ptr]),
            'EVP_CIPHER_CTX_set_padding': (integer, [ptr, integer]),
            'EVP_CIPHER_CTX_ctrl': (integer, [ptr, integer, integer, ptr]),
            'EVP_EncryptInit_ex2': (integer, [ptr, ptr, ptr, ptr, ptr]),
            'EVP_DecryptInit_ex2': (integer, [ptr, ptr, ptr, ptr, ptr]),
            'EVP_EncryptUpdate': (integer, [ptr, ptr, iptr, ptr, integer]),
            'EVP_DecryptUpdate': (integer, [ptr, ptr, iptr, ptr, integer]),
            'EVP_EncryptFinal_ex': (integer, [ptr, ptr, iptr]),
            'EVP_DecryptFinal_ex': (integer, [ptr, ptr, iptr]),
            'OpenSSL_version': (C.c_char_p, [integer]),
        }
        for name, (restype, argtypes) in signatures.items():
            func = getattr(self.lib, name); func.restype = restype; func.argtypes = argtypes
        self.version = self.lib.OpenSSL_version(0).decode()

    @staticmethod
    def checked(value):
        if value != 1:
            raise ValueError('OpenSSL EVP operation failed')

    def ecb(self, key, blocks):
        if len(key) not in (16, 24, 32) or len(blocks) % 16:
            raise ValueError('Invalid AES block/key geometry')
        cipher = self.lib.EVP_CIPHER_fetch(None, f'AES-{len(key)*8}-ECB'.encode(), None)
        ctx = self.lib.EVP_CIPHER_CTX_new()
        if not cipher or not ctx:
            raise ValueError('Installed OpenSSL AES unavailable')
        try:
            self.checked(self.lib.EVP_EncryptInit_ex2(ctx, cipher, key, None, None))
            self.checked(self.lib.EVP_CIPHER_CTX_set_padding(ctx, 0))
            out = C.create_string_buffer(len(blocks) + 32); used = C.c_int(); final = C.c_int()
            self.checked(self.lib.EVP_EncryptUpdate(ctx, out, C.byref(used), blocks, len(blocks)))
            self.checked(self.lib.EVP_EncryptFinal_ex(ctx, C.byref(out, used.value), C.byref(final)))
            if used.value + final.value != len(blocks):
                raise ValueError('Unexpected AES block length')
            return out.raw[:used.value + final.value]
        finally:
            self.lib.EVP_CIPHER_CTX_free(ctx); self.lib.EVP_CIPHER_free(cipher)

    def native_siv(self, key, associated, data, tag=None):
        if len(key) not in (32, 48, 64) or (tag is not None and len(tag) != 16):
            raise ValueError('Invalid SIV geometry')
        cipher = self.lib.EVP_CIPHER_fetch(None, f'AES-{len(key)*4}-SIV'.encode(), None)
        ctx = self.lib.EVP_CIPHER_CTX_new()
        if not cipher or not ctx:
            raise ValueError('Installed OpenSSL native AES-SIV unavailable')
        decrypt = tag is not None
        try:
            init = self.lib.EVP_DecryptInit_ex2 if decrypt else self.lib.EVP_EncryptInit_ex2
            update = self.lib.EVP_DecryptUpdate if decrypt else self.lib.EVP_EncryptUpdate
            finish = self.lib.EVP_DecryptFinal_ex if decrypt else self.lib.EVP_EncryptFinal_ex
            self.checked(init(ctx, cipher, key, None, None))
            if decrypt:
                self.checked(self.lib.EVP_CIPHER_CTX_ctrl(ctx, 0x11, 16, tag))
            used = C.c_int(); final = C.c_int()
            for item in associated:
                self.checked(update(ctx, None, C.byref(used), item, len(item)))
            out = C.create_string_buffer(len(data) + 32)
            ok = update(ctx, out, C.byref(used), data, len(data))
            if ok != 1:
                if decrypt:
                    raise AuthenticationError('Native SIV authentication failed')
                self.checked(ok)
            ok = finish(ctx, C.byref(out, used.value), C.byref(final))
            if ok != 1:
                if decrypt:
                    raise AuthenticationError('Native SIV authentication failed')
                self.checked(ok)
            result = out.raw[:used.value + final.value]
            if len(result) != len(data):
                raise ValueError('Unexpected native SIV output length')
            if decrypt:
                return result
            value = C.create_string_buffer(16)
            self.checked(self.lib.EVP_CIPHER_CTX_ctrl(ctx, 0x10, 16, value))
            return value.raw, result
        finally:
            self.lib.EVP_CIPHER_CTX_free(ctx); self.lib.EVP_CIPHER_free(cipher)


def xor(a, b):
    if len(a) != len(b):
        raise ValueError('XOR length mismatch')
    return bytes(x ^ y for x, y in zip(a, b))


def dbl(value):
    if len(value) != 16:
        raise ValueError('Wrong CMAC doubling size')
    integer = int.from_bytes(value, 'big')
    return (((integer << 1) & ((1 << 128) - 1)) ^ (0x87 if integer >> 127 else 0)).to_bytes(16, 'big')


def cmac(aes, key, data):
    k1 = dbl(aes.ecb(key, bytes(16))); k2 = dbl(k1)
    if data and len(data) % 16 == 0:
        prefix, last = data[:-16], xor(data[-16:], k1)
    else:
        amount = len(data) % 16
        prefix = data[:len(data)-amount] if amount else data
        tail = data[len(prefix):]
        last = xor(tail + b'\x80' + bytes(15-len(tail)), k2)
    state = bytes(16)
    for offset in range(0, len(prefix), 16):
        state = aes.ecb(key, xor(state, prefix[offset:offset+16]))
    return aes.ecb(key, xor(state, last))


def s2v(aes, key, strings):
    if len(strings) > 127:
        raise ValueError('RFC5297 S2V component limit exceeded')
    if not strings:
        return cmac(aes, key, bytes(15) + b'\x01')
    state = cmac(aes, key, bytes(16))
    for item in strings[:-1]:
        state = xor(dbl(state), cmac(aes, key, item))
    final = strings[-1]
    if len(final) >= 16:
        final = final[:-16] + xor(final[-16:], state)
    else:
        final = xor(dbl(state), final + b'\x80' + bytes(15-len(final)))
    return cmac(aes, key, final)


def ctr(aes, key, tag, data):
    # RFC5297 section2.5: clear bits31 and63 counting from the right.
    counter = int.from_bytes(tag, 'big') & ~((1 << 31) | (1 << 63))
    blocks = (len(data) + 15) // 16
    if blocks >= 2**31:
        raise ValueError('Fixture message exceeds supported counter range')
    stream = aes.ecb(key, b''.join((counter+i).to_bytes(16, 'big') for i in range(blocks)))
    return xor(data, stream[:len(data)])


def encrypt(aes, key, associated, plaintext):
    if len(key) not in (32, 48, 64) or len(associated) > 126:
        raise ValueError('Invalid RFC5297 key/component count')
    split = len(key) // 2
    tag = s2v(aes, key[:split], list(associated) + [plaintext])
    return tag, ctr(aes, key[split:], tag, plaintext)


def decrypt(aes, key, associated, tag, ciphertext):
    if len(key) not in (32, 48, 64) or len(tag) != 16 or len(associated) > 126:
        raise ValueError('Invalid RFC5297 key/tag/component count')
    split = len(key) // 2
    plaintext = ctr(aes, key[split:], tag, ciphertext)
    expected = s2v(aes, key[:split], list(associated) + [plaintext])
    if not hmac.compare_digest(tag, expected):
        raise AuthenticationError('Reference SIV authentication failed')
    return plaintext


def context(epoch, layer, position, head, model_id=MODEL_ID):
    if not (0 <= epoch < 2**64 and 0 <= layer < 6 and 0 <= position < 2048 and head in (0, 1)):
        raise ValueError('Invalid fixed K/V identity')
    if len(model_id) != 32:
        raise ValueError('Model identity must be SHA256')
    return [DOMAIN, model_id, struct.pack('>QBBHHH', epoch, layer, head, position, PLAIN_BYTES, 1)]


def seal_row(aes, key, associated, row):
    if len(key) != 64 or len(row) != RECORD_BYTES or any(row[PLAIN_BYTES:]):
        raise ValueError('Expected nine canonical plaintext words and AES256-SIV key pair')
    tag, ciphertext = encrypt(aes, key, associated, row[:PLAIN_BYTES])
    return ciphertext + tag + bytes(RECORD_BYTES-PLAIN_BYTES-16)


def open_row(aes, key, associated, record):
    if len(key) != 64 or len(record) != RECORD_BYTES or any(record[PLAIN_BYTES+16:]):
        raise AuthenticationError('Wrong encrypted row shape/padding')
    plaintext = decrypt(aes, key, associated, record[PLAIN_BYTES:PLAIN_BYTES+16], record[:PLAIN_BYTES])
    return plaintext + bytes(RECORD_BYTES-PLAIN_BYTES)
