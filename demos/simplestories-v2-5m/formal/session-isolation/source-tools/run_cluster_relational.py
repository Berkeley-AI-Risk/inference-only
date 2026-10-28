"""Native numerical-cluster parent correspondence after CLEAR, no hard reset.

Observe the full controller and stalled row/postscale pipeline. Tile replies
are matched only at the selected owned registered-read phase; two postscale
products use their stateless operand-congruence contract. Every native tile
and postscale input is observed at its actual consuming phase.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from run_semantic_ingress import tap
from run_service_relational import synthesis_text, width

TOP='board1_clustered_projection_scale2'
TILE='board1_projection_tile16'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    original=(native/'project/cluster-engine.sv').read_bytes();tile_original=(native/'project/cluster-tile.sv').read_bytes()
    raw=original.decode();source=raw;serial='weight_pause_q'in raw
    tile_definition=re.search(r'^module '+TILE+r'\b[\s\S]*?^endmodule\b',tile_original.decode(),re.M)[0]
    tile_ports=parser.ports(tile_definition);tile_con=instance_con(raw,TILE,'u_tile')
    match=re.search(r'        '+TILE+r' u_tile\s*\([\s\S]*?\);',source)
    if not match:raise ValueError('Actual native tile instance changed')
    declarations=[];assignments=[];cuts=[];tile_inputs={};tile_replies={}
    for port,(direction,shape)in tile_ports.items():
        if port in('clk','reset_n'):
            tile_inputs[port]=dict(expression=tile_con[port],kind='shared_clock_or_reset');continue
        w=width(shape)
        if direction=='output':
            name='f_tile_'+port+'_i';declarations.append('    input wire ['+str(4*w-1)+':0] '+name)
            assignments.append('        assign '+tile_con[port]+'='+name+'[tile*'+str(w)+' +:'+str(w)+'];')
            tile_replies[name]=dict(word_width=w,data=port in('dot_o','multiplier_o','exponent_o'))
            cuts.append(dict(instance='g_tile[*].u_tile',module=TILE,port=port,replacement=name,instances=4))
        else:
            guard='1'
            if port=='valid_lanes_i':guard=tile_con['begin_i']
            elif port in('last_i','activation_i','weights_i'):guard=tile_con['accept_i']
            elif port.startswith('metadata_')and port!='metadata_write_i':guard=tile_con['metadata_write_i']
            elif port=='read_lane_i':guard=tile_con['read_i']
            name='f_input_tile_'+port+'_o'
            declarations+=['    output wire ['+str(4*w-1)+':0] '+name,'    output wire [3:0] '+name+'_when']
            assignments+=['        assign '+name+'[tile*'+str(w)+' +:'+str(w)+']='+tile_con[port]+';',
                '        assign '+name+'_when[tile]='+guard+';']
            tile_inputs[port]=dict(expression=tile_con[port],guard=guard,tap=name,width=w,kind='admission_equality')
    source=source[:match.start()]+'\n'.join(assignments)+source[match.end():]
    post_inputs={}
    for instance in('u_scale_low','u_scale_high'):
        con=instance_con(raw,'board1_projection_postscale_mul',instance)
        found=re.search(r'    board1_projection_postscale_mul '+instance+r'\s*\([\s\S]*?\);',source)
        if not found:raise ValueError('Actual stateless postscale instance changed')
        name='f_'+instance+'_product_i';declarations.append('    input wire [47:0] '+name)
        source=source[:found.start()]+'    assign '+con['product_o']+'='+name+';'+source[found.end():]
        post_inputs[instance]=con
        cuts.append(dict(instance=instance,module='board1_projection_postscale_mul',port='product_o',replacement=name,
            contract='Stateless configured multiplier congruence at matching current operands; vendor semantics premise explicit'))
    source=source.replace('\n);',',\n'+',\n'.join(declarations)+'\n);',1)
    # Observe the real successful descriptor register writer, including its
    # higher-priority error handling. No handshake alone grants ownership.
    for before,after in [('if (!reset_n) begin','if (!reset_n) begin\n            f_descriptor_owned<=0;'),
        ("end else if (clear_i === 1'b1) begin","end else if (clear_i === 1'b1) begin\n            f_descriptor_owned<=0;"),
        ('group_q <= fixed_group_i;','group_q <= fixed_group_i;f_descriptor_owned<=1;')]:
        if source.count(before)!=1:raise ValueError('Actual cluster descriptor writer changed')
        source=source.replace(before,after,1)
    source=source.replace('\nendmodule','\n    reg f_descriptor_owned;\nendmodule',1)
    census_name={'baseline':'native-hierarchy-r1','seeded-sampling':'native-hierarchy-seeded-sampling-r1',
        'kv-protected':'native-hierarchy-kv-protected-r1','encrypted-memory':'native-hierarchy-encrypted-memory-r4'}[args.variant]
    census=HERE/'runs'/census_name;c=json.loads((census/'CENSUS.json').read_text())
    rows=[r for r in c['instances']if r['original_module']==TOP]
    if len(rows)!=1:raise ValueError('Native cluster instance is not unique')
    g=json.loads((census/'hierarchy.json').read_text())['modules'][rows[0]['module']]
    qbits={b for cell in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',cell['type'])for b in cell['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
    observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
    pipeline={}
    for family,indices,bits in [('row_pipe_q',range(4),6),('exponent_pipe_q',range(1,4),8)]:
        for i in indices:
            name=family+'['+str(i)+']';item=g['netnames'].get(name,{}).get('bits',[])
            if len(item)!=bits:raise ValueError('Native pipeline word geometry changed')
            observed.update(b for b in item if isinstance(b,int));pipeline[name]=dict(bits=bits,phase=i)
    if not qbits.issubset(observed):raise ValueError('Unobserved native cluster storage')
    relations={n:'1'for n in fields}
    for n in('group_q','valid_lanes_q','columns_q','activation_exponent_q'):relations[n]='f_descriptor_owned'
    for n,phase in [('selected_tile_q',0),('low_operand_q',1),('high_operand_q',1),('scale_operand_q',1),
        ('low_product_q',2),('high_product_q',2),('result_q',3)]:relations[n]='state_q==EMIT && scale_valid_q['+str(phase)+']'
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
        **{'f_when_'+n+'_o':('',pred)for n,pred in relations.items()},
        'f_owner_o':('','f_descriptor_owned'),'f_live_o':('','live'),
        'f_advance_o':('','advance'),'f_issue_o':('','issue'),'f_control_error_o':('','control_error')}
    for n,row in pipeline.items():taps['f_pipe_'+n.replace('[','_').replace(']','')+'_o']=('['+str(row['bits']-1)+':0] ',n)
    for instance,con in post_inputs.items():
        for port in('a_i','b_i'):
            taps['f_input_'+instance+'_'+port+'_o']=('[26:0] 'if port=='a_i'else'[17:0] ',con[port])
    source=tap(source,taps);ports=parser.ports(source)
    coupling={n:'start_valid_i'for n in('fixed_layer_i','fixed_job_i','fixed_group_i','activation_exponent_i')}
    coupling.update({n:'metadata_valid_i'for n in('metadata_exponent_i','metadata_multiplier_i','metadata_row_index_i','metadata_last_i')})
    coupling.update({n:'weight_valid_i'for n in('activation_i','weight_data_i','weight_last_i')})
    coupling.update(result_ready_i='a_result_valid_o',done_ready_i='a_done_valid_o')
    coupling.update({n:'a_f_state_state_q_o==4 && a_f_state_scale_valid_q_o[1]'for n in('f_u_scale_low_product_i','f_u_scale_high_product_i')})
    coupling.update({n:'f_joined'for n,row in tile_replies.items()if not row['data']})
    lines=['module cluster_parent_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in list(coupling)+[n for n,r in tile_replies.items()if r['data']]]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            if copy=='b'and n in tile_replies and tile_replies[n]['data']:
                w=tile_replies[n]['word_width'];words=[]
                for i in reversed(range(4)):
                    guard='a_f_live_o && a_f_state_state_q_o==4 && a_f_state_scale_valid_q_o[0] && a_f_state_selected_tile_q_o=='+str(i)
                    part='['+str(i*w)+' +:'+str(w)+']';words.append('('+guard+' ? '+n+part+' : discarded_'+n+part+')')
                value='{'+','.join(words)+'}'
            con.append('.'+n+'('+value+')')
        lines.append('    '+TOP+' u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;',
        '    always @*if(rst_n && f_joined)begin','        assert(a_f_owner_o==b_f_owner_o);']
    for copy in('a','b'):
        lines+=['        assert('+copy+'_f_state_state_q_o<=5 || '+copy+'_f_state_state_q_o==7);',
            '        if('+copy+'_f_state_fail_q_o)assert('+copy+'_f_state_state_q_o==7);',
            '        if('+copy+'_f_state_state_q_o>=1 && '+copy+'_f_state_state_q_o<=5)assert('+copy+'_f_owner_o);',
            '        if('+copy+'_f_state_state_q_o!=4)assert('+copy+'_f_state_scale_valid_q_o==0);',
            '        if('+copy+'_f_owner_o)assert('+copy+'_f_state_issue_count_q_o<='+copy+'_f_state_valid_lanes_q_o);',
            '        if('+copy+'_f_state_state_q_o>=1 && '+copy+'_f_state_state_q_o<=5)begin',
            '            assert('+copy+'_f_state_valid_lanes_q_o==42 || '+copy+'_f_state_valid_lanes_q_o==51 || '+copy+'_f_state_valid_lanes_q_o==64);',
            '            assert('+copy+'_f_state_metadata_count_q_o<'+copy+'_f_state_valid_lanes_q_o);',
            '        end']
        for stage in range(4):
            count="{1'b0,"+copy+'_f_pipe_row_pipe_q_'+str(stage)+"_o}+7'd1"+''.join(
                "+{6'd0,"+copy+'_f_state_scale_valid_q_o['+str(i)+']}'for i in range(stage))
            lines.append('        if('+copy+'_f_state_state_q_o==4 && '+copy+'_f_state_scale_valid_q_o['+str(stage)+'])assert('+copy+'_f_state_issue_count_q_o=='+count+');')
    for n in fields:
        lines+=['        assert(a_f_when_'+n+'_o==b_f_when_'+n+'_o);',
            '        if(a_f_when_'+n+'_o)assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);']
    for n,row in pipeline.items():
        name='f_pipe_'+n.replace('[','_').replace(']','')+'_o'
        lines.append('        if(a_f_state_state_q_o==4 && a_f_state_scale_valid_q_o['+str(row['phase'])+'])assert(a_'+name+'==b_'+name+');')
    for port,row in tile_inputs.items():
        if row['kind']!='admission_equality':continue
        n=row['tap'];w=row['width'];lines.append('        assert(a_'+n+'_when==b_'+n+'_when);')
        for i in range(4):
            part='['+str(i*w)+' +:'+str(w)+']'
            lines.append('        if(a_'+n+'_when['+str(i)+'])assert(a_'+n+part+'==b_'+n+part+');')
    for instance in post_inputs:
        for port in('a_i','b_i'):
            name='f_input_'+instance+'_'+port+'_o'
            lines.append('        if(a_f_state_state_q_o==4 && a_f_state_scale_valid_q_o[1])assert(a_'+name+'==b_'+name+');')
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_result_valid_o'if n.startswith('result_')and n!='result_valid_o'else'1'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_state_low_operand_q_o!=b_f_state_low_operand_q_o);',
        '        cover(rst_n && f_joined && a_metadata_ready_o && metadata_valid_i);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-cluster.sv':original,'production-tile.sv':tile_original,
        'cluster.sv':('`undef FORMAL\n'+source).encode(),'wrapper.sv':wrapper.encode(),
        'runner.py':Path(__file__).read_bytes(),'native-state-census.json':json.dumps(g,sort_keys=True,indent=2).encode()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='cluster_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            concrete_module=TOP,initial_hard_reset=False,native_sequential_bits=len(qbits),
            sequential_fields=fields,per_field_relation=relations,native_pipeline_words=pipeline,
            actual_tile_inputs=tile_inputs,actual_postscale_inputs=post_inputs,
            operand_coupling_predicates=coupling,tile_reply_coupling=tile_replies,
            selected_tile_data_reply_condition='live, EMIT, scale_valid[0], and selected tile index; other registered reply lanes independent',
            serial=serial),cuts=cuts,depth=3,induction_depth=2,cover_depth=8,timeout=args.timeout,
        source_list=['cluster.sv','wrapper.sv'],expected_memories=0,map_literal_roms=True,
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Conditional native numerical-cluster controller and stalled postscale pipeline correspondence after CLEAR without hard reset. All native register/pipeline bits and every actual tile/postscale input observed under consumption ownership. Selected registered tile replies and stateless postscale products are explicit contracts. No assembled cluster or device theorem.')


if __name__=='__main__':raise SystemExit(main())
