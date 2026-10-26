#!/usr/bin/env python3
"""Download only the exact, already selected model's 86 KiB tokenizer JSON."""
import hashlib
from pathlib import Path
from urllib.request import Request, urlopen

URL = 'https://huggingface.co/SimpleStories/SimpleStories-V2-5M/resolve/c4b3a4bb81297f5316697098e1d4b65c1249daf8/tokenizer.json'
SHA256 = '01b6553da99789d461cec48eed624684a803f259a5177616a67f7391700acf51'
target = Path(__file__).resolve().parent / 'assets/tokenizer.json'
if target.exists():
    assert target.is_file() and not target.is_symlink()
    data = target.read_bytes()
else:
    with urlopen(Request(URL, headers={'User-Agent':'fixed-fpga-tokenizer/1'}), timeout=30) as response:
        data = response.read(86464)
assert len(data) == 86463 and hashlib.sha256(data).hexdigest() == SHA256
if not target.exists():
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open('xb') as out: out.write(data)
print('Pinned tokenizer verified; no model weights downloaded or executed.')
