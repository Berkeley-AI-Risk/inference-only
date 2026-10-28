"""Concrete native projection-metadata reader correspondence after drained CLEAR."""
import argparse
import json
from pathlib import Path
import re
import subprocess

from run_attention_ownership import HERE, load
from run_service_relational import synthesis_text
from run_semantic_ingress import tap

TOP='board1_fixed_projection_metadata_reader'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=25)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant);found=[]
    for relative in binding['distributed_inputs']:
        if not relative.endswith('.sv'):continue
        raw=(native/relative).read_bytes()
        for m in re.finditer(r'^module\s+'+TOP+r'\b[\s\S]*?^endmodule\b',raw.decode(),re.M):found.append((relative,raw,m[0]))
    if len(found)!=1:raise ValueError('Native metadata reader not unique')
    relative,original,raw=found[0]
    prepare=args.run.resolve().with_name(args.run.name+'-prepare');prepare.mkdir(parents=True,exist_ok=False)
    (prepare/'probe.sv').write_text('`undef FORMAL\n'+raw)
    (prepare/'probe.ys').write_text('read_verilog -formal -sv -nosynthesis -D SYNTHESIS probe.sv\nchparam -set ADDR_W 19 '+TOP+'\nhierarchy -check -top '+TOP+'\nproc\nwrite_json probe.json\n')
    with(prepare/'probe.log').open('w')as log:cp=subprocess.run(['yosys','-Q','probe.ys'],cwd=prepare,stdout=log,stderr=subprocess.STDOUT,timeout=30)
    if cp.returncode:raise ValueError('Native metadata reader state inventory failed')
    g=json.loads((prepare/'probe.json').read_text())['modules'][TOP]
    qbits={b for c in g['cells'].values()if re.match(r'^\$(?:a?dff|sdff|dffe|adffe|sdffe|dlatch|adlatch)',c['type'])for b in c['connections']['Q']if isinstance(b,int)}
    assigned=set(re.findall(r'\b(\w+)\s*(?:\[[^\]]+\])?\s*<=',synthesis_text(raw)))
    fields={n:len(g['netnames'][n]['bits'])for n in sorted(assigned)if n in g['netnames']and qbits.intersection(g['netnames'][n]['bits'])}
    observed={b for n in fields for b in g['netnames'][n]['bits']if isinstance(b,int)}
    if not qbits.issubset(observed):raise ValueError('Unobserved native metadata reader state')
    masks={'group_base_word_q','valid_lanes_q','group_q','job_q','layer_q'}
    source=raw
    for before,after in [
        ('if (!reset_n) begin','if (!reset_n) begin\n            f_descriptor_owned<=0;'),
        ('end else if (clear_i) begin','end else if (clear_i) begin\n            f_descriptor_owned<=0;'),
        ('group_base_word_q <= descriptor_base_word;','group_base_word_q <= descriptor_base_word;\n                            f_descriptor_owned<=1;')]:
        if source.count(before)!=1:raise ValueError('Actual descriptor writer changed')
        source=source.replace(before,after,1)
    source=source.replace('\nendmodule','\n    reg f_descriptor_owned;\nendmodule',1)
    taps={**{'f_state_'+n+'_o':('['+str(w-1)+':0] ',n)for n,w in fields.items()},
        'f_descriptor_owned_o':('','f_descriptor_owned')}
    source=tap(source,taps);ports=parser.ports(source)
    coupling={
        'fixed_layer_i':'start_valid_i','fixed_job_i':'start_valid_i','fixed_group_i':'start_valid_i',
        'private_word_rsp_data_i':'private_word_rsp_valid_i','private_word_rsp_fault_i':'private_word_rsp_valid_i',
        'metadata_ready_i':'a_metadata_valid_o','done_ready_i':'a_done_valid_o',
        'private_word_req_ready_i':'a_private_word_req_valid_o',
    }
    lines=['module metadata_reader_relational(',',\n'.join(
        ['    input wire '+sh+('rst_n'if n=='reset_n'else n)for n,(di,sh)in ports.items()if di=='input']+
        ['    input wire '+ports[n][1]+'discarded_'+n for n in coupling]),');','    reg f_joined=0;']
    for copy in('a','b'):
        for n,(di,sh)in ports.items():
            if di=='output':lines.append('    wire '+sh+copy+'_'+n+';')
        con=[]
        for n,(di,_)in ports.items():
            value=('rst_n'if n=='reset_n'else n)if di=='input'else copy+'_'+n
            if copy=='b'and n in coupling:value='('+coupling[n]+' ? '+n+' : discarded_'+n+')'
            con.append('.'+n+'('+value+')')
        lines.append('    '+TOP+' #(.ADDR_W(19))u_'+copy+'('+','.join(con)+');')
    lines+=['    always @(posedge clk)if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=model_locked_i && !upstream_fail_closed_i && !private_word_rsp_valid_i && !a_fail_closed_o && !b_fail_closed_o && !a_f_state_request_outstanding_q_o && !b_f_state_request_outstanding_q_o;',
        '    always @*if(rst_n && f_joined)begin',
        '        assert(a_f_descriptor_owned_o==b_f_descriptor_owned_o);']
    for copy in('a','b'):
        lines+=['        assert('+copy+'_f_state_state_q_o<=5 || '+copy+'_f_state_state_q_o==7);',
            '        if('+copy+'_f_state_state_q_o>=1 && '+copy+'_f_state_state_q_o<=4)assert('+copy+'_f_descriptor_owned_o);']
    for n in fields:
        guard='a_f_descriptor_owned_o'if n in masks else'1'
        lines.append('        if('+guard+')assert(a_f_state_'+n+'_o==b_f_state_'+n+'_o);')
    for n,(di,_)in ports.items():
        if di!='output'or n.startswith('f_'):continue
        guard='a_metadata_valid_o'if n.startswith('metadata_')and n!='metadata_valid_o'else'1'
        if n=='private_word_req_index_o':guard='a_private_word_req_valid_o'
        lines.append('        if('+guard+')assert(a_'+n+'==b_'+n+');')
    lines+=['    end','    always @(posedge clk)begin',
        '        cover(rst_n && !f_joined && a_f_state_response_word_q_o!=b_f_state_response_word_q_o);',
        '        cover(rst_n && f_joined && a_metadata_valid_o && metadata_ready_i);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-reader.sv':original,'reader.sv':('`undef FORMAL\n'+source).encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes(),
        **{p.name:p.read_bytes()for p in prepare.iterdir()if p.is_file()}}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='metadata_reader_relational',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=relative,concrete_module=TOP,initial_hard_reset=False,
            native_sequential_bits=len(qbits),sequential_fields=fields,descriptor_fields_masked_until_actual_write=sorted(masks),
            operand_coupling_predicates=coupling,
            entry_policy='Healthy model-locked common CLEAR, both native outstanding-request flags empty and no response that cycle'),cuts=[],
        depth=3,induction_depth=2,cover_depth=12,timeout=args.timeout,
        source_list=['reader.sv','wrapper.sv'],expected_memories=0,map_literal_roms=True,
        optimize_full=True,primary_only=True,solver_cli={'z3':['--unroll','-S','-memory:1024']},
        scope='Concrete complete native projection-metadata reader two-run correspondence after healthy drained CLEAR without initial hard reset. All native register bits observed, retained descriptors masked until actual register write, independent irrelevant descriptor/response payloads and delivery readiness. No numerical abstraction or whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
