"""Actual boot wrapper, watchdog, readback CDC and controller/FIFO/adapter.

Only four scalar outputs of the image authenticator are replaced by arbitrary
inputs. Its data/hash correctness remains outside this ordering theorem.
All native dimensions, clocks, synchronizers, gates and reset logic remain.
"""
import argparse
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
TOP='board1_context2048_ddr_locked_auth_watchdog_cdc_quarantined_payload'
WRAPPER='project/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_ddr_locked_auth_watchdog_cdc.sv'
AUTH='project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_semantic_image_auth_compact.sv'
AUTH_CUTS=[
    dict(output='readback_word_ready_o',connected_net='auth_readback_ready',input='f_auth_cut_ready_i',width=1),
    dict(output='digest_done_o',connected_net='auth_digest_done',input='f_auth_cut_done_i',width=1),
    dict(output='digest_ok_o',connected_net='auth_digest_ok',input='f_auth_cut_ok_i',width=1),
    dict(output='fail_closed_o',connected_net='auth_fail_closed',input='f_auth_cut_fault_i',width=1),
]
MUTATIONS={
    'bypass-physical-suppression':('assign app_cmd_en_o = boundary_app_cmd_en && !physical_suppress_now;',
        'assign app_cmd_en_o = boundary_app_cmd_en;'),
    'trust-early-digest-lock':('assign model_locked_o = boundary_model_locked && !output_fail;',
        'assign model_locked_o = (boundary_model_locked || digest_success_app) && !output_fail;'),
}


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_wrapper_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def multiclock_boot_monitor(original):
    # A sampled $past register can retain an unconstrained induction history
    # while its clock never moves. Use a reset-epoch observational latch and
    # an always-active assertion for the same sticky-fault obligation.
    before='    always_ff @(posedge clk) if (reset_n && f_past_valid_q && $past(reset_n) && $past(fail_closed))\n        assert(fail_closed);\n'
    after='''    logic f_failure_seen_q;
    always_ff @(posedge clk or negedge reset_n) begin
        if (!reset_n) f_failure_seen_q <= 0;
        else if (fail_closed) f_failure_seen_q <= 1;
    end
    always_comb if (reset_n && f_failure_seen_q) assert(fail_closed);
'''
    return load('run_boot_boundary').once(original,before,after)


def cover_stimulus(steps=48,mutant=None):
    text=''
    for step in range(steps):
        text+=f'state {step}\n'
        values=dict(app_clk_i=bool(step%2),trusted_clk_i=bool((step//2)%2),
            app_reset_n_i=step>=2,trusted_reset_n_i=step>=2,
            private_fixed_source_ready_i=step>=2,private_boot_progress_i=step>=2,
            private_loader_done_i=mutant=='bypass-physical-suppression'and step>=32,private_loader_valid_i=step>=2,
            private_runtime_req_valid_i=False,private_runtime_req_write_i=False,
            private_runtime_rsp_ready_i=True,private_runtime_endpoint_fail_closed_i=False,
            controller_pll_lock_i=step>=2,controller_init_calib_complete_i=step>=2,
            app_cmd_ready_i=True,app_wr_data_ready_i=True,
            app_rd_data_valid_i=False,app_rd_data_end_i=False,
            f_auth_cut_ready_i=True,f_auth_cut_done_i=mutant=='trust-early-digest-lock'and step>=2,
            f_auth_cut_ok_i=mutant=='trust-early-digest-lock'and step>=2,f_auth_cut_fault_i=False)
        for name,value in values.items():text+='assume (= ['+name+'] '+str(value).lower()+')\n'
        for name,width in [('private_loader_data_i',256),('private_runtime_req_word_address_i',19),
            ('private_runtime_req_write_data_i',256),('app_rd_data_i',256)]:
            text+='assume (= ['+name+'] (_ bv0 '+str(width)+'))\n'
    return text


def instrument(original,boot_monitor,boundary_monitor,wrapper_monitor):
    boundary=load('run_boot_boundary');once=boundary.once
    files=boundary.instrument({n:original[n]for n in boundary.SOURCES},boot_monitor,boundary_monitor)
    # Additional observation outputs only. They remain disconnected from all
    # production decisions and are consumed solely by the wrapper monitor.
    src=files['boundary.sv'].decode()
    src=once(src,'\n);',',\n    output wire f_observe_inner_read_seen_o, f_observe_inner_final_return_o\n);')
    src=once(src,'\nendmodule','\n    assign f_observe_inner_read_seen_o = f_boundary_read_seen_q;\n    assign f_observe_inner_final_return_o = f_observe_final_return;\nendmodule')
    files['boundary.sv']=src.encode()
    wrapper=original['wrapper.sv'].decode()
    match=re.search(r'^    (\w+) u_sole_readback_auth \(',wrapper,re.M)
    if not match or match[1]not in ('board1_context2048_semantic_image_auth_compact','tang_confidential_ciphertext_image_auth'):
        raise ValueError('Unreviewed native image-authenticator module')
    start=match.start()
    end=wrapper.index(');',start)+2
    instance=wrapper[start:end]
    for row in AUTH_CUTS:
        if '.'+row['output']+'('+row['connected_net']+')'not in instance:
            raise ValueError('Image-authenticator output binding changed')
    assignments='\n'.join('    assign '+r['connected_net']+' = '+r['input']+';'for r in AUTH_CUTS)
    wrapper=once(wrapper,instance,assignments)
    header_end=wrapper.index('\n);')
    wrapper=wrapper[:header_end]+',\n'+',\n'.join('    input wire '+r['input']for r in AUTH_CUTS)+wrapper[header_end:]
    wrapper=once(wrapper,'    wire boundary_model_locked;',
        '    wire f_observe_inner_read_seen, f_observe_inner_final_return;\n    wire boundary_model_locked;')
    wrapper=once(wrapper,'            boundary_raw_response_protocol_fault_now)\n    );',
        '            boundary_raw_response_protocol_fault_now),\n        .f_observe_inner_read_seen_o(f_observe_inner_read_seen),\n        .f_observe_inner_final_return_o(f_observe_inner_final_return)\n    );')
    end=wrapper.index('\nendmodule')
    wrapper=wrapper[:end]+'\n'+wrapper_monitor+wrapper[end:]
    files['wrapper.sv']=b'`undef FORMAL\n'+wrapper.encode()
    files['async-fifo.sv']=b'`undef FORMAL\n'+original['async-fifo.sv']
    return files,instance


def main():
    common,boundary,engine=load('run_handoff'),load('run_boot_boundary'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--directed-cover',action='store_true',help='Finite legal boot-write stimulus for COVER only; never used by safety or induction')
    parser.add_argument('--mutant',choices=tuple(MUTATIONS))
    args=parser.parse_args();_,root,bound=common.binding(args.package,args.variant)
    paths=dict(boundary.SOURCES,**{'wrapper.sv':WRAPPER,'async-fifo.sv':'project/fifo.sv'})
    original={name:(root/path).read_bytes()for name,path in paths.items()}
    original_boot_monitor=(HERE/'boot-order-monitor.inc.sv').read_text()
    boot_monitor=multiclock_boot_monitor(original_boot_monitor)
    boundary_monitor=(HERE/'boot-boundary-monitor.inc.sv').read_text()
    wrapper_monitor=(HERE/'boot-wrapper-monitor.inc.sv').read_text()
    native=dict(original)
    if args.mutant:
        before,after=MUTATIONS[args.mutant]
        native['wrapper.sv']=boundary.once(native['wrapper.sv'].decode(),before,after).encode()
    files,auth_instance=instrument(native,boot_monitor,boundary_monitor,wrapper_monitor)
    files.update({'production-'+n:r for n,r in original.items()})
    files.update({'boot-monitor.inc.sv':boot_monitor.encode(),'boundary-monitor.inc.sv':boundary_monitor.encode(),
        'wrapper-monitor.inc.sv':wrapper_monitor.encode(),'cut-auth-instance.sv.txt':auth_instance.encode(),
        'production-auth.sv':(root/AUTH).read_bytes(),'runner.py':Path(__file__).read_bytes(),
        'boundary_builder.py':(HERE/'run_boot_boundary.py').read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),'SOURCES.json':(HERE/'SOURCES.json').read_bytes()})
    cuts=[dict(row,instance='u_sole_readback_auth',replacement='unrestricted module input '+row['input'])for row in AUTH_CUTS]
    binding=dict(bound,variant=args.variant,production_sources={n:dict(path=paths[n],sha256=common.sha(r))for n,r in original.items()},
        authentication_source_sha256=common.sha((root/AUTH).read_bytes()),
        authenticator_outputs_arbitrary=cuts,original_model_words=227062,
        readback_cdc_width=257,readback_cdc_depth=4,
        boot_monitor_original_sha256=common.sha(original_boot_monitor.encode()),
        boot_monitor_epoch_safe_sha256=common.sha(boot_monitor.encode()),
        directed_early_write_cover=args.directed_cover,
        observer_feedback_into_production=False,
        original_payload_source_retained_but_unconsumed_auth_payload_may_be_optimized_out=True)
    scope=('Actual native outer boot wrapper, exact watchdog, reset releases, scalar digest synchronizers, '
        'readback CDC and complete boot controller/FIFO2/adapter. Four image-authenticator scalar outputs '
        'are unrestricted inputs, with exact child source retained as provenance only. Original 227062-word '
        'model, 19-bit addressing and full FIFO parameters retained. Source-level payload RAM is not cut, '
        'but unused authenticator-input payload may be optimized away. LOCK requires prior wrapper output '
        'read and input response; model writes form a prefix before the first wrapper output read. '
        'No SHA/image authentication, CDC payload-integrity/physical-metastability, outer handoff or final '
        'asynchronous DDR transport theorem. No fairness or safety input protocol assumption. Full LOCK reachability '
        'is not searched; only early boot writes are covered.')
    if args.directed_cover:scope+=' COVER alone uses a finite explicit 2:1 clock and legal early-write stimulus; no frequency or fairness assumption enters safety/induction.'
    reset='initial\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\n'
    if args.mutant:
        reset+=cover_stimulus(mutant=args.mutant)
        binding['directed_negative_probe']=True
        scope+=' Negative control only: a finite explicit clock/input stimulus selects a source-contract violation or early abstract digest success. No induction theorem is requested for a mutant.'
    raise SystemExit(engine.check(args.run,files,top=TOP,reset_constraints=reset,
        assertions=sum(m.count('assert(')for m in (boot_monitor,boundary_monitor,wrapper_monitor)),
        covers=3,binding=binding,scope=scope,cuts=cuts,depth=48 if args.mutant else 12,induction_depth=8,
        cover_depth=48 if args.directed_cover else 40,
        cover_constraints=cover_stimulus()if args.directed_cover else None,
        timeout=args.timeout,source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv','async-fifo.sv','wrapper.sv'],
        expected_register_memories={
            'u_locked_boundary.u_request_fifo.write_q':{'width':1,'size':2},
            'u_locked_boundary.u_request_fifo.addr_q':{'width':19,'size':2},
            'u_locked_boundary.u_request_fifo.data_q':{'width':256,'size':2}},
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},multiclock=True,mutant=args.mutant,
        constraint_scope_description='Directed negative probe only: reset and 48 explicit input states; no induction requested.'if args.mutant else None))


if __name__=='__main__':main()
