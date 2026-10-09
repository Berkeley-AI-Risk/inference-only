#!/usr/bin/env python3
"""Offline actual-UART trace tests and five deliberately faulty controls.

These negatives are directed simulation counterexamples, not SAT proofs.
No board, server, vendor tools, or network are used.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor
import difflib
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

assert sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize


def sha(data): return hashlib.sha256(data).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', required=True, type=Path)
    parser.add_argument('--work', required=True, type=Path)
    options = parser.parse_args()
    package, work = options.package.absolute(), options.work.absolute()
    assert work != package and not work.is_relative_to(package)
    manifest = json.loads((package / 'MANIFEST.json').read_text())
    def read(relative):
        path = package / relative
        assert not path.is_symlink()
        data = path.read_bytes()
        assert sha(data) == manifest['files'][relative]['sha256'], relative
        assert len(data) == manifest['files'][relative]['bytes'], relative
        return data
    production = read('hardware/project/fpga/token_only_model0_mac_uart0/rtl/token_only_model0_uart_bridge.sv').decode()
    bridge = read('formal/frame/token_only_model0_uart_bridge.sv').decode()
    a, b = production.splitlines(keepends=True), bridge.splitlines(keepends=True)
    changes = [row for row in difflib.SequenceMatcher(a=a, b=b, autojunk=False).get_opcodes() if row[0] != 'equal']
    assert len(changes) == 1 and changes[0][0] == 'insert'
    inserted = ''.join(b[changes[0][3]:changes[0][4]])
    assert inserted.count('assert(') == 46 and 'assume(' not in inserted
    shared = {name: read('formal/frame/' + name)
              for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv', 'tb_frame_refinement.sv')}
    for name in ('fixed_uart_rx.sv', 'fixed_uart_tx.sv'):
        assert shared[name] == read('hardware/project/fpga/token_only_model0_mac_uart0/rtl/' + name)
    mutations = {
        'actual': None,
        'crc-bypass': ('rx_byte != request_crc_q ||', "1'b0 ||"),
        'wrong-append-token': ('''command_token_q <= {
                                request_token_high_q[3:0],
                                request_token_low_q
                            };''', "command_token_q <= 12'd0;"),
        'ack-leaks-token': ("prepare_response(8'h80, 12'b0);", "prepare_response(8'h80, 12'd1);"),
        'wrong-reply-crc': ('response_crc_q <= computed_response_crc;', "response_crc_q <= computed_response_crc ^ 8'h01;"),
        'duplicate-reply': ('''end else begin
                            state_q <= BRIDGE_IDLE;
                        end''', '''end else begin
                            state_q <= BRIDGE_SEND;
                        end'''),
    }
    work.mkdir(parents=False, exist_ok=False)
    shutil.copyfile(__file__, work / 'checker.py')
    jobs = {}
    for label, change in mutations.items():
        candidate = bridge
        if change:
            old, new = change
            assert production.count(old) == 1 and bridge.count(old) == 1, label
            candidate = candidate.replace(old, new)
        job = work / label
        job.mkdir()
        files = dict(shared, **{'token_only_model0_uart_bridge.sv': candidate.encode()})
        for name, data in files.items(): (job / name).write_bytes(data)
        jobs[label] = {'files': {name: sha(data) for name, data in files.items()}, 'edit': change}
    (work / 'INPUTS.json').write_text(json.dumps(jobs, indent=2) + '\n')
    def check(label):
        job = work / label
        argv = [shutil.which('iverilog'), '-g2012', '-gno-assertions', '-DSYNTHESIS',
                '-s', 'tb_frame_refinement', '-o', 'sim.vvp', 'fixed_uart_rx.sv',
                'fixed_uart_tx.sv', 'token_only_model0_uart_bridge.sv', 'tb_frame_refinement.sv']
        with (job / 'compile.log').open('w') as log:
            compile_exit = subprocess.run(argv, cwd=job, stdout=log, stderr=subprocess.STDOUT).returncode
        assert compile_exit == 0, label
        with (job / 'simulation.log').open('w') as log:
            code = subprocess.run([shutil.which('vvp'), 'sim.vvp'], cwd=job, stdout=log,
                                  stderr=subprocess.STDOUT, timeout=60).returncode
        text = (job / 'simulation.log').read_text()
        passed = ((code == 0 and 'PASS_FRAME_TRACE cases=12 bytes=60 commands=7 cpb=217' in text)
                  if label == 'actual' else
                  (code != 0 and ('PROVEN_' in text or 'SCOREBOARD_MISMATCH' in text)
                   and 'TIMEOUT' not in text and 'COVERAGE_COUNTS' not in text))
        unchanged = all(sha((job / name).read_bytes()) == digest for name, digest in jobs[label]['files'].items())
        return label, {'passed': passed and unchanged, 'exit': code, 'source_unchanged': unchanged,
                       'log_sha256': sha(text.encode()), 'expected': 'pass' if label == 'actual' else 'simulation counterexample'}
    with ThreadPoolExecutor(max_workers=6) as pool:
        records = dict(pool.map(check, mutations))
    finished = {'passed': all(row['passed'] for row in records.values()), 'jobs': records,
                'hardware_access': False, 'network_access': False,
                'scope': 'Finite actual-217-clock UART traces and simulation sensitivity, not formal refinement.'}
    (work / 'FINISHED.json').write_text(json.dumps(finished, indent=2) + '\n')
    print('FRAME_TRACE_FINISHED passed=' + str(finished['passed']), flush=True)
    return 0 if finished['passed'] else 1


if __name__ == '__main__': raise SystemExit(main())
