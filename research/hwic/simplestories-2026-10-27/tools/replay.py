#!/usr/bin/env python3
"""Rebuild the frozen complete RTL and compare fresh independent Q0 fixtures."""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import argparse
import hashlib
import importlib.util
import json
import os
import re
import resource
import shutil
import signal
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def save(path, value):
    with path.open('x') as stream:
        json.dump(value, stream, indent=2, sort_keys=True)
        stream.write('\n')


def execute(work, name, argv, cwd, timeout=1800):
    began = time.monotonic()
    started = datetime.now(timezone.utc).isoformat()
    log = work/(name+'.log')
    with log.open('xb') as out:
        child = subprocess.Popen(argv, cwd=cwd, stdout=out, stderr=subprocess.STDOUT, start_new_session=True)
        save(work/(name+'-STARTED.json'), dict(pid=child.pid, argv=argv, cwd=str(cwd), started_utc=started))
        print(json.dumps(dict(stage=name, pid=child.pid)), flush=True)
        while True:
            pid, status, usage = os.wait4(child.pid, os.WNOHANG)
            if pid:
                break
            if time.monotonic()-began > timeout:
                os.killpg(child.pid, signal.SIGTERM)
                pid, status, usage = os.wait4(child.pid, 0)
                child.returncode = os.waitstatus_to_exitcode(status)
                raise TimeoutError((name, child.returncode))
            time.sleep(0.1)
        child.returncode = os.waitstatus_to_exitcode(status)
    row = dict(pid=child.pid, argv=argv, cwd=str(cwd), exit=child.returncode,
        started_utc=started, finished_utc=datetime.now(timezone.utc).isoformat(), wall_seconds=time.monotonic()-began,
        CPU_user_seconds=usage.ru_utime, CPU_system_seconds=usage.ru_stime, ru_maxrss_platform_units=usage.ru_maxrss,
        raw_wait_status=status, log_sha256=sha(log.read_bytes()))
    save(work/(name+'-EXECUTION.json'), row)
    return row, log.read_text(errors='replace')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--rom', type=Path, required=True, help='Authenticated canonical Q0 directory;not a deployed model loader.')
    parser.add_argument('--work', type=Path, required=True, help='New, whitespace-free output directory.')
    parser.add_argument('--build-jobs', type=int, default=8)
    parser.add_argument('--sim-jobs', type=int, default=4)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--fault-weight', action='store_true', help='Require the actual changed embedding image to fail its tensor check.')
    args = parser.parse_args()
    assert sys.flags.isolated and sys.flags.dont_write_bytecode and not sys.flags.optimize
    import numpy as np
    assert np.__version__ == '1.26.4'
    assert 1 <= args.build_jobs <= 24 and 1 <= args.sim_jobs <= 8
    work = args.work.absolute()
    assert not any(c.isspace() for c in str(work)), 'Verilator/Make output path must have no whitespace'
    work.mkdir(parents=True, exist_ok=False)
    began = time.monotonic()
    self_before = resource.getrusage(resource.RUSAGE_SELF)
    provenance = json.loads((ROOT/'PROVENANCE.json').read_text())
    source_pins = {}
    for row in provenance['RTL_sources']:
        src = ROOT/row['path']
        assert sha(src.read_bytes()) == row['sha256']
        relative = row['path'].removeprefix('rtl/')
        if relative == 'sources.f':
            relative = 'hwic_sources.f'
        dst = work/relative
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(src, dst)
        source_pins[relative] = row['sha256']
    for row in provenance['reference_sources']:
        assert sha((ROOT/row['path']).read_bytes()) == row['sha256']
    sys.path.insert(0, str(ROOT/'reference'))
    from quantization import oracle
    model = oracle.QuantizedModel.load(args.rom.resolve(strict=True))
    spec = importlib.util.spec_from_file_location('unchanged_awic_image_derivation', ROOT/'tools/reference_image.py')
    image_builder = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(image_builder)
    outputs, image_audit = image_builder.derive(model, np)
    image = outputs['board1-real-semantic-image2048.bin']
    assert sha(image) == provenance['fixed_image_sha256']
    image_path = work/'reference-image.bin'
    image_path.write_bytes(image)
    weights = image[:211800*32]
    assert len(weights) == 84720*80
    generated = {'fixed/weights640.memh': b''.join(weights[i:i+80][::-1].hex().encode()+b'\n' for i in range(0,len(weights),80))}
    misc = b''.join(image[a*32:b*32] for a,b in [(211920,214248),(214261,214773),(215286,227062)])
    assert len(misc) == 14616*32
    generated['fixed/misc256.memh'] = b''.join(misc[i:i+32][::-1].hex().encode()+b'\n' for i in range(0,len(misc),32))
    norms = outputs[image_builder.NORM_ROM].splitlines(keepends=True)
    assert len(norms) == 3328
    generated['fixed/norm_layers34.memh'] = b''.join(norms[:3072])
    generated['fixed/norm_final34.memh'] = b''.join(norms[3072:])
    for name in ('metadata192.memh','digests32.memh',image_builder.EXP_ROM):
        generated[name] = outputs[name]
    expected_assets = provenance['common_generated_asset_sha256']
    assert set(generated) == set(expected_assets)
    assert all(sha(data) == expected_assets[name] for name,data in generated.items())
    save(work/'IMAGE-DERIVATION.json', dict(image_sha256=sha(image), exhaustive_packing_audit=image_audit,
        fixed_assets_sha256={name:sha(data) for name,data in generated.items()}))
    reference_argv = [sys.executable,'-I','-B',str(ROOT/'tools/reference.py'),'--rom',str(args.rom.resolve()),
        '--work',str(work),'--image',str(image_path)] + (['--smoke'] if args.smoke else [])
    ref, text = execute(work,'reference',reference_argv,work)
    assert ref['exit'] == 0, text[-4000:]
    cases = json.loads((work/'REFERENCE.json').read_text())['cases']
    if not args.smoke:
        historical = json.loads((ROOT/'evidence/original-rtl-validation.json').read_text())['cases']
        assert len(cases) == 7
        for name,case in cases.items():
            assert all(case[key] == historical[name][key] for key in case)
    for name in cases:
        for relative,data in generated.items():
            path = work/name/relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
    if args.fault_weight:
        embedding = next(row for row in image_audit['projection_jobs'] if row['tensor'] == 'model.embed_tokens.weight')
        first_bit = embedding['first_word']*256
        assert first_bit % 640 == 0
        word = first_bit//640 + (378//64)*256
        bit = (378%64)*10
        for name in cases:
            path = work/name/'fixed/weights640.memh'
            lines = path.read_text().splitlines()
            original = lines[word]
            lines[word] = f'{int(original,16) ^ (1 << bit):0160x}'
            path.write_text('\n'.join(lines)+'\n')
        save(work/'ACTUAL-FAULT.json', dict(kind='embedding_token378_column0_weight_bit_flip', word=word, bit=bit,
            original_word=original, mutated_word=lines[word], unchanged_reference_image_sha256=sha(image),
            scope='Changed DUT manufacturing image only;fresh independent reference tensors remain unchanged.'))
    argv = provenance['original_compile_argv'][:]
    argv[argv.index('--build-jobs')+1] = str(args.build_jobs)
    argv[argv.index('--Mdir')+1] = str(work/'obj')
    argv[argv.index('-MAKEFLAGS')+1] = 'CURDIR='+str(work/'obj')+' OPT_FAST=-O3 OPT_SLOW=-O3'
    build, text = execute(work,'compile',argv,work)
    assert build['exit'] == 0 and '%Error' not in text, text[-4000:]
    executable = work/'obj/Vtb_hwic_simplestories'
    executable_sha256 = sha(executable.read_bytes())
    def run_case(item):
        name,case = item
        row,log = execute(work,name,[str(executable),*case['flags']],work/name)
        if args.fault_weight:
            row['passed_expected_fault_detection'] = row['exit'] != 0 and 'TENSOR_MISMATCH' in log
            assert row['passed_expected_fault_detection'], log[-3000:]
        else:
            assert row['exit'] == 0 and not re.search(r'%Error|%Fatal|Assertion failed|Aborting|WATCHDOG|TENSOR_MISMATCH|TOKEN_MISMATCH|PRIVATE_CACHE_',log)
            assert len(re.findall(r'^PASS_HWIC_MODEL ',log,re.M)) == 1
            assert 'tensor_values='+str(case['tensor_values'])+' ' in log
            tokens = [int(t) for t in re.findall(r'^HWIC_TOKEN .* token=(\d+) ',log,re.M)]
            assert tokens == case['generated_tokens']+case['replay_tokens']
            row.update(passed_numerical_case=True, exact_tokens=tokens, selected_tensor_checks=case['tensor_values'])
        return name,row
    with ThreadPoolExecutor(max_workers=args.sim_jobs) as pool:
        results = dict(pool.map(run_case,cases.items()))
    assert all(sha((work/name).read_bytes()) == digest for name,digest in source_pins.items())
    assert sha(executable.read_bytes()) == executable_sha256
    for name,case in cases.items():
        assert sha((work/name/'expected.memh').read_bytes()) == case['expected_sha256']
    own_usage = resource.getrusage(resource.RUSAGE_SELF)
    result = dict(passed=True, kind='expected_manufacturing_fault_detection' if args.fault_weight else 'complete_RTL_numerical_replay',
        smoke_only=args.smoke, current_RTL_sources_unchanged=True, independent_expected_tensors_unchanged=True,
        executable_sha256=executable_sha256, provenance_sha256=sha((ROOT/'PROVENANCE.json').read_bytes()),
        runner_sha256=sha(Path(__file__).read_bytes()), reference=ref, build=build, cases=results,
        exact_token_count=0 if args.fault_weight else sum(len(v['exact_tokens']) for v in results.values()),
        selected_tensor_checks=0 if args.fault_weight else sum(v['selected_tensor_checks'] for v in results.values()),
        wall_seconds=time.monotonic()-began, controller_CPU_user_seconds=own_usage.ru_utime-self_before.ru_utime,
        controller_CPU_system_seconds=own_usage.ru_stime-self_before.ru_stime, no_paid_services=True,
        timing_scope='Per-child wait4 usage;controllerCPU excludes children. Whole-run wall overlaps children and is not added to leaf times.',
        ASIC_qualified=False, scope='Actual complete sealed RTL with fresh separately generated integer fixtures. '
            'Model data is fixed before execution;host supplies no DUT arithmetic or memory service. '
            'Functional ROM/private SRAM models do not qualify physical ASIC memories,timing,power or physical security.')
    save(work/'FINISHED.json',result)
    print(json.dumps(dict(passed=True,kind=result['kind'],cases=len(results),tokens=result['exact_token_count'],
        selected_checks=result['selected_tensor_checks'],ASIC_qualified=False)),flush=True)


if __name__ == '__main__':
    main()
