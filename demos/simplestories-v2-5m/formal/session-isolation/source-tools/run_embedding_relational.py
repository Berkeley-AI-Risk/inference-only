"""Native tied-embedding controller correspondence after healthy drained CLEAR."""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap
from run_service_memory import boundaries
from run_service_relational import synthesis_text, width
from run_projection_relational import instance_con


def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25);args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(HERE.parents[1]/'fpga-demo/public-release','baseline')
    top='board1_fixed_embedding_lookup';definitions={}
    for name in binding['distributed_inputs']:
        if not name.endswith('.sv'):continue
        raw=(native/name).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',raw.decode(),re.M):definitions[m[1]]=(m[0],name,raw)
    raw,relative,original=definitions[top];source,files,cuts,count=boundaries(raw,definitions,parser)
    if count!=2:raise ValueError('Native tied-embedding child inventory changed')
    p=HERE/'runs/native-hierarchy-r1';c=json.loads((p/'CENSUS.json').read_text())
    rows=[r for r in c['instances']if r['original_module']==top]
    if len(rows)!=1:raise ValueError('Native embedding is not unique')
    g=json.loads((p/'hierarchy.json').read_text())['modules'][rows[0]['module']]
    q={b for cell in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe)',cell['type'])for b in cell['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and q.intersection(g['netnames'][n]['bits'])}
    if not q.issubset({b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}):raise ValueError('Native embedding scalar state omitted')
    for before,after in [('token_q <= fixed_token_i;','token_q <= fixed_token_i;f_token_owned<=1;f_header_owned<=0;'),
        ('row_exponent_q <= selected_header_exponent;','row_exponent_q <= selected_header_exponent;f_header_owned<=1;'),
        ("token_q <= 12'd0;","token_q <= 12'd0;f_token_owned<=0;f_header_owned<=0;"),
        ('state_q <= ST_DRAIN;','state_q <= ST_DRAIN;f_token_owned<=0;f_header_owned<=0;')]:
        if source.count(before)!=1:raise ValueError('Actual embedding ownership writer changed')
        source=source.replace(before,after,1)
    source=source.replace('\nendmodule','\n    reg f_token_owned,f_header_owned;\nendmodule',1)
    relations={n:'1'for n in fields};relations.update(token_q='f_token_owned',row_exponent_q='f_header_owned',row_multiplier_q='f_header_owned')
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
        **{'f_when_'+n+'_o':('',pred)for n,pred in relations.items()},
        'f_token_owned_o':('','f_token_owned'),'f_header_owned_o':('','f_header_owned'),
        'f_fatal_o':('','aggregate_fault || (start_valid_i && state_q!=ST_IDLE)'),
        'f_drained_o':('','!group_busy && !norm_busy')}
    child_inputs={};coupling={}
    for instance in sorted({r['instance']for r in cuts}):
        module=next(r['module']for r in cuts if r['instance']==instance)
        con=instance_con(raw,module,instance);declared=parser.ports(definitions[module][0]);child_inputs[instance]={}
        replies=[r for r in cuts if r['instance']==instance]
        valid=next(r['replacement']for r in replies if r['port']in('group_valid_o','result_valid_o'))
        for row in replies:
            condition='f_joined'
            if row['port'].startswith('group_')and row['port']!='group_valid_o':condition='f_joined && '+valid
            elif row['port'].startswith('weight_')and row['port']!='weight_valid_o':
                weight=next(r['replacement']for r in replies if r['port']=='weight_valid_o');condition='f_joined && '+weight
            elif row['port'].startswith('result_')and row['port']!='result_valid_o':condition='f_joined && '+valid
            elif row['port']=='private_word_req_index_o':condition='f_joined && '+next(r['replacement']for r in replies if r['port']=='private_word_req_valid_o')
            coupling[row['replacement']]=condition
        for name,(di,shape)in declared.items():
            if di!='input':continue
            if name in('clk','rst_n','reset_n'):
                child_inputs[instance][name]=dict(expression=con[name],kind='shared_clock_or_reset');continue
            guard='1'
            if name in('fixed_layer_i','fixed_job_i','fixed_group_i'):guard=con['start_valid_i']
            elif name.startswith('input_')and name not in('input_valid_i','input_ready_i'):guard=con['input_valid_i']
            elif name=='group_ready_i':guard='group_valid'
            elif name=='weight_ready_i':guard='group_weight_valid'
            elif name=='result_ready_i':guard='norm_result_valid'
            elif name=='done_ready_i':guard='norm_done_valid'if 'normalizer'in module else'group_done_valid'
            elif name in('private_word_rsp_data_i','private_word_rsp_fault_i'):guard=con['private_word_rsp_valid_i']
            port='f_input_'+instance+'_'+name+'_o';taps[port]=('['+str(width(shape)-1)+':0] ',con[name]);taps[port+'_when']=('',guard)
            child_inputs[instance][name]=dict(expression=con[name],guard=guard,tap=port,kind='admission_equality')
    source=tap(source,taps);ports=parser.ports(source)
    coupling.update(fixed_token_i='start_valid_i',result_ready_i='a_result_valid_o',done_ready_i='a_done_valid_o',
        private_word_rsp_data_i='private_word_rsp_valid_i',private_word_rsp_fault_i='private_word_rsp_valid_i')
    lines=['module embedding_parent_relational(',',\n'.join(
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
        lines.append('    '+top+' #(.ADDR_W(19))u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=model_lock_i && !upstream_fault_i && !a_f_fatal_o && !b_f_fatal_o && a_f_drained_o && b_f_drained_o;',
        '    always @*if(rst_n && f_joined)begin']
    for n in fields:lines+=['        assert(a_f_when_'+n+'_o==b_f_when_'+n+'_o);',
        '        if(a_f_when_'+n+'_o)assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);']
    lines+=['        assert(a_f_token_owned_o==b_f_token_owned_o);assert(a_f_header_owned_o==b_f_header_owned_o);']
    for copy in('a','b'):
        state=copy+'_f_state_state_q_o'
        lines+=['        assert('+state+'<=8 || '+state+'==15);',
            '        if('+state+'>=1 && '+state+'<=7)assert('+copy+'_f_token_owned_o);',
            '        if('+state+'>=3 && '+state+'<=7)assert('+copy+'_f_header_owned_o);']
    for instance,rows in child_inputs.items():
        for n,row in rows.items():
            if row['kind']!='admission_equality':continue
            port=row['tap'];lines+=['        assert(a_'+port+'_when==b_'+port+'_when);',
                '        if(a_'+port+'_when)assert(a_'+port+'==b_'+port+');']
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_result_valid_o'if n.startswith('result_')and n!='result_valid_o'else'a_private_word_req_valid_o'if n=='private_word_req_index_o'else'1'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_state_token_q_o!=b_f_state_token_q_o);',
        '        cover(rst_n && f_joined && a_start_ready_o && start_valid_i);','    end','endmodule']
    wrapper='\n'.join(lines)+'\n';files.update({'production-embedding.sv':original,
        'embedding.sv':('`undef FORMAL\n'+source).encode(),'wrapper.sv':wrapper.encode(),
        'runner.py':Path(__file__).read_bytes(),'native-state-census.json':json.dumps(g,indent=2,sort_keys=True).encode()})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='embedding_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant='baseline',
            initial_hard_reset=False,concrete_module=top,native_sequential_bits=len(q),sequential_fields=fields,
            per_field_relation=relations,actual_child_inputs=child_inputs,reply_coupling_predicates=coupling,
            entry_policy='Healthy drained model-locked CLEAR, with no actual aggregate or invalid-start fatal condition in either copy'),
        cuts=cuts,depth=3,induction_depth=3,cover_depth=8,timeout=args.timeout,
        source_list=['embedding.sv','wrapper.sv'],expected_memories=0,primary_only=True,optimize_full=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Conditional actual tied-embedding controller correspondence after healthy drained CLEAR without hard reset. All 83 native scalar bits, actual group-stream/normalizer inputs and guarded outputs compared; real descriptor/header writers initialize retained metadata. Concrete selected-coefficient multiplication retained. Whole child reply contracts and enclosing completed drain remain explicit; no device theorem.')


if __name__=='__main__':raise SystemExit(main())
