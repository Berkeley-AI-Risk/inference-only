"""Conditional isolation of the configured projection MAC recurrence.

The source contains a native registered MULTALU27X18 and its behavioral
recurrence. This proves the latter and records/checks the native configuration.
Vendor primitive implementation of that recurrence remains an explicit premise.
"""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True)
    ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True)
    ap.add_argument('--timeout',type=int,default=30)
    args=ap.parse_args()
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/'project/cluster-tile.sv').read_bytes()
    found=re.findall(r'^module board1_projection_dsp_accumulator\b[\s\S]*?^endmodule',raw.decode(),re.M)
    if len(found)!=1:raise ValueError('Native MAC source not unique')
    original=found[0];source=original
    branch=source.split('`ifdef BOARD1_PROJECTION_MAC_NATIVE',1)[1].split('`else',1)[0]
    parameters=dict(re.findall(r'\.([A-Z0-9_]+)\("([A-Z0-9]+)"\)',branch))
    for n,v in parameters.items():
        if n.endswith('_CLK')and v!=('CLK0'if n in('PREG_CLK','OREG_CLK')else'BYPASS'):
            raise ValueError('Unreviewed native MAC register configuration '+n)
        if n.startswith('DYN_')and v!=('TRUE'if n=='DYN_ACC_SEL'else'FALSE'):
            raise ValueError('Unexpected native dynamic arithmetic control '+n)
    for n in ('FB_PREG_EN','SOA_PREG_EN'):
        if parameters.get(n)!='FALSE':raise ValueError('Unexpected vendor feedback mode')
    for exact in [".ACCSEL(!first_i)",".CE({accumulate_i,multiply_i})",".CLK({1'b0,clk})",".RESET(2'b00)",
                  '.PREG_CE("CE0")','.OREG_CE("CE1")']:
        if branch.count(exact)!=1:raise ValueError('Native MAC recurrence seam changed: '+exact)
    source=source.replace('\n);',',\n    output wire signed [25:0] f_product_o\n);',1)
    source=source.replace('\nendmodule','\n    assign f_product_o=product_q;\nendmodule',1)
    wrapper='''module projection_mac_isolation(
    input wire clk,rst_n,clear_i,multiply_i,accumulate_i,first_i,
    input wire signed [15:0] activation_i,discarded_activation_i,
    input wire signed [9:0] weight_i,discarded_weight_i);
    reg f_product_owned=0,f_acc_owned=0;
    wire signed [25:0] a_product,b_product;
    wire signed [47:0] a_acc,b_acc;
    board1_projection_dsp_accumulator u_a(.clk(clk),.multiply_i(multiply_i),.accumulate_i(accumulate_i),
        .first_i(first_i),.activation_i(activation_i),.weight_i(weight_i),
        .accumulator_o(a_acc),.f_product_o(a_product));
    board1_projection_dsp_accumulator u_b(.clk(clk),.multiply_i(multiply_i),.accumulate_i(accumulate_i),
        .first_i(first_i),.activation_i(multiply_i ? activation_i : discarded_activation_i),
        .weight_i(multiply_i ? weight_i : discarded_weight_i),.accumulator_o(b_acc),.f_product_o(b_product));
    always @(posedge clk)begin
        if(!rst_n || clear_i)begin f_product_owned<=0;f_acc_owned<=0;end
        else begin
            if(multiply_i)f_product_owned<=1;
            if(accumulate_i)f_acc_owned<=f_product_owned && (first_i || f_acc_owned);
        end
    end
    always @*begin
        if(f_product_owned)assert(a_product==b_product);
        if(f_acc_owned)assert(a_acc==b_acc);
    end
    always @(posedge clk)begin
        cover(!f_acc_owned && a_acc!=b_acc);
        cover(f_acc_owned && accumulate_i && !first_i);
    end
endmodule
'''
    files={'production-tile.sv':raw,'mac.sv':('`undef BOARD1_PROJECTION_MAC_NATIVE\n`undef FORMAL\n'+source+'\n').encode(),
           'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='projection_mac_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='No native MAC reset exists. Initial product/accumulator states arbitrary and independent; observer ownership initially false. CLEAR revokes logical ownership only. Invalid multiply operands may differ.',
        assertions=2,covers=2,binding=dict(native_join=binding,variant=args.variant,production_path='project/cluster-tile.sv',
            configured_native_primitive='MULTALU27X18',native_parameter_strings=parameters,
            vendor_recurrence_semantics_assumed=True,initial_hard_reset=False),cuts=[],
        depth=3,induction_depth=1,cover_depth=8,timeout=args.timeout,
        source_list=['mac.sv','wrapper.sv'],optimize_full=True,solver_cli={s:['--unroll']for s in ('z3','cvc5')},
        scope='Actual RTL behavioral projection MAC recurrence, two independent old product/accumulator states, no physical reset. Fresh multiply establishes product ownership; first accumulation with owned product overwrites old accumulator, subsequent owned accumulations preserve isolation. Native registered DSP configuration and CE/ACCSEL wiring checked; vendor implementation of the recurrence assumed. Not vendor primitive verification or whole-device isolation.')


if __name__=='__main__':raise SystemExit(main())
