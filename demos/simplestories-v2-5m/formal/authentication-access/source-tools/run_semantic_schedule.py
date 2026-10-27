"""Actual six-layer sequencer: fixed schedule and private vector admission."""
import argparse
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
REL='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv'


def load(name,path):
    s=importlib.util.spec_from_file_location('_semantic_schedule_'+name,path)
    m=importlib.util.module_from_spec(s);s.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True);p.add_argument('--variant',default='kv-protected')
    p.add_argument('--timeout',type=int,default=45);p.add_argument('--mutant',choices=('skip-stage',))
    args=p.parse_args();common=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,bound=common.binding(args.package,args.variant);original=(native/REL).read_bytes();source=original.decode()
    if args.mutant:
        a="stage_q <= stage_q + 1'b1;";b="stage_q <= stage_q + 2'd2;"
        if source.count(a)!=1:raise ValueError('Actual stage transition changed')
        source=source.replace(a,b,1)
    monitor=(HERE/'semantic-schedule-monitor.inc.sv').read_text()
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files={'sequence.sv':b'`undef FORMAL\n'+source.encode(),'production-sequence.sv':original,
        'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'engine.py')
    reset='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'
    if args.mutant:
        # This concrete legal stream is only a negative witness. No such
        # caller promise is present in a positive base or induction theorem.
        for step in range(2,264):
            reset+=f'state {step}\n'
            for name,value in [('rst_n',True),('clear_i',False),('model_lock_i',True),('upstream_fault_i',False),
                    ('start_valid_i',step==2),('input_valid_i',3<=step<=258),('input_last_i',step==258),
                    ('private_stage_ready_i',True),('private_stage_done_i',step==260),('private_stage_fault_i',False),
                    ('result_ready_i',True),('done_ready_i',True)]:
                reset+='assume (= ['+name+'] '+('true'if value else'false')+')\n'
            for name,width,value in [('fixed_position_i',11,0),('input_exponent_i',8,0),
                    ('input_index_i',8,step-3 if 3<=step<=258 else 0),('input_mantissa_i',16,0),
                    ('private_result_mantissa_i',16,0),('private_result_exponent_i',8,0),('committed_prefixes_i',72,0)]:
                reset+=f'assume (= [{name}] (_ bv{value} {width}))\n'
    return engine.check(args.run,files,top='board1_context2048_semantic_sequence',
        reset_constraints=reset,
        assertions=monitor.count('assert('),covers=2,binding=dict(native_join=bound,variant=args.variant,
            actual_sequence_retained=True,all_private_callers_and_datapath_replies_unrestricted=True),cuts=[],
        depth=264 if args.mutant else 10,induction_depth=3,cover_depth=12,timeout=args.timeout,mutant=args.mutant,
        source_list=['sequence.sv'],optimize_full=True,
        solver_cli={s:(['--unroll','-t','260:264']if args.mutant else['--unroll'])for s in('z3','cvc5')},
        scope='Actual immutable six-layer sequencer; all private stream, completion, prefix, and numerical replies unrestricted. Proves ordered ingress and fixed stage/layer descriptors, exclusive ownership and response gates. Data bytes are arbitrary at the private interface; token-to-ingress and datapath implementation connections require their separate source-bound joins.')


if __name__=='__main__':raise SystemExit(main())
