"""Actual four encrypted banks and native shared SHA pool: chain ownership.

All private crypto replies are arbitrary inputs. No property of AES is needed
for the SHA ownership guarantee. The actual native pool and full bank RAMs are
retained, with only separately proved stateless SHA arithmetic equivalences.
"""
import argparse
import hashlib
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
OLD=HERE.parent/'formal-assurance'


def load(name,path):
    spec=importlib.util.spec_from_file_location('_encrypted_owner_'+name,path)
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


HARNESS='''module encrypted_hash_bank_ownership(
    input wire clk,reset_n,other_private_fault_i,
    input wire [3:0] cancel_i,begin_valid_i,fill_valid_i,fill_last_i,read_valid_i,response_ready_i,
    input wire [43:0] begin_page_i,
    input wire [1023:0] expected_digest_i,fill_data_i,
    input wire [27:0] read_word_i,
    input wire [3:0] crypto_request_ready_i,crypto_response_valid_i,
    input wire [511:0] crypto_response_block_i,
    output wire [3:0] begin_ready_o,fill_ready_o,read_ready_o,response_valid_o,assigned_o,verified_o,
    output wire [1023:0] response_data_o,
    output wire [3:0] crypto_request_valid_o,
    output wire [511:0] crypto_request_block_o,
    output wire fault_o
);
    wire [3:0] bank_fault,hash_request_valid,hash_request_ready,hash_pending,hash_response_valid;
    wire [2047:0] hash_request_block;
    wire [1023:0] hash_request_state,hash_response_state;
    wire hash_fault;
    assign fault_o=other_private_fault_i || hash_fault || (|bank_fault);
    tang_private_sha256_pool2 #(.BANKS(4)) u_hash_pool (
        .clk(clk),.reset_n(reset_n),.abort_i(fault_o),
        .request_valid_i(hash_request_valid),.request_ready_o(hash_request_ready),
        .request_block_i(hash_request_block),.request_state_i(hash_request_state),
        .pending_o(hash_pending),.response_valid_o(hash_response_valid),
        .response_state_o(hash_response_state),.fault_o(hash_fault));
    generate for(genvar b=0;b<4;b=b+1) begin: g_bank
        wire [10:0] page;
        tang_pooled_confidential_page_bank #(.IMAGE_WORDS(227062),
            .KEY_IS_PROVISIONED(1'b1),.MODEL_NONCE(96'h112233445566778899aabbcc)) u_bank (
            .clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i[b]),
            .begin_valid_i(begin_valid_i[b]),.begin_ready_o(begin_ready_o[b]),
            .begin_page_i(begin_page_i[b*11 +: 11]),.expected_digest_i(expected_digest_i[b*256 +: 256]),
            .fill_valid_i(fill_valid_i[b]),.fill_ready_o(fill_ready_o[b]),
            .fill_data_i(fill_data_i[b*256 +: 256]),.fill_last_i(fill_last_i[b]),
            .read_valid_i(read_valid_i[b]),.read_ready_o(read_ready_o[b]),.read_word_i(read_word_i[b*7 +: 7]),
            .response_valid_o(response_valid_o[b]),.response_ready_i(response_ready_i[b]),
            .response_data_o(response_data_o[b*256 +: 256]),.assigned_o(assigned_o[b]),.verified_o(verified_o[b]),
            .page_o(page),.fault_o(bank_fault[b]),
            .crypto_request_valid_o(crypto_request_valid_o[b]),.crypto_request_ready_i(crypto_request_ready_i[b]),
            .crypto_request_block_o(crypto_request_block_o[b*128 +: 128]),
            .crypto_response_valid_i(crypto_response_valid_i[b]),.crypto_response_block_i(crypto_response_block_i[b*128 +: 128]),
            .hash_request_valid_o(hash_request_valid[b]),.hash_request_ready_i(hash_request_ready[b]),
            .hash_request_block_o(hash_request_block[b*512 +: 512]),
            .hash_request_state_o(hash_request_state[b*256 +: 256]),.hash_pending_i(hash_pending[b]),
            .hash_response_valid_i(hash_response_valid[b]),.hash_response_state_i(hash_response_state[b*256 +: 256]));
    end endgenerate
    always_ff @(posedge clk) if(reset_n && !fault_o) begin
        cover(|(hash_request_valid & hash_request_ready));
        cover(|hash_response_valid);
    end
endmodule
'''


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--run',type=Path,required=True)
    p.add_argument('--timeout',type=int,default=90)
    p.add_argument('--mutant',choices=('wrong-held-bank','wrong-expected-digest','corrupt-filled-word'))
    p.add_argument('--lifecycle',action='store_true')
    p.add_argument('--safety-only',action='store_true',help='Retain source-identical native call/return coverage from the separately audited ownership model')
    args=p.parse_args();common=load('binding',OLD/'run_handoff.py');engine=load('engine',HERE/'engine.py')
    arithmetic=load('arithmetic',HERE/'proved_arithmetic.py')
    _,directory,bound=common.binding(args.package,'encrypted-memory')
    original={n:(directory/('project/'+n)).read_bytes()for n in('sha.sv','bank.sv','service.sv','shared_token_probe.sv','uart_core.sv')}
    if re.findall(rb'\.AUTH_BANKS\((\d+)\)',original['uart_core.sv'])!=[b'4']:
        raise ValueError('Actual native bank count differs')
    if b'.BANKS(AUTH_BANKS),.ADDR_W(19)'not in original['shared_token_probe.sv']:
        raise ValueError('Actual service parameter wiring differs')
    for literal in(b".KEY_IS_PROVISIONED(1'b1)",b".MODEL_NONCE(96'h112233445566778899aabbcc)"):
        if literal not in original['shared_token_probe.sv']:raise ValueError('Actual confidentiality parameters differ')
    sha_source,obligations,premise_files=arithmetic.rewrite(original['sha.sv'])
    # The module-scope procedural loop temporary is otherwise diagnosed as
    # an always_comb latch by Yosys before unused-variable removal. Its only
    # reads are inside the for loop, after its unconditional initializer.
    # Narrow its scope without changing any expression, bound or native net.
    a=sha_source.index(b'module tang_private_sha256_pool2 #(');b=sha_source.index(b'\nendmodule',a)+len(b'\nendmodule')
    native_pool=sha_source[a:b]
    lines=[line.strip()for line in native_pool.decode().splitlines()if re.search(r'\boffset\b',line)]
    if lines!=['integer engine,offset,slot,bank;',
        'for(offset=0;offset<GROUP_BANKS;offset=offset+1) begin',
        "slot=(int'(rr_q[engine])+offset)&(GROUP_BANKS-1);"]:
        raise ValueError('The loop temporary is no longer private to its initialized loop')
    scoped_pool=native_pool.replace(b'integer engine,offset,slot,bank;',b'integer engine,slot,bank;',1)
    scoped_pool=scoped_pool.replace(b'for(offset=0;offset<GROUP_BANKS;offset=offset+1)',b'for(integer offset=0;offset<GROUP_BANKS;offset=offset+1)',1)
    sha_source=sha_source[:a]+scoped_pool+sha_source[b:]
    if args.mutant=='wrong-held-bank':
        before=b"SLOT_W'(int'(owner_q[g])/2) : grant_slot[g];"
        if sha_source.count(before)!=1:raise ValueError('Native held-bank selector mutation site changed')
        sha_source=sha_source.replace(before,b'grant_slot[g] : grant_slot[g];',1)
    data_route_monitor=(HERE/'encrypted-pool-data-route-monitor.inc.sv').read_bytes()
    anchor=b'    end\n\n    wire protocol_error=bad_return'
    if sha_source.count(anchor)!=1:raise ValueError('Native engine input bus observer insertion point changed')
    sha_source=sha_source.replace(anchor,data_route_monitor+anchor,1)
    pool_monitor=(HERE/'encrypted-pool-owner-monitor.inc.sv').read_bytes()
    a=sha_source.index(b'module tang_private_sha256_pool2 #(');b=sha_source.index(b'\nendmodule',a)
    sha_source=sha_source[:b]+b'\n'+pool_monitor+sha_source[b:]
    bank_monitor=(HERE/'encrypted-bank-owner-monitor.inc.sv').read_bytes()
    lifecycle_monitor=b''
    if args.lifecycle:
        lifecycle_monitor=(HERE/'encrypted-bank-lifecycle-monitor.inc.sv').read_bytes()
        bank_monitor+=b'\n'+lifecycle_monitor
    bank_source=original['bank.sv']
    if args.mutant in('wrong-expected-digest','corrupt-filled-word'):
        if not args.lifecycle:raise ValueError('Bank data controls require the full lifecycle observer')
        before,after=(b'expected_q<=expected_digest_i;',b'expected_q<=~expected_digest_i;')if args.mutant=='wrong-expected-digest'else(
            b'<=memory_write_data;',b"<=memory_write_data^256'd1;")
        if bank_source.count(before)!=1:raise ValueError('Native bank data mutation site changed')
        bank_source=bank_source.replace(before,after,1)
    bank_source=bank_source.replace(b'\nendmodule',b'\n'+bank_monitor+b'\nendmodule',1)
    harness=HARNESS
    if args.lifecycle:
        bank_source=bank_source.replace(b'\n);',b',\n    input wire f_service_active_i\n);',1)
        harness=harness.replace('.clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i[b]),',
            '.clk(clk),.reset_n(reset_n),.cancel_read_i(cancel_i[b]),.f_service_active_i(!fault_o),',1)
    if args.safety_only:harness=re.sub(r'cover\([^;]*\);',';',harness)
    files={'sha.sv':b'`undef FORMAL\n'+sha_source,'bank.sv':b'`undef FORMAL\n'+bank_source,
        'harness.sv':harness.encode(),'bank-monitor.inc.sv':bank_monitor,'pool-monitor.inc.sv':pool_monitor,
        'data-route-monitor.inc.sv':data_route_monitor,
        'pool-loop-native.sv':native_pool,'pool-loop-scoped.sv':scoped_pool,
        **{'production-'+n:raw for n,raw in original.items()},**premise_files,
        'runner.py':Path(__file__).read_bytes(),'proved_arithmetic.py':(HERE/'proved_arithmetic.py').read_bytes(),
        'binding_helper.py':(OLD/'run_handoff.py').read_bytes(),'SOURCES.json':(OLD/'SOURCES.json').read_bytes()}
    cover=''
    mask=4 if args.mutant else 1
    for state in range(2,155 if args.mutant else 200):
        cover+=f'state {state}\nassume (= [reset_n] true)\nassume (= [other_private_fault_i] false)\n'
        values={'begin_valid_i':mask if state==2 else 0,'fill_valid_i':mask if 3<=state<=130 else 0,
            'fill_last_i':mask if state==130 else 0,'cancel_i':0,'read_valid_i':0,'response_ready_i':15,
            'crypto_request_ready_i':15,'crypto_response_valid_i':mask if state in(133,135,139,141)else 0}
        for name,value in values.items():cover+=f'assume (= [{name}] (_ bv{value} 4))\n'
        for name,width in(('begin_page_i',44),('fill_data_i',1024),('crypto_response_block_i',512)):
            value=(2<<22)if args.mutant and name=='begin_page_i'else 0
            cover+=f'assume (= [{name}] (_ bv{value} {width}))\n'
    binding=dict(native_join=bound,native_banks=4,native_image_words=227062,native_nonce='112233445566778899aabbcc',
        key_is_provisioned=True,actual_native_pool_and_four_full_banks=True,
        crypto_replies_and_all_producer_consumer_inputs_unrestricted=True,crypto_behavior_assumptions=[],
        arithmetic_substitution_premises=obligations,all_substitution_premises_independently_discharged=True,
        owner_chain_contract_assumed=False,actual_private_service_to_bank_allocation_not_composed_here=True)
    binding['full_encrypted_sealed_copy_lifecycle_included']=args.lifecycle
    binding['service_active_observer_input_has_no_production_fanout']=args.lifecycle
    binding['separate_native_call_return_coverage_run']='encrypted-hash-owner-r4-data-routing'if args.safety_only else None
    binding['frontend_loop_temporary_scope_normalization']=dict(module='tang_private_sha256_pool2',temporary='offset',
        native_module_sha256=hashlib.sha256(native_pool).hexdigest(),scoped_module_sha256=hashlib.sha256(scoped_pool).hexdigest(),
        all_reads_dominated_by_loop_initializer=True,no_native_net_expression_or_bound_changed=True,
        separate_normalization_audit_required=True)
    reset='initial\nassume (= [reset_n] false)\nstate 1\nassume (= [reset_n] false)\n'
    return engine.check(args.run,files,top='encrypted_hash_bank_ownership',
        reset_constraints=reset+(cover if args.mutant else''),
        assertions=38+4*lifecycle_monitor.count(b'assert('),covers=0 if args.safety_only else 2,binding=binding,cuts=obligations,depth=155 if args.mutant else 5,induction_depth=3,
        cover_depth=200,cover_constraints=None if args.safety_only else cover,timeout=args.timeout,mutant=args.mutant,
        source_list=['sha.sv','bank.sv','harness.sv'],expected_memories=4,map_literal_roms=True,optimize_full=True,
        observer_constants=4 if args.lifecycle else 0,
        solver_order=('cvc5','z3')if args.lifecycle else('z3','cvc5'),induction_first=args.lifecycle,
        solver_cli={s:['--unroll']for s in('z3','cvc5')},
        scope='Actual native four encrypted page banks and two-engine SHA pool. Prove chain inputs are held through actual accepted calls/returns, engine ownership and return routing, without an owner promise. Full bank RAM and native SHA retained, with independently proved stateless arithmetic substitutions. Private crypto replies and all bank callers are unrestricted, making this independent of AES behavior. No full encrypted bank lifecycle, parent service/consumer, AES correctness, hash-hardness, physical or whole-device training theorem.')


if __name__=='__main__':raise SystemExit(main())
