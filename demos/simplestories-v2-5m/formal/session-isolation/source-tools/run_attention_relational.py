"""Two-copy attention parent with explicit shared child-reply contracts.

This discharges parent correspondence, not the child contracts. Actual RAM
history and ownership are separate premises; numerical-child session contracts
must also be discharged before crediting complete attention/session isolation.
"""
import argparse
from pathlib import Path

from run_attention_ownership import derive, load, HERE, TOP

CONTROL = [
    ('state_q',6),('position_q',11),('query_exponent_q',8),('query_beat_q',2),
    ('attention_head_q',2),('scan_position_q',11),('element_q',11),('coordinate_q',6),
    ('result_beat_q',2),('compute_cycles_q',32),('captured_cache_kind_q',2),
    ('captured_value_exponent_q',8),('value_align_exponent_q',8),('score_exponent_q',8),
    ('score_max_q',16),('softmax_denominator_q',42),('normalize_candidate_q',8),
    ('normalize_all_fit_q',1),('normalize_any_nonzero_q',1),('normalize_output_q',1),
    ('result_exponent_q',8),('score_accumulator_q',38),('pending_score_exponent_q',8),
    ('exp_index_q',13),('shift_client_q',3),('fault_cache_outstanding_q',1),
    ('workspace_read_return_q',6),('output_read_return_q',6),
    ('value_group_exponent_q[0]',8),('value_group_exponent_q[1]',8),
    ('value_align_candidate_by_kv_q[0]',8),('value_align_candidate_by_kv_q[1]',8),
    ('value_align_any_by_kv_q[0]',1),('value_align_any_by_kv_q[1]',1),
    ('accumulator_initialized_groups_q',32),('range_fault_o',1),
]

# Payload equality is allowed only after the appropriate native history or
# valid/capture boundary. Invalid data remains independent in the two copies.
COUPLING={
    'u_query_bram_read_data_o':'a_query_live',
    'u_output_bram_read_data_o':'a_out_live',
    **{'u_workspace_bram_bank'+str(i)+'_read_data_o':'a_ws_live'for i in range(3)},
    'u_accumulator_bram_read_data_o':'a_acc_live',
    'u_accumulator_bram_read_tag_o':'f_child_u_accumulator_bram_read_valid_o',
    'u_norm_stage_first_fit_o':'a_norm_owned',
    'u_norm_stage_nonzero_o':'a_norm_owned',
    'u_align8_response_vector_o':'f_child_u_align8_response_valid_o',
    'u_align8_response_magnitude_or_o':'f_child_u_align8_response_valid_o',
    'u_align8_response_fault_o':'f_child_u_align8_response_valid_o',
    'u_value_prefix_exponent0_o':'f_child_u_value_prefix_read_valid_o',
    'u_value_prefix_exponent1_o':'f_child_u_value_prefix_read_valid_o',
    'u_shift_response_result_o':'f_child_u_shift_response_valid_o',
    'u_shift_response_fault_o':'f_child_u_shift_response_valid_o',
    'u_divider_response_result_o':'f_child_u_divider_response_valid_o',
    'u_divider_response_fault_o':'f_child_u_divider_response_valid_o',
    'u_exp_lut_value_o':'f_child_u_exp_lut_response_valid_o && !f_child_u_exp_lut_response_fault_o',
    'u_score_lane_product0_o':"a_state==6'd33",
    'u_value_lane_product0_o':"a_state==6'd24",
}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=60)
    ap.add_argument('--clear-entry',action='store_true')
    ap.add_argument('--audit-child-inputs',action='store_true')
    args=ap.parse_args()
    monitors=[HERE/n for n in ('query-ownership-monitor.inc.sv','workspace-ownership-monitor.inc.sv',
              'output-accumulator-ownership-monitor.inc.sv','registered-consumption-monitor.inc.sv')]
    files,binding,cuts,monitor=derive(args.package,args.variant,monitors)
    original_monitor=monitor
    # The ownership suite is a separate completed safety proof. Retain only
    # its ghost histories here, and reprove the few needed admission facts
    # below. Large unrelated phase invariants need not be induction premises.
    for keyword in ('assert','cover'):
        while keyword+'('in monitor:
            start=monitor.index(keyword+'(');end=start+len(keyword)+1;level=1
            while level:level+=(monitor[end]=='(')-(monitor[end]==')');end+=1
            if monitor[end]!=';':raise ValueError('Observer statement changed')
            monitor=monitor[:start]+' begin end '+monitor[end+1:]
    files['attention.sv']=files['attention.sv'].replace(original_monitor.encode(),monitor.encode())
    files['parent-ownership-monitor.inc.sv']=original_monitor.encode()
    files['monitor.inc.sv']=monitor.encode()
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    source=files['attention.sv'].decode()
    ports=parser.ports(source)
    taps={
        'control':(sum(w for _,w in CONTROL),'{'+','.join(n for n,_ in CONTROL)+'}'),
        'state':(6,'state_q'),'coordinate':(6,'coordinate_q'),
        'live':(1,'interface_live'),'new_start':(1,'start_valid_i && start_ready_o'),
        'query_owned':(1,'f_scope0.f_query_staging_owned'),
        'query_buffer':(1024,'query_buffer_q'),
        'capture_owned':(1,'f_scope3.f_capture_owned'),
        'capture_buffer':(1024,'captured_cache_vector_q'),
        'aligned_owned':(1,'f_scope3.f_aligned_owned[f_rel_lane_i[2:0]]'),
        'aligned_group':(128,'aligned_value_groups_q[f_rel_lane_i[2:0]]'),
        'aligned_mask':(8,'f_scope3.f_aligned_owned'),
        **{'aligned_group'+str(i):(128,'aligned_value_groups_q['+str(i)+']')for i in range(8)},
        'score_key_group':(128,'score_key_group_q'),
        'query_read':(1,'query_bram_read_enable'),
        'result_word':(16,'result_buffer_q[f_rel_lane_i*16 +:16]'),
        'result_beat':(2,'result_beat_q'),
        'align_request':(1,'interface_live && state_q==ST_VALUE_ALIGN'),
        'align_vector':(128,'captured_cache_vector_q[coordinate_q[5:3]*128 +:128]'),
        'norm_capture':(1,'interface_live && state_q==ST_NORM_CAPTURE'),
        'norm_source':(72,'{normalize_source_value_comb,normalize_source_exponent_comb}'),
        'query_write':(1,'query_bram_write_enable'),
        'query_write_data':(16,'query_bram_write_data'),
        'workspace_return':(6,'workspace_read_return_q'),
        'output_return':(6,'output_read_return_q'),
        **{n+'_live':(1,'f_scope3.f_'+n+'_read_live')for n in ('query','ws','out','acc')},
        **{n+'_tag':(w,'f_scope3.f_'+n+'_read_tag')for n,w in [('query',5),('ws',13),('out',8),('acc',5)]},
        'normalize_output':(1,'normalize_output_q'),
        'norm_owned':(1,'f_scope3.f_norm_captured'),
        'ws_consume':(1,'f_scope3.f_ws_consume'),
        'out_consume':(1,'f_scope3.f_out_consume'),
        'acc_consume':(1,'accumulator_consume'),
        'shift_request':(1,'shift_request_valid'),
        'shift_client':(3,'shift_client_q'),
        'shift_operands':(73,'{shift_request_value_comb,shift_request_amount_comb}'),
        'div_request':(1,'div_request_valid'),
        'div_operands':(128,'{div_request_numerator,div_request_denominator}'),
        'exp_request':(1,'state_q==ST_EXP_LUT_REQUEST'),
        'exp_index':(13,'exp_index_q'),
        'score_operands':(256,'{query_bram_read_group,score_key_group_q}'),
        'value_operands':(144,'{workspace_probability_at_scan,aligned_value_selected_group}'),
        'query_read_address':(5,'query_bram_read_address'),
        'query_write_address':(8,'query_bram_write_address'),
        'workspace_read':(1,'workspace_bram_read_enable'),
        'workspace_read_address':(13,'workspace_bram_read_address'),
        'workspace_write':(1,'workspace_bram_write_enable'),
        'workspace_write_address':(13,'workspace_bram_write_address'),
        'workspace_write_data':(54,'{workspace_bank0_write_data,workspace_bank1_write_data,workspace_bank2_write_data}'),
        'output_read':(1,'output_bram_read_enable'),
        'output_read_address':(8,'output_bram_read_address'),
        'output_write':(1,'output_bram_write_enable'),
        'output_write_address':(8,'output_bram_write_address'),
        'output_write_data':(18,'output_bram_write_data'),
        'acc_read':(1,'accumulator_read_enable'),
        'acc_read_address':(5,'accumulator_read_address'),
        'acc_write':(1,'accumulator_write_enable'),
        'acc_write_address':(5,'accumulator_current_address'),
        'acc_write_data':(304,'accumulator_write_group'),
    }
    child_obligations=[]
    if args.audit_child_inputs:
        from attention_contract_inputs import observe
        import re
        raw=files['production-attention.sv'].decode()
        definitions={}
        for filename,data in files.items():
            if filename.startswith('production-child-'):
                for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',data.decode(),re.M):
                    definitions[m[1]]=m[0]
        child_taps,child_obligations,child_manifest=observe(raw,definitions,parser)
        taps.update(child_taps)
        binding['actual_child_input_obligations']=child_manifest
        files['attention-contract-inputs.py']=(HERE/'attention_contract_inputs.py').read_bytes()
        files['service-contract-parser.py']=(HERE/'run_service_relational.py').read_bytes()
    extra=',\n    input wire [5:0] f_rel_lane_i,\n'+',\n'.join(
        '    output wire '+(f'[{width-1}:0] 'if width>1 else'')+'f_rel_'+name+'_o'
        for name,(width,_)in taps.items())+'\n'
    source=source.replace('\n);',extra+');',1)
    source=source.replace('\nendmodule','\n'+'\n'.join('    assign f_rel_'+name+'_o='+expr+';'
        for name,(_,expr)in taps.items())+'\nendmodule',1)
    files['attention.sv']=source.encode()
    lines=['`default_nettype none','module attention_parent_relational(',
        ',\n'.join(['    input wire '+shape+name for name,(direction,shape)in ports.items()if direction=='input']+
                   ['    input wire '+ports['f_child_'+n][1]+'discarded_'+n for n in COUPLING]),');',
        '    (* anyconst *) reg [5:0] f_lane;', '    reg f_past_valid=0;',
        '    reg f_result_owned,f_score_key_owned;']
    for copy in ('a','b'):
        for name,(direction,shape)in ports.items():
            if direction=='output':lines.append('    wire '+shape+copy+'_'+name+';')
        for name,(width,_)in taps.items():
            lines.append('    wire '+(f'[{width-1}:0] 'if width>1 else'')+copy+'_'+name+';')
        connections=['.'+name+'('+ (
            '('+COUPLING[name[8:]]+' ? '+name+' : discarded_'+name[8:]+')'
            if copy=='b'and name.startswith('f_child_')and name[8:]in COUPLING else
            name if direction=='input'else copy+'_'+name)+')'
            for name,(direction,_)in ports.items()]
        connections += ['.f_rel_lane_i(f_lane)']+['.f_rel_'+name+'_o('+copy+'_'+name+')'for name in taps]
        lines += ['    '+TOP+' u_'+copy+'('+','.join(connections)+');']
    lines += ['    always @(posedge clk)begin', '        f_past_valid<=1;',
        '        if(!rst_n || clear_i || !a_live || a_new_start)begin',
        '            f_result_owned<=0;f_score_key_owned<=0;', '        end else begin',
        "            if(a_state==6'd35 && a_coordinate==f_lane)f_result_owned<=1;",
        "            if(a_state==6'd20 && a_result_valid_o && result_ready_i && a_result_beat!=3)f_result_owned<=0;",
        '            if(a_query_read)f_score_key_owned<=1;', '        end',
        '        if(f_past_valid && rst_n)begin',
        '            assert(a_control==b_control);assert(a_live==b_live);',
        '            if(a_range_fault_o)assert(a_state==31);',
        '            assert(a_query_owned==b_query_owned);',
        '            assert(a_capture_owned==b_capture_owned);',
        '            assert(a_aligned_owned==b_aligned_owned);',
        *['            assert(a_'+n+'==b_'+n+');'for n in ('query_live','ws_live','out_live','acc_live','norm_owned')],
        *['            if(a_'+n+'_live)assert(a_'+n+'_tag==b_'+n+'_tag);'for n in ('query','ws','out','acc')],
        '            assert(a_aligned_mask==b_aligned_mask);',
        *['            if(a_aligned_mask['+str(i)+'])assert(a_aligned_group'+str(i)+'==b_aligned_group'+str(i)+');'for i in range(8)],
        '            if(a_query_owned)assert(a_query_buffer==b_query_buffer);',
        '            if(a_capture_owned)assert(a_capture_buffer==b_capture_buffer);',
        '            if(a_aligned_owned)assert(a_aligned_group==b_aligned_group);',
        '            if(f_score_key_owned)assert(a_score_key_group==b_score_key_group);',
        '            if(f_result_owned)assert(a_result_word==b_result_word);',
        '            assert(a_start_ready_o==b_start_ready_o);',
        '            assert(a_query_ready_o==b_query_ready_o);',
        '            assert(a_private_cache_request_valid_o==b_private_cache_request_valid_o);',
        '            assert(a_private_cache_request_kind_o==b_private_cache_request_kind_o);',
        '            assert(a_private_cache_request_position_o==b_private_cache_request_position_o);',
        '            assert(a_private_cache_request_kv_head_o==b_private_cache_request_kv_head_o);',
        '            assert(a_private_cache_response_ready_o==b_private_cache_response_ready_o);',
        '            assert(a_result_valid_o==b_result_valid_o);',
        '            assert(a_done_valid_o==b_done_valid_o);',
        '            if(a_live)begin',
        '                if(a_ws_consume)assert(a_ws_live);',
        '                if(a_out_consume)assert(a_out_live);',
        '                if(a_acc_consume)assert(a_acc_live);',
        '                if(a_state==33)assert(a_query_live);',
        '                if(a_state==30)assert(a_norm_owned);',
        '                if((a_state>=6 && a_state<=17) || (a_state>=22 && a_state<=24) || a_state==29 || a_state==38 || a_state==41)assert(!a_normalize_output);',
        '                if(a_state==18 || a_state==19)assert(a_normalize_output);',
        '                if(a_state==36)assert(!a_normalize_output);',
        '                if(a_state==37)assert(a_normalize_output);',
        '                if(a_state==28 && (a_shift_client==1 || a_shift_client==2 || a_shift_client==5))assert(!a_normalize_output);',
        '                if(a_state==28 && (a_shift_client==3 || a_shift_client==4))assert(a_normalize_output);',
        '                if(a_state==36 && a_workspace_return==24)assert(a_coordinate==0);',
        "                if(a_state==23 || a_state==38)assert(a_aligned_mask==((9'b1<<a_coordinate[5:3])-1'b1));",
        '                if(a_state==24 || (a_state==36 && a_workspace_return==24))assert(&a_aligned_mask);',
        *['                assert(a_'+n+'==b_'+n+');'for n in
          ('shift_request','div_request','exp_request','query_read','query_write',
           'workspace_read','workspace_write','output_read','output_write','acc_read','acc_write')],
        *['                if(a_'+guard+')assert(a_'+value+'==b_'+value+');'for guard,value in
          [('shift_request','shift_operands'),('div_request','div_operands'),('exp_request','exp_index'),
           ('query_read','query_read_address'),('query_write','query_write_address'),
           ('workspace_read','workspace_read_address'),('workspace_write','workspace_write_address'),
           ('workspace_write','workspace_write_data'),('output_read','output_read_address'),
           ('output_write','output_write_address'),('output_write','output_write_data'),
           ('acc_read','acc_read_address'),('acc_write','acc_write_address'),('acc_write','acc_write_data')]],
        '                if(a_state==33)assert(a_score_operands==b_score_operands);',
        '                if(a_state==24)assert(a_value_operands==b_value_operands);',
        "                assert(a_state<=6'd41);",
        "                assert(a_state!=2 && a_state!=3 && a_state!=25 && a_state!=39);",
        "                if(a_state==36)assert(a_workspace_return==40 || a_workspace_return==6 || a_workspace_return==7 || a_workspace_return==8 || a_workspace_return==9 || a_workspace_return==10 || a_workspace_return==24);",
        "                if(a_state==37)assert(a_output_return==40 || a_output_return==18 || a_output_return==19);",
        '                if(a_query_write)assert(a_query_owned);',
        "                if(a_state==6'd33 || a_state==6'd26)assert(a_capture_owned);",
        '                if(a_align_request)assert(a_capture_owned);',
        "                if(a_state==38)assert(a_capture_owned);",
        "                if(a_state==23 || a_state==38)begin",
        "                    assert(a_coordinate[2:0]==0);",
        "                    if(f_lane[2:0]<a_coordinate[5:3])assert(a_aligned_owned);",
        '                end',
        "                if(a_state==24 || (a_state==36 && a_workspace_return==24))assert(a_aligned_owned);",
        "                if(a_state==24)assert(a_aligned_group==b_aligned_group);",
        "                if(a_state==6'd33)begin assert(f_score_key_owned);assert(a_score_key_group==b_score_key_group);end",
        "                if((a_state==6'd34 || a_state==6'd35) && f_lane<a_coordinate)assert(f_result_owned);",
        "                if(a_state==6'd20)assert(f_result_owned);",
        '                if(a_result_valid_o)assert(a_result_word==b_result_word);',
        '                if(a_align_request)assert(a_align_vector==b_align_vector);',
        '                if(a_norm_capture)assert(a_norm_source==b_norm_source);',
        '                if(a_query_write)assert(a_query_write_data==b_query_write_data);',
        '            end',
        '            if(!clear_i && !a_range_fault_o)begin',
        '                if(a_ws_consume)assert(a_ws_live);',
        '                if(a_out_consume)assert(a_out_live);',
        '                if(a_acc_consume)assert(a_acc_live);',
        '            end',
        '            if(!clear_i && a_div_request)assert(a_div_operands==b_div_operands);',
        *child_obligations,
        '        end',
        '        cover(f_past_valid && rst_n && a_live && a_state==32 && a_coordinate==2);',
        '        cover(f_past_valid && rst_n && a_state==0 && a_query_buffer!=b_query_buffer);',
        '    end', 'endmodule','`default_nettype wire']
    wrapper='\n'.join(lines)+'\n'
    end=sum(width for _,width in CONTROL)
    split=[]
    for name,width in CONTROL:
        begin=end-width
        split.append(f'            assert(a_control[{end-1}:{begin}]==b_control[{end-1}:{begin}]); // {name}')
        end=begin
    wrapper=wrapper.replace('assert(a_control==b_control);','\n'+'\n'.join(split)+'\n')
    # Combinational relational invariants avoid an extra assertion-register
    # delay between corresponding controller states. Ghost updates stay clocked.
    start=wrapper.index('        if(f_past_valid && rst_n)begin')
    end=wrapper.index('\n        cover(',start)
    checks=wrapper[start:end]
    checks=checks.replace('if(f_past_valid && rst_n)begin','if(rst_n)begin',1)
    wrapper=wrapper[:start]+wrapper[end:]
    wrapper=wrapper.replace('\nendmodule','\n    always @*begin\n'+checks+'\n    end\nendmodule',1)
    if args.clear_entry:
        wrapper=wrapper.replace('    reg f_result_owned,f_score_key_owned;',
            '    reg f_result_owned,f_score_key_owned;\n    reg f_joined=0;\n    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i && a_state==0 && b_state==0)f_joined<=1;')
        wrapper=wrapper.replace('if(rst_n)begin','if(rst_n && f_joined)begin')
        wrapper=wrapper.replace('\nendmodule',
            '\n    always @(posedge clk)cover(rst_n && !f_joined && a_control!=b_control);\nendmodule',1)
    files['wrapper.sv']=wrapper.encode();files['relational-runner.py']=Path(__file__).read_bytes()
    binding['child_reply_coupling']='Control/valid status shared; payload shared only at the listed valid or ownership boundaries. Native history and child contracts still require composition.'
    binding['payload_coupling_predicates']=COUPLING
    binding['initial_hard_reset']=not args.clear_entry
    binding['clear_entry_policy']='Common CLEAR from both native IDLE states enables the relation; actual completed CLEAR/drain admission is required at composition'if args.clear_entry else'Common hard reset'
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='attention_parent_relational',
        reset_constraints=('initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n'if args.clear_entry else
            'initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n'),
        constraint_scope_description='No initial hard reset. Independent arbitrary native initial controls and transient payloads. A common CLEAR edge while both copies are IDLE enables the relation. Child contracts and completed top-level CLEAR/drain remain separate.'if args.clear_entry else None,
        assertions=wrapper.count('assert('),
        covers=wrapper.count('cover('),binding=binding,cuts=cuts,
        observer_constants=1,depth=6,induction_depth=4,
        cover_depth=12,timeout=args.timeout,source_list=['attention.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Two-copy actual attention parent and resetless transient registers. Identical public/private inputs and explicitly shared whole child replies. Owned transient values, consumed child operands, control and per-symbolic-lane result agree despite arbitrary independent initial transient payloads. Native RAM and numerical-child reply contracts must be joined before claiming complete attention/session isolation; no whole-device token-output theorem.')


if __name__=='__main__':raise SystemExit(main())
