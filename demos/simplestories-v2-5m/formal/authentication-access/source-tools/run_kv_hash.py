"""Native K/V identity, payload, padding and live-chain ownership correspondence."""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import struct

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_kv_hash_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--variant',choices=('kv-protected','encrypted-memory'),default='kv-protected')
    p.add_argument('--timeout',type=int,default=60);p.add_argument('--mutant',choices=('wrong-role-header','wrong-word-byte-order'))
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    package=common.model_package(args.package);_,directory,bound=common.binding(args.package,args.variant)
    original={n:(directory/'project'/n).read_bytes()for n in('kv_page_hash.sv','sha.sv')}
    source=original['kv_page_hash.sv']
    if args.mutant:
        before,after=(b"31'd0,role_i,",b"31'd0,(role_i^1'b1),")if args.mutant=='wrong-role-header'else(
            b'value[8*i +:8]',b'value[255-8*i -:8]')
        if source.count(before)!=1:raise ValueError('Native K/V mutation site changed')
        source=source.replace(before,after,1)
    domain=struct.pack('>16s',b'IO-KV-ROLE-v2')
    header=struct.pack('>16sQIIIIIII12x',b'IO-KV-ROLE-v2',0,0,0,0,0,1,16,32)
    cover_digest=hashlib.sha256(header+bytes(160)).hexdigest()
    monitor=(HERE/'kv-hash-monitor.inc.sv').read_bytes().replace(b'@DOMAIN@',domain.hex().encode()).replace(b'@COVER_DIGEST@',cover_digest.encode())
    source=source.replace(b'\nendmodule',b'\n'+monitor+b'\nendmodule',1)
    files={'kv_page_hash.sv':b'`undef FORMAL\n'+source,'sha.sv':b'`undef FORMAL\n'+original['sha.sv'],
        **{'production-'+n:raw for n,raw in original.items()},'monitor.inc.sv':monitor,
        'reference-role-pages-model.py':(package/'simulation/kv-protected/role-pages/model.py').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    stimulus=''
    word=int.from_bytes(bytes(range(32)),'little')if args.mutant else 0
    for state in range(2,100 if args.mutant else 320):
        stimulus+=f'state {state}\nassume (= [reset_n] true)\nassume (= [clear_i] false)\n'
        stimulus+='assume (= [begin_valid_i] '+('true'if state==2 else'false')+')\n'
        stimulus+='assume (= [word_valid_i] true)\nassume (= [digest_ready_i] false)\n'
        for name,width,value in(('epoch_i',64,0),('layer_i',3,0),('page_i',7,0),('head_i',1,0),('role_i',1,0),('positions_i',5,1),('word_i',256,word)):
            stimulus+=f'assume (= [{name}] '+(('true'if value else'false')if width==1 else f'(_ bv{value} {width})')+')\n'
    reset='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    return engine.check(args.run,files,top='kv_page_hash',reset_constraints=reset+(stimulus if args.mutant else''),
        assertions=monitor.count(b'assert('),covers=2,binding=dict(native_join=bound,variant=args.variant,
            complete_actual_SHA_child=True,private_data_cuts=[],caller_protocol_assumptions=[],
            reference_header_format='>16sQIIIIIII12x',reference_domain=domain.hex(),
            one_position_zero_payload_cover_digest=cover_digest),cuts=[],depth=100 if args.mutant else 7,
        induction_depth=3,cover_depth=320,cover_constraints=stimulus,timeout=args.timeout,mutant=args.mutant,
        source_list=['sha.sv','kv_page_hash.sv'],map_literal_roms=True,optimize_full=True,
        solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native K/V page hash wrapper and complete native SHA. Identity header, accepted payload ordering, byte order, odd/even SHA padding, chaining, live-chain ownership, exact call count and final-only digest exposure for arbitrary callers and CLEAR patterns. No caller promise or digest/data oracle. Native compressor FIPS correspondence is independently proved; actual guard tag/cache/capture use is a separate composition. No cryptographic-hardness, physical, bitstream or whole-device training theorem.')


if __name__=='__main__':raise SystemExit(main())
