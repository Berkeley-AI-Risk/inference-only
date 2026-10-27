"""Universal native compact-SHA correspondence to a circular FIPS reference."""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
TOP='board1_sha256_compact_compress'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_auth_access_'+name,path)
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--mutant',choices=('wrong-round-constant','wrong-schedule-tap','wrong-result-lane'))
    args=parser.parse_args()
    common=load('run_handoff',OLD/'run_handoff.py')
    engine=load('engine',HERE/'engine.py')
    ref=load('fips180_4',HERE/'fips180_4.py')
    joins={}; original=None
    for variant in ('baseline','seeded-sampling'):
        _,root,bound=common.binding(args.package,variant)
        raw=(root/'project/sha.sv').read_bytes()
        if original is not None and original!=raw:raise ValueError('Selected SHA sources differ')
        original=raw; joins[variant]=bound
    constants='    function automatic [31:0] f_k(input [5:0] t);\n        case(t)\n'
    constants+=''.join(f"            6'd{n}: f_k=32'h{k:08x};\n" for n,k in enumerate(ref.K))
    constants+="            default: f_k=32'h00000000;\n        endcase\n    endfunction"
    monitor=(HERE/'sha-compact-reference-monitor.inc.sv').read_text()
    if monitor.count('__REFERENCE_K_FUNCTION__')!=1:raise ValueError('Reference template changed')
    monitor=monitor.replace('__REFERENCE_K_FUNCTION__',constants)
    source=original.decode()
    if args.mutant:
        cases={
            'wrong-round-constant':("6'd0:  round_constant = 32'h428a2f98;","6'd0:  round_constant = 32'h428a2f99;"),
            'wrong-schedule-tap':('small_sigma1(schedule_q[14]) + schedule_q[9] +','small_sigma1(schedule_q[13]) + schedule_q[9] +'),
            'wrong-result-lane':('initial_state_q[255:224] + next_a,','initial_state_q[255:224] + next_e,'),
        }
        before,after=cases[args.mutant]
        if source.count(before)<1:raise ValueError('Mutation source boundary changed')
        source=source.replace(before,after,1)
    start=source.index('module '+TOP+' (')
    end=source.index('\nendmodule',start)
    source=source[:end]+'\n'+monitor+source[end:]
    files={'sha.sv':b'`undef FORMAL\n'+source.encode(),'production-sha.sv':original,
        'reference-monitor.inc.sv':monitor.encode(),'reference.py':(HERE/'fips180_4.py').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    binding=dict(native_joins=joins,production_path='project/sha.sv',production_sha256=hashlib.sha256(original).hexdigest(),
        reference_standard='FIPS 180-4 sections 4.1.2, 4.2.2 and 6.2.2',
        reference_url='https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf',
        accepted_block_and_chaining_state_arbitrary=True,no_state_hold_contract=True,
        source_compressor_unmodified=args.mutant is None,read_only_reference=True)
    scope=('Actual native compact one-round SHA-256 compressor, full sixteen-word schedule and eight '
        'working words, against an independent circular-schedule/packed-word FIPS reference. Arbitrary '
        'input blocks and chaining state at every accepted START, arbitrary later input changes and '
        'busy START offers, arbitrary digital reset cancellation. Prove complete state/result/control '
        'correspondence by base and induction; accepted transactions complete after all 64 rounds. '
        'No internal data cut, no digest oracle, no arithmetic assumption. This is not yet the page-bank '
        'multi-round compressor, SHA stream composition, image authentication, collision resistance '
        'or a physical implementation theorem.')
    return engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=16+13,covers=1,binding=binding,scope=scope,cuts=[],depth=5,induction_depth=3,
        cover_depth=70,timeout=args.timeout,source_list=['sha.sv'],mutant=args.mutant,map_literal_roms=True)


if __name__=='__main__':raise SystemExit(main())
