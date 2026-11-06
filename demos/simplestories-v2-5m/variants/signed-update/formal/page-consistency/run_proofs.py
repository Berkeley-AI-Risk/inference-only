#!/usr/bin/env python3
"""Inductive page-controller accounting properties under an explicit SHA contract."""
import argparse
import hashlib
import json
import subprocess
import time
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE=HERE.parents[1]/'rtl/su_page_table_check.sv'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--depth',type=int,default=12)
    parser.add_argument('--job',choices=['page','compressor'],default='page')
    args=parser.parse_args()
    out=args.output.resolve()
    out.mkdir(parents=True,exist_ok=False)
    source=SOURCE.read_text()
    properties=(HERE/('page_properties.sv' if args.job=='page' else 'compressor_properties.sv')).read_text()
    module='su_page_table_check' if args.job=='page' else 'swic_boot_compressor_mux3'
    at=source.index('\nendmodule') if args.job=='page' else source.rindex('\nendmodule')
    (out/'design.sv').write_text(source[:at]+'\n'+properties+source[at:])
    (out/'sha_contract.sv').write_bytes((HERE/'page_sha_contract.sv').read_bytes())
    (out/'prove.ys').write_text(f'''read_verilog -formal -D SYNTHESIS -sv design.sv sha_contract.sv
prep -top {module} -flatten
async2sync
dffunmap
opt_clean
write_smt2 -wires model.smt2
''')
    records={}
    commands=[('prepare',['yosys','-Q','-T','prove.ys']),
              ('base',['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-t',str(args.depth),'--dump-vcd','base.vcd','model.smt2']),
              ('induction',['yosys-smtbmc','-s','cvc5','--presat','--noprogress','-i','-t',str(args.depth),'--dump-vcd','induction.vcd','model.smt2'])]
    passed=True
    for name,command in commands:
        started=time.monotonic()
        with (out/(name+'.log')).open('w') as log:
            result=subprocess.run(command,cwd=out,stdout=log,stderr=subprocess.STDOUT)
        text=(out/(name+'.log')).read_text()
        ok=result.returncode==0 and (name=='prepare' or 'Status: PASSED' in text)
        records[name]=dict(command=command,exit_code=result.returncode,passed=ok,
                           elapsed_seconds=time.monotonic()-started,log_sha256=hashlib.sha256(text.encode()).hexdigest())
        print(json.dumps(dict(stage=name,**records[name])),flush=True)
        if not ok:
            passed=False
            break
    result=dict(result='PASS' if passed else 'NOT_PROVEN',records=records,
                source_sha256=hashlib.sha256(source.encode()).hexdigest(),
                properties_sha256=hashlib.sha256(properties.encode()).hexdigest(),
                sha_contract_sha256=hashlib.sha256((out/'sha_contract.sv').read_bytes()).hexdigest(),
                job=args.job,image_bytes=7265984,page_bytes=4096,
                scope=('Binary clocked controller: exact input/page coverage before verification, page bounds, reset, padding region, sticky failure and verdict checks. SHA flow abstracted; no hash correctness, DDR or whole-machine theorem.' if args.job=='page' else
                       'Binary clocked compressor arbitration: exclusive acceptance/completion, accepted requesting owner retains the completion, and one outstanding operation. Compressor flow abstracted; no hash correctness or liveness theorem.'))
    (out/'RESULT.json').write_text(json.dumps(result,indent=2)+'\n')
    if not passed:
        raise SystemExit(1)


if __name__=='__main__':
    main()
