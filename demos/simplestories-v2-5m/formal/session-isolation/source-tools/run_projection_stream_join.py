"""Native projection-job/DDR-stream activation ownership and column alignment.

Retain both actual controllers and the complete activation RAM. Numerical
engine outputs and complete metadata/width-buffer children remain unrestricted.
No child protocol assumption or hard reset is inserted.
"""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance
from run_service_memory import CASES, boundaries, monitor_for

STREAM='board1_fixed_group_ddr_stream'
DELTA='board1_private_outstanding_delta'
ADAPTER='board1_shared_projection_scale_group_adapter'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    relative,top,_=CASES['projection'];original=(native/relative).read_bytes()
    definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',raw.decode(),re.M):
            row=(m[0],name,raw)
            if m[1]in definitions and definitions[m[1]][0]!=row[0]:raise ValueError('Ambiguous native module')
            definitions[m[1]]=row
    found=re.findall(r'^module '+top+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Native job module changed')
    source,files,cuts,count=boundaries(found[0],{ADAPTER:definitions[ADAPTER]},parser)
    if count!=1:raise ValueError('Native numerical adapter instance count differs')
    stream_raw,stream_path,stream_file=definitions[STREAM]
    stream,stream_files,stream_cuts,stream_count=boundaries(stream_raw,
        {n:r for n,r in definitions.items()if n!=DELTA},parser)
    if stream_count!=3:raise ValueError('Native stream child inventory differs')
    files.update(stream_files);cuts+=stream_cuts
    free={n:sh for n,(di,sh)in parser.ports(stream).items()if di=='input'and n.startswith('f_child_')}
    stream_taps={
        'f_stream_state_o':('[2:0] ','state_q'),
        'f_stream_owner_o':('[1:0] ','owner_q'),
        'f_stream_outstanding_o':('[11:0] ','outstanding_words_q'),
        'f_stream_columns_o':('[9:0] ','group_beats_q'),
        'f_stream_accepted_o':('[9:0] ','accepted_beats_q'),
        'f_stream_layer_o':('[2:0] ','layer_q'),
        'f_stream_job_o':('[3:0] ','job_q'),
        'f_stream_group_o':('[5:0] ','group_q'),
    }
    stream=tap(stream,stream_taps)
    source=source.replace('\n);',',\n'+',\n'.join('    input wire '+sh+n for n,sh in free.items())+'\n);',1)
    source=extend_instance(source,'u_group_stream',{**{n:n for n in free},**{n:n for n in stream_taps}})
    declarations='\n'.join('    wire '+sh+n+';'for n,(sh,_)in stream_taps.items())
    memory_monitor=monitor_for('projection').replace('always @*if(reset_n && !clear_i)',
        'always @*if(reset_n && !clear_i && f_completed_clear)').replace('cover((', 'cover(f_completed_clear && (')
    monitor='''
    reg f_completed_clear=0;
    reg f_job_owned;
    always @(posedge clk)begin
        if(!reset_n)f_completed_clear<=0;
        else if(clear_i)f_completed_clear<=!integrated_fail &&
            f_stream_owner_o==0 && f_stream_outstanding_o==0 && !private_word_rsp_valid_i;
        if(!reset_n || clear_i || (done_valid_o && done_ready_i))f_job_owned<=0;
        else if(start_transfer && incoming_descriptor_valid)f_job_owned<=1;
    end
    always @*if(reset_n && f_completed_clear && !clear_i && !integrated_fail)begin
        assert(state_q==JOB_IDLE || state_q==JOB_LOAD || state_q==JOB_GROUP_START ||
               state_q==JOB_GROUP_RUN || state_q==JOB_DONE || state_q==JOB_DRAIN);
        assert(f_stream_state_o<=5);
        if(f_job_owned)begin
            assert(job_q<=7 && groups_q!=0);
            assert(columns_q==columns_for_job(job_q));
            assert(rows_q==rows_for_job(job_q));
            assert(groups_q==groups_for_job(job_q));
        end
        if(state_q==JOB_LOAD || state_q==JOB_GROUP_START || state_q==JOB_GROUP_RUN || state_q==JOB_DONE)
            begin assert(f_job_owned);assert({1'b0,group_q}<groups_q);end
        if(state_q==JOB_IDLE || state_q==JOB_LOAD || state_q==JOB_GROUP_START || state_q==JOB_DONE || state_q==JOB_DRAIN)
            assert(f_stream_state_o==0);
        if(f_stream_state_o>=1 && f_stream_state_o<=5)begin
            assert(state_q==JOB_GROUP_RUN);
            assert(f_job_owned);
            assert(f_stream_columns_o==columns_q);
            assert(f_stream_layer_o==layer_q && f_stream_job_o==job_q && f_stream_group_o==group_q);
        end
        if(stream_done_seen_q)assert(f_stream_state_o==0);
        if(stream_done_seen_q || engine_done_seen_q)assert(state_q==JOB_GROUP_RUN);
        if(f_stream_state_o==5 || stream_done_seen_q)
            assert(f_read_tag==(({1'b0,group_q}==groups_q-1) ? columns_q-1 : 0));
        if(state_q==JOB_GROUP_START || (f_stream_state_o>=1 && f_stream_state_o<=3))begin
            assert(column_q==0);
        end
        if(f_stream_state_o>=1 && f_stream_state_o<=3)assert(f_stream_accepted_o==0);
        if(f_stream_state_o==4)begin
            assert(f_stream_accepted_o==column_q);
            assert(f_stream_accepted_o<f_stream_columns_o);
        end
        if(f_stream_state_o==5)begin
            assert(f_stream_accepted_o==f_stream_columns_o);
            assert(column_q==0);
        end
        if(state_q==JOB_GROUP_START || (f_stream_state_o>=1 && f_stream_state_o<=4))begin
            assert(f_read_live);
            assert(f_read_tag==column_q);
        end
        if(stream_group_valid || stream_weight_valid)begin
            assert(f_job_owned);
            assert(state_q==JOB_GROUP_RUN);
        end
        if(weight_transfer)begin
            assert(f_read_live);
            assert(f_read_tag==column_q);
            assert(!weight_protocol_error);
        end
    end
'''
    source=source.replace('\nendmodule','\n'+declarations+'\n'+memory_monitor+'\n'+monitor+'\nendmodule',1)
    ports=parser.ports(source)
    wrapper='module native_projection_stream_join(\n'+',\n'.join('    '+di+' wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+('rst_n'if n=='reset_n'else n)+')'for n in ports)+');\nendmodule\n'
    files.update({'production-service.sv':original,'production-stream.sv':stream_file,
        'production-delta.sv':definitions[DELTA][2],'delta.sv':('`undef FORMAL\n'+definitions[DELTA][0]).encode(),
        'service.sv':('`undef FORMAL\n'+source).encode(),'stream.sv':('`undef FORMAL\n'+stream).encode(),
        'wrapper.sv':wrapper.encode(),'ownership-monitor.inc.sv':memory_monitor.encode(),
        'join-monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'boundary-helper.py':(HERE/'run_service_memory.py').read_bytes(),
        'tap-helper.py':(HERE/'run_semantic_ingress.py').read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_projection_stream_join',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=memory_monitor.count('assert(')+monitor.count('assert('),
        covers=memory_monitor.count('cover('),observer_constants=1,
        binding=dict(native_join=binding,variant=args.variant,production_path=relative,
            retained_actual_children=['u_group_stream','u_outstanding_delta'],initial_hard_reset=False,
            entry_policy='Healthy common CLEAR with native stream owner/outstanding count empty and no model-word response'),
        cuts=cuts,depth=3,induction_depth=3,cover_depth=12,timeout=args.timeout,
        source_list=['delta.sv','stream.sv','service.sv','wrapper.sv'],optimize_full=True,
        map_literal_roms=True,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual projection job and native DDR stream control plus complete activation RAM after healthy drained CLEAR without hard reset. Current-job descriptor/read ownership and exact column alignment at accepted weights; no protocol assumption. Complete numerical adapter and stream grandchildren unrestricted. No full service or device session theorem.')


if __name__=='__main__':raise SystemExit(main())
