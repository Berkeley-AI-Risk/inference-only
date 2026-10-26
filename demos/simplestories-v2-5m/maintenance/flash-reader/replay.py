#!/usr/bin/env python3
"""Offline checks of the auxiliary SRAM flash reader; no physical board access."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
import time

if not (sys.flags.isolated and sys.flags.no_site and sys.flags.dont_write_bytecode) or sys.flags.optimize:
    raise SystemExit('Use Python -I -S -B, without -O.')


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def inventory(source):
    manifest = json.loads((source / 'MANIFEST.json').read_text())
    expected = set(manifest['files']) | {'MANIFEST.json'}
    if any(p.is_symlink() for p in source.rglob('*')):
        raise ValueError('Source tree contains a symbolic link')
    if {p.relative_to(source).as_posix() for p in source.rglob('*') if p.is_file()} != expected:
        raise ValueError('Source inventory differs')
    for name, row in manifest['files'].items():
        path = source / name
        if not path.is_file() or path.stat().st_size != row['bytes'] or sha(path) != row['sha256']:
            raise ValueError('Changed source: ' + name)
    return manifest


def put(path, value):
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', type=Path, default=Path(__file__).absolute().parent)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--verilator', default='verilator')
    args = parser.parse_args()
    source, work = args.source.absolute(), args.work.absolute()
    manifest = inventory(source)
    if work == source or work.is_relative_to(source) or any(c.isspace() for c in str(work)):
        raise ValueError('Use a fresh, space-free work directory outside the source tree')
    work.mkdir(parents=False, exist_ok=False)
    (work / 'replay.py').write_bytes(Path(__file__).read_bytes())
    verilator = shutil.which(args.verilator)
    if verilator is None:
        raise ValueError('Verilator not found')

    def execute(folder, name, argv, timeout):
        started = time.monotonic()
        with (folder / (name + '.log')).open('xb') as log:
            process = subprocess.Popen(argv, cwd=folder, stdout=log, stderr=subprocess.STDOUT)
            put(folder / (name + '-STARTED.json'), {'pid': process.pid, 'argv': argv, 'hardware_access': False})
            try:
                code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
                code = 124
        return {'exit': code, 'seconds': time.monotonic() - started,
                'log_sha256': sha(folder / (name + '.log')), 'argv': argv}

    def run(label):
        folder = work / label
        folder.mkdir()
        if label == 'host':
            names = [name for name in manifest['files'] if name.startswith('host/')]
            for name in names:
                shutil.copyfile(source / name, folder / Path(name).name)
            result = execute(folder, 'tests', [sys.executable, '-I', '-S', '-B', '-m', 'unittest', 'discover', '-v'], 60)
            log = (folder / 'tests.log').read_text(errors='replace')
            result['passed'] = result['exit'] == 0 and re.findall(r'^Ran (\d+) tests in ', log, re.M) == ['10'] and re.search(r'^OK$', log, re.M) is not None
            result['source_files_unchanged'] = all(sha(folder / Path(n).name) == manifest['files'][n]['sha256'] for n in names)
        else:
            count, uart, spi = {'fast': (257, 16, 3), 'rate-one': (1, 434, 25), 'rate-257': (257, 434, 25)}[label]
            names = [n for n in manifest['files'] if n.startswith(('rtl/', 'tb/'))]
            for name in names:
                target = folder / name
                target.parent.mkdir(exist_ok=True)
                shutil.copyfile(source / name, target)
            argv = [verilator, '--binary', '--timing', '--assert', '-j', '4', '-Wall',
                '-Wno-DECLFILENAME', '-Wno-UNUSEDSIGNAL', '-Wno-BLKSEQ', '-Wno-SYNCASYNCNET', '-Wno-PROCASSINIT',
                '--top-module', 'tb_readonly_flash_reader', '--Mdir', 'obj',
                '-MAKEFLAGS', 'CURDIR=' + str(folder / 'obj'),
                '-GN=' + str(count), '-GU=' + str(uart), '-GSPI_HALF=' + str(spi),
                'rtl/fixed_uart_rx.sv', 'rtl/fixed_uart_tx.sv', 'rtl/readonly_flash_reader.sv', 'tb/tb_readonly_flash_reader.sv']
            compile_result = execute(folder, 'compile', argv, 300)
            result = {'compile': compile_result, 'bytes_per_simulated_read': count, 'uart_divider': uart, 'spi_half_divider': spi, 'passed': False}
            if compile_result['exit'] == 0:
                result['simulation'] = execute(folder, 'simulation', [str(folder / 'obj/Vtb_readonly_flash_reader')], 120)
                log = (folder / 'simulation.log').read_text(errors='replace')
                result['passed'] = result['simulation']['exit'] == 0 and log.count('PASS readonly SRAM flash reader bytes=' + str(count) + ' ') == 1 and 'complete_reads=2' in log
            result['source_files_unchanged'] = all(sha(folder / n) == manifest['files'][n]['sha256'] for n in names)
        result['passed'] = result['passed'] and result['source_files_unchanged']
        put(folder / 'FINISHED.json', result)
        print('FLASH_READER_REPLAY ' + label + ' passed=' + str(result['passed']), flush=True)
        return label, result

    with ThreadPoolExecutor(max_workers=4) as pool:
        records = dict(pool.map(run, ('host', 'fast', 'rate-one', 'rate-257')))
    unchanged = inventory(source) == manifest
    result = {'passed': unchanged and all(row['passed'] for row in records.values()),
        'source_manifest_sha256': sha(source / 'MANIFEST.json'), 'source_unchanged': unchanged,
        'jobs': records, 'hardware_access': False, 'network_access': False,
        'scope': 'Ten synthetic/pseudo-terminal receiver tests and three reader RTL simulations, including production UART/SPI rates with shortened data length. Not a native build, full-length RTL proof or physical qualification.'}
    put(work / 'FINISHED.json', result)
    print('FLASH_READER_REPLAY_FINISHED passed=' + str(result['passed']), flush=True)
    return 0 if result['passed'] else 1


if __name__ == '__main__':
    raise SystemExit(main())
