"""Native K/V guard control for unrestricted private hash/DDR replies.

This retains the actual tag, partial and staging RAMs. It proves control and
interface restrictions independently of the hash child; checked-data RAM
correspondence and hash framing require their separate compositions.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_guard_control_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--variant',choices=('kv-protected','encrypted-memory'),default='kv-protected')
    p.add_argument('--timeout',type=int,default=45);p.add_argument('--mutant',choices=('wrong-write-address','wrong-epoch-step'))
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    _,directory,bound=common.binding(args.package,args.variant)
    original=(directory/'project/kv_integrity_guard.sv').read_bytes();source=original.decode()
    if args.mutant:
        before,after=('m_wr_shadow=address(layer_q,position_q,{1\'b0,head_q},row_word_q);',
            'm_wr_shadow=address(layer_q,position_q,{1\'b0,head_q},row_word_q)^19\'d1;')if args.mutant=='wrong-write-address'else(
            "epoch_q<=epoch_q+1'b1;","epoch_q<=epoch_q+64'd2;")
        if source.count(before)!=1:raise ValueError('Native guard sensitivity site changed')
        source=source.replace(before,after,1)
    matches=list(re.finditer(r'    kv_page_hash u_hash\([\s\S]*?\);',source))
    if len(matches)!=1:raise ValueError('Actual private hash child boundary changed')
    match=matches[0];removed=match[0]
    replacement='    assign hash_begin_ready=f_hash_begin_ready_i;\n    assign hash_word_ready=f_hash_word_ready_i;\n'
    replacement+='    assign hash_digest_valid=f_hash_digest_valid_i;\n    assign hash_digest=f_hash_digest_i;\n    assign hash_fault=f_hash_fault_i;'
    source=source[:match.start()]+replacement+source[match.end():]
    ports=',\n    input wire f_hash_begin_ready_i,f_hash_word_ready_i,f_hash_digest_valid_i,f_hash_fault_i,\n    input wire [255:0] f_hash_digest_i'
    source=source.replace('\n);',ports+'\n);',1)
    monitor=(HERE/'kv-guard-control-monitor.inc.sv').read_text()
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    top='board1_kv_integrity_guard'if args.variant=='kv-protected'else'tang_kv_integrity_guard_epoch'
    files={'guard.sv':b'`undef FORMAL\n'+source.encode(),'production-guard.sv':original,
        'monitor.inc.sv':monitor.encode(),'removed-hash-instance.sv.txt':removed.encode(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    stimulus=''
    for state in range(2,24):
        stimulus+=f'state {state}\nassume (= [reset_n] true)\nassume (= [model_locked_i] true)\nassume (= [upstream_fault_i] false)\n'
        stimulus+='assume (= [clear_i] '+('true'if args.mutant=='wrong-epoch-step'and state==2 else'false')+')\n'
        stimulus+='assume (= [s_wr_valid] '+('true'if args.mutant!='wrong-epoch-step'and state==2 else'false')+')\n'
        for name,value in(('s_rd_valid',False),('s_wr_cpl_ready',False),('s_rd_rsp_ready',True),('m_wr_ready',True),
                ('m_wr_cpl_valid',state==4),('m_wr_cpl_fault',False),('m_rd_ready',True),('m_rd_rsp_valid',False),('m_rd_rsp_fault',False),
                ('f_hash_begin_ready_i',True),('f_hash_word_ready_i',True),('f_hash_digest_valid_i',False),('f_hash_fault_i',False)):
            stimulus+='assume (= ['+name+'] '+('true'if value else'false')+')\n'
        for name,width,value in(('s_wr_layer',3,0),('s_wr_position',12,0),('s_wr_head',2,0),('s_wr_word',4,0),
                ('s_wr_shadow',19,227072),('s_wr_data',256,0),('f_hash_digest_i',256,0)):
            stimulus+=f'assume (= [{name}] (_ bv{value} {width}))\n'
    reset='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    cuts=[dict(instance='u_hash',output=n,replacement='unrestricted private input',assumptions=[])for n in('begin_ready','word_ready','digest_valid','digest','fault')]
    return engine.check(args.run,files,top=top,reset_constraints=reset+(stimulus if args.mutant else''),
        assertions=monitor.count('assert('),covers=2,binding=dict(native_join=bound,variant=args.variant,
            production_source_sha256=hashlib.sha256(original).hexdigest(),actual_native_all_RAMS_retained=True,
            private_hash_and_DDR_replies_unrestricted=True,child_behavior_assumptions=[]),cuts=cuts,
        depth=8 if args.mutant else 5,induction_depth=3,cover_depth=24,cover_constraints=stimulus,timeout=args.timeout,mutant=args.mutant,
        source_list=['guard.sv'],optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native protected K/V guard control with native timeout and tag/partial/stage RAMs. Epoch saturation, typed-address arithmetic, single owner, cancellation, output gating, cache verification event and request identity are checked independently of every private hash/DDR reply. No caller protocol or payload promise. Actual trusted-tag and same-staging-RAM data correspondence, hash composition, machine capture, cryptographic hardness, physical and whole-device training guarantees require separate evidence.')


if __name__=='__main__':raise SystemExit(main())
