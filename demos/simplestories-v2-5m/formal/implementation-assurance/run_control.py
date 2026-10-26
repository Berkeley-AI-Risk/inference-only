"""Fresh current greedy UART/core/token-shell implementation proof.

Uses actual UART RX/TX, parser, adapter, core gates, shell, arithmetic and RAMs.
The six-layer private service has 37 explicitly unrestricted output boundaries.
"""
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
    common,model,engine = load('run_handoff'),load('control_model'),load('engine')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory'),required=True)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--mutant',choices=('bypass-kv-write-fault-gate','bypass-kv-read-fault-gate'))
    parser.add_argument('--secondary-base-only',action='store_true',help='Prove all 134 properties with Z3; use cvc5 for the base only. No cvc5 induction claim.')
    args = parser.parse_args()
    files,sources,binding = model.derive(args.package.resolve(),args.variant,common)
    if args.mutant:
        key = model.MACHINE_DIR+model.CORE_NAME+'.sv'
        lane = 'write' if args.mutant == 'bypass-kv-write-fault-gate' else 'read'
        old = f'assign kv_{lane}_req_valid_o = !root_terminal && child_kv_{lane}_req_valid;'.encode()
        new = f'assign kv_{lane}_req_valid_o = child_kv_{lane}_req_valid;'.encode()
        if files[key].count(old) != 1:
            raise ValueError('Fault-gate mutation site changed')
        files[key] = files[key].replace(old,new)
    if binding['assertions'] != 134 or len(binding['private_semantic_output_cuts']) != 37:
        raise ValueError('Reviewed connected controller scope changed')
    for name in ('control_model.py','CONTROL-SUPPORT.json','CONTROL-DERIVATION.json','CONTROL-DERIVATION.diff','run_handoff.py'):
        files[name] = (HERE/name).read_bytes()
    files['runner.py'] = Path(__file__).read_bytes()
    files['SOURCES.json'] = (HERE/'SOURCES.json').read_bytes()
    return engine.check(args.run,files,top=model.TOP,assertions=134,covers=0,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        binding=dict(variant=args.variant,**binding['native_binding'],control_composition=binding),
        scope='Joint current greedy production UART RX/TX217, parser, operation adapter, core authorization gates, full token shell, real local arithmetic and memories. Reproves 134 safety assertions with 37 arbitrary private six-layer service outputs. One constant tape-slot observer is read-only. Does not prove the numerical model, private memory/authentication composition, clock crossing, or bitstream equivalence.',
        cuts=binding['private_semantic_output_cuts'],depth=4,induction_depth=4,timeout=120,
        source_list=sources,observer_constants=1,expected_memories=17,solver_cli={'cvc5':['--unroll']},mutant=args.mutant,
        secondary_base_only=args.secondary_base_only)


if __name__ == '__main__':
    raise SystemExit(main())
