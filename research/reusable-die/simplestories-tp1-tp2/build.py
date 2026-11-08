"""Build the rank wrapper with the SimpleStories projection multiplier."""
import os
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
DEFAULT = HERE.parents[2] / 'demos' / 'simplestories-v2-5m'
PUBLIC = Path(os.environ.get('SIMPLESTORIES_RELEASE', DEFAULT)).resolve()
LANE = 'hardware/project/fpga/token_only_model0_ddr_board1/unified_dsp0/rtl/board1_unified_projection_head_mul_exact.sv'

def build():
    if sys.byteorder != 'little':
        raise ValueError('Packet and Verilator port adapter require a little-endian host')
    gen = HERE / 'build' / 'gen'
    gen.mkdir(exist_ok=True, parents=True)
    # Local relative path keeps make-style source lists free of workspace spaces.
    shutil.copyfile(PUBLIC / LANE, gen / 'lane.sv')
    vroot = Path(subprocess.check_output(['verilator','--getenv','VERILATOR_ROOT'],text=True).strip())
    inc = vroot / 'include'
    subprocess.run(['verilator','--cc','--top-module','rank_model','--Mdir','build/gen',
                    'rank.sv','build/gen/lane.sv'],cwd=HERE,check=True)
    lib = HERE / 'build' / ('rank.dylib' if sys.platform == 'darwin' else 'rank.so')
    flags = ['-dynamiclib'] if sys.platform == 'darwin' else ['-shared','-fPIC']
    subprocess.run(['c++','-std=c++20','-O2','-DVL_TIME_CONTEXT',*flags,'-pthread','-I'+str(gen),'-I'+str(inc),
                    '-I'+str(inc/'vltstd'),*map(str,sorted(gen.glob('Vrank_model*.cpp'))),
                    str(inc/'verilated.cpp'),str(inc/'verilated_threads.cpp'),str(HERE/'native.cpp'),
                    '-o',str(lib)],check=True,cwd=HERE)
    return lib

if __name__ == '__main__':
    build()
