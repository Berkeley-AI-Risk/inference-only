"""Exhaustive finite validation of native fixed digest and metadata ROM bytes.

This is a complete check of every constant page/row, not an unbounded RTL
selection theorem. The actual RTL index/assembly and consumer paths require
their separate formal proofs.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent


def sha(raw):return hashlib.sha256(raw).hexdigest()


def read_words(raw,width):
    words=raw.decode('ascii').split()
    if any(not re.fullmatch('[0-9a-fA-F]{'+str(width//4)+'}',w)for w in words):
        raise ValueError('Unexpected ROM constant syntax')
    return [int(w,16)for w in words]


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    args=p.parse_args()
    spec=importlib.util.spec_from_file_location('_constant_binding',HERE.parent/'formal-assurance/run_handoff.py')
    common=importlib.util.module_from_spec(spec);spec.loader.exec_module(common)
    package=common.model_package(args.package)
    plain=(package/'assets/board1-real-semantic-image2048.bin').read_bytes()
    cipher=(package/'assets/board1-encrypted-model2048.bin').read_bytes()
    if len(plain)!=227062*32 or len(cipher)!=len(plain):raise ValueError('Native image length changed')
    pages=(len(plain)+4095)//4096
    digests=[hashlib.sha256(plain[i*4096:(i+1)*4096].ljust(4096,b'\0')).digest()for i in range(pages)]
    # Each stored 192-bit row expands to eight 32-bit numerical metadata lanes.
    rows=[]
    for row in range(2328):
        word=plain[(211920+row)*32:(211921+row)*32]
        lanes=[int.from_bytes(word[lane*4:lane*4+4],'little')for lane in range(8)]
        if any(v>=1<<24 for v in lanes):raise ValueError('Fixed metadata is not zero-extended 24-bit lanes')
        rows.append(sum(v<<(24*lane)for lane,v in enumerate(lanes)))
    joins={}
    auth_path='project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv'
    for variant in('baseline','seeded-sampling','kv-protected','encrypted-memory'):
        _,directory,binding=common.binding(args.package,variant)
        rom=(directory/'project/digests32.memh').read_bytes();table=read_words(rom,32)
        if len(table)!=pages*8:raise ValueError('Digest ROM length differs from native page count')
        actual=[b''.join(v.to_bytes(4,'big')for v in table[i*8:i*8+8])for i in range(pages)]
        if actual!=digests:raise ValueError('A fixed page digest differs from the exact zero-tailed image')
        metadata=(directory/'project/metadata192.memh').read_bytes()
        if read_words(metadata,192)!=rows:raise ValueError('A metadata ROM row differs from the fixed image')
        split={}
        for name,expected in(('first192.memh',rows[:2048]),('last192.memh',rows[2048:])):
            path=directory/'project'/name
            if path.is_file():
                raw=path.read_bytes()
                if read_words(raw,192)!=expected:raise ValueError('Split metadata ROM differs from the fixed image')
                split[name]=sha(raw)
        auth=(directory/auth_path).read_text()
        expected=sha(cipher if variant=='encrypted-memory'else plain)
        if "256'h"+expected not in auth:raise ValueError('Native boot policy digest differs from the fixed asset')
        joins[variant]=dict(image_sha256=binding['image_sha256'],boot_expected_asset_sha256=expected,
            digest_rom_sha256=sha(rom),all_pages_checked=pages,metadata_rom_sha256=sha(metadata),
            all_metadata_rows_checked=len(rows),split_metadata_rom_sha256=split,
            service_source_sha256=binding['distributed_inputs']['project/service.sv'])
    out=dict(schema='exhaustive-fixed-native-digest-and-metadata-rom-validation-v1',passed=True,
        plaintext_bytes=len(plain),plaintext_sha256=sha(plain),ciphertext_sha256=sha(cipher),
        pages=pages,last_page_valid_words=118,last_page_zero_tail_bytes=320,
        metadata_rows=len(rows),metadata_lanes=len(rows)*8,native_joins=joins,
        checker_sha256=sha(Path(__file__).read_bytes()),
        scope='Every native page digest and on-chip metadata row matches the current fixed plaintext image, with exact last-page zero padding; boot policies match plaintext/ciphertext assets as applicable. Exhaustive finite constant validation, not a proof of RTL ROM addressing, hash hardness, AES arithmetic, consumer provenance or physical immutability.')
    (HERE/'FIXED-DIGEST-ASSETS-AUDIT.json').write_text(json.dumps(out,indent=2,sort_keys=True)+'\n');print(json.dumps(out))


if __name__=='__main__':main()
