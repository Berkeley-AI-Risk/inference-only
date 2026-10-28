"""Native weight-buffer isolation after their actual local cancellation reset."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load

SPECS={
    'beat-register':('board1_private_weight_beat_register',{'valid_q','data_q'}),
    'width-adapter':('board1_private_ddr256_to_w640',{'phase','low_word','middle_word','shared_half_word'}),
}


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--kind',choices=SPECS,required=True);ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=30);args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    top,expected=SPECS[args.kind];found=[]
    for path in binding['distributed_inputs']:
        if not path.endswith('.sv'):continue
        raw=(native/path).read_bytes()
        for m in re.finditer(r'^module '+top+r'\b[\s\S]*?^endmodule',raw.decode(),re.M):found.append((m[0],path,raw))
    if len(found)!=1:raise ValueError('Actual buffer definition not unique')
    source,path,raw=found[0]
    assigned=set(re.findall(r'\b(\w+)\s*<=',source.split('`ifdef FORMAL',1)[0]))
    if assigned!=expected:raise ValueError('Uncovered native buffer storage')
    ports=parser.ports(source)
    if args.kind=='width-adapter':
        taps={'phase':('[2:0] ','phase'),'payload':('[639:0] ','{low_word,middle_word,shared_half_word}')}
        source=source.replace('\n);',',\n'+',\n'.join('    output wire '+shape+'f_'+n+'_o'for n,(shape,_)in taps.items())+'\n);',1)
        source=source.replace('\nendmodule','\n'+'\n'.join('    assign f_'+n+'_o='+value+';'for n,(_,value)in taps.items())+'\nendmodule',1)
    else:taps={}
    data='in_data_i'if args.kind=='beat-register'else'ddr_word_data'
    valid='in_valid_i'if args.kind=='beat-register'else'ddr_word_valid'
    lines=['module weight_buffer_isolation(',
        ',\n'.join(['    input wire '+shape+('rst_n'if n=='reset_n'else n)for n,(d,shape)in ports.items()if d=='input']+
                  ['    input wire '+ports[data][1]+'discarded_data_i']),');',
        '    reg f_joined=0;always @(posedge clk)if(!rst_n)f_joined<=1;']
    for copy in ('a','b'):
        for n,(d,shape)in ports.items():
            if d=='output':lines.append('    wire '+shape+copy+'_'+n+';')
        for n,(shape,_)in taps.items():lines.append('    wire '+shape+copy+'_f_'+n+';')
        connections=['.'+n+'('+(
            '('+valid+' ? '+data+' : discarded_data_i)'if copy=='b'and n==data else
            'rst_n'if n=='reset_n'else n if d=='input'else copy+'_'+n)+')'for n,(d,_)in ports.items()]
        connections+=['.f_'+n+'_o('+copy+'_f_'+n+')'for n in taps]
        lines.append('    '+top+' u_'+copy+'('+','.join(connections)+');')
    lines+=['    always @*if(rst_n && f_joined)begin']
    if args.kind=='beat-register':
        lines+=['        assert(a_in_ready_o==b_in_ready_o);assert(a_out_valid_o==b_out_valid_o);',
                '        if(a_out_valid_o)assert(a_out_data_o==b_out_data_o);']
        covers=['f_joined && rst_n && !a_out_valid_o && a_out_data_o!=b_out_data_o','f_joined && rst_n && a_out_valid_o']
    else:
        lines+=['        assert(a_f_phase==b_f_phase);assert(a_f_phase<=4);',
                '        assert(a_f_payload==b_f_payload);',
                '        assert(a_ddr_word_ready==b_ddr_word_ready);assert(a_weight_valid==b_weight_valid);',
                '        assert(a_pair_boundary==b_pair_boundary);',
                '        if(a_weight_valid)assert(a_weight_data==b_weight_data);']
        covers=['!f_joined && a_f_payload!=b_f_payload','f_joined && rst_n && a_weight_valid && a_f_phase==4']
    lines+=['    end','    always @(posedge clk)begin']+['        cover('+c+');'for c in covers]+['    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-buffer.sv':raw,'buffer.sv':('`undef FORMAL\n'+source+'\n').encode(),
        'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='weight_buffer_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='Native local adapter_reset_n is the cancellation interface: no initial hard reset, arbitrary independent old state. One common local reset/cancel edge enables the relation. Data may differ while input-valid is false. Production stream derives this local reset from CLEAR and its weight phase.',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=path,concrete_module=top,local_cancellation_reset=True,sequential_variables=sorted(assigned)),cuts=[],
        depth=4,induction_depth=2,cover_depth=12,timeout=args.timeout,
        source_list=['buffer.sv','wrapper.sv'],optimize_full=True,solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native private weight buffer, two arbitrary independent old states. Production local cancellation reset revokes invalid payload authority; fresh accepted words determine valid640-bit output beats. Input data may differ while invalid. Full native dimensions. No physical top hard-reset requirement or whole-device session theorem.')


if __name__=='__main__':raise SystemExit(main())
