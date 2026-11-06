#!/usr/bin/env python3
"""Ordinary SHA/page-stream unit fixtures; no signatures, DDR or hardware access."""
import argparse
import hashlib
import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--full-geometry',action='store_true')
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    names=['rtl/vendor/sha.sv','rtl/su_sha256.sv','rtl/su_page_table_check.sv','tests/tb_page_consistency.sv']
    source_hashes={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in names}
    geometries=[(128,64,32),(8203,4096,4064)]
    if args.full_geometry:
        geometries.append((7265984,4096,6856352))
    results=[]
    for size,page,suffix in geometries:
        case=out/f'bytes-{size}'
        case.mkdir()
        # GNU Make used by Verilator cannot build below a path with spaces.
        build=Path(tempfile.mkdtemp(prefix='sawic-page-consistency-'))
        data=bytes((i*73+i//251+19)&255 for i in range(size))
        digests=b''.join(hashlib.sha256(data[i:i+page].ljust(page,b'\0')).digest() for i in range(0,size,page))
        (case/'image.hex').write_text(''.join(f'{b:02x}\n' for b in data))
        (case/'digests.hex').write_text(''.join(digests[i:i+4].hex()+'\n' for i in range(0,len(digests),4)))
        (case/'expected.hex').write_text(hashlib.sha256(data).hexdigest()+'\n'+hashlib.sha256(data[suffix:]).hexdigest()+'\n')
        for name in names:
            shutil.copyfile(root/name,build/Path(name).name)
        command=['verilator','--binary','--timing','-Wno-fatal','--top-module','tb_page_consistency',
                 '-j','1','-CFLAGS','-O2','--Mdir','obj',f'-GIMAGE_BYTES={size}',f'-GPAGE_BYTES={page}',
                 f'-GSUFFIX_AT={suffix}']+[Path(name).name for name in names]
        started=time.monotonic()
        with (case/'build.log').open('w') as log:
            subprocess.run(command,cwd=build,stdout=log,stderr=subprocess.STDOUT,check=True)
        with (case/'run.log').open('w') as log:
            run=subprocess.run([str(build/'obj/Vtb_page_consistency'),f'+FIXTURES={case}'],
                               cwd=build,stdout=log,stderr=subprocess.STDOUT)
        log=(case/'run.log').read_text()
        passed=run.returncode==0 and f'PASS page consistency bytes={size} ' in log
        row=dict(bytes=size,page_bytes=page,suffix_at=suffix,result='PASS' if passed else 'FAIL',
                 command=command,build_directory=str(build),exit_code=run.returncode,elapsed_seconds=time.monotonic()-started,
                 image_sha256=hashlib.sha256(data).hexdigest(),digest_table_sha256=hashlib.sha256(digests).hexdigest(),
                 run_log_sha256=hashlib.sha256(log.encode()).hexdigest())
        results.append(row)
        (case/'RESULT.json').write_text(json.dumps(row,indent=2)+'\n')
        print(json.dumps(row),flush=True)
        if not passed:
            break
    assert all(hashlib.sha256((root/n).read_bytes()).hexdigest()==h for n,h in source_hashes.items()),'source changed during run'
    summary=dict(result='PASS' if len(results)==len(geometries) and all(r['result']=='PASS' for r in results) else 'FAIL',
                 cases=results,source_sha256=source_hashes,hardware_access=False,
                 scope='synthetic ordinary stream fixtures; actual SHA compressor; reset, stalls, page order and zero padding')
    (out/'RESULT.json').write_text(json.dumps(summary,indent=2)+'\n')
    if summary['result']!='PASS':
        raise SystemExit(1)


if __name__=='__main__':
    main()
