"""Native token shell connected to the complete embedding model-read path.

RMS, selector, embedding-normalizer and semantic replies remain explicit
numerical/service seams. No model-read hierarchy reply is replaced.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_service_memory import boundaries
from run_semantic_ingress import tap, extend_instance


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variant',choices=('baseline','seeded-sampling'),default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    prior=HERE/'runs/embedding-drain-r1';pi=json.loads((prior/'INPUTS.json').read_text())
    parent=HERE/'runs'/('shell-parent-seeded-clear-r1'if args.variant=='seeded-sampling'else'shell-parent-clear-r4')
    si=json.loads((parent/'INPUTS.json').read_text());original=(parent/'production-shell.sv').read_bytes()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    files={n:(prior/n).read_bytes()for n in pi['files']if n.endswith('.sv')and n!='wrapper.sv'}
    definitions={}
    for module in {r['module']for r in si['internal_cuts']if r.get('instance')and r['module']!='board1_fixed_embedding_lookup'}:
        raw=(parent/('production-child-'+module+'.sv')).read_bytes()
        bodies=re.findall(r'^module\s+'+module+r'\b[\s\S]*?^endmodule\b',raw.decode(),re.M)
        if len(bodies)!=1:raise ValueError('Native service module not unique')
        definitions[module]=(bodies[0],'native numerical child contract',raw)
    source,extra,cuts,count=boundaries(original.decode(),definitions,parser)
    if count!=2:raise ValueError('Expected only RMS and selector child seams')
    embedding=files['embedding.sv'].decode()
    free={n:sh for n,(di,sh)in parser.ports(embedding).items()if di=='input'and n.startswith('f_child_')}
    embedding=tap(embedding,{
        'f_shell_pending_o':('[12:0] ','f_pending'),'f_shell_scope_o':('','f_scope'),
        'f_shell_state_o':('[3:0] ','state_q'),'f_shell_clear_seen_o':('','f_clear_seen'),
        'f_shell_quiet_o':('','f_quiet')})
    files['embedding.sv']=embedding.encode()
    source=source.replace('\n);',',\n'+',\n'.join('    input wire '+sh+n for n,sh in free.items())+'\n);',1)
    source=extend_instance(source,'u_fixed_embedding',{
        **{n:n for n in free},'f_shell_pending_o':'f_embed_pending','f_shell_scope_o':'f_embed_scope',
        'f_shell_state_o':'f_embed_state','f_shell_clear_seen_o':'f_embed_clear_seen','f_shell_quiet_o':'f_embed_quiet'})
    monitor='''
    wire[12:0]f_embed_pending;wire[3:0]f_embed_state;
    wire f_embed_scope,f_embed_clear_seen,f_embed_quiet;
    reg f_active=0,f_any_reset=0,f_clear_seen=0,f_quiet=0,f_cleared_pending=0;
    reg[12:0]f_pending=0;
    wire f_arm=rst_n && model_lock_i && !fail_q && !child_fault && !upstream_fault_i &&
        state_q==ST_IDLE && ddr_owner_q==DDR_OWNER_NONE && !embed_busy &&
        !rms_busy && !argmax_busy && !private_layer_busy_i && f_embed_scope && f_embed_pending==0;
    wire f_scope=f_active || f_arm;
    wire f_request=private_word_req_valid_o && private_word_req_ready_i;
    wire f_response=private_word_rsp_valid_i && private_word_rsp_ready_o;
    always @(posedge clk)begin
        if(!rst_n)begin
            f_active<=0;f_any_reset<=1;f_clear_seen<=0;f_quiet<=0;f_pending<=0;f_cleared_pending<=0;
        end else begin
            if(f_scope)begin
                f_active<=1;
                f_pending<=(f_active ? f_pending : 13'd0)+{12'd0,f_request}-{12'd0,f_response};
            end
            if(clear_i && f_scope)begin
                f_clear_seen<=1;f_quiet<=1;
                if(f_active && f_pending!=0)f_cleared_pending<=1;
            end else if(append_transfer || step_transfer)f_quiet<=0;
        end
    end
    wire f_healthy=rst_n && f_scope && !fail_q && !embed_fault;
    always @*if(rst_n && !f_active)begin assert(f_pending==0);assert(!f_clear_seen);end
    always @*if(f_healthy)begin
        assert(f_embed_scope);
        assert(f_pending==f_embed_pending);
        assert(state_q!=ST_FAIL);
        if(state_q==ST_CLEAR_DRAIN)assert(f_clear_seen && f_quiet);
        assert(ddr_owner_q==DDR_OWNER_NONE || ddr_owner_q==DDR_OWNER_EMBED);
        if(ddr_owner_q==DDR_OWNER_NONE)assert(f_embed_pending==0 && !embed_req_valid);
        if(ddr_owner_q==DDR_OWNER_NONE && state_q!=ST_CLEAR_DRAIN)assert(!embed_busy && f_embed_state==0);
        if(state_q==ST_EMBED_CAPTURE || state_q==ST_EMBED_DONE)assert(ddr_owner_q==DDR_OWNER_EMBED);
        if(ddr_owner_q==DDR_OWNER_EMBED)assert(state_q==ST_EMBED_CAPTURE || state_q==ST_EMBED_DONE || state_q==ST_CLEAR_DRAIN);
        if(state_q==ST_IDLE || state_q==ST_TAPE_READ || state_q==ST_EMBED_START)
            assert(!embed_busy && f_embed_state==0 && ddr_owner_q==DDR_OWNER_NONE);
        if(!busy_o)assert(f_pending==0 && !embed_busy);
        if(append_ready_o || step_ready_o)assert(f_pending==0 && !private_word_req_valid_o);
        if(private_word_req_valid_o)assert(busy_o);
        if(f_clear_seen && f_quiet)begin
            assert(state_q==ST_IDLE || state_q==ST_CLEAR_DRAIN);
            assert(f_embed_clear_seen && f_embed_quiet);
            assert(!private_word_req_valid_o);
            assert(tape_count_q==0 && committed_count_q==0 && replay_position_q==0);
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && f_active && clear_i && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && busy_o && f_pending!=0);
        cover(f_healthy && !f_any_reset && f_cleared_pending && !clear_i && !busy_o && append_ready_o && f_pending==0);
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule',1)
    top='board1_context2048_token_shell';ports=parser.ports(source)
    wrapper='module shell_drain(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update(extra);files.update({'production-shell.sv':original,'shell.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'shell-drain-monitor.inc.sv':monitor.encode(),'shell-drain-runner.py':Path(__file__).read_bytes()})
    for n in('INPUTS.json','FINISHED.json'):files['embedding-prerequisite-'+n]=(prior/n).read_bytes()
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='shell_drain',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=pi['assertion_cells']+monitor.count('assert('),covers=pi['cover_cells']+3,
        binding=dict(native_join=si['binding']['native_join'],variant=args.variant,initial_hard_reset=False,
            concrete_hierarchy_modules=[top]+pi['binding']['concrete_hierarchy_modules'],
            fully_connected_embedding_model_reader=True,entry_policy='Tracking starts at healthy native shell/embedding IDLE with no pending reads; arbitrary old RAM/payloads. Later busy CLEAR does not reset pending accounting.'),
        cuts=pi['internal_cuts']+cuts,depth=4,induction_depth=4,cover_depth=24,timeout=args.timeout,
        source_list=pi['compile_sources'][:-1]+['shell.sv','wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual '+args.variant+' token shell connected to full embedding/group model-read hierarchy, native tape/vector RAMs retained. Healthy shell busy-low or public command-ready implies no owed model reply; model requests imply busy. Busy CLEAR drains existing work without new reads until fresh upper work. Numerical/service child seams and core/outer/typed K/V composition remain explicit.')


if __name__=='__main__':raise SystemExit(main())
