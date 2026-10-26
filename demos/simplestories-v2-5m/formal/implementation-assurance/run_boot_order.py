"""Actual fixed-length boot controller: write phase, readback, then LOCK.

All input ports remain arbitrary, including digest success. This checks the
controller sequencing that cannot be seen when the whole boot block is cut.
The model length and every address/control parameter are the native values.
"""
import argparse
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
SOURCE='project/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv'
MUTATIONS={
    'skip-model-load':('state_q <= ST_LOAD;','state_q <= ST_READBACK;'),
    'early-lock':('state_q <= ST_WAIT_SOURCE;','state_q <= ST_LOCKED;'),
}


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_order_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    common,engine=load('run_handoff'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--mutant',choices=tuple(MUTATIONS))
    args=parser.parse_args()
    _,root,bound=common.binding(args.package,'baseline')
    original=(root/SOURCE).read_bytes();source=original.decode()
    if source.count('\nendmodule')!=1:raise ValueError('Boot controller source boundary changed')
    for literal in ('parameter integer MODEL_WORDS = 227062','parameter integer ADDR_W = 19',
        'parameter integer SCRATCH_BASE_WORD = 227072','parameter integer SCRATCH_WORDS = 221184'):
        if source.count(literal)!=1:raise ValueError('Native boot controller geometry changed')
    joins={}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,r,b=common.binding(args.package,variant)
        if(r/SOURCE).read_bytes()!=original:raise ValueError('Native boot controller differs: '+variant)
        joins[variant]=b
    monitor=(HERE/'boot-order-monitor.inc.sv').read_text()
    if args.mutant:
        old,new=MUTATIONS[args.mutant]
        if source.count(old)!=1:raise ValueError('Boot-order mutation boundary changed')
        source=source.replace(old,new)
    source='`undef FORMAL\n'+source.replace('\nendmodule','\n'+monitor+'\nendmodule')
    files={'boot.sv':source.encode(),'production-boot.sv':original,'monitor.inc.sv':monitor.encode(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),
        'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    binding=dict(native_joins=joins,production_source=SOURCE,production_sha256=common.sha(original),
        model_words=227062,address_width=19,sha_engine_assumed_correct=False)
    scope=('Actual boot/lock controller: all 227062 words, native 19-bit addressing, no internal cuts '
        'or protocol assumptions. The source write phase precedes readback and cannot return after '
        'a boot read; LOCK requires the final readback response and completed sequence even if digest '
        'success is arbitrary. No digest algorithm/collision theorem, response provenance below this '
        'seam, FIFO/adapter composition or physical DDR theorem. Only early boot-write reachability '
        'is searched; full LOCK coverage would traverse the complete fixed model and is not claimed.')
    raise SystemExit(engine.check(args.run,files,top='board1_context2048_private_ddr_lock_bridge',
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=monitor.count('assert('),covers=1,binding=binding,scope=scope,cuts=[],
        depth=14,induction_depth=8,cover_depth=16,timeout=args.timeout,
        expected_memories=0,solver_cli={'cvc5':['--unroll']},mutant=args.mutant))


if __name__=='__main__':main()
