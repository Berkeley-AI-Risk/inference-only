"""Native image-auth input/admission safety, with the complete SHA RTL retained."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
AUTH='project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv'
TOP='board1_context2048_semantic_image_auth_compact'


def load(name):
    spec=importlib.util.spec_from_file_location('_authentication_access_'+name,OLD/(name+'.py'))
    module=importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory'),default='baseline')
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--mutant',choices=('reverse-word-bytes','wrong-padding-length','accept-wrong-digest'))
    args=parser.parse_args()
    common,engine=load('run_handoff'),load('engine')
    originals=None
    joins={}
    group=('baseline','seeded-sampling') if args.variant=='baseline' else (args.variant,)
    for variant in group:
        _,root,bound=common.binding(args.package,variant)
        actual={'auth.sv':(root/AUTH).read_bytes(),'sha.sv':(root/'project/sha.sv').read_bytes()}
        if originals is not None and originals!=actual:
            raise ValueError('The claimed native source identity does not hold')
        originals=actual
        joins[variant]=bound
    monitor=(HERE/'image-auth-monitor.inc.sv').read_text()
    top=TOP
    expected='cad8d015db37a3603e340edfc0009f36d6b12de2bc789d60687011fc700cc3b0'
    if args.variant=='encrypted-memory':
        top='tang_confidential_ciphertext_image_auth'
        encrypted_expected='88da38f3eb64bacc21aa472666b0cc8ea1e516cb04c80e0678f768425e6390eb'
        if monitor.count(expected)!=1:raise ValueError('Independent digest policy boundary changed')
        monitor=monitor.replace(expected,encrypted_expected)
        expected=encrypted_expected
    source=originals['auth.sv'].decode()
    if args.mutant:
        sites={
            'reverse-word-bytes':('word_buffer_q[word_byte_q*8 +: 8]','word_buffer_q[255-word_byte_q*8 -: 8]'),
            'wrong-padding-length':("IMAGE_BITS[63 - (padding_byte_q-56)*8 -: 8]","8'h00"),
            'accept-wrong-digest':('if (sha_digest == EXPECTED_SHA256) begin','if (sha_digest != EXPECTED_SHA256) begin'),
        }
        before,after=sites[args.mutant]
        if source.count(before)!=1:raise ValueError('Mutation boundary changed')
        source=source.replace(before,after)
    if source.count('\n`ifdef FORMAL')!=1:raise ValueError('Native instrumentation boundary changed')
    source=source.replace('\n`ifdef FORMAL','\n'+monitor+'\n`ifdef FORMAL',1)
    files={'auth.sv':b'`undef FORMAL\n'+source.encode(),
        'sha.sv':b'`undef FORMAL\n'+originals['sha.sv'],
        **{'production-'+n:raw for n,raw in originals.items()},
        'monitor.inc.sv':monitor.encode(),'runner.py':Path(__file__).read_bytes(),
        'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    binding=dict(native_joins=joins,production_paths={'auth.sv':AUTH,'sha.sv':'project/sha.sv'},
        production_sources={n:hashlib.sha256(raw).hexdigest() for n,raw in originals.items()},
        entire_sha_child_elaborated=True,read_only_observers=True,production_dimensions_changed=False,
        variant=args.variant,expected_digest=expected)
    scope=('The actual selected boot image authenticator and complete production SHA stream/compressor. '
        'Native 227062-word image and full 256-bit word data retained, with arbitrary input words and stalls. '
        'Read-only histories check accepted word serialization, exact SHA padding bytes, matching-digest admission '
        'and sticky failure. No internal output cut, arbitrary digest reply, or client protocol promise. '
        'This campaign does not yet establish SHA algorithm correspondence, parent LOCK composition, physical '
        'DDR behavior or a full native boot reachability witness. Component covers exercise early input, byte '
        'transfer and rejection; they do not cover native-length successful authentication.')
    return engine.check(args.run,files,top=top,
        reset_constraints='initial\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [trusted_reset_n_i] false)\n',
        assertions=monitor.count('assert('),covers=monitor.count('cover('),binding=binding,
        scope=scope,cuts=[],depth=8,induction_depth=5,cover_depth=12,timeout=args.timeout,
        source_list=['auth.sv','sha.sv'],mutant=args.mutant)


if __name__=='__main__':raise SystemExit(main())
