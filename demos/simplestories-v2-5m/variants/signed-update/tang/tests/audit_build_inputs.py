#!/usr/bin/env python3
"""Check the retained compiled simulation copies against the concrete source."""
from pathlib import Path
import hashlib,json
ROOT=Path(__file__).resolve().parents[1]
for campaign in ['tang-fast-simulation','tang-simulation']:
    out=ROOT/'evidence'/campaign;receipt=(out/'BUILD.json').read_bytes();build=json.loads(receipt)
    directory=Path(build['build_directory']);files={}
    for name,expected in build['source_sha256'].items():
        source=ROOT/name;assert hashlib.sha256(source.read_bytes()).hexdigest()==expected,name
        compiled=directory/('project/'+name[len('hardware/project/'):] if name.startswith('hardware/project/') else Path(name).name)
        assert source.read_bytes()==compiled.read_bytes(),name
        files[str(compiled.relative_to(directory))]=expected
    if build['fast_flash_source_abstraction']:
        s=(ROOT/'hardware/project/swic/swic_qspi_boot_source.sv').read_text();start=s.index('module ');end=s.index('\n);',start)+4
        expected='`timescale 1ns/1ps\n'+s[start:end]+'\n'+(ROOT/'tests/fast_flash_body.sv').read_text()
        assert (directory/'fast_flash.sv').read_text()==expected
        files['fast_flash.sv']=hashlib.sha256(expected.encode()).hexdigest()
    result={'result':'PASS','build_receipt_sha256':hashlib.sha256(receipt).hexdigest(),
            'binary_sha256':hashlib.sha256(Path(build['binary']).read_bytes()).hexdigest(),
            'retained_compiled_files_sha256':files,'fast_flash_source_abstraction':build['fast_flash_source_abstraction']}
    (out/'SOURCE-AUDIT.json').write_text(json.dumps(result,indent=2)+'\n')
    print('PASS retained compiled input audit:',campaign)
