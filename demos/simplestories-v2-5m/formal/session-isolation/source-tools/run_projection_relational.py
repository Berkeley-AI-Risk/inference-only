"""Conditional two-run native projection job and DDR-stream correspondence.

Keep actual controller transitions. Replace only the registered activation
reply and completed immutable metadata header with explicit history seams.
Native full-memory history proofs and child numerical contracts remain separate.
"""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load
from run_semantic_ingress import tap, extend_instance
from run_service_relational import synthesis_text, port_connections, width
from run_semantic_relational import erase_checks
from record_progress import audit, sha
from run_projection_stream_join import STREAM, DELTA, ADAPTER


def instance_con(raw,module,instance):
    m=re.search(r'\b'+module+r'\s*(?:#\([\s\S]*?\)\s*)?'+instance+r'\s*\(',raw)
    if not m:raise ValueError('Actual child binding missing '+instance)
    start=m.end();end=start;depth=1
    while depth:depth+=(raw[end]=='(')-(raw[end]==')');end+=1
    return port_connections(raw[start:end-1])


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--source-run',type=Path,required=True)
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args();prior=args.source_run.resolve()
    receipt=audit(prior.name,'projection controller prerequisite')
    if receipt['status']!='proved_component':raise ValueError('Native controller join is incomplete')
    inputs=json.loads((prior/'INPUTS.json').read_text())
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    files={n:(prior/n).read_bytes()for n in inputs['files']if n.startswith('production')or n in('delta.sv',)}
    service=(prior/'service.sv').read_text();stream=(prior/'stream.sv').read_text()
    memory_monitor=(prior/'ownership-monitor.inc.sv').read_text()
    if service.count(memory_monitor)!=1:raise ValueError('Frozen RAM observer identity differs')
    service=service.replace(memory_monitor,erase_checks(memory_monitor))
    service=service.replace('if(reset_n && f_completed_clear && !clear_i && !integrated_fail)',
        'if(reset_n && f_rel_join_i && f_completed_clear && !clear_i && !integrated_fail)')
    service=service.replace('\n);',',\n    input wire f_rel_join_i\n);',1)
    # Native synchronous activation data is replaced only at its registered
    # read result. Its actual writer/control/read-enable/tag logic remains.
    pattern=r'if\s*\(activation_store_read\)\s*activation_q\s*<=\s*activation_memory_q\[activation_store_read_address\];'
    if len(re.findall(pattern,service))!=1:raise ValueError('Native activation read register differs')
    service=re.sub(pattern,'begin end',service)
    service=service.replace('\n);',',\n    input wire [15:0] f_ram_reply_i\n);',1)
    service=service.replace('\nendmodule','\n    assign activation_q=f_ram_reply_i;\nendmodule',1)
    # Packed row metadata does not drive stream control. The complete fresh
    # header is a separate native-memory history contract, not zeroed storage.
    header=re.compile(r'    genvar lane;\s*generate[\s\S]*?endgenerate')
    if len(header.findall(stream))!=1:raise ValueError('Native packed metadata output binding differs')
    stream=header.sub('    assign group_row_exponent_o=f_header_exponents_i;\n    assign group_row_multiplier_o=f_header_multipliers_i;',stream)
    stream=stream.replace('\n);',',\n    input wire [511:0] f_header_exponents_i,\n    input wire [1023:0] f_header_multipliers_i\n);',1)
    # Attach descriptor ownership to the real register-writer branches. A
    # ready/valid pulse can coincide with an error of higher priority and must
    # not make retained descriptor bits authoritative when the write is skipped.
    for kind,text,flag,clear_branch,done_branch in [
        ('job',service,'f_rel_descriptor_owned',"end else if (clear_i === 1'b1) begin",'if (done_valid_o && done_ready_i) begin'),
        ('stream',stream,'f_descriptor_owned','end else if (clear_i) begin','end else if (done_transfer) begin')]:
        for before,after in [
            ('if (!reset_n) begin','if (!reset_n) begin\n            '+flag+'<=0;'),
            (clear_branch,clear_branch+'\n            '+flag+'<=0;'),
            ('layer_q <= fixed_layer_i;','layer_q <= fixed_layer_i;\n                                '+flag+'<=1;'),
            (done_branch,done_branch+'\n                            '+flag+'<=0;')]:
            if text.count(before)!=1:raise ValueError('Actual '+kind+' descriptor-writer branch changed: '+before)
            text=text.replace(before,after,1)
        text=text.replace('\nendmodule','\n    reg '+flag+';\nendmodule',1)
        if kind=='job':service=text
        else:stream=text
    service=service.replace('\n);',',\n    input wire [511:0] f_header_exponents_i,\n    input wire [1023:0] f_header_multipliers_i\n);',1)
    service=extend_instance(service,'u_group_stream',{
        'f_header_exponents_i':'f_header_exponents_i','f_header_multipliers_i':'f_header_multipliers_i'})
    census=HERE/'runs/native-hierarchy-r1'
    inventory=json.loads((census/'CENSUS.json').read_text())
    graph=json.loads((census/'hierarchy.json').read_text())['modules']
    state_inventory={};sources={'job':service,'stream':stream};originals={
        'job':(prior/'production-service.sv').read_text(),
        'stream':(prior/'production-stream.sv').read_text().split('\nendmodule',1)[0]+'\nendmodule'}
    modules={'job':'board1_fixed_group_projection_scale_job','stream':STREAM}
    masks={'job':{'layer_q','job_q','activation_exponent_q','rows_q','columns_q','groups_q'},
        'stream':{'layer_q','job_q','group_q','valid_lanes_q','group_beats_q','group_words_q','weight_base_word_q'}}
    maps={}
    for kind,module in modules.items():
        rows=[r for r in inventory['instances']if r['original_module']==module]
        if kind=='stream':rows=[r for r in rows if r['path'].endswith('/u_projection/u_group_stream')]
        if len(rows)!=1:raise ValueError('Native controller instance is not unique')
        g=graph[rows[0]['module']]
        qbits={b for c in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])for b in c['connections']['Q']if isinstance(b,int)}
        assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(originals[kind])))
        fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
        observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
        if not qbits.issubset(observed):raise ValueError('Uninventoried native controller state')
        state_inventory[kind]=dict(native_bits=len(qbits),fields=fields)
        if kind=='job':
            if fields.pop('activation_q')!=16:raise ValueError('Registered activation seam width changed')
            extra={'owner':('','f_rel_descriptor_owned'),'ram_live':('','f_read_live'),'clear_done':('','f_completed_clear')}
        else:extra={'owner':('','f_descriptor_owned')}
        taps={**{'f_rel_'+kind+'_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
            **{'f_rel_'+kind+'_'+n+'_o':row for n,row in extra.items()}}
        maps[kind]=taps
        sources[kind]=tap(sources[kind],taps)
    stream=sources['stream'];service=sources['job']
    # Forward the stream observations through its real native parent.
    service=tap(service,{n:(sh,n)for n,(sh,_)in maps['stream'].items()})
    declarations='\n'.join('    wire '+sh+'f_stream_wire_'+n+';'for n,(sh,_)in maps['stream'].items())
    # Parent output names and nested stream output names are distinct nets.
    for n in maps['stream']:
        before='    assign '+n+'='+n+';'
        if service.count(before)!=1:raise ValueError('Observer forwarding changed')
        service=service.replace(before,'    assign '+n+'=f_stream_wire_'+n+';')
    service=service.replace('\nendmodule','\n'+declarations+'\nendmodule',1)
    service=extend_instance(service,'u_group_stream',{n:'f_stream_wire_'+n for n in maps['stream']})
    cuts=inputs['internal_cuts'];coupling={'f_ram_reply_i':'a_f_rel_job_ram_live_o',
        'f_header_exponents_i':'a_f_rel_stream_state_q_o==3',
        'f_header_multipliers_i':'a_f_rel_stream_state_q_o==3'}
    for instance in sorted({r['instance']for r in cuts}):
        rows=[r for r in cuts if r['instance']==instance];by_port={r['port']:r['replacement']for r in rows}
        for row in rows:
            port=row['port'];condition=None
            for prefix,valid in [('result_','result_valid_o'),('metadata_','metadata_valid_o'),
                ('weight_data','weight_valid'),('out_data_','out_valid_o')]:
                if port.startswith(prefix)and port!=valid and valid in by_port:condition=by_port[valid]
            if port=='private_word_req_index_o':condition=by_port['private_word_req_valid_o']
            if condition:coupling[row['replacement']]=condition
    # Every actual child input is observed. The two nested real controllers
    # are retained; their history/numerical children are conditional seams.
    child_manifest={};service_taps={};stream_taps={}
    service_taps.update({
        'f_memory_write_o':('','activation_store_write'),
        'f_memory_write_address_o':('[9:0] ','activation_count_q'),
        'f_memory_write_data_o':('[15:0] ','activation_i'),
        'f_memory_read_o':('','activation_store_read'),
        'f_memory_read_address_o':('[9:0] ','activation_store_read_address'),
    })
    stream_taps.update({
        'f_metadata_write_o':('','metadata_transfer'),
        'f_metadata_write_address_o':('[5:0] ','metadata_count_q[5:0]'),
        'f_metadata_write_data_o':('[23:0] ','{meta_exponent,meta_multiplier}'),
    })
    definitions={}
    for name,data in files.items():
        if name.startswith('production'):
            for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',data.decode(),re.M):definitions[m[1]]=m[0]
    definitions[STREAM]=originals['stream']
    children=[('job','u_group_stream',STREAM),('job','u_shared_engine',ADAPTER)]+[
        ('stream',instance,next(r['module']for r in cuts if r['instance']==instance))
        for instance in sorted({r['instance']for r in cuts if r['instance']!='u_shared_engine'})]
    children.append(('stream','u_outstanding_delta',DELTA))
    for kind,instance,module in children:
        con=instance_con(originals[kind],module,instance);ports=parser.ports(definitions[module]);entries={}
        for port,(di,sh)in ports.items():
            if di!='input':continue
            if port=='clk'or port in('reset_n','rst_n')and con[port]=='reset_n':
                entries[port]=dict(expression=con[port],kind='shared_clock_or_reset');continue
            guard='1';control=port.endswith(('_valid_i','_ready_i'))or port in('clear_i','model_locked_i','upstream_fail_closed_i','ddr_word_valid','weight_ready','out_ready_i')
            if not control:
                if port.startswith('group_')or port=='activation_exponent_i'and kind=='job'and instance=='u_shared_engine':guard=con['group_valid_i']
                elif port in('activation_i','weight_data_i','weight_last_i'):guard=con['weight_valid_i']
                elif port.startswith('fixed_'):guard=con['start_valid_i']
                elif port.startswith('private_word_rsp_'):guard=con['private_word_rsp_valid_i']
                elif port=='ddr_word_data':guard=con['ddr_word_valid']
                elif port=='in_data_i':guard=con['in_valid_i']
            name='f_input_'+kind+'_'+instance+'_'+port+'_o'
            target=service_taps if kind=='job'else stream_taps
            target[name]=(sh,con[port]);target[name+'_when']=('',guard)
            entries[port]=dict(tap=name,guard=guard,expression=con[port],kind='admission_equality')
        child_manifest[kind+'.'+instance]=dict(module=module,inputs=entries)
    stream=tap(stream,stream_taps)
    service=tap(service,{**service_taps,**{n:(sh,'f_stream_wire_'+n)for n,(sh,_)in stream_taps.items()}})
    service=service.replace('\nendmodule','\n'+'\n'.join('    wire '+sh+'f_stream_wire_'+n+';'for n,(sh,_)in stream_taps.items())+'\nendmodule',1)
    service=extend_instance(service,'u_group_stream',{n:'f_stream_wire_'+n for n in stream_taps})
    ports=parser.ports(service)
    lines=['module projection_parent_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items()if di=='input'and n!='f_rel_join_i']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if n=='f_rel_join_i':value='f_joined'
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+modules['job']+' #(.ADDR_W(19))u_'+copy+'('+','.join(con)+');')
    admission='model_locked_i && !upstream_fail_closed_i && !private_word_rsp_valid_i && !a_fail_closed_o && !b_fail_closed_o && a_f_rel_stream_state_q_o!=7 && b_f_rel_stream_state_q_o!=7 && !a_f_rel_stream_owner_q_o && !b_f_rel_stream_owner_q_o && !a_f_rel_stream_outstanding_words_q_o && !b_f_rel_stream_outstanding_words_q_o'
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<='+admission+';',
        '    always @*if(rst_n && f_joined)begin']
    for copy in('a','b'):
        lines+=['        assert('+copy+'_f_rel_job_clear_done_o);',
            '        if('+copy+'_f_rel_stream_state_q_o>=1 && '+copy+'_f_rel_stream_state_q_o<=5)assert('+copy+'_f_rel_stream_owner_o);',
            '        if(!clear_i && !'+copy+'_fail_closed_o && '+copy+'_f_rel_job_state_q_o>=1 && '+copy+'_f_rel_job_state_q_o<=4)assert('+copy+'_f_rel_job_owner_o);',
            '        if(!clear_i && !'+copy+'_fail_closed_o && '+copy+'_f_rel_job_state_q_o>=2 && '+copy+'_f_rel_job_state_q_o<=4)assert('+copy+'_f_rel_job_ram_live_o);']
    for kind,taps in maps.items():
        owner='a_f_rel_'+kind+'_owner_o'
        lines.append('        assert('+owner+'==b_f_rel_'+kind+'_owner_o);')
        for name in taps:
            field=name[len('f_rel_'+kind+'_'):-2]
            guard=owner if field in masks[kind]else'1'
            lines.append('        if('+guard+')assert(a_'+name+'==b_'+name+');')
    for enable,fields in [('f_memory_write_o',['f_memory_write_address_o','f_memory_write_data_o']),
        ('f_memory_read_o',['f_memory_read_address_o']),
        ('f_metadata_write_o',['f_metadata_write_address_o','f_metadata_write_data_o'])]:
        lines.append('        assert(a_'+enable+'==b_'+enable+');')
        lines+=['        if(a_'+enable+')assert(a_'+name+'==b_'+name+');'for name in fields]
    for row in child_manifest.values():
        for p in row['inputs'].values():
            if p['kind']!='admission_equality':continue
            name=p['tap'];lines+=['        assert(a_'+name+'_when==b_'+name+'_when);',
                '        if(a_'+name+'_when)assert(a_'+name+'==b_'+name+');']
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_result_valid_o'if n.startswith('result_')and n!='result_valid_o'else'1'
        if n=='private_word_req_index_o':guard='a_private_word_req_valid_o'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_rel_job_activation_exponent_q_o!=b_f_rel_job_activation_exponent_q_o);',
        '        cover(rst_n && f_joined && a_activation_ready_o && activation_valid_i);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files.update({'service.sv':service.encode(),'stream.sv':stream.encode(),'wrapper.sv':wrapper.encode(),
        'runner.py':Path(__file__).read_bytes(),'native-census.json':(census/'CENSUS.json').read_bytes(),
        'source-ownership-INPUTS.json':(prior/'INPUTS.json').read_bytes(),
        'source-ownership-monitor.inc.sv':(prior/'join-monitor.inc.sv').read_bytes(),
        'sequential-inventory.json':json.dumps(state_inventory,sort_keys=True,indent=2).encode()})
    count=wrapper.count('assert(')+2*(prior/'join-monitor.inc.sv').read_text().count('assert(')
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='projection_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=count,covers=2,observer_constants=0,binding=dict(native_join=inputs['binding']['native_join'],
            variant='baseline',initial_hard_reset=False,sequential_inventory=state_inventory,
            registered_activation_history_bits=16,
            entry_policy='Common model-locked CLEAR, both native stream states outside terminal FAIL, parent/stream/grandchild faults healthy, stream owner/outstanding count empty and no model-word response',
            reply_coupling_predicates=coupling,actual_child_inputs=child_manifest,
            source_controller_receipt=receipt,metadata_header_memory_history_seam=True),cuts=cuts,
        depth=3,induction_depth=2,cover_depth=10,timeout=args.timeout,
        source_list=['delta.sv','stream.sv','service.sv','wrapper.sv'],expected_memories=0,
        map_literal_roms=True,optimize_full=True,primary_only=True,
        solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Conditional actual projection job and DDR-stream two-run controller correspondence after healthy drained CLEAR, with independent discarded descriptors and invalid payloads. All native scalar state except registered activation data is observed, and every actual child input is checked. Fresh activation read and complete packed metadata histories remain explicit seams, as do numerical/grandchild state contracts. No complete service or device theorem.')


if __name__=='__main__':raise SystemExit(main())
