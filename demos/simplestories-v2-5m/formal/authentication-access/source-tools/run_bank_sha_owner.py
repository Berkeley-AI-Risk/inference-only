"""Discharge the real page-bank SHA chain ownership contract with native RTL."""
import argparse
import hashlib
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'
TOP='board1_verified_page_bank'
VENDOR=Path('/Volumes/GowinIDE/GowinIDE.app/Contents/Resources/Gowin_EDA/IDE/simlib/gw5a/prim_sim.v')


def load(name,path):
    spec=importlib.util.spec_from_file_location('_bank_owner_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory'),default='baseline')
    p.add_argument('--lifecycle',action='store_true')
    p.add_argument('--block-sequence',action='store_true')
    p.add_argument('--mutant',choices=('wrong-expected-digest','corrupt-filled-word'))
    p.add_argument('--timeout',type=int,default=90)
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    package=common.model_package(args.package)
    group=('baseline','seeded-sampling')if args.variant=='baseline'else(args.variant,)
    original=None;joins={}
    for variant in group:
        _,directory,bound=common.binding(args.package,variant)
        actual={n:(directory/('project/'+n)).read_bytes()for n in ('bank.sv','sha.sv')}
        if original is not None and original!=actual:raise ValueError('Claimed source identity differs')
        original=actual;joins[variant]=bound
    source=original['bank.sv'].decode()
    if args.mutant:
        if not args.lifecycle:raise ValueError('Semantic data controls require the sealed-copy lifecycle observer')
        before,after=('expected_q<=expected_digest_i;','expected_q<=~expected_digest_i;')if args.mutant=='wrong-expected-digest'else(
            'memory_q[fill_count_q[6:0]]<=memory_write_data;',"memory_q[fill_count_q[6:0]]<=memory_write_data^256'd1;")
        if source.count(before)!=1:raise ValueError('Native mutation site changed')
        source=source.replace(before,after,1)
    if '.state_i(chain_q)'not in source or '.start_i(state_q==LAUNCH && !fault_o)'not in source:
        raise ValueError('Native child ownership wiring changed')
    monitor=(HERE/'bank-sha-owner-monitor.inc.sv').read_text()
    constants=0
    lifecycle_original=None
    if args.lifecycle:
        if args.variant=='encrypted-memory':raise ValueError('Encrypted pooled bank has a distinct lifecycle')
        lifecycle_original=(package/'formal/current-seeded-page-bank/bank_monitor.inc.sv').read_text()
        lifecycle=lifecycle_original
        if args.variant=='kv-protected':
            # The protected native bank reads each pair before START; it has
            # none of the baseline's concurrent next-block prefetch registers.
            a=lifecycle.index('            if (state_q == HASH) begin\n')
            b=lifecycle.index('            assert(response_valid_q == f_consumer_pending);',a)
            lifecycle=lifecycle[:a]+lifecycle[b:]
        monitor=lifecycle+'\n'+monitor
        constants=1
    if args.block_sequence:
        monitor+='''
    logic [6:0] f_calls_q,f_returns_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if(!reset_n) begin f_calls_q<=0;f_returns_q<=0;end
        else if(begin_fire) begin f_calls_q<=0;f_returns_q<=0;end
        else begin
            if(f_sha_start && !sha_busy) f_calls_q<=f_calls_q+7'd1;
            if(state_q==HASH && sha_done) f_returns_q<=f_returns_q+7'd1;
        end
    end
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        assert(f_calls_q<=65 && f_returns_q<=65 && f_returns_q<=f_calls_q);
        if(state_q==FILL || state_q==ZERO) assert(f_calls_q==0 && f_returns_q==0);
        if(state_q==READ0 || state_q==READ1 || state_q==CAP1 || state_q==LAUNCH)
            assert(f_calls_q==block_q && f_returns_q==block_q);
        if(state_q==HASH) assert(f_calls_q==block_q+7'd1 && f_returns_q==block_q);
        if(state_q==COMPARE || verified_o) assert(f_calls_q==65 && f_returns_q==65);
    end
'''
    if source.count('\nendmodule')!=1:raise ValueError('Native insertion boundary changed')
    source=source.replace('\nendmodule','\n'+monitor+'\nendmodule')
    files={'bank.sv':b'`undef FORMAL\n'+source.encode(),'sha.sv':b'`undef FORMAL\n'+original['sha.sv'],
        **{'production-'+n:data for n,data in original.items()},'monitor.inc.sv':monitor.encode(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),
        'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    if lifecycle_original is not None:files['lifecycle-original.inc.sv']=lifecycle_original.encode()
    sources=['bank.sv','sha.sv']
    vendor=None
    if args.variant!='baseline':
        raw=VENDOR.read_bytes()
        if hashlib.sha256(raw).hexdigest()!='a5c5193b4b1cd1d86084e2c3a6a3d15d3fbacb931faa6cd08aa8c9c793fa37bd':
            raise ValueError('Vendor model changed')
        a=raw.index(b'module MULTALU27X18 ');b=raw.index(b'\nendmodule',a)+len(b'\nendmodule')
        files['private-vendor-MULTALU27X18.v']=raw[a:b];sources.append('private-vendor-MULTALU27X18.v')
        vendor={'library_sha256':hashlib.sha256(raw).hexdigest(),'module_sha256':hashlib.sha256(raw[a:b]).hexdigest(),'private_dependency_not_for_publication':True}
    binding=dict(native_joins=joins,variant=args.variant,production_sources={n:hashlib.sha256(raw).hexdigest()for n,raw in original.items()},
        complete_actual_sha_child=True,arbitrary_internal_sha_replies=False,
        owner_chain_contract_assumed=False,real_32768_bit_page_ram=True,
        full_existing_lifecycle_included=args.lifecycle,vendor_functional_model=vendor)
    binding['all_64_data_blocks_and_one_padding_block_sequence_checked']=args.block_sequence
    binding['baseline_only_prefetch_observer_removed']=args.lifecycle and args.variant=='kv-protected'
    scope=('Actual page bank and complete native SHA implementation. Independently prove the live SHA '
        'chaining input retains its accepted value through BUSY and DONE, so the private compressor '
        'feed-forward contract can be composed without an owner assumption. Real full page RAM and '
        'actual data paths remain; no SHA boundary cut or arithmetic oracle. Existing lifecycle '
        'invariants are additionally included only when explicitly requested. This is a digital '
        'ownership/composition result, not a complete page-service/consumer or cryptographic-hardness theorem.')
    # One ordinary complete zero page, followed by a compressor transaction.
    # This stimulus is used only to reach the COVER goals. Safety/induction
    # retain fully arbitrary producer data, stalls and malformed requests.
    cover=''
    expected=hashlib.sha256(bytes(4096)).hexdigest()
    for state in range(2,180):
        cover+=f'state {state}\nassume (= [reset_n] true)\n'
        for name,value in [('begin_valid_i',state==2),('fill_valid_i',3<=state<=130),
            ('fill_last_i',state==130),('read_valid_i',False),('cancel_read_i',False),('response_ready_i',True)]:
            cover+='assume (= ['+name+'] '+('true'if value else'false')+')\n'
        cover+='assume (= [begin_page_i] (_ bv0 11))\nassume (= [fill_data_i] (_ bv0 256))\n'
        cover+='assume (= [expected_digest_i] #x'+expected+')\n'
    return engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n',
        assertions=monitor.count('assert('),covers=monitor.count('cover('),binding=binding,scope=scope,cuts=[],
        depth=7 if args.mutant else 5,induction_depth=3,cover_depth=180,cover_constraints=cover,timeout=args.timeout,source_list=sources,
        observer_constants=constants,map_literal_roms=True,optimize_full=True,
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},mutant=args.mutant)


if __name__=='__main__':raise SystemExit(main())
