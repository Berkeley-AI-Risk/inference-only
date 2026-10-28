"""Native immutable RMS ROM and resetless registered-read isolation."""
import argparse
from pathlib import Path
import re

from run_attention_ownership import HERE, load

REL='project/fpga/token_only_model0_ddr_board1/fixed_vector_rmsnorm0/rtl/board1_fixed_rmsnorm_rom.sv'
TOP='board1_fixed_rmsnorm_rom'


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--package',type=Path,required=True);ap.add_argument('--variant',default='baseline')
    ap.add_argument('--run',type=Path,required=True);ap.add_argument('--timeout',type=int,default=30)
    args=ap.parse_args();binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py')
    _,native,binding=binder.binding(args.package,args.variant)
    raw=(native/REL).read_bytes();source=raw.decode()
    assets=re.findall(r'parameter NORM_ROM_FILE\s*=\s*"([^"]+)"',source)
    if len(assets)!=1:raise ValueError('Native RMS ROM asset changed')
    asset=assets[0];data=(native/'project'/asset).read_bytes()
    if binding['distributed_inputs'].get('project/'+asset)!=binder.sha(data):raise ValueError('Unbound ROM image')
    if len(data.decode().split())!=3328:raise ValueError('Native RMS ROM word count changed')
    wrapper='''module rms_rom_isolation(input wire clk,rst_n,clear_i,read_i,input wire [11:0] fixed_address_i);
    reg f_owned=0;
    wire [33:0] a_word,b_word;
    board1_fixed_rmsnorm_rom u_a(.clk(clk),.read_i(read_i),.fixed_address_i(fixed_address_i),
        .coefficient_o(a_word[9:0]),.multiplier_o(a_word[25:10]),.tensor_exponent_o(a_word[33:26]));
    board1_fixed_rmsnorm_rom u_b(.clk(clk),.read_i(read_i),.fixed_address_i(fixed_address_i),
        .coefficient_o(b_word[9:0]),.multiplier_o(b_word[25:10]),.tensor_exponent_o(b_word[33:26]));
    always @(posedge clk)begin
        if(!rst_n || clear_i)f_owned<=0;
        else if(read_i && fixed_address_i<3328)f_owned<=1;
        cover(!f_owned && a_word!=b_word);
        cover(f_owned && read_i && fixed_address_i==3327);
    end
    always @*if(f_owned)assert(a_word==b_word);
endmodule
'''
    files={'rom.sv':raw,asset:data,'wrapper.sv':wrapper.encode(),'runner.py':Path(__file__).read_bytes()}
    engine=load('engine',HERE/'proof_engine.py')
    return engine.check(args.run,files,top='rms_rom_isolation',
        reset_constraints='initial\nassume (= [rst_n] true)\nstate 1\nassume (= [rst_n] true)\n',
        constraint_scope_description='No initial hard reset; ROM registered outputs arbitrary and independent. Identical immutable native3328-word assets. A valid matched read establishes output ownership; logical CLEAR revokes ownership and does not physically erase the output.',
        assertions=1,covers=2,binding=dict(native_join=binding,variant=args.variant,production_path=REL,
            rom_asset=asset,rom_sha256=binder.sha(data),native_words=3328,initial_hard_reset=False),cuts=[],
        depth=3,induction_depth=1,cover_depth=6,timeout=args.timeout,map_literal_roms=True,optimize_full=True,
        source_list=['rom.sv','wrapper.sv'],solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Native immutable RMS3328-word ROM and complete registered coefficient/multiplier/exponent pipeline. A fresh valid matched read determines all owned outputs despite arbitrary unequal old read-register payloads. No mathematical weight reconstruction, parent read permission or whole-device theorem.')


if __name__=='__main__':raise SystemExit(main())
