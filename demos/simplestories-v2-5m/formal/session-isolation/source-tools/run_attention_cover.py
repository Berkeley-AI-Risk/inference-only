"""Concrete legal query upload through first score write, at native geometry.

The parent controller is unchanged. Its child-output boundary ports and public
inputs are connected to explicit cover stimulus constants. This is reachability
of that parent scope, not successful full-model or authenticated-boot execution.
"""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, TOP, derive, load


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=60)
    args=ap.parse_args()
    files,binding,cuts,monitor=derive(args.package,args.variant,HERE/'query-ownership-monitor.inc.sv')
    source=files['attention.sv'].decode().replace(monitor,'')
    parser=load('parser',HERE.parent/'evidence/protected-cache-compact-prefix-joint-proof-preparation-v1/formal/kv-integrity/parent_model.py')
    ports=parser.ports(source)
    source=source.replace('\n);',',\n    output wire f_cover_last_o,f_cover_write_o\n);',1)
    source=source.replace('\nendmodule',"\n    assign f_cover_last_o=query_beat_q==3;\n    assign f_cover_write_o=workspace_bram_write_enable;\nendmodule",1)
    files['attention.sv']=source.encode()
    connections=[];stimulus={}
    for name,(direction,shape)in ports.items():
        if direction=='output':value=''
        elif name in ('clk','rst_n'):value=name
        elif name=='query_last_i':value='last'
        else:
            width=re.search(r'\[(\d+):0\]',shape);width=int(width[1])+1 if width else 1
            bit=int(name in ('model_lock_i','start_valid_i','query_valid_i','private_cache_request_ready_i',
                            'private_cache_response_valid_i','f_child_u_value_prefix_read_valid_o'))
            value=str(width)+"'d"+str(bit);stimulus[name]=value
        connections.append('.'+name+'('+value+')')
    connections+=['.f_cover_last_o(last)','.f_cover_write_o(written)']
    wrapper=('module native_attention_cover(input wire clk,rst_n);\n'
             '    wire last,written; reg f_past_valid=0;\n'
             '    '+TOP+' u_native('+','.join(connections)+');\n'
             '    always @(posedge clk)begin f_past_valid<=1;\n'
             '        cover(f_past_valid && rst_n && written);\n    end\nendmodule\n')
    files['wrapper.sv']=wrapper.encode();files['cover-runner.py']=Path(__file__).read_bytes()
    binding['reachability_only']=True;binding['explicit_cover_stimulus']=stimulus
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='native_attention_cover',
        reset_constraints='initial\nassume (= [rst_n] false)\nstate 1\nassume (= [rst_n] false)\n',
        assertions=0,covers=1,binding=binding,cuts=cuts,depth=4,induction_depth=2,
        cover_depth='260:285',cover_constraints='state 2:285\nassume (= [rst_n] true)\n',
        timeout=args.timeout,source_list=['attention.sv','wrapper.sv'],optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Reachability only: actual full-geometry attention parent uploads four 64-word query beats and issues a score-workspace write, with explicit cover-only constant stimulus at every public/private/child-reply port. No reduced counters or production parameters. No native numerical-child or boot reachability theorem.')


if __name__=='__main__':raise SystemExit(main())
