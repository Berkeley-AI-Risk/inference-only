"""Prove the actual fixed native SHA DSP adder against the vendor RTL model.

The installed vendor model is a private dependency and is not a public release
asset. It models digital functional behavior, not electrical or silicon effects.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
VENDOR=Path('/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v')
VENDOR_SHA='a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd'
TOP='native_sha_add32_formal'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_native_sha_add_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--csa',action='store_true',help='Check the actual three-input carry-save composition')
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    raw=VENDOR.read_bytes()
    if hashlib.sha256(raw).hexdigest()!=VENDOR_SHA:raise ValueError('The installed vendor functional model changed')
    start=raw.index(b'module MULTALU27X18 ');end=raw.index(b'\nendmodule',start)+len(b'\nendmodule')
    vendor=raw[start:end]
    _,directory,bound=common.binding(args.package,'kv-protected')
    native=(directory/'project/sha.sv').read_bytes()
    if b'`define TANG_SHA_DSP_ADDER'not in native or b'`ifdef VERILATOR'in native:
        raise ValueError('The native macro selection policy changed')
    wrapper=b'''module native_sha_add32_formal(input wire [31:0] a_i,b_i,output wire [31:0] sum_o);
    tang_sha_dsp_add32 u_native (.a_i(a_i),.b_i(b_i),.sum_o(sum_o));
    always @* begin
        assert(sum_o==32'(a_i+b_i));
        cover(a_i==32'hffffffff && b_i==32'd1 && sum_o==0);
    end
endmodule
'''
    if args.csa:
        wrapper=b'''module native_sha_add32_formal(input wire [31:0] a_i,b_i,c_i,output wire [31:0] sum_o);
    tang_sha_csa3_add32 u_native (.x_i(a_i),.y_i(b_i),.z_i(c_i),.sum_o(sum_o));
    always @* begin
        assert(sum_o==32'(a_i+b_i+c_i));
        cover(a_i==32'hffffffff && b_i==32'd1 && c_i==0 && sum_o==0);
    end
endmodule
'''
    files={'sha.sv':b'`undef FORMAL\n'+native,'production-sha.sv':native,
        'private-vendor-MULTALU27X18.v':vendor,'wrapper.sv':wrapper,
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    binding=dict(native_join=bound,production_sha256=hashlib.sha256(native).hexdigest(),
        vendor_library_path=str(VENDOR),vendor_library_sha256=VENDOR_SHA,
        vendor_module_sha256=hashlib.sha256(vendor).hexdigest(),
        native_synthesis_macro_selected=True,portable_fallback_selected=False,
        vendor_bytes_private_not_for_publication=True)
    binding['arithmetic_operation']='three-input modulo-2^32 sum'if args.csa else'two-input modulo-2^32 sum'
    scope=('Actual released protected SHA DSP-adder wrapper and full, unmodified installed Gowin '
        'MULTALU27X18 digital functional module, specialized by the actual native constant parameters '
        'and input ties. Prove modulo-2^32 addition for every pair of 32-bit inputs, with no cut or '
        'replacement arithmetic in the DUT. No portable fallback, no arbitrary primitive output. '
        'The vendor model is a trusted functional specification; this does not certify physical '
        'silicon, mapped wiring, timing, fault resistance or the larger SHA controller.')
    return engine.check(args.run,files,top=TOP,reset_constraints='',assertions=1,covers=1,
        binding=binding,scope=scope,cuts=[],depth=1,induction_depth=1,cover_depth=1,timeout=60,
        source_list=['sha.sv','private-vendor-MULTALU27X18.v','wrapper.sv'],optimize_full=True)


if __name__=='__main__':raise SystemExit(main())
