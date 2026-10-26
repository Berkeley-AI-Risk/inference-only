"""Independently check a complete SPI cover trace against the emitted SMT RTL.

The primary solver finds the trace. The secondary solver checks its concrete
state/input/output values, every transition, all safety properties and both
cover goals. Concrete trace values are witnesses, not safety-proof assumptions.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import time

TOP = 'board1_context2048_qspi_read03_master'


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def read_vcd(path):
    symbols,values,states = {},{},{}
    in_header = True
    current_step = None
    current_has_step = False
    def finish():
        if current_has_step:
            if current_step in states:
                raise ValueError('Repeated VCD state')
            states[current_step] = dict(values)
    for line in path.read_text().splitlines():
        if in_header:
            if line.startswith('$var '):
                parts = line.split()
                if parts[3].startswith('n'):
                    symbols[parts[3]] = (parts[4],int(parts[2]))
            if line == '$enddefinitions $end':
                in_header = False
            continue
        if line.startswith('#'):
            finish()
            current_has_step = False
        elif line.startswith('b'):
            bits,name = line[1:].split()
            if name == 't':
                current_step,current_has_step = int(bits,2),True
            elif name in symbols:
                if set(bits)-set('01'):
                    raise ValueError('Unknown trace bit')
                values[name] = bits
    finish()
    if not symbols or sorted(states) != list(range(len(states))):
        raise ValueError('Noncontiguous or empty VCD trace')
    return symbols,states


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--proof',type=Path,required=True)
    parser.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    vcd = args.proof/'z3-cover-0.vcd'
    design = args.proof/'design.smt2'
    text = design.read_text()
    symbols,states = read_vcd(vcd)
    # SMTBMC emits a final clock-only timestamp after the last modeled state.
    # The reached goals are pinned to the actual recorded state 162.
    if 162 not in states:
        raise ValueError('SPI coverage state is missing')
    states = {i:s for i,s in states.items() if i <= 162}
    parts = ['(set-logic QF_AUFBV)','(set-option :produce-models true)',text]
    for step,state in states.items():
        parts += [f'(declare-fun s{step} () |{TOP}_s|)',
            f'(assert (|{TOP}_h| s{step}))',f'(assert (|{TOP}_u| s{step}))',
            f'(assert (= (|{TOP}_is| s{step}) {"true" if step == 0 else "false"}))',
            f'(assert (|{TOP}_a| s{step}))']
        if step == 0:
            parts.append(f'(assert (|{TOP}_i| s0))')
        else:
            parts.append(f'(assert (|{TOP}_t| s{step-1} s{step}))')
        for symbol,(name,width) in symbols.items():
            if symbol not in state:
                raise ValueError('Trace wire value missing')
            if not re.fullmatch(r'\w+',name) or f'(define-fun |{TOP}_n {name}|' not in text:
                raise ValueError('Unexpected trace wire: '+name)
            bits = state[symbol]
            if len(bits) != width:
                raise ValueError('Trace width mismatch')
            value = ('true' if bits == '1' else 'false') if width == 1 else '#b'+bits
            parts.append(f'(assert (= (|{TOP}_n {name}| s{step}) {value}))')
    parts += [f'(assert (|{TOP}_c 0| s162))',f'(assert (|{TOP}_c 1| s162))','(check-sat)','(exit)']
    query = ('\n'.join(parts)+'\n').encode()
    (args.out/'witness.smt2').write_bytes(query)
    (args.out/'checker.py').write_bytes(Path(__file__).read_bytes())
    start = time.monotonic()
    command = ['cvc5','--lang=smt2','--incremental','--tlimit-per=120000',str((args.out/'witness.smt2').resolve())]
    with (args.out/'cvc5.log').open('w') as out:
        cp = subprocess.run(command,stdout=out,stderr=subprocess.STDOUT,timeout=130)
    raw = (args.out/'cvc5.log').read_bytes()
    answers = [line for line in raw.decode().splitlines() if line in ('sat','unsat','unknown')]
    passed = cp.returncode == 0 and answers == ['sat'] and b'(error ' not in raw
    result = dict(schema='current-qspi-independent-complete-witness-check-v1',passed=passed,
        command=command,exit=cp.returncode,answers=answers,states_checked=len(states),wires_checked=len(symbols),
        all_state_transitions_checked=True,all_safety_properties_checked=True,cover_goals_checked=2,
        seconds=time.monotonic()-start,primary_trace_sha256=sha(vcd.read_bytes()),
        emitted_smt_sha256=sha(design.read_bytes()),query_sha256=sha(query),log_sha256=sha(raw),
        safety_proof_assumptions_added=False)
    (args.out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(result),flush=True)
    return 0 if passed else 1


if __name__ == '__main__':
    raise SystemExit(main())
