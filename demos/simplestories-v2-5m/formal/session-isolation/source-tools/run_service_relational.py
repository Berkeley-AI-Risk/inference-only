"""Conditional two-run service controller correspondence after CLEAR.

All named scalar storage is observed. Native mutable RAM read-register data is
an explicit history-contract seam, with independent invalid payloads. Whole
numerical child replies use valid-only contracts; every actual child input is
observed for the matching admission/consumption phase. No whole-device claim.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load
from run_service_memory import CASES, boundaries


def port_connections(text):
    result={}
    for m in re.finditer(r'\.([A-Za-z_][A-Za-z0-9_]*)\s*\(',text):
        at=m.end();end=at;depth=1
        while depth:depth+=(text[end]=='(')-(text[end]==')');end+=1
        if m[1]in result:raise ValueError('Duplicate child connection')
        result[m[1]]=text[at:end-1].strip()
    return result


def width(shape):
    m=re.search(r'\[([^:]+):([^\]]+)\]',shape)
    if m is None:return 1
    def number(expr):
        expr=expr.replace('ADDR_W','19')
        if not re.fullmatch(r'[0-9+* /()-]+',expr):raise ValueError('Unresolved source width '+expr)
        return int(eval(expr,{'__builtins__':{}},{}))
    return abs(number(m[1])-number(m[2]))+1


def synthesis_text(raw):
    raw=re.sub(r'/\*[\s\S]*?\*/|//[^\n]*','',raw)
    enabled=True;stack=[];rows=[]
    for line in raw.splitlines():
        m=re.match(r'\s*`(ifdef|ifndef)\s+(\w+)',line)
        if m:
            if m[2]not in('FORMAL','SYNTHESIS'):raise ValueError('Unreviewed controller macro '+m[2])
            value=m[2]=='SYNTHESIS'
            if m[1]=='ifndef':value=not value
            stack.append((enabled,value));enabled=enabled and value;continue
        if re.match(r'\s*`else\b',line):
            parent,value=stack[-1];stack[-1]=(parent,not value);enabled=parent and not value;continue
        if re.match(r'\s*`endif\b',line):enabled=stack.pop()[0];continue
        if enabled:rows.append(line)
    if stack:raise ValueError('Unbalanced source guards')
    return'\n'.join(rows)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--kind',choices=('rms','normalizer'),required=True);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=30);args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,bound=binder.binding(args.package,args.variant);relative,top,expected_children=CASES[args.kind]
    original=(native/relative).read_bytes();found=re.findall(r'^module '+top+r'\b[\s\S]*?^endmodule',original.decode(),re.M)
    if len(found)!=1:raise ValueError('Native service not unique')
    raw=found[0];definitions={}
    for path in bound['distributed_inputs']:
        if not path.endswith('.sv'):continue
        data=(native/path).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule',data.decode(),re.M):definitions[m[1]]=(m[0],path,data)
    source,files,cuts,count=boundaries(raw,definitions,parser)
    if count!=expected_children:raise ValueError('Native child inventory changed')
    prepare=args.run.resolve().with_name(args.run.name+'-prepare');prepare.mkdir(parents=True,exist_ok=False)
    (prepare/'probe.sv').write_text('`undef FORMAL\n'+source+'\n')
    (prepare/'probe.ys').write_text('read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv\nhierarchy -check -top '+top+'\nproc\nwrite_json probe.json\n')
    with(prepare/'probe.log').open('w')as log:
        cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=prepare,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Scalar service inventory failed')
    graph=json.loads((prepare/'probe.json').read_text())['modules'][top]
    reset='rst_n'
    if args.kind=='rms':memory,read_data,read_enable,read_address,bits='vector_mem_q','vector_read_q','vector_read_enable','lane_index_q',16
    else:memory,read_data,read_enable,read_address,bits='record_mem_q','record_read_q','record_read_enable','scan_index_q',58
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]\n]+\])?\s*<=',synthesis_text(raw)))
    sequential_bits={bit for c in graph['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])
                     for bit in c['connections']['Q']if isinstance(bit,int)}
    # The token <= is also a comparison. Keep only actual inventoried FF Q
    # variables; never mistake a numerical-child wire for parent storage.
    fields={n:len(graph['netnames'][n]['bits'])for n in sorted(assigned-{memory,read_data})if n in graph['netnames']
            and sequential_bits.intersection(graph['netnames'][n]['bits'])}
    removed=re.compile(r'if\s*\('+read_enable+r'\)\s*'+read_data+r'\s*<=\s*'+memory+r'\['+read_address+r'\];')
    if len(removed.findall(source))!=1:raise ValueError('Registered native RAM read seam changed')
    source=removed.sub('begin end',source)
    taps={**{'state_'+n:(w,n)for n,w in fields.items()},'ram_live':(1,'f_ram_live'),
        'ram_read':(1,read_enable),'ram_address':(8 if args.kind=='rms'else 10,read_address),
        'live':(1,'interface_live')}
    child_inputs={};conditions={}
    for instance in sorted({r['instance']for r in cuts}):
        module=next(r['module']for r in cuts if r['instance']==instance)
        header=re.search(r'\b'+module+r'\s*(?:#\([\s\S]*?\)\s*)?'+instance+r'\s*\(',raw)
        if header is None:raise ValueError('Actual child instance absent')
        at=header.end();end=at;depth=1
        while depth:depth+=(raw[end]=='(')-(raw[end]==')');end+=1
        connection=port_connections(raw[at:end-1])
        child=parser.ports(definitions[module][0]);valid=None
        for candidate in ('request_valid_i','input_valid_i','start_valid_i','read_i'):
            if candidate in connection:valid=connection[candidate];break
        if 'dsp_lane'in module:valid='state_q==ST_SQUARE_ACCUM || state_q==ST_MUL_WEIGHT || state_q==ST_MUL_SCALE'
        child_inputs[instance]={}
        for port,(direction,shape)in child.items():
            if direction!='input' or port in('clk','rst_n','reset_n'):continue
            name='input_'+instance+'_'+port;taps[name]=(width(shape),connection[port])
            # Control/admission/ready/cancel/status inputs always match.
            control=port.endswith(('_valid_i','_ready_i'))or port in('clear_i','cancel_i','read_i','model_lock_i','model_locked_i','upstream_fault_i','upstream_fail_closed_i')
            condition='1'if control else valid or'1'
            if condition not in('1',):
                key='admit_'+instance
                taps[key]=(1,condition);condition='a_'+key
            if 'dsp_lane'in module and port=='direct_weight_i':condition='a_state_state_q==11'
            if module=='board1_fixed_vector_normalizer'and port in('result_ready_i','done_ready_i'):
                response='result_valid_o'if port=='result_ready_i'else'done_valid_o'
                valid_reply=[r['replacement']for r in cuts if r['instance']==instance and r['port']==response]
                if len(valid_reply)!=1:raise ValueError('Missing normalizer delivery-valid output')
                condition='a_live && '+valid_reply[0]
            child_inputs[instance][port]=dict(tap=name,condition=condition,expression=connection[port])
        valid_outputs=[r['replacement']for r in cuts if r['instance']==instance and r['port']in('response_valid_o','result_valid_o')]
        for row in [r for r in cuts if r['instance']==instance]:
            condition=None
            if module=='board1_fixed_rmsnorm_rom':condition='a_rom_live'
            elif 'dsp_lane'in module:condition='a_admit_'+instance
            elif valid_outputs and row['port']not in('request_ready_o','response_valid_o','result_valid_o','input_ready_o','start_ready_o','done_valid_o','busy_o','range_fault_o'):
                condition=valid_outputs[0]
            if condition:conditions[row['replacement']]=condition
    if args.kind=='rms':taps['rom_live']=(1,'f_rom_live')
    extra=f',\n    input wire [{bits-1}:0] f_ram_reply_i,\n'+',\n'.join(
        f'    output wire [{w-1}:0] f_rel_{n}_o'for n,(w,_)in taps.items())+'\n'
    source=source.replace('\n);',extra+');',1)
    ghosts='''
    reg f_ram_live;
    always @(posedge clk)begin
        if(!rst_n || clear_i || (start_valid_i && start_ready_o))f_ram_live<=0;
        else if('''+read_enable+''')f_ram_live<=1;
    end
'''
    if args.kind=='rms':ghosts+='''
    reg f_rom_live;
    always @(posedge clk)begin
        if(!rst_n || clear_i || (start_valid_i && start_ready_o))f_rom_live<=0;
        else if(state_q==ST_LANE_READ && rom_address<3328)f_rom_live<=1;
    end
'''
    source=source.replace('\nendmodule','\n'+ghosts+'\n    assign '+read_data+'=f_ram_reply_i;\n'+'\n'.join(
        '    assign f_rel_'+n+'_o='+expression+';'for n,(_,expression)in taps.items())+'\nendmodule',1)
    ports=parser.ports(source);inputs={n:shape for n,(d,shape)in ports.items()if d=='input'}
    conditions['f_ram_reply_i']='a_ram_live'
    for ready,valid in [('result_ready_i','result_valid_o'),('done_ready_i','done_valid_o')]:
        if ready in inputs and valid in ports:conditions[ready]='a_'+valid
    lines=['module service_parent_relational(',',\n'.join(['    input wire '+shape+n for n,shape in inputs.items()]+
        ['    input wire '+inputs[n]+'discarded_'+n for n in conditions]),');',
        '    reg f_joined=0;always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;']
    for copy in('a','b'):
        for n,(d,shape)in ports.items():
            if d=='output':lines.append('    wire '+shape+copy+'_'+n+';')
        con=[]
        for n,(d,_)in ports.items():
            value=n if d=='input'else copy+'_'+n
            if copy=='b'and n in conditions:value='('+conditions[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+top+' u_'+copy+'('+','.join(con)+');')
        for n in taps:lines.append('    wire ['+str(taps[n][0]-1)+':0] '+copy+'_'+n+'='+copy+'_f_rel_'+n+'_o;')
    lines+=['    always @*if(rst_n && f_joined)begin']
    if args.kind=='rms':
        lines+=['        assert(a_state_state_q<=14 || a_state_state_q==31);',
                '        assert(a_state_selector_q<=12);',
                '        if(a_state_state_q==3 || (a_state_state_q>=9 && a_state_state_q<=13))assert(a_ram_live);',
                '        if(a_state_state_q>=9 && a_state_state_q<=13)assert(a_rom_live);']
    else:
        lines+=['        assert(a_state_state_q<=12 || a_state_state_q==15);',
                '        if(a_state_state_q==5 || a_state_state_q==8 || a_state_state_q==11)assert(a_ram_live);']
    lines+=['        assert(a_'+n+'==b_'+n+');'for n in taps if n.startswith('state_')or n in('ram_live','ram_read','ram_address','rom_live')]
    lines+=['        if('+p['condition']+')assert(a_'+p['tap']+'==b_'+p['tap']+');'for entry in child_inputs.values()for p in entry.values()]
    data_prefixes=('result_',)
    for n,(direction,_)in ports.items():
        if direction!='output'or n.startswith('f_rel_'):continue
        guard='a_result_valid_o'if n.startswith(data_prefixes)and n!='result_valid_o'else'1'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(!f_joined && rst_n && a_state_state_q!=b_state_state_q);',
        '        cover(f_joined && rst_n && start_valid_i && a_start_ready_o);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files.update({'production-service.sv':original,'service.sv':('`undef FORMAL\n'+source+'\n').encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
        **{p.name:p.read_bytes()for p in prepare.iterdir()if p.is_file()}})
    cuts.append(dict(internal_seam=read_data,native_memory=memory,reply_contract='Fresh owned registered RAM history',replacement='f_ram_reply_i'))
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='service_parent_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=bound,variant=args.variant,
            production_path=relative,service=args.kind,sequential_fields=fields,child_input_contracts=child_inputs,
            reply_coupling_predicates=conditions,initial_hard_reset=False),cuts=cuts,depth=3,induction_depth=1,cover_depth=8,
        timeout=args.timeout,source_list=['service.sv','wrapper.sv'],map_literal_roms=True,optimize_full=True,expected_memories=0,
        solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Conditional actual service parent correspondence after CLEAR with arbitrary old controls and invalid RAM/child payloads. All named scalar storage and actual child admission operands observed. Native RAM history and numerical child contracts require composition; no whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
