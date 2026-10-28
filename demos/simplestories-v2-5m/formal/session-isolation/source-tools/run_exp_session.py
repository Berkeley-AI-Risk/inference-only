"""Concrete ROM/pipeline session isolation, including the distinct endpoint."""
import argparse
import json
from pathlib import Path
import re

from run_attention_ownership import HERE, load

REL='project/fpga/token_only_model0_ddr_board1/fixed_attention0/rtl/board1_fixed_attention_exp_lut_sync.sv'
TOP='board1_fixed_attention_exp_lut_sync'


def elaborate_initializer(source,data):
    """Evaluate only the native constant ROM initialization loop.

    Yosys cannot collect a memory initialized from a second staging memory.
    Check the exact loop, enumerate its four disjoint index blocks, and emit
    literal initial values. The entire runtime source remains untouched.
    """
    block=re.search(r'    initial begin : load_complete_image[\s\S]*?\n    end',source)
    if block is None:raise ValueError('ROM initializer absent')
    compact=re.sub(r'//[^\n]*|\s+','',block[0])
    expected=('initialbegin:load_complete_imagelogic[31:0]initialization_image[0:4096];integeraddress;'
              '$readmemh(FILE,initialization_image);for(address=0;address<1024;address=address+1)begin'
              'value_mem[address]=initialization_image[address];'
              'value_mem[address+1024]=initialization_image[address+1024];'
              'value_mem[address+2048]=initialization_image[address+2048];'
              'value_mem[address+3072]=initialization_image[address+3072];'
              'endendpoint_value=initialization_image[4096];end')
    if compact!=expected:raise ValueError('Native constant initializer changed')
    words=[int(w,16)for w in data.decode().split()]
    if len(words)!=4097 or any(w<0 or w>=2**32 for w in words):raise ValueError('ROM image geometry changed')
    indices=[i+offset for i in range(1024)for offset in (0,1024,2048,3072)]
    if sorted(indices)!=list(range(4096)):raise ValueError('Initializer blocks do not partition low ROM')
    literal='    initial begin : load_complete_image\n'+'\n'.join(
        f"        value_mem[{i}] = 32'h{words[i]:08x};"for i in indices)+f"\n        endpoint_value = 32'h{words[4096]:08x};\n    end"
    return source[:block.start()]+literal+source[block.end():],dict(
        method='Exact checked constant-loop enumeration; runtime RTL unchanged',
        low_words=4096,distinct_endpoint_word=4096,assigned_once=True,
        original_initializer=block[0],literal_initializer=literal)


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=45)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/REL).read_bytes();source=raw.decode();ports=parser.ports(source)
    asset=re.findall(r'parameter FILE = "([^"]+)"',source)
    if len(asset)!=1:raise ValueError('ROM parameter changed')
    asset=asset[0];data=(native/'project'/asset).read_bytes()
    if binding['distributed_inputs'].get('project/'+asset)!=binder.sha(data):raise ValueError('ROM asset not source bound')
    variables=set(re.findall(r'\b(\w+)\s*(?:\[[^\]\n]+\])?\s*<=',source))
    if variables!={'endpoint_select_q','low_data_q','response_valid_q','response_index_fault_q','range_fault_o'}:
        raise ValueError('Mutable ROM-pipeline state census changed')
    source,initialization=elaborate_initializer(source,data)
    taps={'f_rom_data_o':('[31:0] ','rom_data_q'),
          'f_index_fault_o':('','response_index_fault_q')}
    source=source.replace('\n);',',\n'+',\n'.join('    output wire '+shape+n for n,(shape,_)in taps.items())+'\n);',1)
    source=source.replace('\nendmodule','\n'+'\n'.join('    assign '+n+'='+value+';'for n,(_,value)in taps.items())+'\nendmodule',1)
    lines=['module exp_session_isolation(',
        ',\n'.join(['    input wire '+shape+n for n,(direction,shape)in ports.items()if direction=='input']+
                   ['    input wire [12:0] discarded_index_i']),');',
        '    reg f_joined=0,f_payload_owned;',
        '    always @(posedge clk)begin',
        '        if(!rst_n)f_joined<=0;else if(clear_i)f_joined<=1;',
        '        if(!rst_n || clear_i)f_payload_owned<=0;',
        '        else if(request_valid_i && index_i<=4096)f_payload_owned<=1;',
        '    end']
    for copy in ('a','b'):
        for n,(direction,shape)in ports.items():
            if direction=='output':lines.append('    wire '+shape+copy+'_'+n+';')
        for n,(shape,_)in taps.items():lines.append('    wire '+shape+copy+'_'+n+';')
        connections=['.'+n+'('+ ('(request_valid_i ? index_i : discarded_index_i)'if copy=='b'and n=='index_i'else
                                n if direction=='input'else copy+'_'+n)+')'for n,(direction,_)in ports.items()]
        connections+=['.'+n+'('+copy+'_'+n+')'for n in taps]
        lines+=['    '+TOP+' u_'+copy+'('+','.join(connections)+');']
    lines+=['    always @*if(rst_n && f_joined)begin',
        '        assert(a_response_valid_o==b_response_valid_o);',
        '        assert(a_response_fault_o==b_response_fault_o);',
        '        assert(a_range_fault_o==b_range_fault_o);',
        '        assert(a_f_index_fault_o==b_f_index_fault_o);',
        '        if(f_payload_owned)assert(a_f_rom_data_o==b_f_rom_data_o);',
        '        if(a_response_valid_o && !f_payload_owned)begin',
        '            assert(a_f_index_fault_o);assert(a_range_fault_o);end',
        '        if(a_response_valid_o && !a_response_fault_o)begin',
        '            assert(f_payload_owned);assert(a_value_o==b_value_o);end',
        '    end','    always @(posedge clk)begin',
        '        cover(!f_joined && rst_n && a_f_rom_data_o!=b_f_rom_data_o);',
        '        cover(f_joined && rst_n && a_response_valid_o && !a_response_fault_o);',
        '    end','endmodule']
    wrapper='\n'.join(lines)+'\n'
    files={'production-exp.sv':raw,'exp.sv':('`undef FORMAL\n'+source+'\n').encode(),
           asset:data,'initializer-elaboration.json':(json.dumps(initialization,indent=2)+'\n').encode(),
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='exp_session_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='No initial hard reset: independent arbitrary old mutable pipeline state, fixed identical native4097-word ROM asset. f_joined starts false and common CLEAR enables the relation. Base/cover rst_n high in states0/1 only; induction unconstrained.',
        assertions=wrapper.count('assert('),covers=2,binding=dict(native_join=binding,variant=args.variant,
            production_path=REL,rom_asset=asset,rom_sha256=binder.sha(data),rom_words=4097,
            mutable_sequential_variables=sorted(variables),initial_hard_reset=False),cuts=[],
        depth=3,induction_depth=1,cover_depth=8,timeout=args.timeout,
        source_list=['exp.sv','wrapper.sv'],optimize_full=True,map_literal_roms=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Concrete exponential ROM/pipeline CLEAR isolation. No initial hard reset; old pipeline payloads may differ. Matched future requests yield identical fault/valid status and identical healthy valid values after CLEAR. All4097 native asset words including endpoint retained. Raw value without healthy valid ownership is not an observation. Not numerical exponential accuracy or whole-device isolation.')


if __name__=='__main__':raise SystemExit(main())
