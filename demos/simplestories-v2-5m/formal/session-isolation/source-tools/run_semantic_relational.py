"""Conditional native semantic controller correspondence after drained CLEAR.

Observe every parent scalar field and actual child input. RAM and numerical
replies are explicit valid/history seams; this does not close their contracts.
Retained exponents, RoPE/SiLU payloads and query lanes are observed only after
their actual current-session writer. No initial hard reset is used.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load
from run_service_relational import port_connections, synthesis_text, width


def erase_checks(text):
    for keyword in ('assert','cover'):
        while keyword+'('in text:
            start=text.index(keyword+'(');end=start+len(keyword)+1;level=1
            while level:level+=(text[end]=='(')-(text[end]==')');end+=1
            if text[end]!=';':raise ValueError('Observer statement changed')
            text=text[:start]+' begin end '+text[end+1:]
    return text


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=20)
    ap.add_argument('--primary-only',action='store_true')
    ap.add_argument('--solver-memory-mib',type=int,default=0)
    args=ap.parse_args()
    if args.solver_memory_mib and(not args.primary_only or args.solver_memory_mib<1):
        raise ValueError('A positive Z3 memory cap requires explicit primary-only mode')
    builder=load('datapath',HERE.parent/'authentication-access/run_datapath_access.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    files,binding,cuts,original_monitor=builder.derive(args.package,args.variant)
    raw=files['production-datapath.sv'].decode();top=builder.TOP
    source=files['datapath.sv'].decode().replace(original_monitor,erase_checks(original_monitor))
    prep=args.run.resolve().with_name(args.run.name+'-prepare');prep.mkdir(parents=True,exist_ok=False)
    (prep/'probe.sv').write_text(source)
    (prep/'probe.ys').write_text('read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv\nhierarchy -check -top '+top+'\nproc\nwrite_json probe.json\n')
    with(prep/'probe.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=prep,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Native parent state inventory failed')
    census_name={'baseline':'native-hierarchy-r1','seeded-sampling':'native-hierarchy-seeded-sampling-r1',
        'kv-protected':'native-hierarchy-kv-protected-r1','encrypted-memory':'native-hierarchy-encrypted-memory-r4'}[args.variant]
    census=HERE/'runs'/census_name
    native_graph=json.loads((census/'hierarchy.json').read_text())['modules']
    native_inventory=json.loads((census/'CENSUS.json').read_text())
    rows=[row for row in native_inventory['instances']if row['original_module']==top]
    if len(rows)!=1:raise ValueError('Actual native parent instance not unique')
    graph=native_graph[rows[0]['module']]
    qbits={b for c in graph['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])
           for b in c['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(graph['netnames'][n]['bits'])for n in sorted(assigned)if n in graph['netnames']and qbits.intersection(graph['netnames'][n]['bits'])}
    observed={b for n in fields for b in graph['netnames'][n]['bits']if isinstance(b,int)}
    if not qbits.issubset(observed):raise ValueError('Unobserved native scalar state')
    scratch=(HERE/'semantic-scratch-monitor.inc.sv').read_text()
    metadata=(HERE/'semantic-metadata-monitor.inc.sv').read_text()
    scratch=scratch.replace('(* anyconst *) reg [9:0] f_word;','wire [9:0] f_word=f_rel_word_i;')
    scratch=scratch.replace('(* anyconst *) reg [4:0] f_rope_word;','wire [4:0] f_rope_word=f_rel_rope_i;')
    monitor=(scratch+'\n'+metadata).replace('always @*if(rst_n && !clear_i && !fault_q)',
        'always @*if(rst_n && !clear_i && !fault_q && f_rel_join_i)')
    access=original_monitor.replace('if (rst_n) begin','if (rst_n && f_rel_join_i) begin')
    if access==original_monitor:raise ValueError('Original ownership guard changed')
    source=source.replace(erase_checks(original_monitor),access)
    meta={n+'_exponent_q':'f_'+n+'_meta'for n in('hidden','rms','query','key','value','attention','output','gate','up')}
    relation={n:'1'for n in fields}
    for n,predicate in meta.items():
        if n not in relation:raise ValueError('Retained exponent inventory changed')
        relation[n]=predicate
    for name,owner in [('rope_cosine_q','f_rope_cos_owned'),('rope_sine_q','f_rope_sin_owned'),
                       ('rope_operand0_q','f_rope_op0_owned'),('rope_operand1_q','f_rope_op1_owned'),('silu_value_q','f_silu_owned')]:
        if name not in relation:raise ValueError('Retained payload inventory changed')
        relation[name]=owner
    for n in('rope_phase_q','rope_head_q','rope_half_q','rope_second_index_q'):
        relation[n]='engine_state_q==E_ROPE'
    for n in('elem_phase_q','elem_index_q'):relation[n]='engine_state_q==E_ELEM'
    for n in('attention_head_q','attention_result_head_q'):relation[n]='engine_state_q==E_ATTN'
    query='attention_query_vector_q'
    if fields.pop(query,None)!=1024:raise ValueError('Native query staging width changed')
    relation.pop(query)
    ghosts=set(re.findall(r'\b(f_[a-zA-Z0-9_]+)\s*(?:[,;=])',monitor))
    # Only declared scalar owner flags are part of the relation. Symbolic-word
    # masks are retained for source faithfulness but need no cross-copy premise.
    owner_names=sorted(set(meta.values())|{'f_silu_owned','f_rope_cos_owned','f_rope_sin_owned',
        'f_rope_op0_owned','f_rope_op1_owned','f_query_lane_owned','f_rope_operand_read_live',
        'f_rope_operand_is_query','f_rope_read_live'})
    taps={**{'state_'+n:(w,n)for n,w in fields.items()},
        **{'relation_'+n:(1,p)for n,p in relation.items()},
        **{'owner_'+n:(1,n)for n in owner_names},
        'query_owned':(1,'f_query_lane_owned'),'query_word':(16,query+'[f_word[5:0]*16 +:16]'),
        'query_mask':(64,'f_rel_query_mask'),'query_full_buffer':(1024,query),
        'child_fault':(1,'child_fault'),
        'elem_data_phase':(1,'engine_state_q==E_ELEM && elem_phase_q!=EL_NORM_START && elem_phase_q!=EL_RAM_REQ'),
        'elem_is_silu':(1,'current_stage_q==STAGE_SILU_MUL')}
    coupling={};manifest={};live=[]
    definitions={}
    for filename,data in files.items():
        if filename.startswith('production-child-'):
            for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',data.decode(),re.M):definitions[m[1]]=m[0]
    for match in re.finditer(r'^    (board1_\w+)\s+(?:#\([^\n]*\)\s+)?(u_\w+)\s*\(',raw,re.M):
        module,instance=match[1],match[2];end=match.end();level=1
        while level:level+=(raw[end]=='(')-(raw[end]==')');end+=1
        con=port_connections(raw[match.end():end-1]);ports=parser.ports(definitions[module])
        if set(con)!=set(ports):raise ValueError('Incomplete production port inventory')
        ram='private_read_enable_i'in con
        if ram:
            flag='f_rel_live_'+instance;live.append('    reg '+flag+';\n    always @(posedge clk)if(!rst_n || clear_i)'+flag+'<=0;else if('+con['private_read_enable_i']+')'+flag+'<=1;')
            taps[flag]=(1,flag)
        entries={}
        for port,(direction,shape)in ports.items():
            if direction!='input':continue
            if port in('clk','rst_n','reset_n'):
                entries[port]=dict(expression=con[port],kind='clock_or_reset');continue
            guard='1'
            control=port.endswith(('_valid_i','_ready_i'))or port in('clear_i','model_lock_i','model_locked_i','upstream_fault_i','upstream_fail_closed_i','endpoint_fault_i',
                'summary_stage_begin_i','summary_pending_complete_i','summary_commit_i')
            if not control:
                if ram:
                    if port=='private_read_address_i':guard=con['private_read_enable_i']
                    elif port.startswith('private_write_')and port!='private_write_enable_i':guard=con['private_write_enable_i']
                elif port.startswith('private_word_rsp_'):guard=con['private_word_rsp_valid_i']
                elif port.startswith('kv_read_rsp_'):guard=con['kv_read_rsp_valid_i']
                elif port.startswith('kv_write_cpl_'):guard=con['kv_write_cpl_valid_i']
                elif port.startswith('lut_'):guard=con['lut_response_valid_i']
                elif instance=='u_kv_cache':
                    if port.startswith('stage_'):guard=con['stage_payload_valid_i']if port in('stage_coordinate_i','stage_key_i','stage_value_i','stage_last_i')else con['stage_begin_valid_i']
                    elif port.startswith('commit_'):guard=con['commit_valid_i']
                    elif port.startswith('attention_'):guard=con['attention_req_valid_i']
                elif instance=='u_attention':
                    if port.startswith('summary_stage_'):
                        guard='('+con['summary_stage_begin_i']+') || ('+con['summary_stage_value_valid_i']+')'if port=='summary_stage_exponent_i'else con['summary_stage_value_valid_i']
                    elif port.startswith('private_cache_response_'):guard=con['private_cache_response_valid_i']
                    elif port.startswith('query_'):guard=con['query_valid_i']if port!='query_exponent_i'else con['start_valid_i']
                    else:guard=con['start_valid_i']
                elif port.startswith('input_')and port!='input_exponent_i':guard=con['input_valid_i']
                elif instance=='u_projection'and port in('activation_i','activation_last_i'):guard=con['activation_valid_i']
                else:guard=con.get('request_valid_i',con.get('start_valid_i','1'))
                if instance=='u_elementwise_lane'and port in('cosine_i','sine_i'):
                    guard='('+guard+') && ('+con['operation_i']+'==0)'
                if instance=='u_elementwise_lane'and port=='lut_value_i':
                    guard='('+guard+') && f_silu_owned'
            delivery={'result_ready_i':'result_valid_o','response_ready_i':'response_valid_o',
                      'done_ready_i':'done_valid_o','attention_rsp_ready_i':'attention_rsp_valid_o',
                      'private_word_req_ready_i':'private_word_req_valid_o'}
            if port in delivery:
                valid_port=delivery[port]
                if valid_port not in con:raise ValueError('Missing corresponding child valid port')
                guard=con[valid_port]
            name='input_'+instance+'_'+port;taps[name]=(width(shape),con[port]);taps[name+'_when']=(1,guard)
            entries[port]=dict(expression=con[port],guard=guard,tap=name,kind='admission_equality')
        manifest[instance]=dict(module=module,inputs=entries)
        valid={r['port']:r['replacement']for r in cuts if r['instance']==instance and r['port'].endswith('_valid_o')}
        for row in [r for r in cuts if r['instance']==instance]:
            port=row['port'];predicate=None
            if ram:predicate='a_'+flag
            elif port.startswith('result_')and port!='result_valid_o':predicate=valid.get('result_valid_o')
            elif port.startswith('response_')and port not in('response_valid_o','response_ready_o'):predicate=valid.get('response_valid_o')
            elif port.startswith('attention_rsp_')and port!='attention_rsp_valid_o':predicate=valid.get('attention_rsp_valid_o')
            if predicate:coupling[row['replacement']]=predicate
            if ram and instance=='u_gate_scratch':
                # This extension is redundant on the actual joined controller:
                # its proved LUT request implies the same sticky fresh-read
                # flag. It prevents impossible free requests from comparing
                # an unowned speculative RAM payload in the parent index check.
                coupling[row['replacement']]='(a_'+flag+' || f_child_u_elementwise_lane_lut_request_o)'
    if len(manifest)!=17:raise ValueError('Semantic child inventory changed')
    extra=',\n    input wire f_rel_join_i,\n    input wire [9:0] f_rel_word_i,\n    input wire [4:0] f_rel_rope_i,\n'+',\n'.join(
        '    output wire ['+str(w-1)+':0] f_rel_'+n+'_o'for n,(w,_)in taps.items())+'\n'
    source=source.replace('\n);',extra+');',1)
    query_mask='''
    reg [63:0] f_rel_query_mask;
    always @(posedge clk)begin
        if(!rst_n || clear_i || f_new_attention || attention_query_fire)f_rel_query_mask<=0;
        else if(engine_state_q==E_ATTN && attention_query_read_valid_q)
            f_rel_query_mask[attention_query_load_lane_q]<=1;
    end
'''
    source=source.replace('\nendmodule','\n'+monitor+'\n'+query_mask+'\n'+'\n'.join(live)+'\n'+'\n'.join(
        '    assign f_rel_'+n+'_o='+expr+';'for n,(_,expr)in taps.items())+'\nendmodule',1)
    ports=parser.ports(source);ports.pop('f_rel_word_i');ports.pop('f_rel_rope_i');ports.pop('f_rel_join_i')
    lines=['module semantic_parent_relational(',',\n'.join(
        ['    input wire '+sh+n for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');',
        '    (* anyconst *)reg[9:0]f_word;',
        '    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        for n,(w,_)in taps.items():lines.append('    wire ['+str(w-1)+':0] '+copy+'_'+n+'='+copy+'_f_rel_'+n+'_o;')
        con=[]
        for n,(di,_)in ports.items():
            value=n if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        con+=['.f_rel_word_i(f_word)',".f_rel_rope_i(5'd0)",'.f_rel_join_i(f_joined)']
        lines.append('    '+top+' #(.ADDR_W(19))u_'+copy+'('+','.join(con)+');')
    healthy=' && '.join('!'+c+'_state_'+n for c in('a','b')for n in('fault_q','ddr_arbiter_fault_q','ddr_owner_q','ddr_pending_q'))
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i && model_lock_i && !private_word_rsp_valid_i && !a_child_fault && !b_child_fault && '+healthy+')f_joined<=1;',
        '    always @*if(rst_n && f_joined)begin']
    if not re.search(r'E_FAULT\s*=\s*4\x27d15',raw):raise ValueError('Native fault-state encoding changed')
    lines+=['        if(a_state_fault_q)assert(a_state_engine_state_q==15 || a_state_engine_state_q==0);',
            '        if(b_state_fault_q)assert(b_state_engine_state_q==15 || b_state_engine_state_q==0);',
            '        assert(a_state_lock_seen_q);assert(b_state_lock_seen_q);']
    for copy in ('a','b'):
        for valid,ram in [('hidden_read_valid_q','u_hidden_state'),('rms_read_valid_q','u_rms_scratch'),
            ('down_gate_valid_q','u_gate_scratch'),('attention_read_valid_q','u_attention_scratch'),
            ('kv_read_valid_q','u_key_state'),('kv_read_valid_q','u_value_state'),
            ('attention_query_read_valid_q','u_query_state')]:
            lines.append('        if('+copy+'_state_'+valid+')assert('+copy+'_f_rel_live_'+ram+');')
        lines+=['        if('+copy+'_owner_f_rope_operand_read_live)begin',
                '            if('+copy+'_owner_f_rope_operand_is_query)assert('+copy+'_f_rel_live_u_query_state);',
                '            else assert('+copy+'_f_rel_live_u_key_state);','        end',
                '        if('+copy+'_owner_f_rope_read_live)assert('+copy+'_f_rel_live_u_rope_raw_scratch);']
        lines+=['        if('+copy+'_elem_data_phase && !'+copy+'_state_fault_q)begin',
                '            if('+copy+'_elem_is_silu)begin',
                '                assert('+copy+'_f_rel_live_u_gate_scratch);assert('+copy+'_f_rel_live_u_up_scratch);',
                '            end else begin',
                '                assert('+copy+'_f_rel_live_u_hidden_state);assert('+copy+'_f_rel_live_u_output_scratch);',
                '            end','        end']
    for n in owner_names:
        guard='if(a_owner_f_rope_operand_read_live)'if n=='f_rope_operand_is_query'else''
        lines.append('        '+guard+'assert(a_owner_'+n+'==b_owner_'+n+');')
    for n in fields:
        lines+=['        assert(a_relation_'+n+'==b_relation_'+n+');',
                '        if(a_relation_'+n+')assert(a_state_'+n+'==b_state_'+n+');']
    lines+=['        assert(a_query_owned==b_query_owned);','        if(a_query_owned)assert(a_query_word==b_query_word);']
    lines+=['        assert(a_query_mask==b_query_mask);',
            '        if(a_input_u_attention_query_valid_i)assert(&a_query_mask);']
    for i in range(64):
        lines.append('        if(a_query_mask['+str(i)+'])assert(a_query_full_buffer['+str(16*i)+' +:16]==b_query_full_buffer['+str(16*i)+' +:16]);')
        for copy in ('a','b'):
            lines.append('        if(!clear_i && !'+copy+'_state_fault_q && '+copy+'_state_engine_state_q==5 && ('+
                str(i)+'<'+copy+'_state_attention_query_load_lane_q || '+copy+'_state_attention_query_loaded_q))assert('+
                copy+'_query_mask['+str(i)+']);')
    for n in taps:
        if n.startswith('f_rel_live_'):lines.append('        assert(a_'+n+'==b_'+n+');')
    for entry in manifest.values():
        for row in entry['inputs'].values():
            if row['kind']!='admission_equality':continue
            n=row['tap'];lines+=['        assert(a_'+n+'_when==b_'+n+'_when);',
                '        if(a_'+n+'_when)assert(a_'+n+'==b_'+n+');']
    # Final hidden-vector reads need the enclosing caller's completion and
    # owned-read boundary. Observe every other native external output here.
    observations={};unobserved={}
    for n,(direction,_)in ports.items():
        if direction!='output'or n.startswith('f_rel_'):continue
        if n in('private_result_mantissa_o','private_result_exponent_o'):
            unobserved[n]='Final hidden-vector caller completion and read ownership must be joined separately.';continue
        guard='1'
        for prefix,valid in [('private_head_result_','private_head_result_valid_o'),
                             ('kv_write_req_','kv_write_req_valid_o'),('kv_read_req_','kv_read_req_valid_o')]:
            if n.startswith(prefix)and n!=valid:guard='a_'+valid
        if n=='private_word_req_index_o':guard='a_private_word_req_valid_o'
        observations[n]=guard
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    for copy in ('a','b'):
        lines.append('        if(!clear_i && !'+copy+'_state_fault_q && '+copy+'_state_engine_state_q==6 && ('+
            copy+'_state_elem_phase_q==2 || '+copy+'_state_elem_phase_q==3))assert('+copy+'_state_current_stage_q==13);')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_state_hidden_exponent_q!=b_state_hidden_exponent_q);',
        '        cover(rst_n && f_joined && private_stage_valid_i && a_private_stage_ready_o);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files.update({'datapath.sv':source.encode(),'wrapper.sv':wrapper.encode(),
        'relational-runner.py':Path(__file__).read_bytes(),'service-parser.py':(HERE/'run_service_relational.py').read_bytes(),
        'scratch-monitor.inc.sv':scratch.encode(),'metadata-monitor.inc.sv':metadata.encode(),
        'native-state-census.json':json.dumps(graph,indent=2,sort_keys=True).encode(),
        'native-census-receipt.json':(census/'CENSUS.json').read_bytes(),
        **{p.name:p.read_bytes()for p in prep.iterdir()if p.is_file()}})
    binding.update(initial_hard_reset=False,sequential_fields=fields,per_field_relation=relation,
        native_parent_sequential_bits=len(qbits),actual_child_inputs=manifest,reply_coupling_predicates=coupling,
        observed_native_outputs=observations,unobserved_native_outputs=unobserved,
        entry_policy='Common CLEAR with model LOCK, both parents and child aggregate faults healthy, drained DDR owner/pending count, and no model-word reply that cycle',
        required_nested_permission='The actual compact lane consumes LUT data only in ST_SILU_WAIT. A response there must imply current-session f_silu_owned; this is a separate actual-controller protocol-join obligation, not an assumption in this parent proof.')
    binding['gate_read_reply_extension']='Fresh-read OR LUT-request equality. The actual controller protocol must prove LUT request implies the identical sticky gate read flag, making this extension redundant on concrete traces.'
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='semantic_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert(')+2*(original_monitor.count('assert(')+monitor.count('assert(')),
        covers=2+2*original_monitor.count('cover('),observer_constants=1,binding=binding,cuts=cuts,
        depth=3,induction_depth=1,cover_depth=8,timeout=args.timeout,source_list=['datapath.sv','wrapper.sv'],
        optimize_full=True,expected_memories=0,primary_only=args.primary_only,
        solver_cli={s:['--unroll']+(['-S','-memory:'+str(args.solver_memory_mib)]if s=='z3'and args.solver_memory_mib else[])for s in('z3','cvc5')},
        scope='Conditional actual semantic controller correspondence after healthy drained CLEAR, arbitrary old retained fields and independent invalid RAM/numerical replies. Native RAM/child session contracts and enclosing token publication remain separate; no whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
