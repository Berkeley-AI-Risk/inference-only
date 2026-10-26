"""Actual memory ownership path with the boot wrapper retained.

Discharge the transport's source-side model-write-prefix and LOCK/response
preconditions using real boot/runtime gates. Only the image authenticator's
four scalar outputs are arbitrary; no complete boot module is blackboxed.
"""
import argparse
import importlib.util
from pathlib import Path
import re

HERE=Path(__file__).resolve().parent
TOP='board1_private_booted_shared_ddr'


def top_module(source):
    match=re.search(r'^module (\w+) \(',source.decode(),re.M)
    if not match or match[1]not in (TOP,'tang_confidential_booted_shared_ddr'):
        raise ValueError('Unexpected native memory module')
    return match[1]


def load(name):
    spec=importlib.util.spec_from_file_location('_memory_path_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def instrument(original,boot,boundary_monitor,wrapper_monitor,handoff_monitor,parent_monitor):
    boundary,wrapper=load('run_boot_boundary'),load('run_boot_wrapper');once=boundary.once
    files,auth_instance=wrapper.instrument(original,boot,boundary_monitor,wrapper_monitor)
    src=files['wrapper.sv'].decode();close=src.index('\n);')
    src=src[:close]+',\n    output wire f_observe_wrapper_read_seen_o, f_observe_wrapper_return_seen_o,\n    output wire [2:0] f_observe_wrapper_app_release_o'+src[close:]
    close=src.index('\nendmodule')
    src=src[:close]+'\n    assign f_observe_wrapper_read_seen_o = f_wrapper_read_seen_q;\n    assign f_observe_wrapper_return_seen_o = f_wrapper_return_seen_q;\n    assign f_observe_wrapper_app_release_o = app_release_q;\n'+src[close:]
    files['wrapper.sv']=src.encode()
    handoff=once(original['handoff.sv'].decode(),'    output logic fault_o\n',
        '    output logic fault_o,\n    output wire f_observe_runtime_phase_o\n')
    handoff=once(handoff,'\nendmodule','\n'+handoff_monitor+'\n    assign f_observe_runtime_phase_o = runtime_q;\nendmodule')
    files['handoff.sv']=b'`undef FORMAL\n'+handoff.encode()
    parent=original['memory.sv'].decode();close=parent.index('\n);')
    parent=parent[:close]+',\n'+',\n'.join('    input wire '+r['input']for r in wrapper.AUTH_CUTS)+parent[close:]
    parent=once(parent,'    logic fault_q;','    logic fault_q;\n    wire f_observe_boot_read_seen,f_observe_boot_return_seen,f_observe_runtime_phase;\n    wire [2:0] f_observe_boot_app_release;')
    old='.model_locked_o(boot_locked),.fail_closed_o(boot_fault),.watchdog_fault_o(boot_watchdog));'
    new='.model_locked_o(boot_locked),.fail_closed_o(boot_fault),.watchdog_fault_o(boot_watchdog),\n'
    new+=',\n'.join('        .'+r['input']+'('+r['input']+')'for r in wrapper.AUTH_CUTS)
    new+=',\n        .f_observe_wrapper_read_seen_o(f_observe_boot_read_seen),\n        .f_observe_wrapper_return_seen_o(f_observe_boot_return_seen),\n        .f_observe_wrapper_app_release_o(f_observe_boot_app_release));'
    parent=once(parent,old,new)
    parent=once(parent,'.runtime_locked_o(handoff_locked),.fault_o(handoff_fault));',
        '.runtime_locked_o(handoff_locked),.fault_o(handoff_fault),.f_observe_runtime_phase_o(f_observe_runtime_phase));')
    parent=once(parent,'\nendmodule','\n'+parent_monitor+'\nendmodule')
    files['memory.sv']=b'`undef FORMAL\n'+parent.encode()
    return files,auth_instance


def cover_stimulus(steps=48):
    text=''
    for step in range(steps):
        text+=f'state {step}\n'
        values=dict(app_clk_i=bool(step%2),trusted_clk_i=bool((step//2)%2),
            app_reset_n_i=step>=2,trusted_reset_n_i=step>=2,
            private_fixed_source_ready_i=step>=2,private_boot_progress_i=step>=2,
            private_loader_done_i=False,private_loader_valid_i=step>=2,
            private_req_valid_i=False,private_req_write_i=False,
            private_runtime_app_fault_i=False,private_source_fault_i=False,
            controller_pll_lock_i=step>=2,controller_init_calib_complete_i=step>=2,
            app_cmd_ready_i=True,app_wr_data_ready_i=True,app_rd_data_valid_i=False,app_rd_data_end_i=False,
            f_auth_cut_ready_i=True,f_auth_cut_done_i=False,f_auth_cut_ok_i=False,f_auth_cut_fault_i=False)
        for name,value in values.items():text+='assume (= ['+name+'] '+str(value).lower()+')\n'
        for name,width in [('private_loader_data_i',256),('private_req_word_i',19),('private_req_data_i',256),('app_rd_data_i',256)]:
            text+='assume (= ['+name+'] (_ bv0 '+str(width)+'))\n'
    return text


def main():
    common,boundary,wrapper,engine=load('run_handoff'),load('run_boot_boundary'),load('run_boot_wrapper'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),default='baseline')
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--complete-source-contract',action='store_true')
    args=parser.parse_args();pin,root,bound=common.binding(args.package,args.variant)
    paths=dict(boundary.SOURCES,**{'wrapper.sv':wrapper.WRAPPER,'async-fifo.sv':'project/fifo.sv',
        'memory.sv':'project/booted_memory.sv','handoff.sv':'project/handoff.sv'})
    original={name:(root/path).read_bytes()for name,path in paths.items()}
    boot=wrapper.multiclock_boot_monitor((HERE/'boot-order-monitor.inc.sv').read_text())
    boundary_monitor=(HERE/'boot-boundary-monitor.inc.sv').read_text()
    wrapper_monitor=(HERE/'boot-wrapper-monitor.inc.sv').read_text()
    handoff_monitor=(HERE/'handoff-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    parent_monitor=(HERE/'memory-path-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    if args.complete_source_contract:parent_monitor+='\n'+(HERE/'memory-source-contract.inc.sv').read_text()
    files,auth_instance=instrument(original,boot,boundary_monitor,wrapper_monitor,handoff_monitor,parent_monitor)
    files.update({'production-'+n:r for n,r in original.items()})
    files.update({'boot-monitor.inc.sv':boot.encode(),'boundary-monitor.inc.sv':boundary_monitor.encode(),
        'wrapper-monitor.inc.sv':wrapper_monitor.encode(),'handoff-monitor.inc.sv':handoff_monitor.encode(),
        'parent-monitor.inc.sv':parent_monitor.encode(),'cut-auth-instance.sv.txt':auth_instance.encode(),
        'production-auth.sv':(root/wrapper.AUTH).read_bytes(),'runner.py':Path(__file__).read_bytes(),
        'boundary_builder.py':(HERE/'run_boot_boundary.py').read_bytes(),
        'wrapper_builder.py':(HERE/'run_boot_wrapper.py').read_bytes(),
        'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),'SOURCES.json':(HERE/'SOURCES.json').read_bytes()})
    cuts=[dict(r,instance='u_boot.u_sole_readback_auth',replacement='unrestricted module input '+r['input'])for r in wrapper.AUTH_CUTS]
    binding=dict(bound,variant=args.variant,production_sources={n:dict(path=paths[n],sha256=common.sha(r))for n,r in original.items()},
        authentication_source_sha256=common.sha((root/wrapper.AUTH).read_bytes()),
        authenticator_outputs_arbitrary=cuts,original_model_words=227062,runtime_adapter_max_reads=32,
        readback_cdc_width=257,readback_cdc_depth=4,observer_feedback_into_production=False,
        no_whole_boot_module_cut=True,source_model_write_prefix_contract=True,
        lock_requires_prior_source_read_and_response=True)
    if args.complete_source_contract:binding['complete_source_contract']=True
    scope=('Actual native booted-memory parent with real boot wrapper/watchdog/CDC, fixed-length controller, '
        'FIFO2, boot/runtime adapters and one-way handoff. Only four scalar image-authenticator outputs '
        'are arbitrary; all native model/address/FIFO/watchdog dimensions and original gates remain. '
        'No safety input protocol assumptions or fairness. Proves source model-write prefix and that '
        'runtime lock requires an earlier emitted source read and input response. No SHA/ciphertext '
        'authentication, final asynchronous DDR transport, physical CDC or whole-machine theorem. '
        'COVER alone uses finite early legal-write stimulus; full LOCK reachability is not searched.')
    reset='initial\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\nassume (= [trusted_reset_n_i] false)\n'
    monitors=[boot,boundary_monitor,wrapper_monitor,handoff_monitor,parent_monitor]
    raise SystemExit(engine.check(args.run,files,top=top_module(original['memory.sv']),reset_constraints=reset,
        assertions=sum(m.count('assert(')for m in monitors),covers=4,binding=binding,scope=scope,cuts=cuts,
        depth=12,induction_depth=8,cover_depth=48,cover_constraints=cover_stimulus(),timeout=args.timeout,
        source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv','async-fifo.sv','wrapper.sv','handoff.sv','memory.sv'],
        expected_register_memories={
            'u_boot.u_locked_boundary.u_request_fifo.write_q':{'width':1,'size':2},
            'u_boot.u_locked_boundary.u_request_fifo.addr_q':{'width':19,'size':2},
            'u_boot.u_locked_boundary.u_request_fifo.data_q':{'width':256,'size':2}},
        solver_cli={s:['--unroll']for s in ('z3','cvc5')},multiclock=True))


if __name__=='__main__':main()
