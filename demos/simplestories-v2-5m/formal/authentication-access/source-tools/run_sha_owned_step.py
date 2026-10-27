"""Native baseline/seeded private two-round SHA work/result correspondence."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
TOP='board1_sha256_bank_owned_compress'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_owned_sha_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--run',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=120)
    p.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory'),default='baseline')
    p.add_argument('--mutant',choices=('wrong-k','wrong-schedule-tap'))
    p.add_argument('--proved-arithmetic-leaves',action='store_true')
    p.add_argument('--cache-reference',action='store_true',help='Refine through the proved h+K+W cache invariant and universal modular regrouping lemma')
    args=p.parse_args()
    common=load('bindings',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    ref=load('reference',HERE/'fips180_4.py')
    original=None;joins={}
    group=('baseline','seeded-sampling')if args.variant=='baseline'else(args.variant,)
    for variant in group:
        _,directory,bound=common.binding(args.package,variant)
        raw=(directory/'project/sha.sv').read_bytes()
        if original is not None and original!=raw:raise ValueError('Claimed native SHA identity changed')
        original=raw;joins[variant]=bound
        if 'board1_sha256_bank_owned_compress #(.REGISTER_RESULT(0)) u_sha'not in ((directory/'project/bank.sv').read_text()+(directory/'project/sha.sv').read_text()):
            raise ValueError('Native page-bank result mode changed')
    functions=(HERE/'sha-compact-reference-monitor.inc.sv').read_text().split('    logic [31:0] f_ring_q',1)[0]
    constants='    function automatic [31:0] f_k(input [5:0] t);\n        case(t)\n'
    constants+=''.join(f"            6'd{n}: f_k=32'h{k:08x};\n"for n,k in enumerate(ref.K))
    constants+="            default: f_k=32'h0;\n        endcase\n    endfunction"
    functions=functions.replace('__REFERENCE_K_FUNCTION__',constants)
    monitor=(HERE/'sha-owned-step-monitor.inc.sv').read_text().replace('__REFERENCE_FUNCTIONS__',functions)
    reference_premise=None;reference_files={}
    if args.cache_reference:
        if args.variant=='baseline':raise ValueError('Baseline has no precomputed h+K+W cache')
        lemma=HERE/'runs/modular-sum-regroup-r1'
        receipt=json.loads((lemma/'FINISHED.json').read_bytes())
        digest=lambda raw:hashlib.sha256(raw).hexdigest()
        if not receipt['passed']or not receipt['no_assumptions']or receipt['word_width']!=32:
            raise ValueError('Modular regrouping lemma is incomplete')
        if digest((lemma/'lemma.smt2').read_bytes())!=receipt['query_sha256']:
            raise ValueError('Regrouping formula changed')
        for row in receipt['results']:
            if not row['passed']or row['answers']!=['sat','unsat']or digest((lemma/(row['solver']+'.log')).read_bytes())!=row['log_sha256']:
                raise ValueError('Regrouping solver evidence changed')
        a=functions.index('    function automatic [255:0] f_round(')
        b=functions.index('    endfunction',a)+len('    endfunction')
        cached=functions[a:b].replace('f_round','f_round_cached')
        cached=cached.replace('input [31:0] w, input [31:0] k','input [31:0] cached_hkw')
        cached=cached.replace('t1=h+f_S1(e)+((e & f) ^ (~e & g))+k+w;',
            't1=f_S1(e)+((e & f) ^ (~e & g))+cached_hkw;')
        if 'input [31:0] cached_hkw'not in cached or 't1=h+'in cached:
            raise ValueError('Reference function regrouping site changed')
        monitor=monitor.replace(functions,functions+'\n'+cached)
        monitor=monitor.replace('f_round(f_work,schedule_q[0],f_k(round_q))','f_round_cached(f_work,hkw_q)')
        monitor=monitor.replace("f_round(f_step1,schedule_q[1],f_k(round_q+6'd1))",'f_round_cached(f_step1,gkw_q)')
        reference_premise=dict(kind='proved-equivalent-reference-regrouping',lemma_run=lemma.name,
            result_sha256=digest((lemma/'FINISHED.json').read_bytes()),
            cache_relations_checked_as_assertions=True,independently_discharged=True)
        reference_files={'regroup-lemma.smt2':(lemma/'lemma.smt2').read_bytes(),
            'regroup-FINISHED.json':(lemma/'FINISHED.json').read_bytes()}
    if args.variant!='baseline':
        monitor+='''
    always_ff @(posedge clk_i) if(reset_n_i && busy_o) begin
        assert(hkw_q==32'(h_q+f_k(round_q)+schedule_q[0]));
        assert(gkw_q==32'(g_q+f_k(round_q+6'd1)+schedule_q[1]));
    end
'''
    model_source=original;obligations=[];premise_files={}
    if args.proved_arithmetic_leaves:
        if args.variant=='baseline':raise ValueError('Baseline has no native DSP-adder leaves')
        arithmetic=load('proved_arithmetic',HERE/'proved_arithmetic.py')
        model_source,obligations,premise_files=arithmetic.rewrite(original)
    source=model_source.decode();start=source.index('module '+TOP+' #(');end=source.index('\nendmodule',start)
    if args.mutant:
        selected=source[start:end]
        before,after=("6'd0:  round_constant = 32'h428a2f98;","6'd0:  round_constant = 32'h428a2f99;")if args.mutant=='wrong-k'else('small_sigma1(schedule_q[14])','small_sigma1(schedule_q[13])')
        if selected.count(before)!=1:raise ValueError('Selected native mutation site changed')
        selected=selected.replace(before,after,1)
        source=source[:start]+selected+source[end:];end=start+len(selected)
    source=source[:end]+'\n'+monitor+source[end:]
    files={'sha.sv':b'`undef FORMAL\n'+source.encode(),'production-sha.sv':original,
        'reference-monitor.inc.sv':monitor.encode(),'reference.py':(HERE/'fips180_4.py').read_bytes(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    files.update(premise_files)
    files.update(reference_files)
    if args.proved_arithmetic_leaves:files['proved_arithmetic.py']=(HERE/'proved_arithmetic.py').read_bytes()
    sources=['sha.sv']
    vendor=None
    if args.variant!='baseline' and not args.proved_arithmetic_leaves:
        raw=Path('/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v').read_bytes()
        if hashlib.sha256(raw).hexdigest()!='a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd':raise ValueError('Vendor model changed')
        a=raw.index(b'module MULTALU27X18 ');b=raw.index(b'\nendmodule',a)+len(b'\nendmodule')
        files['private-vendor-MULTALU27X18.v']=raw[a:b];sources.append('private-vendor-MULTALU27X18.v')
        vendor=dict(library_sha256=hashlib.sha256(raw).hexdigest(),module_sha256=hashlib.sha256(raw[a:b]).hexdigest(),private_not_for_publication=True)
    cover=''
    block=b'abc'+b'\x80'+b'\x00'*52+(24).to_bytes(8,'big')
    iv='6a09e667bb67ae853c6ef372a54ff53a510e527f9b05688c1f83d9ab5be0cd19'
    for i in range(2,40):
        cover+=f'state {i}\nassume (= [reset_n_i] true)\nassume (= [start_i] '+('true'if i==2 else'false')+')\n'
        cover+='assume (= [state_i] #x'+iv+')\n'
        if i==2:cover+='assume (= [block_i] #x'+block.hex()+')\n'
    binding=dict(native_joins=joins,production_path='project/sha.sv',production_sha256=hashlib.sha256(original).hexdigest(),
        variant=args.variant,vendor_functional_model=vendor,actual_native_DSP_path_retained=args.variant!='baseline' and not args.proved_arithmetic_leaves,
        arithmetic_substitution_premises=obligations,all_substitution_premises_independently_discharged=bool(obligations),
        reference_regrouping_premise=reference_premise,
        result_mode=0,native_bank_result_mode_checked=True,accepted_block_and_chain_arbitrary=True,
        state_input_unrestricted_during_safety_and_induction=True,owner_contract_discharge_pending=True,
        reference_standard='FIPS 180-4 sections 4.1.2, 4.2.2 and 6.2.2')
    scope=('Actual selected two-round private SHA compressor in its native REGISTER_RESULT=0 mode. '
        'Prove complete sixty-four-round work-state correspondence through initialization and per-transition correspondence to the FIPS '
        'reference for arbitrary accepted blocks/chaining state and later input changes, and the exact '
        'live-input feed-forward relation at DONE. Digest correctness for the accepted chain additionally '
        'requires the parent to preserve that chain at DONE; that composition is NOT established here. '
        'No private owner assumption or arbitrary arithmetic output cut. The finite ABC cover holds '
        'the chain as a legal transaction witness only; those conditions do not enter safety or induction. '
        'Native DSP implementations are retained unless independently proved stateless arithmetic leaves are explicitly substituted; exact native identities and discharged premises are recorded. No portable macro fallback is selected.')
    return engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [reset_n_i] false)\nstate 1\nassume (= [reset_n_i] false)\n',
        assertions=monitor.count('assert(')+7,covers=1,binding=binding,scope=scope,cuts=obligations,
        depth=7 if args.mutant else 5,induction_depth=3,cover_depth=40,cover_constraints=cover,timeout=args.timeout,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},source_list=sources,map_literal_roms=True,optimize_full=True,mutant=args.mutant)


if __name__=='__main__':raise SystemExit(main())
