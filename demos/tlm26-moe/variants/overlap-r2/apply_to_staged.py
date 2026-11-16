"""Apply the measured schedule to a separately staged, verified baseline.

File-only overlay. No downloads, EDA launch, programmer or serial access.
"""
import argparse
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('staged',type=Path);a=p.parse_args()
    target=a.staged.resolve();identity=json.loads((HERE/'SOURCE-IDENTITIES.json').read_text())
    before=identity['baseline_native_input_sha256'];after=identity['measured_native_input_sha256']
    actual={n:sha(target/n) for n in before}
    if actual==after:
        print('Already matches the measured 28-input schedule variant.');return
    assert actual==before,'Stage differs from the pinned baseline; no file was changed.'
    decoder=(HERE/'rtl/tlm_decoder.sv').read_bytes()
    original_sdc=(target/'product.sdc').read_bytes()
    report_sdc=(HERE/'additional-reports.sdc').read_bytes()
    assert hashlib.sha256(decoder).hexdigest()==after['tlm_decoder.sv']
    assert hashlib.sha256(original_sdc+report_sdc).hexdigest()==after['product.sdc']
    (target/'tlm_decoder.sv').write_bytes(decoder)
    (target/'product.sdc').write_bytes(original_sdc+report_sdc)
    assert {n:sha(target/n) for n in before}==after
    print('Verified all 28 measured inputs: one RTL schedule change and report-only SDC addition.')
if __name__=='__main__':main()
