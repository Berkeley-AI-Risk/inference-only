"""Prove the actual flash reader emits the fixed read header on SPI pins."""
import argparse
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location('_assurance_'+name,HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    common,engine = load('run_handoff'),load('engine')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),required=True)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--mutant',choices=('program-opcode','change-flash-address'))
    args = parser.parse_args()
    pin,root,bound = common.binding(args.package.resolve(),args.variant)
    relative = 'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_qspi_read03_master.sv'
    original = (root/relative).read_bytes()
    source = original.decode()
    if args.mutant:
        old,new = (('READ_OPCODE = 8\'h03','READ_OPCODE = 8\'h02') if args.mutant == 'program-opcode' else
                   ('IMAGE_BASE = 24\'h801000','IMAGE_BASE = 24\'h801020'))
        if source.count(old) != 1:
            raise ValueError('Flash mutation boundary changed')
        source = source.replace(old,new)
    monitor = (HERE/'qspi-monitor.inc.sv').read_bytes()
    if source.count('\nendmodule') != 1 or monitor.count(b'assert(') != 24 or monitor.count(b'cover(') != 2:
        raise ValueError('Flash proof inventory changed')
    source = b'`undef FORMAL\n'+source.encode().replace(b'\nendmodule',b'\n'+monitor+b'\nendmodule')
    files = {'qspi.sv':source,'production-qspi.sv':original,'monitor.inc.sv':monitor,
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),
        'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    # Directed inputs are used for cover witnesses only. Safety base/induction
    # retain arbitrary START, READY, flash data and subsequent reset values.
    cover_stimulus = ''.join(f'state {step}\nassume (= [start_i] {"true" if step == 2 else "false"})\n'
        'assume (= [data_ready_i] true)\n'+('assume (= [reset_n_i] true)\n' if step >= 2 else '')
        for step in range(180))
    return engine.check(args.run,files,top='board1_context2048_qspi_read03_master',
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=24,covers=2,binding=dict(variant=args.variant,**bound),cuts=[],depth=12,induction_depth=8,
        cover_depth='162:180',cover_constraints=cover_stimulus,secondary_cover_witness=True,timeout=120,
        mutant=args.mutant,
        scope='Actual immutable flash SPI reader, complete production byte count and start/ready/data ports arbitrary. The actual 32 rising header edges carry 0x03 and fixed address 0x801000, then MOSI is released for reads. No flash program/erase opcode. Does not authenticate read bytes, prove flash-controller physics, model-data numerical correctness or boot-stream composition.')


if __name__ == '__main__':
    raise SystemExit(main())
