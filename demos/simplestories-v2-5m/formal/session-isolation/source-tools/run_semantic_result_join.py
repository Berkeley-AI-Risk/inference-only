"""Native sequence/datapath final-result ownership after healthy drained CLEAR.

No hard reset or erased RAM is assumed. Numerical and RAM child outputs remain
unrestricted; this checks when a final registered reply may be consumed, not
its numerical value or the complete device session theorem.
"""
import argparse
from pathlib import Path

from run_attention_ownership import HERE, load
from run_semantic_ingress import ROOT, tap, extend_instance


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    ap.add_argument('--mutant',choices=('premature-hidden-result',))
    args=ap.parse_args()
    builder=load('datapath',HERE.parent/'authentication-access/run_datapath_access.py')
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    files,dp_binding,cuts,dp_monitor=builder.derive(args.package,args.variant)
    original_monitor=dp_monitor
    long_cover='cover(engine_state_q == E_RMS && rms_start_valid);'
    if dp_monitor.count(long_cover)!=1:raise ValueError('Native RMS cover changed')
    dp_monitor=dp_monitor.replace(long_cover,'begin end').replace(
        'if (rst_n) begin','if (rst_n && f_session_join_i) begin')
    if dp_monitor==original_monitor:raise ValueError('Native assertion guard changed')
    dp=files['datapath.sv'].decode().replace(original_monitor,dp_monitor)
    metadata_writer=(HERE/'semantic-metadata-monitor.inc.sv').read_text().split('    always @*if(',1)[0]
    parent_read_observer='''
    reg f_rel_live_u_hidden_state;
    always @(posedge clk)if(!rst_n || clear_i)f_rel_live_u_hidden_state<=0;
        else if(hidden_ram_read_enable)f_rel_live_u_hidden_state<=1;
'''
    dp=dp.replace('\nendmodule','\n'+metadata_writer+'\n'+parent_read_observer+'\nendmodule',1)
    dp=dp.replace('\n);',',\n    input wire f_session_join_i\n);',1)
    dp_ports=parser.ports(dp)
    free={n:sh for n,(di,sh)in dp_ports.items()if n.startswith('f_child_')and di=='input'}
    dp_taps={
        'f_hidden_write_o':('', 'hidden_ram_write_enable'),
        'f_hidden_write_address_o':('[7:0] ', 'hidden_ram_write_address'),
        'f_hidden_read_o':('', 'hidden_ram_read_enable'),
        'f_hidden_read_address_o':('[7:0] ', 'hidden_ram_read_address'),
        'f_hidden_live_consume_o':('', 'rms_input_valid || (lane_request_valid && engine_state_q==E_ELEM && current_stage_q!=STAGE_SILU_MUL)'),
        'f_datapath_child_fault_o':('', 'child_fault'),
        'f_datapath_layer_active_o':('', 'engine_state_q!=E_IDLE && engine_state_q!=E_HEAD && engine_state_q!=E_FAULT'),
        'f_datapath_state_o':('[3:0] ', 'engine_state_q'),
        'f_datapath_transaction_o':('', 'transaction_seen_q'),
        'f_datapath_lock_seen_o':('', 'lock_seen_q'),
        'f_datapath_current_stage_o':('[4:0] ', 'current_stage_q'),
        'f_datapath_current_layer_o':('[2:0] ', 'current_layer_q'),
        'f_datapath_expected_stage_o':('[4:0] ', 'expected_stage_q'),
        'f_datapath_expected_layer_o':('[2:0] ', 'expected_layer_q'),
        'f_datapath_ddr_owner_o':('[1:0] ', 'ddr_owner_q'),
        'f_datapath_ddr_pending_o':('[3:0] ', 'ddr_pending_q'),
        'f_datapath_ddr_fault_o':('', 'ddr_arbiter_fault_q'),
        'f_initial_hidden_meta_o':('', 'engine_state_q==E_IDLE && !head_start_accept && stage_accept && private_stage_i==expected_stage_q && private_layer_i==expected_layer_q && !transaction_seen_q'),
        'f_parent_hidden_meta_o':('', 'f_hidden_meta'),
        'f_parent_hidden_read_live_o':('', 'f_rel_live_u_hidden_state'),
    }
    dp=tap(dp,dp_taps);files['datapath.sv']=dp.encode()
    sequence_raw=(native/(ROOT+'board1_context2048_semantic_sequence.sv')).read_bytes()
    sequence_taps={
        'f_sequence_state_o':('[2:0] ','state_q'),
        'f_sequence_stream_o':('[7:0] ','stream_index_q'),
        'f_sequence_stage_o':('[4:0] ','stage_q'),
        'f_sequence_layer_o':('[2:0] ','layer_q'),
        'f_sequence_lock_seen_o':('','lock_seen_q'),
        'f_sequence_protocol_fault_o':('','protocol_fault'),
    }
    files['production-sequence.sv']=sequence_raw
    sequence=sequence_raw.decode()
    if args.mutant:
        before='(state_q == S_RESULT) &&'
        if sequence.count(before)!=1:raise ValueError('Native result-publication mutation site changed')
        sequence=sequence.replace(before,'((state_q == S_RESULT) || (state_q == S_INGRESS)) &&',1)
    files['sequence.sv']=('`undef FORMAL\n'+tap(sequence,sequence_taps)).encode()
    layer_raw=(native/(ROOT+'board1_context2048_semantic_layer.sv')).read_bytes()
    layer=layer_raw.decode()
    layer=layer.replace('\n);',',\n'+',\n'.join('    input wire '+sh+n for n,sh in free.items())+'\n);',1)
    layer=extend_instance(layer,'u_datapath',{**{n:n for n in free},**{n:n for n in dp_taps},'f_session_join_i':'f_joined'})
    layer=extend_instance(layer,'u_sequence',{n:n for n in sequence_taps})
    declarations='\n'.join('    wire '+sh+n+';'for n,(sh,_)in {**dp_taps,**sequence_taps}.items())
    monitor='''
    (* anyconst *) reg [7:0] f_address;
    reg f_joined=0;
    reg f_hidden_owned, f_hidden_meta;
    reg f_read_live, f_read_owned;
    reg [7:0] f_read_address;
    wire f_start=start_valid_i && start_ready_o;
    wire f_clear_admit=clear_i && model_lock_i && !range_fault_o &&
        !f_datapath_child_fault_o && !f_sequence_protocol_fault_o &&
        !f_datapath_ddr_owner_o && !f_datapath_ddr_pending_o &&
        !f_datapath_ddr_fault_o && !private_word_rsp_valid_i;
    wire f_not_aborted=rst_n && f_joined && !clear_i &&
        !range_fault_o && !f_sequence_protocol_fault_o;
    always @(posedge clk)begin
        if(!rst_n)f_joined<=0;
        else if(clear_i)f_joined<=f_clear_admit;
        if(!rst_n || clear_i || f_start)begin
            f_hidden_owned<=0;f_hidden_meta<=0;
            f_read_live<=0;f_read_owned<=0;f_read_address<=0;
        end else begin
            if(f_hidden_write_o && f_hidden_write_address_o==f_address)f_hidden_owned<=1;
            if(f_initial_hidden_meta_o)f_hidden_meta<=1;
            if(f_hidden_read_o)begin
                f_read_live<=1;
                f_read_address<=f_hidden_read_address_o;
                f_read_owned<=f_hidden_read_address_o==f_address && f_hidden_owned;
            end
        end
        if(f_not_aborted)begin
            assert(f_datapath_lock_seen_o && f_sequence_lock_seen_o);
            assert(f_sequence_layer_o<=5 && f_sequence_stage_o<=16);
            if(f_sequence_state_o==1)assert(f_sequence_stage_o==0 && f_sequence_layer_o==0);
            if(f_sequence_state_o==0 || f_sequence_state_o==1 || f_sequence_state_o==5)begin
                assert(!f_datapath_transaction_o);
                assert(f_datapath_expected_stage_o==0 && f_datapath_expected_layer_o==0);
            end
            if(f_datapath_state_o==8)assert(f_sequence_state_o==0);
            if(f_sequence_state_o==2)begin
                assert(f_datapath_state_o==0);
                assert(f_datapath_expected_stage_o==f_sequence_stage_o);
                assert(f_datapath_expected_layer_o==f_sequence_layer_o);
            end
            if(f_sequence_state_o==3)begin
                assert(f_datapath_current_stage_o==f_sequence_stage_o);
                assert(f_datapath_current_layer_o==f_sequence_layer_o);
                if(stage_done)begin
                    assert(f_datapath_state_o==0);
                    assert(f_datapath_expected_stage_o==(f_sequence_stage_o==16 ? 0 : f_sequence_stage_o+1));
                    assert(f_datapath_expected_layer_o==((f_sequence_stage_o==16) ? ((f_sequence_layer_o==5) ? 0 : f_sequence_layer_o+1) : f_sequence_layer_o));
                end else begin
                    assert(f_datapath_state_o!=0);
                    assert(f_datapath_expected_stage_o==f_sequence_stage_o);
                    assert(f_datapath_expected_layer_o==f_sequence_layer_o);
                end
                if(stage_done && f_sequence_stage_o==16 && f_sequence_layer_o==5)
                    assert(!f_datapath_transaction_o);
            end
            if(f_sequence_state_o==5)begin
                assert(f_datapath_state_o==0);
                assert(!f_datapath_transaction_o);
            end
            if(f_datapath_layer_active_o)assert(f_sequence_state_o==3);
            if(f_sequence_state_o!=0 && f_sequence_state_o!=7)assert(f_sequence_lock_seen_o);
            if(f_sequence_state_o==1 && f_address<f_sequence_stream_o)assert(f_hidden_owned);
            if(f_sequence_state_o==2 || f_sequence_state_o==3 || f_sequence_state_o==4 ||
               f_sequence_state_o==5 || f_sequence_state_o==6)assert(f_hidden_owned);
            if(f_hidden_live_consume_o)assert(f_hidden_owned);
            if(f_datapath_transaction_o)assert(f_hidden_meta);
            if(f_hidden_meta)assert(f_parent_hidden_meta_o);
            if(f_read_live)assert(f_parent_hidden_read_live_o);
            if(f_sequence_state_o==3 && f_sequence_stage_o==15 && f_sequence_layer_o==5 && stage_done)
                begin assert(f_hidden_meta);assert(f_parent_hidden_meta_o);end
            if(result_valid_o)begin
                assert(f_hidden_owned);
                assert(f_hidden_meta);
                assert(f_read_live);
                assert(f_parent_hidden_meta_o);
                assert(f_parent_hidden_read_live_o);
                assert(f_read_address==result_index_o);
                if(result_index_o==f_address)assert(f_read_owned);
            end
            if(f_sequence_state_o==4 || f_sequence_state_o==6)begin
                assert(f_datapath_state_o==0);
                assert(f_sequence_stage_o==15 && f_sequence_layer_o==5);
                assert(f_datapath_expected_stage_o==16 && f_datapath_expected_layer_o==5);
                assert(f_hidden_read_o);
                assert(f_hidden_read_address_o==f_sequence_stream_o);
            end
            if(ingress_write && model_lock_i && !f_datapath_child_fault_o)begin
                assert(f_hidden_write_o);
                assert(f_hidden_write_address_o==input_index_i);
            end
        end
        cover(rst_n && !f_joined && f_datapath_transaction_o);
        cover(f_not_aborted && model_lock_i && !f_datapath_child_fault_o && ingress_write && input_index_i==2);
    end
'''
    layer=layer.replace('\nendmodule','\n'+declarations+'\n'+monitor+'\nendmodule',1)
    files['production-layer.sv']=layer_raw;files['layer.sv']=('`undef FORMAL\n'+layer).encode()
    ports=parser.ports(layer)
    wrapper='module native_semantic_result_join(\n'+',\n'.join('    '+di+' wire '+sh+n for n,(di,sh)in ports.items())+'\n);\n'
    wrapper+='    board1_context2048_semantic_layer #(.ADDR_W(19))u_native('+','.join('.'+n+'('+n+')'for n in ports)+');\nendmodule\n'
    files.update({'wrapper.sv':wrapper.encode(),'result-monitor.inc.sv':monitor.encode(),
        'metadata-writer.inc.sv':metadata_writer.encode(),'parent-read-observer.inc.sv':parent_read_observer.encode(),
        'result-runner.py':Path(__file__).read_bytes(),'ingress-helpers.py':(HERE/'run_semantic_ingress.py').read_bytes()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_semantic_result_join',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=dp_monitor.count('assert(')+monitor.count('assert('),
        covers=dp_monitor.count('cover(')+monitor.count('cover('),observer_constants=1,
        binding=dict(native_join=binding,datapath_binding=dp_binding,variant=args.variant,
            initial_hard_reset=False,entry_policy='Healthy model-locked CLEAR with no sequence protocol fault, aggregate child fault, collision fault, model-word reply or pending native DDR ownership'),
        cuts=cuts,depth=8 if args.mutant else 3,induction_depth=4,cover_depth=12,timeout=args.timeout,mutant=args.mutant,
        source_list=['datapath.sv','sequence.sv','layer.sv','wrapper.sv'],optimize_full=True,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual native semantic sequence/datapath/layer join after healthy drained CLEAR without hard reset. Complete fresh hidden-vector ingress and metadata initialization precede consumption; final result beats require the correct fresh registered read. All numerical/RAM children unrestricted. No numerical equality, full service composition or complete device session theorem.')


if __name__=='__main__':raise SystemExit(main())
