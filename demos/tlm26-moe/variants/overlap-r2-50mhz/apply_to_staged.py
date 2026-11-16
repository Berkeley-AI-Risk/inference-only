# SPDX-License-Identifier: Apache-2.0
"""Apply the exact measured clock delta to an owned verified overlap-r2 stage.

This helper performs local file operations only. It never starts EDA, opens a
hardware device, fetches model/vendor inputs or grants programming permission.
"""
from pathlib import Path
import argparse
import hashlib
import json
import shutil

def hashes(stage, names):
    return {name: hashlib.sha256((stage/name).read_bytes()).hexdigest() for name in names}

def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('stage', type=Path)
    args=ap.parse_args()
    here=Path(__file__).resolve().parent
    ids=json.loads((here/'SOURCE-IDENTITIES.json').read_text())
    stage=args.stage.resolve()
    expected=ids['measured_native_input_sha256']
    actual=hashes(stage,expected)
    if actual!=expected:
        assert actual==ids['baseline_native_input_sha256'], 'Expected the exact verified 12.5 MHz overlap-r2 native stage'
        for name in ids['changed_native_inputs']:
            replacement=here/'rtl'/name
            assert hashlib.sha256(replacement.read_bytes()).hexdigest()==expected[name]
        for name in ids['changed_native_inputs']:
            shutil.copyfile(here/'rtl'/name,stage/name)
        assert hashes(stage,expected)==expected
    print(json.dumps({'accepted':True,'native_inputs':len(expected),'already_or_now_applied':True,'EDA_run':False,'board_access':False}))

if __name__=='__main__':main()
