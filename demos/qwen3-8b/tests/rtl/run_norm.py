"""Finite released RMSNorm regression; no model, hardware or network access."""
import argparse
from datetime import datetime, timezone
import importlib.util
import json
import os
from pathlib import Path
import shutil
import time

HERE = Path(__file__).resolve().parent
HELPER_SHA = '49dd774fc968ad97a516b8ab30c993a9ed865811428aec572701a6a33e5a8da0'
SPEC = importlib.util.spec_from_file_location('qwen_arithmetic_helpers', HERE/'run.py')
HELPER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(HELPER)
SOURCES = ('HardFloat_primitives.v', 'HardFloat_specialize.v', 'HardFloat_rawFN.v',
           'fNToRecFN.v', 'recFNToRecFN.v', 'recFNToFN.v', 'isSigNaNRecFN.v',
           'mulRecFN.v', 'addRecFN.v', 'divSqrtRecFN_small.v',
           'qwen_fp32_mul_stage.sv', 'qwen_rms_norm.sv')
CASE = dict(name='rmsnorm', top='qwen_rms_norm', sources=SOURCES,
            headers=HELPER.HEADERS, bench='rmsnorm.cpp', widths=[128,4096])
need, identity, save = HELPER.need, HELPER.identity, HELPER.save


def verify_sources():
    need(identity(HERE/'run.py')['sha256'] == HELPER_SHA, 'Frozen helper changed; review before reuse')
    binding = HELPER.verify_sources([CASE])
    source = (HELPER.ROOT/'hardware/design/qwen_rms_norm.sv').read_text()
    need("12'd127 : 12'd4095" in source and 'two BF16 rounding boundaries' in source,
         'Production RMS widths/rounding contract changed')
    return binding


def validate_summary(result):
    need(result.get('passed') is True, 'Native RMSNorm test did not succeed')
    need(all(type(v) is int and v >= 0 for k,v in result.items() if k != 'passed'),
         'Native counts must be nonnegative integers')
    exact = dict(normal_frames=26, head_frames=13, full_frames=13, error_frames=8,
                 cancelled_frames=6, checked_values=54934, clears=4, resets=2)
    need(all(result.get(k) == v for k,v in exact.items())
         and all(result.get(k,0)>0 for k in ('held_checks','input_bubbles','accepted_inputs','cycles')),
         'Incomplete RMSNorm finite arithmetic/protocol workload')


def run(output, binding, verilator, jobs):
    folder=output/'rmsnorm'
    folder.mkdir()
    source=folder/'source'
    source.mkdir()
    inputs={}
    for name in SOURCES+HELPER.HEADERS:
        shutil.copyfile(HELPER.ROOT/'hardware/design'/name, source/name)
        need(identity(source/name) == binding['files'][name], 'Staged RTL input changed')
        inputs[name]=identity(source/name)
    shutil.copyfile(HERE/'rmsnorm.cpp', source/'rmsnorm.cpp')
    inputs['rmsnorm.cpp']=identity(HERE/'rmsnorm.cpp')
    need(identity(source/'rmsnorm.cpp') == inputs['rmsnorm.cpp'], 'Bench changed during staging')
    flags='-std=c++17 -O2 -ffp-contract=off -frounding-math -fno-fast-math'
    argv=[str(verilator), '--cc', '--exe', '--build', '--assert', '-Wno-fatal',
          '--top-module','qwen_rms_norm','-j',str(jobs),'-Mdir',str(folder/'build'),
          '-I'+str(source),'-CFLAGS',flags]
    argv += [str(source/name) for name in SOURCES]+[str(source/'rmsnorm.cpp')]
    save(folder/'INPUTS.json',dict(case=CASE,source_files=inputs,compiler_flags=flags))
    build=HELPER.command(argv,folder,folder/'compile',180)
    binary=folder/'build/Vqwen_rms_norm'
    binary_id=identity(binary)
    execute=HELPER.command([str(binary)],folder,folder/'execute',60)
    result=json.loads((folder/'execute/stdout.log').read_text())
    validate_summary(result)
    need(all(identity(source/name)==value for name,value in inputs.items()), 'Native inputs changed')
    need(identity(binary)==binary_id, 'Native binary changed')
    record=dict(passed=True,finite_regression_only=True,checks=result,binary=binary_id,
                source_files=inputs,compile=build,execute=execute)
    save(folder/'FINISHED.json',record)
    return record


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--plan',action='store_true')
    p.add_argument('--output',type=Path)
    p.add_argument('--jobs',type=int,choices=(1,2),default=1)
    p.add_argument('--verilator',type=Path)
    args=p.parse_args(argv)
    binding=verify_sources()
    if args.plan:
        print(json.dumps(dict(case=CASE,binding=binding,native_tools_run=False,model_loaded=False,
                              hardware_access=False,network_access=False),indent=2))
        return 0
    need(args.output is not None,'Choose a fresh --output directory')
    output=args.output.resolve()
    need(not output.exists() and not any(c.isspace() for c in str(output))
         and not output.is_relative_to(HELPER.ROOT.resolve()),'Output must be fresh, whitespace-free and outside the demo')
    executable=args.verilator or shutil.which('verilator')
    need(executable is not None,'Install Verilator normally; no automatic download')
    verilator=Path(executable).resolve()
    need(verilator.is_file() and os.access(verilator,os.X_OK),'Verilator executable unavailable')
    output.mkdir()
    record=dict(started_utc=datetime.now(timezone.utc).isoformat(),binding=binding,
                runner=identity(Path(__file__)),helper=identity(HERE/'run.py'),
                verilator=identity(verilator),compiler_jobs=args.jobs,automatic_retry=False,
                FPGA_accessed=False,AWS_accessed=False,model_loaded=False,
                scope='Finite 128/4096 RMSNorm arithmetic and local synchronous protocol only; no full-core, CDC, authentication, timing or security qualification.')
    save(output/'STARTED.json',record)
    tick=time.monotonic()
    try:
        HELPER.command([str(verilator),'--version'],output,output/'tool-version',10)
        record['result']=run(output,binding,verilator,args.jobs)
        need(verify_sources()==binding,'Original source binding changed')
    except BaseException as error:
        record.update(passed=False,error=dict(type=type(error).__name__,message=str(error)),
                      elapsed_seconds=time.monotonic()-tick)
        save(output/'FAILED.json',record)
        raise
    record.update(passed=True,elapsed_seconds=time.monotonic()-tick)
    save(output/'FINISHED.json',record)
    print(json.dumps(dict(output=str(output),passed=True,elapsed_seconds=record['elapsed_seconds'],
                          checks=record['result']['checks'],finite_regression_only=True),indent=2))
    return 0


if __name__=='__main__':
    raise SystemExit(main())
