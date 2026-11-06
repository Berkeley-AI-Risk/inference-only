#!/usr/bin/env python3
"""Source/timing-gated SRAM-only plain S-AWIC campaign with restoration."""
import argparse
import datetime
import fcntl
import hashlib
import json
from pathlib import Path
import re
import subprocess
import sys
import time

WORK = Path(__file__).resolve().parents[2]
OLD = WORK/'simplestories-swic-tang-20261103'
HOME = WORK/'sawic-home-authorization-20261103'
RECOVERY = WORK/'sawic-model-replacement-20261105'
PROGRAMMER = Path('/Users/halcrow/Holliday Team Dropbox/Wes Holliday/Mac/Documents/GitHub/pause/vendor-installers/gowin/programmer-1.9.12.03-2712-macos-arm64/Programmer/bin/programmer_cli')
LOADER = Path('/opt/homebrew/bin/openFPGALoader')
RESTORE = RECOVERY/'bitstreams/original_swic_product.fs'
PORT = '/dev/cu.usbserial-20250303171'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def require_device_identity(text):
    assert 'ERROR' not in text.upper() and 'Finished' in text, 'Device-ID operation failed'
    assert re.search(r'^\s*ID Code is:\s*0x0001081B\s*$', text, re.M | re.I), 'Missing/wrong actual FPGA ID'


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2)
        stream.write('\n')


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--review', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--location', required=True, help='Current channel-0 location from programmer_cli --scan-cables F')
    p.add_argument('--reuse-readback', type=Path, help='Validated readback from this SRAM-only campaign; retains original capture receipt')
    a = p.parse_args()
    out = a.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    native = json.loads((a.build/'RESULT.json').read_text())
    review = json.loads(a.review.read_text())
    assert native['exit_code'] == 0 and review['result'] == 'COMPILED_SOURCE_BOUND'
    assert review['functional_board_test_allowed'] and review['nominal_core_hz'] == 25000000
    image = Path(native['directory'])/'project/impl/pnr/swic_product.fs'
    assert sha(image) == review['sha256'] and review['native_inputs_sha256'] == sha(a.build/'INPUTS.json')
    for name, expected in json.loads((a.build/'INPUTS.json').read_text()).items():
        if name != 'project/product.gprj.user':
            assert sha(Path(native['directory'])/name) == expected, name
    assert sha(RESTORE) == '4545bd0b0c4076eaea8358d547b19ff0176952417daa0e0f07d1c346aee5fee2'
    assert sha(PROGRAMMER) == '41a967c1d18ec73b420801d52bf83ad40b92ca032683231d55a5ef158d523cfb'
    assert sha(LOADER) == 'f880eb583695f8056566da308248ba539a1a1c4cabb6305c3d801acfd58f9e1b'
    lock = open('/tmp/inference-only-tang-mega-2025030317.lock', 'a+')
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    owners = subprocess.run(['/usr/sbin/lsof', PORT, '/dev/cu.usbserial-20250303170'], capture_output=True, text=True)
    assert owners.returncode == 1 and not owners.stdout, 'Board serial port is owned'
    save(out/'STARTED.json', dict(started_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
        native_receipt_sha256=sha(a.build/'RESULT.json'), review_sha256=sha(a.review),
        candidate_sha256=sha(image), restore_sha256=sha(RESTORE), flash_write=False,
        runner_sha256=sha(Path(__file__))))

    def run(command, label):
        started = datetime.datetime.now(datetime.timezone.utc).isoformat()
        start = time.monotonic()
        log = out/(label+'.log')
        with log.open('xb') as stream:
            result = subprocess.run(command, stdout=stream, stderr=subprocess.STDOUT)
        record = dict(command=command, exit_code=result.returncode, started_utc=started,
                      completed_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                      elapsed_seconds=time.monotonic()-start, log_sha256=sha(log))
        save(out/(label+'.command.json'), record)
        text = log.read_text(errors='replace')
        assert result.returncode == 0 and 'ERROR' not in text.upper(), label
        return text

    def load(path, label):
        text = run([str(PROGRAMMER), '--device', 'GW5AST-138C', '--cable-index', '4',
            '--location', a.location, '--frequency', '0.9MHz', '--operation_index', '2', '--fsFile', str(path)], label)
        assert 'Finished' in text and 'ERROR' not in text.upper(), label

    def verify(label):
        run([sys.executable, str(OLD/'tools/uart_check.py'), '--device', PORT,
             '--expected', '108,32', '--output', str(out/(label+'.json'))], label)

    verify('baseline-before')
    identity = run([str(PROGRAMMER), '--device', 'GW5AST-138C', '--cable-index', '4',
                    '--location', a.location, '--frequency', '0.9MHz', '--operation_index', '0'], 'identity')
    require_device_identity(identity)
    changed = False
    try:
        readback = out/'readback.bin'
        readback_record = out/'readback.bin.json'
        if a.reuse_readback:
            readback = a.reuse_readback.resolve()
            readback_record = Path(str(readback)+'.json')
            capture = json.loads(readback_record.read_text())
            assert capture['status'] == 'PASS' and capture['array_write'] is False
            assert capture['tool_sha256'] == sha(LOADER)
            assert readback.stat().st_size == capture['bytes'] == 16777216
            assert sha(readback) == capture['sha256']
            assert readback.read_bytes() == (RECOVERY/'model-A/array.bin').read_bytes()
            save(out/'READBACK-REUSE.json', dict(source=str(readback), record=str(readback_record),
                record_sha256=sha(readback_record), array_sha256=sha(readback),
                original_capture_started_utc=capture['started_utc'],
                scope='Retained validated capture from the same campaign. Intervening recovery uses SRAM programming, USB reset and UART only; no flash write. Original capture and failure evidence remain unchanged.'))
        else:
            # The qualified flash reader changes SRAM configuration; it never
            # requests flash erase/program or a persistent protection change.
            changed = True
            run([sys.executable, str(OLD/'tools/read_flash_jtag.py'), '--openloader', str(LOADER),
                 '--tool-sha256', sha(LOADER), '--serial', '2025030317', '--output', str(readback),
                 '--expected-array', str(RECOVERY/'model-A/array.bin')], 'readback')
        changed = True
        load(image, 'load-candidate')
        time.sleep(45)
        verify('candidate-base')
        slot = readback.read_bytes()[0xf00000:0xf40000]
        save(out/'BOARD-RESULT.json', dict(result='PASS', bitstream_sha256=sha(image),
            cases=[dict(case='base', admission_slot_sha256=hashlib.sha256(slot).hexdigest(),
                        expected_tokens=[108, 32])], flash_write=False,
            scope='Ordinary valid signed base model; no crafted package or mutable-DDR experiment. Paired speed and restoration have separate records.'))
        run([sys.executable, str(OLD/'tools/collect_common_speed.py'),
             '--reference', str(RECOVERY/'model-A/reference.json'), '--bitstream', str(image),
             '--load-record', str(out/'load-candidate.command.json'), '--flash-readback', str(readback),
             '--flash-record', str(readback_record), '--board-result', str(out/'BOARD-RESULT.json'),
             '--output', str(out/'speed'), '--device', PORT], 'common-speed')
    finally:
        failure = sys.exc_info()[1]
        try:
            if failure is not None:
                save(out/'FAILURE.json', dict(result='FAIL', error_type=type(failure).__name__, error=str(failure)))
        finally:
            if changed:
                load(RESTORE, 'restore-sawic')
                sys.path.insert(0, str(HOME/'reference'))
                from usb_debugger import reset_known_debugger
                save(out/'usb-reset-after-restore.json', reset_known_debugger())
                time.sleep(45)
                verify('baseline-after')
                save(out/'RESTORED.json', dict(result='PASS', original_sram_verified=True, flash_write=False))
    speed = json.loads((out/'speed/FINISHED.json').read_text())
    assert speed['passed'] and speed['counted_cached_outputs'] == 254
    save(out/'RESULT.json', dict(result='PASS', fpga_image_sha256=sha(image),
        cached_tokens_per_second=speed['cached_tokens_per_second'], paired_outputs=256,
        original_sram_restored_and_verified=True, flash_write=False,
        independent_configuration_attestation=False, full_timing_signoff=False))
    print(json.dumps(dict(result='PASS', cached_tokens_per_second=speed['cached_tokens_per_second'], flash_write=False)))


if __name__ == '__main__':
    main()
