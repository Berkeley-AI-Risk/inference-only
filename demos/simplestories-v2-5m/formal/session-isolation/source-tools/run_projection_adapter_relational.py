"""Native packed-header projection adapter relation after CLEAR, no hard reset.

Retain real header checks, metadata serialization and weight control. The
numerical cluster is an explicit child contract; every actual input is observed.
"""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from run_service_memory import boundaries
from run_service_relational import synthesis_text, width
from run_semantic_ingress import tap
from record_progress import sha

TOP='board1_shared_projection_scale_group_adapter'
CHILD='board1_clustered_projection_scale2'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    ap.add_argument('--header-congruence',type=Path)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant);definitions={}
    for relative in binding['distributed_inputs']:
        if not relative.endswith('.sv'):continue
        original=(native/relative).read_bytes()
        for m in re.finditer(r'^module\s+(\w+)\b[\s\S]*?^endmodule\b',original.decode(),re.M):
            if m[1]in definitions and definitions[m[1]][0]!=m[0]:raise ValueError('Ambiguous actual module')
            definitions[m[1]]=(m[0],relative,original)
    raw,relative,original=definitions[TOP]
    source,files,cuts,count=boundaries(raw,{CHILD:definitions[CHILD]},parser)
    if count!=1:raise ValueError('Numerical cluster instance count differs')
    congruence=None
    if args.header_congruence:
        path=args.header_congruence.resolve();congruence=json.loads(path.read_text())
        if not congruence['stateless_native_header_congruence_checked']or congruence['mutable_or_opaque_cone_cells']:
            raise ValueError('Stateless header-cone check incomplete')
        if congruence['production_source_sha256']!=sha(original):raise ValueError('Header cone binds another production source')
        for name,digest in congruence['source_manifest'].items():
            if sha(Path(name).read_bytes())!=digest:raise ValueError('Changed header-cone source')
        if sha((path.parent/'cone.json').read_bytes())!=congruence['cone_json_sha256']or sha((path.parent/'runner.py').read_bytes())!=congruence['runner_sha256']:
            raise ValueError('Changed header-cone evidence')
        start=source.index('    logic [6:0] descriptor_groups;');end=source.index('    logic engine_start_valid;',start)
        block=source[start:end]
        if 'header_protocol_error'not in block:raise ValueError('Native header validator location changed')
        source=source[:start]+block.replace('header_protocol_error','f_native_header_protocol_error')+source[end:]
        source=source.replace('\n);',',\n    input wire f_header_error_i\n);',1)
        source=source.replace('\nendmodule','\n    wire header_protocol_error=f_header_error_i;\nendmodule',1)
        files['header-congruence-receipt.json']=path.read_bytes()
        files['header-cone.json']=(path.parent/'cone.json').read_bytes()
        files['header-cone-checker.py']=(path.parent/'runner.py').read_bytes()
        cuts.append(dict(internal_seam='header_protocol_error',replacement='f_header_error_i',
            contract='Identical pure finite combinational function; output equality only under matching complete header inputs when group_valid_i is true',
            source_receipt_sha256=sha(path.read_bytes())))
    prepare=args.run.resolve().with_name(args.run.name+'-prepare');prepare.mkdir(parents=True,exist_ok=False)
    (prepare/'probe.sv').write_text('`undef FORMAL\n'+source)
    (prepare/'probe.ys').write_text('read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv\nhierarchy -check -top '+TOP+'\nproc\nwrite_json probe.json\n')
    with(prepare/'probe.log').open('w')as log:cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=prepare,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Native adapter scalar inventory failed')
    g=json.loads((prepare/'probe.json').read_text())['modules'][TOP]
    qbits={b for c in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])for b in c['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
    observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
    if not qbits.issubset(observed):raise ValueError('Unobserved native adapter state')
    con=instance_con(raw,CHILD,'u_engine');child_ports=parser.ports(definitions[CHILD][0])
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()}}
    child_inputs={}
    for port,(di,sh)in child_ports.items():
        if di!='input':continue
        if port in('clk','reset_n'):
            child_inputs[port]=dict(expression=con[port],kind='shared_clock_or_reset');continue
        guard='1';control=port.endswith(('_valid_i','_ready_i'))or port in('clear_i','model_locked_i','upstream_fail_closed_i')
        if not control:
            if port.startswith('metadata_'):guard=con['metadata_valid_i']
            elif port in('activation_i','weight_data_i','weight_last_i'):guard=con['weight_valid_i']
            else:guard=con['start_valid_i']
        if port in('result_ready_i','done_ready_i'):
            valid='engine_result_valid'if port=='result_ready_i'else'engine_done_valid';guard=valid
        name='f_child_input_'+port+'_o';taps[name]=(sh,con[port]);taps[name+'_when']=('',guard)
        child_inputs[port]=dict(tap=name,guard=guard,expression=con[port],kind='admission_equality')
    source=tap(source,taps);ports=parser.ports(source)
    coupling={n:'group_valid_i'for n in('group_layer_i','group_job_i','group_index_i','group_valid_lanes_i','group_row_exponent_i','group_row_multiplier_i','activation_exponent_i')}
    coupling.update({n:'weight_valid_i'for n in('activation_i','weight_data_i','weight_last_i')})
    coupling.update(result_ready_i='f_child_u_engine_result_valid_o',done_ready_i='f_child_u_engine_done_valid_o')
    if congruence:
        if set(congruence['dependencies'])!={n for n,condition in coupling.items()if condition=='group_valid_i'}:
            raise ValueError('Some stateless header dependency is not coupled at valid admission')
        coupling['f_header_error_i']='group_valid_i'
    for row in cuts:
        if row.get('port','').startswith('result_')and row['port']!='result_valid_o':coupling[row['replacement']]='f_child_u_engine_result_valid_o'
    lines=['module projection_adapter_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        connection=[]
        for n,(di,_)in ports.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            connection.append('.'+n+'('+value+')')
        lines.append('    '+TOP+' u_'+copy+'('+','.join(connection)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;',
        '    always @*if(rst_n && f_joined)begin',
        '        assert(a_f_state_state_q_o<=4 && b_f_state_state_q_o<=4);']
    lines+=['        assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);'for n in fields]
    for row in child_inputs.values():
        if row['kind']!='admission_equality':continue
        name=row['tap'];lines+=['        assert(a_'+name+'_when==b_'+name+'_when);',
            '        if(a_'+name+'_when)assert(a_'+name+'==b_'+name+');']
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_result_valid_o'if n.startswith('result_')and n!='result_valid_o'else'1'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_state_activation_exponent_q_o!=b_f_state_activation_exponent_q_o);',
        '        cover(rst_n && f_joined && a_f_child_input_metadata_valid_i_o);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files.update({'production-adapter.sv':original,'adapter.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
        **{p.name:p.read_bytes()for p in prepare.iterdir()if p.is_file()}})
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='projection_adapter_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            concrete_module=TOP,production_path=relative,initial_hard_reset=False,
            native_sequential_bits=len(qbits),sequential_fields=fields,actual_child_inputs=child_inputs,
            stateless_header_congruence=congruence,
            operand_coupling_predicates=coupling),cuts=cuts,depth=3,induction_depth=2,cover_depth=8,timeout=args.timeout,
        source_list=['adapter.sv','wrapper.sv'],expected_memories=0,map_literal_roms=True,
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Actual native packed-header projection adapter correspondence after CLEAR without hard reset. All native scalar bits, metadata serialization and weight control retained; every actual numerical-cluster input observed. Header validation is concrete unless the recorded stateless-congruence cone contract is enabled. Irrelevant invalid payloads/readiness may differ. Numerical-cluster response/state contracts remain explicit; no full service or device theorem.')


if __name__=='__main__':raise SystemExit(main())
