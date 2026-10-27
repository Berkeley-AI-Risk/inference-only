"""Native byte/block/chaining correspondence under a discharged caller premise."""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
TOP='board1_sha256_compact_padded_stream'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_stream_proof_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--variant',choices=('baseline','encrypted-memory'),default='baseline')
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    _,directory,bound=common.binding(args.package,args.variant)
    original=(directory/'project/sha.sv').read_bytes();monitor=(HERE/'sha-stream-monitor.inc.sv').read_text()
    if args.variant=='encrypted-memory':
        monitor=monitor.replace('logic [503:0] f_bytes_q;','logic [511:0] f_bytes_q;')
        monitor=monitor.replace('{f_bytes_q[495:0],byte_data_i}','{f_bytes_q[503:0],byte_data_i}')
        monitor=monitor.replace('{f_bytes_q,byte_data_i}','{f_bytes_q[503:0],byte_data_i}')
        monitor=monitor.replace('compress_block_q','block_buffer_q')
        monitor+='''
    logic f_child_owned_q;
    logic [511:0] f_child_block_q;
    logic [255:0] f_child_chain_q;
    always_ff @(posedge clk_i or negedge reset_n_i) begin
        if(!reset_n_i) begin f_child_owned_q<=0;f_child_block_q<=0;f_child_chain_q<=0;end
        else if(compress_start_q && !compress_busy) begin
            f_child_owned_q<=1;f_child_block_q<=block_buffer_q;f_child_chain_q<=compress_state_q;
        end else if(compress_done) f_child_owned_q<=0;
    end
    always_ff @(posedge clk_i) if(reset_n_i && (compress_busy || compress_done)) begin
        assert(f_child_owned_q);
        assert(block_buffer_q==f_child_block_q);
        assert(compress_state_q==f_child_chain_q);
    end
'''
    source=original.decode();a=source.index('module '+TOP+' (');b=source.index('\nendmodule',a)
    source=source[:b]+'\n'+monitor+source[b:]
    files={'sha.sv':b'`undef FORMAL\n'+source.encode(),'production-sha.sv':original,
        'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    cover='';block=b'abc'+b'\x80'+b'\x00'*52+(24).to_bytes(8,'big')
    for state in range(2,140):
        cover+=f'state {state}\nassume (= [reset_n_i] true)\n'
        cover+='assume (= [begin_i] '+('true'if state==2 else'false')+')\n'
        cover+='assume (= [byte_valid_i] '+('true'if 3<=state<=66 else'false')+')\n'
        cover+='assume (= [byte_last_i] '+('true'if state==66 else'false')+')\n'
        if 3<=state<=66:cover+=f'assume (= [byte_data_i] (_ bv{block[state-3]} 8))\n'
    binding=dict(native_join=bound,production_path='project/sha.sv',production_sha256=hashlib.sha256(original).hexdigest(),
        variant=args.variant,actual_child='board1_sha256_owner_held_boot_compress'if args.variant=='encrypted-memory'else'board1_sha256_compact_compress',
        owner_held_chain_and_block_premises_proved=args.variant=='encrypted-memory',
        complete_actual_compressor=True,internal_data_cuts=[],
        client_premise='At most one asserted BEGIN after reset, until the next reset.',
        client_premise_asserted_in_caller='image-auth-monitor.inc.sv f_begin_seen_q and sha_begin',
        caller_runs=['image-auth-baseline-r4-once','image-auth-protected-r2-once','image-auth-encrypted-r2-once'])
    scope=('Actual byte-stream wrapper with the complete native compact compressor. Prove ordered '
        'big-endian block formation, initial chaining state, exact block/chain presentation at START, '
        'and final-only digest exposure. The single protocol premise is one BEGIN per hard-reset '
        'epoch, proved independently for the actual image-auth caller. All byte values, valid/last '
        'patterns and stalls are otherwise arbitrary. The caller supplies SHA padding and that '
        'separate fixed-length/padding proof is required for a complete message claim. No digest '
        'oracle or arithmetic cut; compressor arithmetic has its independent source-identical proof.')
    return engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=monitor.count('assert('),covers=2,expected_assumptions=1,binding=binding,scope=scope,cuts=[],
        depth=7,induction_depth=3,cover_depth=140,cover_constraints=cover,timeout=args.timeout,
        source_list=['sha.sv'],map_literal_roms=True,optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')})


if __name__=='__main__':raise SystemExit(main())
