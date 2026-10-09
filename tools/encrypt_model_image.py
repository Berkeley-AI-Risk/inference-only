#!/usr/bin/env python3
"""Reproduce the fixed PUBLIC-TEST-KEY ciphertext offline using OpenSSL.

This command cannot provision keys or access an FPGA. Its key and nonce are
public constants, so its output is not secret from anyone with this package.
"""
import argparse
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

SIZE = 7_265_984
PLAIN_SHA = 'cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
CIPHER_SHA = '88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'
KEY = '000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f'
NONCE = '112233445566778899aabbcc'


def sha(raw): return hashlib.sha256(raw).hexdigest()
def require(ok, message):
    if not ok: raise ValueError(message)


def transform(raw, executable):
    require(len(raw) == SIZE, 'Incorrect fixed image length')
    # The low 32 bits count absolute 16-byte blocks from zero. This image is
    # far below counter wrap; OpenSSL's 128-bit increment therefore agrees.
    command = [str(executable),'enc','-aes-256-ctr','-K',KEY,'-iv',NONCE+'00000000','-nosalt']
    result = subprocess.run(command,input=raw,capture_output=True,timeout=120,check=True)
    require(len(result.stdout) == SIZE, 'OpenSSL returned a truncated image')
    return result.stdout


def reproduce(package, executable):
    package = Path(package)
    plain = (package/'assets/board1-real-semantic-image2048.bin').read_bytes()
    supplied = (package/'assets/board1-encrypted-model2048.bin').read_bytes()
    require(len(plain) == SIZE and sha(plain) == PLAIN_SHA, 'Wrong plaintext model')
    require(len(supplied) == SIZE and sha(supplied) == CIPHER_SHA, 'Wrong ciphertext model')
    ciphertext = transform(plain,executable)
    require(ciphertext == supplied and sha(ciphertext) == CIPHER_SHA, 'Encryption differs from the shipped image')
    require(transform(ciphertext,executable) == plain, 'Independent OpenSSL round trip differs')
    return ciphertext


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=Path(__file__).resolve().parents[1])
    parser.add_argument('--openssl',default=shutil.which('openssl'),help='Explicit OpenSSL executable if not on PATH')
    parser.add_argument('--output',type=Path,help='Optional new output file; existing files are refused')
    args = parser.parse_args()
    require(bool(args.openssl), 'OpenSSL was not found')
    ciphertext = reproduce(args.package,args.openssl)
    if args.output:
        with args.output.open('xb') as target: target.write(ciphertext)
    print(json.dumps(dict(passed=True,bytes=SIZE,plaintext_sha256=PLAIN_SHA,ciphertext_sha256=CIPHER_SHA,
        public_test_key=True,hardware_access=False,network_access=False),indent=2))


if __name__ == '__main__': main()
