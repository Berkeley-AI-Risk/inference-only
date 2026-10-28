"""Actual sequence/datapath join: complete fresh hidden-vector ingress before use."""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load

ROOT='project/fpga/token_only_model0_ddr_board1/context2048_token_machine0/rtl/'


def tap(source, rows):
    source=source.replace('\n);',',\n'+',\n'.join('    output wire '+shape+name for name,(shape,_)in rows.items())+'\n);',1)
    return source.replace('\nendmodule','\n'+'\n'.join('    assign '+name+'='+expr+';'for name,(_,expr)in rows.items())+'\nendmodule',1)


def extend_instance(source, instance, ports):
    marker=instance+' (';start=source.index(marker);opening=start+len(marker)-1
    nesting=1;end=opening+1
    while nesting:
        nesting+=(source[end]=='(')-(source[end]==')');end+=1
    if source[end]!=';':raise ValueError('Instance terminator changed')
    return source[:end-1]+',\n'+',\n'.join('        .'+p+'('+value+')'for p,value in ports.items())+'\n    '+source[end-1:]


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    args=ap.parse_args()
    builder=load('datapath',HERE.parent/'authentication-access/run_datapath_access.py')
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    files,dp_binding,cuts,dp_monitor=builder.derive(args.package,args.variant)
    # Full first-RMS reachability needs >256 native ingress writes. Keep the
    # short head/ingress covers here; do not reduce the production vector size.
    long_cover='cover(engine_state_q == E_RMS && rms_start_valid);'
    if dp_monitor.count(long_cover)!=1:raise ValueError('RMS cover changed')
    files['datapath.sv']=files['datapath.sv'].replace(long_cover.encode(),b'begin end')
    dp_monitor=dp_monitor.replace(long_cover,'begin end')
    dp=files['datapath.sv'].decode();dp_ports=parser.ports(dp)
    free={n:shape for n,(direction,shape)in dp_ports.items()if n.startswith('f_child_')and direction=='input'}
    dp_taps={
        'f_hidden_write_o':('', 'hidden_ram_write_enable'),
        'f_hidden_write_address_o':('[7:0] ', 'hidden_ram_write_address'),
        'f_hidden_live_consume_o':('', 'rms_input_valid || (lane_request_valid && engine_state_q==E_ELEM && current_stage_q!=STAGE_SILU_MUL)'),
        'f_datapath_child_fault_o':('', 'child_fault'),
        'f_datapath_layer_active_o':('', 'engine_state_q!=E_IDLE && engine_state_q!=E_HEAD && engine_state_q!=E_FAULT'),
    }
    dp=tap(dp,dp_taps);files['datapath.sv']=dp.encode()
    sequence_raw=(native/(ROOT+'board1_context2048_semantic_sequence.sv')).read_bytes()
    sequence_taps={'f_sequence_state_o':('[2:0] ','state_q'),
                   'f_sequence_stream_o':('[7:0] ','stream_index_q'),
                   'f_sequence_lock_seen_o':('','lock_seen_q'),
                   'f_sequence_protocol_fault_o':('','protocol_fault')}
    files['production-sequence.sv']=sequence_raw
    files['sequence.sv']=('`undef FORMAL\n'+tap(sequence_raw.decode(),sequence_taps)).encode()
    layer_raw=(native/(ROOT+'board1_context2048_semantic_layer.sv')).read_bytes()
    layer=layer_raw.decode()
    layer=layer.replace('\n);',',\n'+',\n'.join('    input wire '+shape+name for name,shape in free.items())+'\n);',1)
    layer=extend_instance(layer,'u_datapath',{**{n:n for n in free},**{n:n for n in dp_taps}})
    layer=extend_instance(layer,'u_sequence',{n:n for n in sequence_taps})
    declarations='\n'.join('    wire '+shape+name+';'for name,(shape,_)in {**dp_taps,**sequence_taps}.items())
    monitor='''
    (* anyconst *) reg [7:0] f_address;
    reg f_hidden_owned;
    reg f_past_valid=0;
    wire f_start=start_valid_i && start_ready_o;
    wire f_healthy=rst_n && !clear_i && model_lock_i && !range_fault_o && !f_datapath_child_fault_o;
    wire f_not_aborted=rst_n && !clear_i && !range_fault_o && !f_sequence_protocol_fault_o;
    always @(posedge clk)begin
        f_past_valid<=1;
        if(!rst_n || clear_i || f_start)f_hidden_owned<=0;
        else if(f_hidden_write_o && f_hidden_write_address_o==f_address)f_hidden_owned<=1;
        if(f_past_valid && f_not_aborted)begin
            if(f_datapath_layer_active_o)assert(f_sequence_state_o==3);
            if(f_sequence_state_o!=0 && f_sequence_state_o!=7)assert(f_sequence_lock_seen_o);
            if(f_sequence_state_o==1 && f_address<f_sequence_stream_o)assert(f_hidden_owned);
            if(f_sequence_state_o==2 || f_sequence_state_o==3 || f_sequence_state_o==4 ||
               f_sequence_state_o==5 || f_sequence_state_o==6)assert(f_hidden_owned);
            if(f_hidden_live_consume_o)assert(f_hidden_owned);
            if(result_valid_o)assert(f_hidden_owned);
            if(ingress_write && f_healthy)begin
                assert(f_hidden_write_o);
                assert(f_hidden_write_address_o==input_index_i);
            end
        end
        cover(f_past_valid && f_healthy && ingress_write && input_index_i==2);
    end
'''
    layer=layer.replace('\nendmodule','\n'+declarations+'\n'+monitor+'\nendmodule',1)
    files['production-layer.sv']=layer_raw;files['layer.sv']=('`undef FORMAL\n'+layer).encode()
    ports=parser.ports(layer)
    wrapper='module native_semantic_ingress(\n'+',\n'.join('    '+direction+' wire '+shape+name for name,(direction,shape)in ports.items())+'\n);\n'
    wrapper+='    board1_context2048_semantic_layer #(.ADDR_W(19)) u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files['wrapper.sv']=wrapper.encode();files['ingress-monitor.inc.sv']=monitor.encode()
    files['ingress-runner.py']=Path(__file__).read_bytes()
    engine=load('engine',HERE.parent/'authentication-access/engine.py')
    return engine.check(args.run,files,top='native_semantic_ingress',
        reset_constraints='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n',
        assertions=dp_monitor.count('assert(')+monitor.count('assert('),
        covers=dp_monitor.count('cover(')+monitor.count('cover('),observer_constants=1,
        binding=dict(native_join=binding,datapath_binding=dp_binding,variant=args.variant),cuts=cuts,
        depth=6,induction_depth=4,cover_depth=12,timeout=args.timeout,
        source_list=['datapath.sv','sequence.sv','layer.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Actual native semantic sequence, datapath controller and production join. Fresh complete ordered hidden-vector ingress precedes live RMS/residual/final-result consumption. Idle speculative reads may access unowned words but are not consumers. All numerical/RAM children unrestricted; no numerical-service or full-session theorem.')


if __name__=='__main__':raise SystemExit(main())
