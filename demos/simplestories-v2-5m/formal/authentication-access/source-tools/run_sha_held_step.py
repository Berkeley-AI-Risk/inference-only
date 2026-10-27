"""FIPS refinement for encrypted boot/KV one-round, owner-held SHA engines."""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_held_sha_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--role',choices=('boot','kv'),default='boot');p.add_argument('--timeout',type=int,default=90)
    args=p.parse_args();common=load('bindings',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    ref=load('reference',HERE/'fips180_4.py')
    _,directory,bound=common.binding(args.package,'encrypted-memory')
    original=(directory/'project/sha.sv').read_bytes();top='board1_sha256_owner_held_'+args.role+'_compress'
    functions=(HERE/'sha-compact-reference-monitor.inc.sv').read_text().split('    logic [31:0] f_ring_q',1)[0]
    constants='    function automatic [31:0] f_k(input [5:0] t);\n        case(t)\n'
    constants+=''.join(f"            6'd{n}: f_k=32'h{k:08x};\n"for n,k in enumerate(ref.K))
    constants+="            default: f_k=32'h0;\n        endcase\n    endfunction"
    functions=functions.replace('__REFERENCE_K_FUNCTION__',constants)
    monitor=(HERE/'sha-held-step-monitor.inc.sv').read_text().replace('__REFERENCE_FUNCTIONS__',functions)
    source=original.decode();start=source.index('module '+top+' (');end=source.index('\nendmodule',start)
    source=source[:end]+'\n'+monitor+source[end:]
    files={'sha.sv':b'`undef FORMAL\n'+source.encode(),'production-sha.sv':original,
        'reference-monitor.inc.sv':monitor.encode(),'reference.py':(HERE/'fips180_4.py').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    cover='';block=b'abc'+b'\x80'+b'\x00'*52+(24).to_bytes(8,'big')
    iv='6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19'
    for i in range(2,72):
        cover+=f'state {i}\nassume (= [reset_n_i] true)\nassume (= [start_i] '+('true'if i==2 else'false')+')\n'
        cover+='assume (= [state_i] #x'+iv+')\n'
        if i==2:cover+='assume (= [block_i] #x'+block.hex()+')\n'
    binding=dict(native_join=bound,variant='encrypted-memory',role=args.role,
        production_path='project/sha.sv',production_sha256=hashlib.sha256(original).hexdigest(),
        accepted_block_and_chain_arbitrary=True,state_input_unrestricted_during_safety_and_induction=True,
        resetless_native_working_registers_retained=True,owner_contract_discharge_pending=True)
    return engine.check(args.run,files,top=top,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=monitor.count('assert('),covers=1,binding=binding,cuts=[],
        scope='Actual resetless-payload one-round private compressor: FIPS initial-load and all sixty-four round/schedule transitions, progress and exact live-chain feed-forward. No owner promise is assumed. Actual owner chain preservation is a separate composition obligation; arbitrary data values and later input changes remain free. No cryptographic-hardness or physical theorem.',
        depth=5,induction_depth=3,cover_depth=72,cover_constraints=cover,timeout=args.timeout,
        solver_cli={s:['--unroll']for s in('z3','cvc5')},source_list=['sha.sv'],
        map_literal_roms=True,optimize_full=True)


if __name__=='__main__':raise SystemExit(main())
