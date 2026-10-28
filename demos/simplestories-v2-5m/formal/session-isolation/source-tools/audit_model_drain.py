"""Audit exact core transport wiring and the selected busy-CLEAR ledgers.

This is a source/receipt join, not an assembled device solver theorem. It
explicitly records the client-epoch and public-ready obligations still open.
"""
import argparse
import json
from pathlib import Path
import re

from record_progress import audit, sha
from run_attention_ownership import HERE, load
from run_projection_relational import instance_con
from run_semantic_ingress import tap
from audit_proof_instantiations import body
from run_semantic_relational import erase_checks


def block(source):
    start=source.index('    wire shell_queued_req_valid, shell_queued_req_ready;')
    return source[start:source.index('    always_comb begin',start)]


def observer_only(source):
    names=re.findall(r'\b([A-Za-z_]\w*)\s*(?:\[[^\]\n]+\])?\s*<=',erase_checks(source))
    if any(not n.startswith('f_')for n in names):raise ValueError('Monitor drives native state')
    if re.search(r'\bassume\s*\(',source):raise ValueError('Monitor introduces an assumption')


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--out',type=Path,required=True);ap.add_argument('--group-run',default='group-drain-r6')
    ap.add_argument('--transport-run',default='model-transport-drain-client-r1')
    args=ap.parse_args();out=args.out.resolve();out.mkdir(parents=True,exist_ok=False)
    manifest={}
    def pin(path):
        raw=path.read_bytes();manifest[str(path.resolve())]=sha(raw);return raw
    names=[args.transport_run,'semantic-drain-r1',args.group_run]
    receipts={name:audit(name,'native model-request drain and ownership')for name in names}
    if any(r['status']!='proved_component'for r in receipts.values()):raise ValueError('Unclosed drain prerequisite')
    inputs={n:json.loads(pin(HERE/'runs'/n/'INPUTS.json'))for n in names}
    for name,inp in inputs.items():
        if inp['assumption_cells']or inp['binding']['initial_hard_reset']or inp['changed_production_parameters']:
            raise ValueError('Unexpected assumptions, physical reset or native parameter changes')
        for file,row in inp['files'].items():
            if sha(pin(HERE/'runs'/name/file))!=row['sha256']:raise ValueError('Source differs from solver receipt')
        pin(HERE/'runs'/name/'FINISHED.json')
    transport=HERE/'runs'/names[0]
    core=body(pin(transport/'production-core.sv'),'board1_context2048_token_machine_core').decode()
    expected=block(core);wrapper=pin(transport/'wrapper.sv').decode()
    queue_roles={
        'shell_request':('board1_ddr_request_fifo2','u_shell_model_request_queue'),
        'shell_response':('board1_ddr_request_fifo2','u_shell_model_response_queue'),
        'layer_request':('board1_ddr_request_fifo2','u_layer_model_request_queue'),
        'layer_response':('board1_ddr_request_fifo2','u_layer_model_response_queue'),
        'arbiter':('board1_fixed_private_ddr_arbiter','u_private_ddr_arbiter')}
    connections={}
    for role,(module,instance)in queue_roles.items():
        native=instance_con(core,module,instance)
        instrumented=instance_con(wrapper,module,instance)
        if {n:v for n,v in instrumented.items()if not n.startswith('f_')}!=native:
            raise ValueError('A functional core connection differs: '+instance)
        if role!='arbiter'and(native['abort_i']!="1'b0"or native['reset_n']!='child_reset_n'):
            raise ValueError('An accepted local queue is reset/aborted by ordinary CLEAR')
        connections[role]=native
    if connections['arbiter']['reset_n']!='reset_n':raise ValueError('Arbiter no longer keeps core reset ownership')
    fm=pin(transport/'fifo-history-monitor.inc.sv').decode();am=pin(transport/'arbiter-history-monitor.inc.sv').decode()
    observer_only(fm);observer_only(am)
    fifo=body(pin(transport/'production-fifo.sv'),'board1_ddr_request_fifo2').decode()
    fifo=fifo.replace('\n);',',\n    input wire f_scope_i\n);',1)
    fifo=fifo.replace('\nendmodule','\n'+fm+'\nendmodule',1)
    fifo=tap(fifo,{'f_count_o':('[1:0] ','count_q'),'f_write_pointer_o':('','wr_ptr_q'),
        'f_read_pointer_o':('','rd_ptr_q'),'f_raw_addr0_o':('[ADDR_W-1:0] ','addr_q[0]')})
    if pin(transport/'fifo.sv').decode()!='`undef FORMAL\n'+fifo+'\n':raise ValueError('Functional FIFO RTL differs')
    arb=body(pin(transport/'production-arbiter.sv'),'board1_fixed_private_ddr_arbiter').decode()
    if re.search(r'\bclear_i\b',arb):raise ValueError('Public CLEAR can now alter the native owner arbiter')
    arb=tap(arb,{'f_count_o':('[4:0] ','owner_count_q'),'f_write_pointer_o':('[3:0] ','owner_write_pointer_q'),
        'f_read_pointer_o':('[3:0] ','owner_read_pointer_q'),'f_owner_words_o':('[15:0] ','owner_fifo_q'),
        'f_sticky_fail_o':('','fail_q')})
    if inputs[names[0]]['binding'].get('exact_per_client_conservation'):
        arb=tap(arb,{'f_shell_count_o':('[4:0] ','f_shell_count'),'f_layer_count_o':('[4:0] ','f_layer_count')})
    arb=arb.replace('\n);',',\n    input wire f_scope_i\n);',1)
    arb=arb.replace('\nendmodule','\n'+am+'\nendmodule',1)
    if pin(transport/'arbiter.sv').decode()!='`undef FORMAL\n'+arb+'\n':raise ValueError('Functional arbiter RTL differs')
    graph=json.loads(pin(transport/'elaborated.json'))['modules']['model_transport_drain'];memories={}
    for role,(_,instance)in queue_roles.items():
        if role=='arbiter':continue
        for array,bits in [('write_q',1),('addr_q',1 if role.endswith('response')else 19),('data_q',256)]:
            name=instance+'.'+array;words=[]
            for index in range(2):
                word=graph['netnames'].get(name+'['+str(index)+']')
                if not word or len(word['bits'])!=bits or any(b in'01'for b in word.get('attributes',{}).get('init','')):
                    raise ValueError('Native lowered FIFO word resized or initialized')
                constants=[b for b in word['bits']if not isinstance(b,int)]
                native_input=connections[role][{'data_q':'in_data_i','addr_q':'in_addr_i','write_q':'in_write_i'}[array]]
                if constants and not(re.fullmatch(r"\d+'[bdh]0+",native_input)and all(b=='0'for b in constants)):
                    raise ValueError('Unexpected native FIFO payload constant folding')
                words.append(dict(register_bits=sum(isinstance(b,int)for b in word['bits']),constant_zero_bits=len(constants)))
            memories[name]=dict(words=2,bits=bits,lowering='two native words lowered to registers',
                word_encoding=words,explicit_initialization=False)
    binder=load('binding',HERE.parent/'formal-assurance/run_handoff.py');variants={}
    for variant in('baseline','seeded-sampling','kv-protected','encrypted-memory'):
        _,native,bound=binder.binding(HERE.parents[1]/'fpga-demo/public-release',variant)
        cp=inputs[names[0]]['binding']['native_core_path']
        raw=pin(native/cp);current=body(raw,'board1_context2048_token_machine_core').decode()
        if block(current)!=expected:raise ValueError('Core transport wiring differs in '+variant)
        if bound['distributed_inputs'][cp]!=sha(raw):raise ValueError('Current source pin mismatch')
        for file,module in [('production-fifo.sv','board1_ddr_request_fifo2'),('production-arbiter.sv','board1_fixed_private_ddr_arbiter')]:
            target=body(pin(transport/file),module)
            candidates=[pin(native/p)for p in bound['distributed_inputs']if p.endswith('.sv')and
                re.search(rb'^module\s+'+module.encode()+rb'\b',(native/p).read_bytes(),re.M)]
            if not candidates or any(body(r,module)!=target for r in candidates):raise ValueError('Native module source differs')
        variants[variant]=dict(core_source_sha256=sha(raw),image_sha256=bound['image_sha256'],
            exact_native_transport_block_sha256=sha(expected.encode()))
    result=dict(model_transport_source_and_receipt_join_passed=True,receipts=receipts,
        current_variants=variants,actual_functional_connections=connections,native_payload_memories=memories,
        client_epoch_composition_complete=False,public_ready_composition_complete=False,
        physical_transport_composed=False,whole_device_session_theorem=False,
        remaining=['Tie client and core pending histories to one common empty tracking epoch.',
            'Connect embedding/group-reader and semantic busy-to-pending contracts to the actual shell CLEAR/drain barrier.',
            'Join typed K/V, outer transport and complete device mutable-state coverage.'],
        artifact_manifest=manifest)
    (out/'checker.py').write_bytes(Path(__file__).read_bytes())
    result['artifact_manifest'][str((out/'checker.py').resolve())]=sha((out/'checker.py').read_bytes())
    (out/'FINISHED.json').write_text(json.dumps(result,indent=2,sort_keys=True)+'\n')
    print(json.dumps(dict(model_transport_source_and_receipt_join_passed=True,variants=len(variants),native_payload_memories=len(memories),whole_device_session_theorem=False)))


if __name__=='__main__':main()
