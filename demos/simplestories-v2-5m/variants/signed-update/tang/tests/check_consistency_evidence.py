#!/usr/bin/env python3
"""Replay ordinary positive simulation receipts; no engines or hardware."""
import hashlib
import json
import re
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def verify(target,home=False):
    folder=target/'evidence/consistency-verification'
    raw=(folder/'BUILD.json').read_bytes()
    build=json.loads(raw)
    if home:
        assert build['result']=='PASS' and build['permitted_scenarios']==[0,1,2,3]
    else:
        assert build['fast_flash_source_abstraction']
    for name,digest in build['source_sha256'].items():
        p=(target/name).resolve()
        assert p.is_relative_to(target.resolve()),name
        assert sha(p.read_bytes())==digest,name
    copies=json.loads((folder/'PUBLIC-COPIES.json').read_text())
    assert not copies['semantic_results_changed']
    copy=next(row for row in copies['copies'] if row['file']=='BUILD.json')
    assert sha(raw)==copy['public_sha256']
    cases=[0,1,2,3] if home else [0,1]
    for case in cases:
        result=json.loads((folder/f'case-{case}-result.json').read_text())
        log=(folder/f'case-{case}.log').read_bytes()
        text=log.decode()
        assert result['result']=='PASS' and result['exit_code']==0
        assert sha(log)==result['log_sha256']
        assert result['build_receipt_sha256']==copy['original_sha256']
        assert not any(s in text for s in ['%Fatal','%Error','Assertion failed'])
        if home:
            markers={0:['PASS integrated renewal preserves context','PASS home UART turn=1','PASS home UART turn=2'],
                     1:['PASS integrated wrong-model authorization rejection'],
                     2:['PASS integrated lease loss cancels pending inference and suppresses output'],
                     3:['PASS integrated shared verifier rejects corrupt renewal after valid lease']}
            assert all(marker in text for marker in markers[case])
            tokens=[int(n) for n in re.findall(r'PASS token UART status=81 token=(\d+)',text)]
            assert tokens==([108,32] if case==0 else [])
        else:
            assert f'PASS Tang boot case={case}' in text and 'all_norm_rows=3328' in text
            assert f'PASS fast Tang SWIC case={case}' in text
            tokens=[int(n) for n in re.findall(rf'PASS UART case={case} op=1 token=(\d+)',text)]
            assert tokens==([108,32,108] if case==0 else [0,0,0])
    return dict(result='PASS',cases=len(cases),source_files_checked=len(build['source_sha256']))


def main():
    signed=verify(ROOT)
    home=verify(ROOT.parents[1]/'home-authorization',home=True)
    unit=ROOT/'evidence/consistency-verification/normalization-unit'
    norm=json.loads((unit/'result.json').read_text())
    assert norm['result']=='PASS' and norm['positive_models']==2
    assert norm['rows_per_model']==3328 and norm['read_ports']==2
    assert norm['reset_and_output_masking']
    for name,digest in norm['source_sha256'].items():
        source=(ROOT/name).resolve()
        assert source.is_relative_to(ROOT.resolve()),name
        assert sha(source.read_bytes())==digest,name
    norm_log=(unit/'run.log').read_text()
    assert 'PASS norm-store regression' in norm_log
    assert not any(s in norm_log for s in ['%Fatal','%Error','Assertion failed'])
    image=(ROOT.parents[2]/'assets/board1-real-semantic-image2048.bin').read_bytes()
    changed=bytearray(image)
    changed[214250*32:214260*32]=bytes(320)
    for target in [ROOT,ROOT.parents[1]/'home-authorization']:
        fixture=json.loads((target/'evidence/consistency-verification/fixtures.json').read_text())
        assert len(fixture)==2
        assert fixture[0]['image_sha256']==sha(image) and fixture[0]['tokens']==[108,32]
        assert fixture[1]['image_sha256']==sha(changed) and fixture[1]['tokens']==[0,0]
    print(json.dumps(dict(result='PASS',signed=signed,home=home,normalization_unit='PASS',
                          recorded_only=True,physical_qualification=False)))


if __name__=='__main__':
    main()
