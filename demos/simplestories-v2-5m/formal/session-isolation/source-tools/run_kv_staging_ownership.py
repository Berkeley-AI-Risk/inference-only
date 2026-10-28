"""Actual K/V staging RAM freshness after logical CLEAR, without hard reset.

The symbolic coordinate observes all native rows, with arbitrary old payloads.
This checks initialization and permitted staging reads, separately from the
committed-cache/assembly datapath and the protected guard's checked copies.
"""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load
from run_kv_session_drain import TOP
from run_service_relational import width


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variant',choices=('baseline','kv-protected'),default='baseline')
    ap.add_argument('--mutant',action='store_true',help='Negative control: skip actual staging-RAM lane-zero writes.')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=30)
    args=ap.parse_args();baseline=args.variant=='baseline';lanes=8 if baseline else 16
    builder=load('addresses',HERE.parent/'authentication-access/run_model_addresses.py')
    builder.ROOTS['kv-cache']=TOP
    files,binding,count,covers=builder.derive(HERE.parents[1]/'fpga-demo/public-release',args.variant,'kv-cache')
    if count or covers:raise ValueError('Unexpected imported property inventory')
    source=files[TOP+'.sv'].decode()
    before=('logic [31:0] words [0:31];'if baseline else
            'logic [31:0] memory [0:7] /* synthesis syn_ramstyle="distributed_ram" */;')
    observation=('assign f_staged_pairs[bank*32 +:32]=words[5\'d8+{1\'b0,f_coordinate[6:3]}];'if baseline else
                 'assign f_staged_pairs[lane*32 +:32]=memory[f_coordinate[6:4]];')
    if source.count(before)!=1:raise ValueError('Native staging RAM declaration changed')
    source=source.replace(before,before+'\n        '+observation,1)
    if args.mutant:
        old=('if (bank_wr_enable) words[bank_wr_addr] <= bank_wr_data;'if baseline else
             "if (stage_memory_write && expected_coordinate_q[3:0] == 4'(lane))")
        new=('if (bank_wr_enable && bank!=0) words[bank_wr_addr] <= bank_wr_data;'if baseline else
             "if (stage_memory_write && expected_coordinate_q[3:0] == 4'(lane) && lane!=0)")
        if source.count(old)!=1:raise ValueError('Actual staging-RAM writer changed')
        source=source.replace(old,new,1)
    monitor='''
    (* anyconst *) reg [6:0] f_coordinate;
    wire [PAIR_BITS:0] f_staged_pairs;
    wire [31:0] f_staged_pair=f_staged_pairs[COORD_INDEX*32 +:32];
    reg f_epoch=0,f_stage_live=0,f_full=0,f_written=0,f_any_reset=0;
    reg [15:0] f_key,f_value,f_key_exponents,f_value_exponents;
    wire f_begin=stage_begin_valid_i && stage_begin_ready_o && stage_begin_legal && !terminal_fault_event;
    wire f_payload=stage_payload_valid_i && stage_payload_ready_o && stage_payload_legal && !terminal_fault_event;
    wire f_commit=commit_valid_i && commit_ready_o && commit_legal && !terminal_fault_event;
    always @(posedge clk)begin
        if(!reset_n)begin
            f_epoch<=0;f_stage_live<=0;f_full<=0;f_written<=0;f_any_reset<=1;
        end else if(clear_i)begin
            f_epoch<=1;f_stage_live<=0;f_full<=0;f_written<=0;
        end else if(f_epoch)begin
            if(f_begin)begin
                f_stage_live<=1;f_full<=0;f_written<=0;
                f_key_exponents<=stage_key_exponents_i;f_value_exponents<=stage_value_exponents_i;
            end
            if(f_payload)begin
                if(stage_coordinate_i==f_coordinate)begin
                    f_written<=1;f_key<=stage_key_i;f_value<=stage_value_i;
                end
                if(stage_coordinate_i==127)f_full<=1;
            end
            if(f_commit)begin f_stage_live<=0;f_full<=0;end
        end
    end
    wire f_healthy=reset_n && f_epoch && !fault_q && !terminal_fault_now;
    always @*if(reset_n && !f_epoch)begin
        assert(!f_stage_live && !f_full && !f_written);
    end
    always @*if(f_healthy)begin
        if(state_q==ST_IDLE)assert(!pending_persisted_q && !f_stage_live && !f_full);
        if(f_full)assert(f_stage_live);
        if(f_stage_live)assert(state_q==ST_STAGE || STAGING_USE || pending_persisted_q);
        if(pending_persisted_q)assert(PENDING_PHASE);
        if(PRE_WRITE)assert(!write_aborted_q);
        if(f_stage_live)begin
            assert(pending_key_exponents_q==f_key_exponents && pending_value_exponents_q==f_value_exponents);
        end
        if(f_written)assert(f_staged_pair=={f_value,f_key});
        if(f_full)assert(f_written);
        if(state_q==ST_STAGE)begin
            assert(f_stage_live && !f_full);
            if(f_coordinate<expected_coordinate_q)assert(f_written);
        end
        if(STAGING_USE)begin
            assert(f_stage_live && f_full && f_written);
            assert(write_word_q<=8);
        end
        if(pending_persisted_q)assert(f_stage_live && f_full && f_written);
EXTRA
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_begin);
        cover(f_healthy && !f_any_reset && f_written && state_q==ST_STAGE);
    end
'''
    monitor=monitor.replace('PAIR_BITS',str(lanes*32-1)).replace('COORD_INDEX','f_coordinate[2:0]'if baseline else'f_coordinate[3:0]')
    use='((state_q==ST_WRITE_REQ || state_q==ST_WRITE_WAIT) && !write_aborted_q)'
    if baseline:use+=' || state_q==ST_WRITE_PREFETCH_A || state_q==ST_WRITE_PREFETCH_B || state_q==ST_WRITE_PACK || state_q==ST_WRITE_META'
    monitor=monitor.replace('STAGING_USE',use)
    pre_write='state_q==ST_WRITE_REQ'
    if baseline:pre_write+=' || state_q==ST_WRITE_PREFETCH_A || state_q==ST_WRITE_PREFETCH_B || state_q==ST_WRITE_PACK || state_q==ST_WRITE_META'
    monitor=monitor.replace('PRE_WRITE',pre_write)
    phases='state_q==ST_PENDING || state_q==ST_READ_REQ || state_q==ST_READ_WAIT || state_q==ST_RESPONSE'
    phases+=' || state_q==ST_CACHE_READ || state_q==ST_PENDING_READ'if baseline else' || state_q==ST_PENDING_LOAD'
    monitor=monitor.replace('PENDING_PHASE',phases)
    extra='''
        if(store_read_enable && store_read_address>=8)begin
            assert(store_read_address<24);
            assert(f_stage_live && f_full && f_written);
        end
        if(write_prefetch_enable)assert(write_word_q<8);
        if(pending_read_enable)assert(pending_issued_q<8);
    '''if baseline else'''
        if(kv_write_req_valid_o || pending_payload_take)begin
            assert(f_stage_live && f_full && f_written);
            assert(stage_memory_word<=8);
        end
    '''
    monitor=monitor.replace('EXTRA',extra)
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    files[TOP+'.sv']=source.encode();files['staging-owner-monitor.inc.sv']=monitor.encode()
    files['staging-owner-observation.inc.sv']=observation.encode();files['staging-owner-runner.py']=Path(__file__).read_bytes()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source);wrapper='module native_kv_staging(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+TOP+' u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n';files['wrapper.sv']=wrapper.encode()
    binding.update(initial_hard_reset=False,concrete_hierarchy_modules=sorted(binding['isolated_native_modules']),
        actual_all_native_RAMs_retained=True,symbolic_coordinate_bits=7,
        entry_policy='Actual logical CLEAR from arbitrary native control/payload. Subsequent healthy staging uses require complete current initialization; no physical reset or zeroed payload prerequisite. Short covers exercise new stage admission and a current coordinate write; full-stage reachability remains a separate simulation obligation.')
    cover_rows=['initial\nassume (= [reset_n] true)\n']
    for step in range(6):
        cover_rows.append('state '+str(step)+'\n')
        for name,(direction,shape)in ports.items():
            if direction!='input'or name=='clk':continue
            value=int(name in ('reset_n','model_locked_i')or
                (name=='clear_i'and step==0)or(name=='stage_begin_valid_i'and step==1)or
                (name=='stage_payload_valid_i'and step==3))
            bits=width(shape);literal=('true'if value else'false')if bits==1 else'(_ bv'+str(value)+' '+str(bits)+')'
            cover_rows.append('assume (= ['+name+'] '+literal+')\n')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_kv_staging',
        reset_constraints=''.join(cover_rows)if args.mutant else'initial\nassume (= [reset_n] true)\nstate 1\nassume (= [reset_n] true)\n',
        assertions=monitor.count('assert('),covers=2,binding=binding,cuts=[],depth=6 if args.mutant else 2,induction_depth=1,
        mutant='Skip actual native staging-RAM lane-zero writer'if args.mutant else None,
        cover_constraints=''.join(cover_rows),cover_depth=6,timeout=args.timeout,source_list=[n+'.sv'for n in binding['isolated_native_modules']]+['wrapper.sv'],
        optimize_full=True,observer_constants=1,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual native typed K/V controller and all payload RAMs/mapper children. From logical CLEAR, every staged coordinate read by a live K/V use has a current legal stage writer, and observed RAM bits equal that writer. Metadata exponents have current descriptor provenance. Cached committed rows, assembly/output correspondence, guard, outer transport and full device composition remain separate.')


if __name__=='__main__':raise SystemExit(main())
