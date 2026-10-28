"""Conditional native token-shell correspondence after healthy drained CLEAR.

Every native scalar field, actual child input and tape/vector write is observed.
Registered memory histories and complete numerical-child replies remain named
contracts; invalid payloads and old retained metadata may differ.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_shell_memory import REL, TOP
from run_service_memory import boundaries
from run_service_relational import synthesis_text, width
from run_semantic_ingress import tap
from run_projection_relational import instance_con


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--variant',choices=('baseline','seeded-sampling'),default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release',args.variant)
    original=(native/REL).read_bytes();raw=original.decode();definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        data=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',data.decode(),re.M):definitions[m[1]]=(m[0],name,data)
    source,files,cuts,count=boundaries(raw,definitions,parser)
    if count!=3:raise ValueError('Actual shell child inventory changed')
    census=HERE/'runs'/('native-hierarchy-seeded-sampling-r1'if args.variant=='seeded-sampling'else'native-hierarchy-r1')
    c=json.loads((census/'CENSUS.json').read_text());rows=[r for r in c['instances']if r['original_module']==TOP]
    if len(rows)!=1:raise ValueError('Native shell not unique')
    g=json.loads((census/'hierarchy.json').read_text())['modules'][rows[0]['module']]
    qbits={b for cell in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe)',cell['type'])for b in cell['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
    observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
    if not qbits.issubset(observed):raise ValueError('Unobserved native shell sequential state')
    histories={
        'tape':dict(register='tape_read_q',memory='token_tape_q',address='replay_position_q',read='state_q == ST_TAPE_READ',new='step_transfer',bits=12),
        'embedding':dict(register='embedding_read_q',memory='embedding_mem_q',address='stream_index_q',read='state_q == ST_LAYER_INPUT_READ',new='embed_start_transfer',bits=16),
        'layer':dict(register='layer5_read_q',memory='layer5_mem_q',address='stream_index_q',read='state_q == ST_RMS_INPUT_READ',new='layer_start_transfer',bits=16),
        'norm':dict(register='final_norm_read_q',memory='final_norm_mem_q',address='stream_index_q',read='state_q == ST_HEAD_INPUT_READ',new='rms_start_transfer',bits=16),
    }
    taps={};ghosts=[];relations={n:'1'for n in fields};coupling={}
    relations['winner_token_q']='winner_seen_q'
    for kind,row in histories.items():
        before=row['register']+' <= '+row['memory']+'['+row['address']+'];'
        if source.count(before)!=1:raise ValueError('Actual registered read changed')
        source=source.replace(before,'begin end',1)
        port='f_ram_'+kind+'_i'
        source=source.replace('\n);',',\n    input wire ['+str(row['bits']-1)+':0] '+port+'\n);',1)
        ghosts+=['    reg f_live_'+kind+';',
            '    always @(posedge clk)if(!rst_n || clear_i || '+row['new']+')f_live_'+kind+'<=0;else if('+row['read']+')f_live_'+kind+'<=1;',
            '    assign '+row['register']+'='+port+';']
        taps['f_live_'+kind+'_o']=('','f_live_'+kind)
        taps['f_read_'+kind+'_o']=(''if kind=='tape'else'',row['read'])
        taps['f_address_'+kind+'_o']=('[11:0] 'if kind=='tape'else'[7:0] ',row['address'])
        coupling[port]='a_f_live_'+kind+'_o'
        fields.pop(row['register']);relations.pop(row['register'])
        cuts.append(dict(kind='native_registered_memory_history',register=row['register'],replacement=port,memory=row['memory']))
    metadata={
        'embedding_exponent_q':('embedding','embed_result_exponent'),
        'layer5_exponent_q':('layer','private_layer_result_exponent_i'),
        'final_norm_exponent_q':('norm','rms_result_exponent'),
    }
    for field,(kind,value)in metadata.items():
        pattern=r'('+field+r'\s*<=\s*'+value+r';)'
        source,n=re.subn(pattern,r'\1 f_meta_'+kind+'<=1;',source)
        if n!=1:raise ValueError('Actual retained exponent writer changed')
        reset=field+" <= 8'sd0;"
        if source.count(reset)!=1:raise ValueError('Actual exponent reset changed')
        source=source.replace(reset,reset+'f_meta_'+kind+'<=0;',1)
        source=source.replace('state_q <= ST_CLEAR_DRAIN;','state_q <= ST_CLEAR_DRAIN;f_meta_'+kind+'<=0;',1)
        ghosts.append('    reg f_meta_'+kind+';');relations[field]='f_meta_'+kind
        taps['f_meta_'+kind+'_o']=('','f_meta_'+kind)
    writes={
        'append':('append_transfer','tape_count_q','append_token_i',12,12),
        'generated':('generated_commit','tape_count_q','completing_winner',12,12),
        'embedding':('embed_result_transfer','embed_result_index','embed_result_mantissa',8,16),
        'layer':('layer_result_transfer','private_layer_result_index_i','private_layer_result_mantissa_i',8,16),
        'norm':('rms_result_transfer','rms_result_index','rms_result_mantissa',8,16),
    }
    for kind,(enable,address,data,ab,db)in writes.items():
        taps.update({'f_write_'+kind+'_o':('',enable),
            'f_write_'+kind+'_address_o':('['+str(ab-1)+':0] ',address),
            'f_write_'+kind+'_data_o':('['+str(db-1)+':0] ',data)})
    taps.update({'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()})
    taps.update({'f_when_'+n+'_o':('',predicate)for n,predicate in relations.items()})
    taps.update(f_child_fault_o=('','child_fault'),f_fatal_o=('','upstream_fault_i || child_fault || lock_fault || watchdog_fault || public_protocol_fault || private_protocol_fault || ((state_q==ST_IDLE) && model_lock_i && !committed_prefixes_match)'),
        f_drained_o=('','ddr_owner_q==DDR_OWNER_NONE && !embed_busy && !rms_busy && !argmax_busy && !private_layer_busy_i && !private_word_rsp_valid_i'))
    child_inputs={}
    for instance in sorted({r['instance']for r in cuts if 'instance'in r}):
        module=next(r['module']for r in cuts if r.get('instance')==instance)
        con=instance_con(raw,module,instance);declared=parser.ports(definitions[module][0]);child_inputs[instance]={}
        for n,(di,shape)in declared.items():
            if di!='input':continue
            if n in('clk','reset_n','rst_n'):
                child_inputs[instance][n]=dict(expression=con[n],kind='shared_clock_or_reset');continue
            guard='1'
            if n in('fixed_token_i','input_exponent_i'):guard=con['start_valid_i']
            elif n in('input_mantissa_i','input_row_index_i','input_last_i'):guard=con['input_valid_i']
            elif n.startswith('row_')and n!='row_valid_i':guard=con['row_valid_i']
            elif n in('settings_temperature_i','settings_seed_i'):guard=con['settings_valid_i']
            elif n in('private_word_rsp_data_i','private_word_rsp_fault_i'):guard=con['private_word_rsp_valid_i']
            name='f_input_'+instance+'_'+n+'_o';taps[name]=('['+str(width(shape)-1)+':0] ',con[n]);taps[name+'_when']=('',guard)
            child_inputs[instance][n]=dict(expression=con[n],guard=guard,tap=name,width=width(shape),kind='admission_equality')
        replies=[r for r in cuts if r.get('instance')==instance]
        valid=next((r['replacement']for r in replies if r.get('port')in('result_valid_o','winner_valid_o')),None)
        for row in replies:
            guard='f_joined'
            if row['port']in('result_index_o','result_row_index_o','result_mantissa_o','result_exponent_o','result_last_o',
                'winner_token_id_o','winner_scaled_raw_o','winner_source_exponent_o'):
                if valid is None:raise ValueError('Native result payload has no valid')
                guard='f_joined && '+valid
            coupling[row['replacement']]=guard
    source=source.replace('\nendmodule','\n'+'\n'.join(ghosts)+'\nendmodule',1)
    source=tap(source,taps);ports=parser.ports(source)
    coupling.update(append_token_i='append_valid_i',token_ready_i='a_token_valid_o',
        private_word_rsp_data_i='private_word_rsp_valid_i',private_word_rsp_fault_i='private_word_rsp_valid_i')
    for n in ports:
        if n.startswith('private_layer_result_')and n not in('private_layer_result_valid_i','private_layer_result_ready_o')and n.endswith('_i'):coupling[n]='private_layer_result_valid_i'
        if n.startswith('private_head_result_')and n not in('private_head_result_valid_i','private_head_result_ready_o')and n.endswith('_i'):coupling[n]='private_head_result_valid_i'
    if args.variant=='seeded-sampling':coupling.update(settings_temperature_i='settings_valid_i',settings_seed_i='settings_valid_i')
    lines=['module shell_parent_relational(',',\n'.join(
        ['    input wire '+sh+n for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=n if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+TOP+' #(.ADDR_W(19))u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=model_lock_i && !upstream_fault_i && !a_f_state_fail_q_o && !b_f_state_fail_q_o && !a_f_fatal_o && !b_f_fatal_o && a_f_drained_o && b_f_drained_o;',
        '    always @*if(rst_n && f_joined)begin']
    for n in fields:
        lines+=['        assert(a_f_when_'+n+'_o==b_f_when_'+n+'_o);',
            '        if(a_f_when_'+n+'_o)assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);']
    for kind in histories:lines.append('        assert(a_f_live_'+kind+'_o==b_f_live_'+kind+'_o);')
    for kind in('embedding','layer','norm'):lines.append('        assert(a_f_meta_'+kind+'_o==b_f_meta_'+kind+'_o);')
    for copy in('a','b'):
        state=copy+'_f_state_state_q_o';capture=copy+'_f_state_capture_index_q_o'
        lines.append('        assert('+state+'<=23 || '+state+'==31);')
        for kind,capture_state,start,end in [('embedding',3,4,22),('layer',8,9,22),('norm',14,15,22)]:
            cond='('+state+'=='+str(capture_state)+' && '+capture+'!=0) || ('+state+'>='+str(start)+' && '+state+'<='+str(end)+')'
            lines.append('        if(!'+copy+'_f_state_fail_q_o && ('+cond+'))assert('+copy+'_f_meta_'+kind+'_o);')
        lines.append('        if(!'+copy+'_f_state_fail_q_o && '+copy+'_f_state_last_hidden_valid_q_o)assert('+copy+'_f_meta_layer_o);')
        lines.append('        if(!'+copy+'_f_state_fail_q_o && '+copy+'_f_state_last_hidden_valid_q_o)assert('+copy+'_f_meta_embedding_o);')
        for kind,consume_state in [('tape',2),('embedding',7),('layer',13),('norm',19)]:
            lines.append('        if(!clear_i && !'+copy+'_f_state_fail_q_o && '+state+'=='+str(consume_state)+')assert('+copy+'_f_live_'+kind+'_o);')
    for kind,row in writes.items():
        lines.append('        assert(a_f_write_'+kind+'_o==b_f_write_'+kind+'_o);')
        for suffix in('address','data'):lines.append('        if(a_f_write_'+kind+'_o)assert(a_f_write_'+kind+'_'+suffix+'_o==b_f_write_'+kind+'_'+suffix+'_o);')
    for instance,rows in child_inputs.items():
        for n,row in rows.items():
            if row['kind']!='admission_equality':continue
            name=row['tap'];lines+=['        assert(a_'+name+'_when==b_'+name+'_when);',
                '        if(a_'+name+'_when)assert(a_'+name+'==b_'+name+');']
    guards={'private_layer_position_o':'a_private_layer_start_valid_o',
        'private_layer_input_exponent_o':'a_private_layer_start_valid_o',
        'private_head_activation_exponent_o':'a_private_head_start_valid_o',
        'private_word_req_index_o':'a_private_word_req_valid_o','token_o':'a_token_valid_o'}
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard=guards.get(n,'1')
        if n in('private_layer_input_index_o','private_layer_input_mantissa_o','private_layer_input_last_o'):guard='a_private_layer_input_valid_o'
        if n in('private_head_activation_index_o','private_head_activation_mantissa_o','private_head_activation_last_o'):guard='a_private_head_activation_valid_o'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_state_embedding_exponent_q_o!=b_f_state_embedding_exponent_q_o);',
        '        cover(rst_n && f_joined && a_append_ready_o && append_valid_i);','    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files.update({'production-shell.sv':original,'shell.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
        'native-state-census.json':json.dumps(g,indent=2,sort_keys=True).encode()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='shell_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            initial_hard_reset=False,native_sequential_bits=len(qbits),sequential_fields=fields,
            per_field_relation=relations,actual_child_inputs=child_inputs,registered_memory_histories=histories,
            reply_coupling_predicates=coupling,concrete_module=TOP,
            entry_policy='Healthy model-locked CLEAR with no native shell sticky fault or fatal condition, DDR owner empty and all numerical/semantic children idle in both copies'),
        cuts=cuts,depth=3,induction_depth=3,cover_depth=8,timeout=args.timeout,
        source_list=['shell.sv','wrapper.sv'],expected_memories=0,optimize_full=True,
        primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Conditional actual token-shell scalar/control and guarded token-publication correspondence after healthy drained CLEAR without hard reset. All native registers and actual numerical-child admissions/writes observed. Registered tape/vector histories, numerical replies and enclosing completed-drain entry remain explicit contracts; no whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
