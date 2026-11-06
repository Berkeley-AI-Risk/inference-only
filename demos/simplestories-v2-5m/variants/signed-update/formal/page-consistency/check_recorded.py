#!/usr/bin/env python3
"""Check recorded component evidence without running engines or hardware."""
import hashlib
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    package=json.loads((HERE/'PACKAGE.json').read_text())
    for name,digest in package['files'].items():
        p=(HERE/name).resolve()
        assert p.is_relative_to(HERE) and not p.is_symlink(),name
        assert sha(p.read_bytes())==digest,name
    source=(ROOT/'rtl/su_page_table_check.sv').read_text()
    for p in [ROOT/'tang/hardware/project/swic/su_page_table_check.sv',
              ROOT.parent/'home-authorization/hardware/project/swic/su_page_table_check.sv']:
        assert p.read_text()==source,'Tang page checker differs'
    for job,props in [('page','page_properties.sv'),('compressor','compressor_properties.sv')]:
        out=HERE/'records'/job
        result=json.loads((out/'RESULT.json').read_text())
        assert result['result']=='PASS' and result['job']==job
        assert result['source_sha256']==sha(source.encode())
        properties=(HERE/props).read_text()
        assert result['properties_sha256']==sha(properties.encode())
        assert result['sha_contract_sha256']==sha((HERE/'page_sha_contract.sv').read_bytes())
        at=source.index('\nendmodule') if job=='page' else source.rindex('\nendmodule')
        assert (out/'design.sv').read_text()==source[:at]+'\n'+properties+source[at:]
        assert (out/'sha_contract.sv').read_bytes()==(HERE/'page_sha_contract.sv').read_bytes()
        module='su_page_table_check' if job=='page' else 'swic_boot_compressor_mux3'
        recipe=f'read_verilog -formal -D SYNTHESIS -sv design.sv sha_contract.sv\nprep -top {module} -flatten\nasync2sync\ndffunmap\nopt_clean\nwrite_smt2 -wires model.smt2\n'
        assert (out/'prove.ys').read_text()==recipe
        for stage,record in result['records'].items():
            log=(out/(stage+'.log')).read_bytes()
            assert record['passed'] and record['exit_code']==0 and sha(log)==record['log_sha256']
            if stage!='prepare':assert b'Status: PASSED' in log
    unit=json.loads((HERE/'records/unit/RESULT.json').read_text())
    assert unit['result']=='PASS' and len(unit['cases'])==3
    for name,digest in unit['source_sha256'].items():
        assert sha((ROOT/name).read_bytes())==digest,name
    for row in unit['cases']:
        assert row['result']=='PASS' and row['exit_code']==0
        size,page=row['bytes'],row['page_bytes']
        data=bytes((i*73+i//251+19)&255 for i in range(size))
        digests=b''.join(hashlib.sha256(data[i:i+page].ljust(page,b'\0')).digest() for i in range(0,size,page))
        assert sha(data)==row['image_sha256'] and sha(digests)==row['digest_table_sha256']
        log=(HERE/f'records/unit/bytes-{size}.log').read_bytes()
        assert sha(log)==row['run_log_sha256'] and f'PASS page consistency bytes={size} '.encode() in log
        assert b'PASS reset clears completed verification' in log
    print(json.dumps(dict(result='PASS',formal_jobs=2,unit_geometries=3,
                          recorded_only=True,whole_machine_theorem=False)))


if __name__=='__main__':
    main()
