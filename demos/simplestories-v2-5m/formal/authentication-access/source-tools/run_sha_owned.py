"""Native baseline/seeded private two-round SHA work/result correspondence."""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
TOP='board1_sha256_bank_owned_compress'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_owned_sha_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=120)
    args=p.parse_args()
    common=load('bindings',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    ref=load('reference',HERE/'fips180_4.py')
    original=None;joins={}
    for variant in ('baseline','seeded-sampling'):
        _,directory,bound=common.binding(args.package,variant)
        raw=(directory/'project/sha.sv').read_bytes()
        if original is not None and original!=raw:raise ValueError('Claimed native SHA identity changed')
        original=raw;joins[variant]=bound
        if 'board1_sha256_bank_owned_compress #(.REGISTER_RESULT(0)) u_sha'not in (directory/'project/bank.sv').read_text():
            raise ValueError('Native page-bank result mode changed')
    functions=(HERE/'sha-compact-reference-monitor.inc.sv').read_text().split('    logic [31:0] f_ring_q',1)[0]
    constants='    function automatic [31:0] f_k(input [5:0] t);\n        case(t)\n'
    constants+=''.join(f"            6'd{n}: f_k=32'h{k:08x};\n"for n,k in enumerate(ref.K))
    constants+="            default: f_k=32'h0;\n        endcase\n    endfunction"
    functions=functions.replace('__REFERENCE_K_FUNCTION__',constants)
    monitor=(HERE/'sha-owned-reference-monitor.inc.sv').read_text().replace('__REFERENCE_FUNCTIONS__',functions)
    source=original.decode();start=source.index('module '+TOP+' #(');end=source.index('\nendmodule',start)
    source=source[:end]+'\n'+monitor+source[end:]
    files={'sha.sv':b'`undef FORMAL\n'+source.encode(),'production-sha.sv':original,
        'reference-monitor.inc.sv':monitor.encode(),'reference.py':(HERE/'fips180_4.py').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    cover=''
    block=b'abc'+b'\x80'+b'\x00'*52+(24).to_bytes(8,'big')
    iv='6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19'
    for i in range(2,40):
        cover+=f'state {i}\nassume (= [reset_n_i] true)\nassume (= [start_i] '+('true'if i==2 else'false')+')\n'
        cover+='assume (= [state_i] #x'+iv+')\n'
        if i==2:cover+='assume (= [block_i] #x'+block.hex()+')\n'
    binding=dict(native_joins=joins,production_path='project/sha.sv',production_sha256=hashlib.sha256(original).hexdigest(),
        result_mode=0,native_bank_result_mode_checked=True,accepted_block_and_chain_arbitrary=True,
        state_input_unrestricted_during_safety_and_induction=True,owner_contract_discharge_pending=True,
        reference_standard='FIPS 180-4 sections 4.1.2, 4.2.2 and 6.2.2')
    scope=('Actual baseline/seeded two-round private SHA compressor in its native REGISTER_RESULT=0 mode. '
        'Prove complete sixty-four-round work-state correspondence against the independent circular FIPS '
        'reference for arbitrary accepted blocks/chaining state and later input changes, and the exact '
        'live-input feed-forward relation at DONE. Digest correctness for the accepted chain additionally '
        'requires the parent to preserve that chain at DONE; that composition is NOT established here. '
        'No private owner assumption, arithmetic replacement or internal cut. The finite ABC cover holds '
        'the chain as a legal transaction witness only; those conditions do not enter safety or induction. '
        'Protected/encrypted DSP-adder implementations require separate proof and native primitive binding.')
    return engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=monitor.count('assert(')+15,covers=1,binding=binding,scope=scope,cuts=[],
        depth=5,induction_depth=3,cover_depth=40,cover_constraints=cover,timeout=args.timeout,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},source_list=['sha.sv'],map_literal_roms=True)


if __name__=='__main__':raise SystemExit(main())
