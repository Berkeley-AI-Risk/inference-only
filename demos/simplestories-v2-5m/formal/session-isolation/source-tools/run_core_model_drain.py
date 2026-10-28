"""Actual token core, both model-read clients and local transport connected.

This scope concerns the core's digital model-read drain barrier. Numerical
services, typed K/V and outer physical transport remain explicit boundaries.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance
from audit_model_drain import block


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--variant',choices=('baseline','seeded-sampling'),default='baseline')
    ap.add_argument('--entry-at-start',action='store_true')
    ap.add_argument('--only-core-covers',action='store_true')
    ap.add_argument('--abstract-shell-reads',action='store_true')
    ap.add_argument('--timeout',type=int,default=60);args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release',args.variant)
    files={};sources=[];inputs={};modules=[];cuts=[];assertions=0;covers=0
    for key,name in [('shell','seeded-shell-drain-r1'if args.variant=='seeded-sampling'else'shell-drain-r3'),
        ('semantic','connected-semantic-drain-r1'),('transport','model-transport-drain-client-r1')]:
        run=HERE/'runs'/name;inp=json.loads((run/'INPUTS.json').read_text());inputs[key]=(run,inp)
        for n in inp['files']:
            if not n.endswith('.sv')or n=='wrapper.sv':continue
            target=n if n in inp['compile_sources']else'production-'+key+'-'+n if n.startswith('production')else key+'-'+n
            raw=(run/n).read_bytes()
            if target in files and files[target]!=raw:raise ValueError('Conflicting connected native module: '+target)
            files[target]=raw
        sources.extend(n for n in inp['compile_sources']if n!='wrapper.sv')
        modules+=inp['binding'].get('concrete_hierarchy_modules',[]);cuts+=inp['internal_cuts']
        assertions+=inp['assertion_cells'];covers+=inp['cover_cells']
        for n in('INPUTS.json','FINISHED.json'):files[key+'-prerequisite-'+n]=(run/n).read_bytes()
    shell=files['shell.sv'].decode()
    phase_monitor='''
    always @*if(f_healthy && state_q>=ST_GROUP_START && state_q<=ST_RESULTS)
        assert(!group_done_seen_q && !norm_done_seen_q);
'''
    embedding=files['embedding.sv'].decode()
    if embedding.count('\nendmodule')!=1:raise ValueError('Embedding monitor insertion is not unique')
    files['embedding.sv']=embedding.replace('\nendmodule','\n'+phase_monitor+'\nendmodule',1).encode()
    files['core-embedding-phase-monitor.inc.sv']=phase_monitor.encode();assertions+=phase_monitor.count('assert(')
    if args.abstract_shell_reads:
        parent=HERE/'runs'/('shell-parent-seeded-clear-r1'if args.variant=='seeded-sampling'else'shell-parent-clear-r4')
        histories=json.loads((parent/'INPUTS.json').read_text())['binding']['registered_memory_histories']
        free_reads=[]
        for name,row in histories.items():
            port='f_child_core_ram_'+name+'_i'
            pattern=r'\b'+row['register']+r'\s*<=\s*'+row['memory']+r'\['+row['address']+r'\];'
            matches=list(re.finditer(pattern,shell))
            if len(matches)!=1:raise ValueError('Native registered RAM capture changed')
            before=matches[0][0];shell=shell.replace(before,row['register']+' <= '+port+';',1)
            free_reads.append('    input wire['+str(row['bits']-1)+':0]'+port)
            cuts.append(dict(module='board1_context2048_token_shell',port=port,
                kind='unrestricted_registered_RAM_read_payload',native_memory=row['memory'],
                native_read_address=row['address'],native_capture=row['register'],source_statement=before,
                control_and_capture_clock_retained=True,assumptions=[]))
        shell=shell.replace('\n);',',\n'+',\n'.join(free_reads)+'\n);',1)
        files['shell-read-history-reference.json']=(parent/'INPUTS.json').read_bytes()
    shellfree={n:sh for n,(di,sh)in parser.ports(shell).items()if di=='input'and n.startswith('f_child_')}
    files['shell.sv']=tap(shell,{'f_core_pending_o':('[12:0] ','f_pending'),'f_core_scope_o':('','f_scope')}).encode()
    dp=files['datapath.sv'].decode();dpfree={n:sh for n,(di,sh)in parser.ports(dp).items()if di=='input'and n.startswith('f_child_')}
    files['datapath.sv']=tap(dp,{'f_core_pending_o':('[4:0] ','f_pending'),'f_core_scope_o':('','f_scope')}).encode()
    layer_path='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_layer.sv'
    seq_path='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/board1_context2048_semantic_sequence.sv'
    layer_raw=(native/layer_path).read_bytes();layer=layer_raw.decode()
    layer=layer.replace('\n);',',\n'+',\n'.join(['    input wire '+sh+n for n,sh in dpfree.items()]+
        ['    output wire[4:0]f_core_pending_o','    output wire f_core_scope_o'])+'\n);',1)
    layer=extend_instance(layer,'u_datapath',{**{n:n for n in dpfree},'f_core_pending_o':'f_core_pending_o','f_core_scope_o':'f_core_scope_o'})
    files['production-layer.sv']=layer_raw;files['layer.sv']=('`undef FORMAL\n'+layer).encode()
    files['production-sequence.sv']=(native/seq_path).read_bytes();files['sequence.sv']=b'`undef FORMAL\n'+files['production-sequence.sv']
    core_path=inputs['transport'][1]['binding']['native_core_path'];original=(native/core_path).read_bytes();core=original.decode()
    raw_wrapper=(inputs['transport'][0]/'wrapper.sv').read_text()
    start=raw_wrapper.index('    wire arbiter_busy,arbiter_fail;wire f_scope;')
    inst=raw_wrapper.index('    wire shell_queued_req_valid, shell_queued_req_ready;')
    obs=raw_wrapper.index('    reg f_active=0')
    declarations=raw_wrapper[start:inst].replace('wire arbiter_busy,arbiter_fail;wire f_scope;','wire f_scope;',1)
    functional=raw_wrapper[inst:obs]
    monitor=raw_wrapper[obs:raw_wrapper.rindex('\nendmodule')]
    if core.count(block(core))!=1:raise ValueError('Native core transport block not unique')
    core=core.replace(block(core),functional,1)
    free={**{'f_shell_'+n:sh for n,sh in shellfree.items()},**{'f_layer_'+n:sh for n,sh in dpfree.items()}}
    core=core.replace('\n);',',\n'+',\n'.join('    input wire '+sh+n for n,sh in free.items())+'\n);',1)
    core=extend_instance(core,'u_token_shell',{**{n:'f_shell_'+n for n in shellfree},
        'f_core_pending_o':'f_shell_owned_pending','f_core_scope_o':'f_shell_scope'})
    core=extend_instance(core,'u_six_layers',{**{n:'f_layer_'+n for n in dpfree},
        'f_core_pending_o':'f_layer_owned_pending','f_core_scope_o':'f_layer_scope'})
    before='f_owner_write==f_owner_read;'
    if monitor.count(before)!=1:raise ValueError('Native core empty tracking entry changed')
    monitor=monitor.replace(before,'f_owner_write==f_owner_read && machine_active && !aggregate_fail && !shell_busy && !layer_busy && f_shell_scope && f_layer_scope && f_shell_owned_pending==0 && f_layer_owned_pending==0;',1)
    monitor=monitor.replace('wire f_healthy=reset_n && child_reset_n && f_active && !f_owner_fail;',
        'wire f_healthy=reset_n && child_reset_n && f_active && !f_owner_fail && machine_active && !aggregate_fail;',1)
    joined='''
    wire[12:0]f_shell_owned_pending;wire[4:0]f_layer_owned_pending;
    wire f_shell_scope,f_layer_scope;
    always @*if(f_healthy)begin
        assert(f_shell_scope && f_layer_scope);
        assert({7'd0,f_shell_pending}==f_shell_owned_pending);
        assert(f_layer_pending=={1'b0,f_layer_owned_pending});
        if(!busy_o)begin
            assert(f_total_pending==0 && f_owner_count==0);
            assert(f_shell_request_count==0 && f_layer_request_count==0 && f_shell_response_count==0 && f_layer_response_count==0);
            assert(!private_runtime_req_valid_o && !shell_ddr_req_valid && !layer_ddr_req_valid);
        end
    end
    always @(posedge clk)begin
        cover(f_healthy && !f_any_reset && clear_i && f_total_pending!=0);
        cover(f_healthy && !f_any_reset && f_clear_pending && !clear_i && busy_o && f_total_pending!=0);
        cover(f_healthy && !f_any_reset && f_clear_pending && !clear_i && !busy_o && append_ready_o && f_total_pending==0);
    end
'''
    core=core.replace('\nendmodule','\n'+declarations+'\n'+monitor+'\n'+joined+'\nendmodule',1)
    if args.entry_at_start:core=tap(core,{'f_logical_entry_o':('','f_arm')})
    top='board1_context2048_token_machine_core';ports=parser.ports(core)
    wrapper='module core_model_drain(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    '+top+' #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update({'production-core.sv':original,'core.sv':('`undef FORMAL\n'+core).encode(),'wrapper.sv':wrapper.encode(),
        'core-join-monitor.inc.sv':joined.encode(),'core-transport-monitor.inc.sv':monitor.encode(),'core-runner.py':Path(__file__).read_bytes()})
    if args.only_core_covers:
        removed=0
        # Inherited component reachability records remain their own completed
        # receipts. This assembled campaign requests only its three actual
        # core-boundary covers; assertions/transitions are unchanged.
        for name in list(dict.fromkeys(sources))+['layer.sv','sequence.sv','core.sv']:
            text=files[name].decode()
            if name=='core.sv':
                if text.count(joined)!=1:raise ValueError('Core cover monitor not unique')
                text=text.replace(joined,'__CORE_BOUNDARY_MONITOR__',1)
            while 'cover('in text:
                start=text.index('cover(');end=start+6;level=1
                while level:level+=(text[end]=='(')-(text[end]==')');end+=1
                if text[end]!=';':raise ValueError('Inherited cover syntax changed')
                text=text[:start]+' begin end '+text[end+1:];removed+=1
            text=text.replace('__CORE_BOUNDARY_MONITOR__',joined)
            files[name]=text.encode()
        # Raw calls differ from elaborated counts because a group reader is
        # instantiated twice, and disabled original FORMAL blocks may contain
        # other calls. The compiler checks exactly three active core covers.
        covers=0
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='core_model_drain',
        reset_constraints='initial\nassume (= [reset_n] true)\n'+('assume (= [f_logical_entry_o] true)\n'if args.entry_at_start else'')+'state 1\nassume (= [reset_n] true)\n',
        assertions=assertions+joined.count('assert('),covers=covers+3,
        binding=dict(native_join=binding,variant=args.variant,initial_hard_reset=False,
            concrete_hierarchy_modules=sorted(set(modules+[top,'board1_context2048_semantic_layer','board1_context2048_semantic_sequence'])),
            concrete_shell_and_semantic_model_clients=True,common_empty_transport_epoch=True,
            logical_entry_constrained_in_base_and_covers=args.entry_at_start,only_core_reachability_covers=args.only_core_covers,
            inherited_raw_cover_calls_removed=removed if args.only_core_covers else None,
            shell_registered_read_payloads_overapproximated=args.abstract_shell_reads,
            additional_native_phase_invariants=['Embedding GROUP_START through RESULTS retains cleared terminal flags from upper acceptance.'],
            entry_policy='Healthy active core, all native local model queues/owners empty and both actual clients idle/empty at one common tracking boundary. No physical reset or empty-at-CLEAR prerequisite.'),
        cuts=cuts,depth=4,induction_depth=4,cover_depth=24,timeout=args.timeout,
        source_list=list(dict.fromkeys(sources))+['layer.sv','sequence.sv','core.sv','wrapper.sv'],
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual '+args.variant+' core with both model-read clients, sequence/layer, four local FIFOs and native owner arbiter connected. Healthy active busy-low implies no locally owed or presented model read. Ordinary CLEAR may interrupt accepted work. '+('Four native shell registered RAM read payloads are unrestricted data-only overapproximations, with actual capture clocks/controls retained. 'if args.abstract_shell_reads else'Native shell RAMs retained. ')+'Numerical/service replies, typed K/V and outer physical transport remain explicit boundaries; this is not a complete device session theorem.')


if __name__=='__main__':raise SystemExit(main())
