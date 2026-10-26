"""The actual boot controller, two-entry request FIFO and DDR adapter.

Prove the fixed model-write prefix and drain within this native composition.
No SHA, watchdog, asynchronous transport or physical DDR behavior is assumed
proved by this boundary; all its existing external inputs remain arbitrary.
"""
import argparse
import importlib.util
from pathlib import Path

HERE=Path(__file__).resolve().parent
TOP='board1_context2048_ddr_preboard_locked_boundary'
SOURCES={
    'boot.sv':'project/fpga/token_only_model0_ddr_board1/product8_timing_successor2/rtl/board1_context2048_private_ddr_lock_bridge.sv',
    'boundary.sv':'project/fpga/token_only_model0_ddr_board1/product_top4/rtl/board1_context2048_ddr_preboard_locked_boundary.sv',
    'fifo.sv':'project/fpga/token_only_model0_ddr_board1/ddr_preboard_closure0/rtl/board1_ddr_request_fifo2.sv',
    'adapter.sv':'project/adapter.sv',
}
MUTATIONS={
    'wrong-queued-address-row':('fifo.sv','assign out_addr_o = addr_q[rd_ptr_q];',
        'assign out_addr_o = addr_q[~rd_ptr_q];'),
    'bypass-response-fault-command-gate':('boundary.sv',
        'assign app_cmd_en_o = adapter_app_cmd_en &&\n                          !adapter_response_protocol_fault_now;',
        'assign app_cmd_en_o = adapter_app_cmd_en;'),
}


def load(name):
    spec=importlib.util.spec_from_file_location('_boot_boundary_'+name,HERE/(name+'.py'))
    m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m


def once(source,old,new):
    if source.count(old)!=1:raise ValueError('Read-only observer boundary changed: '+old[:60])
    return source.replace(old,new)


def instrument(original,boot_monitor,parent_monitor):
    boot=once(original['boot.sv'].decode(),'\n);',',\n    output wire [18:0] f_observe_reads_o,\n    output wire f_observe_final_return_o\n);')
    boot=once(boot,'\nendmodule','\n'+boot_monitor+'\n    assign f_observe_reads_o = f_read_count_q;\n    assign f_observe_final_return_o = f_final_return_seen_q;\nendmodule')
    fifo=once(original['fifo.sv'].decode(),'\n);',',\n    output wire [43:0] f_observe_state_o\n);')
    fifo=once(fifo,'\nendmodule','\n    assign f_observe_state_o = {count_q,wr_ptr_q,rd_ptr_q,addr_q[1],write_q[1],addr_q[0],write_q[0]};\nendmodule')
    parent=original['boundary.sv'].decode()
    adapter=once(original['adapter.sv'].decode(),'\n);',',\n    output wire f_observe_read_owned_o\n);')
    adapter=once(adapter,'\nendmodule','\n    assign f_observe_read_owned_o = (outstanding_reads_q != 0);\nendmodule')
    parent=once(parent,'    wire bridge_req_valid;','    wire [18:0] f_observe_reads;\n    wire [43:0] f_observe_queue;\n    wire f_observe_final_return, f_observe_adapter_owned;\n    wire bridge_req_valid;')
    parent=once(parent,'.model_locked(model_locked_o), .fail_closed(bridge_fail_closed)',
        '.model_locked(model_locked_o), .fail_closed(bridge_fail_closed),\n        .f_observe_reads_o(f_observe_reads), .f_observe_final_return_o(f_observe_final_return)')
    parent=once(parent,'.out_addr_o(adapter_req_addr), .out_data_o(adapter_req_data)',
        '.out_addr_o(adapter_req_addr), .out_data_o(adapter_req_data),\n        .f_observe_state_o(f_observe_queue)')
    parent=once(parent,'.calib_done_o(calib_done), .calib_error_o(calib_error),',
        '.calib_done_o(calib_done), .calib_error_o(calib_error),\n        .f_observe_read_owned_o(f_observe_adapter_owned),')
    parent=once(parent,'\nendmodule','\n'+parent_monitor+'\nendmodule')
    return {n:b'`undef FORMAL\n'+s.encode()for n,s in [('boot.sv',boot),('fifo.sv',fifo),('boundary.sv',parent),('adapter.sv',adapter)]}


def main():
    common,engine=load('run_handoff'),load('engine')
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--timeout',type=int,default=90)
    parser.add_argument('--mutant',choices=tuple(MUTATIONS))
    args=parser.parse_args();joins={};original=None
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        _,root,bound=common.binding(args.package,variant)
        files={local:(root/path).read_bytes()for local,path in SOURCES.items()}
        if original is not None and original!=files:raise ValueError('Boot boundary composition differs: '+variant)
        original=files;joins[variant]=bound
    boot_monitor=(HERE/'boot-order-monitor.inc.sv').read_text()
    parent_monitor=(HERE/'boot-boundary-monitor.inc.sv').read_text()
    elaborated_original=dict(original)
    if args.mutant:
        member,before,after=MUTATIONS[args.mutant]
        elaborated_original[member]=once(elaborated_original[member].decode(),before,after).encode()
    files=instrument(elaborated_original,boot_monitor,parent_monitor)
    files.update({'production-'+n:r for n,r in original.items()})
    files.update({'boot-monitor.inc.sv':boot_monitor.encode(),'parent-monitor.inc.sv':parent_monitor.encode(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),
        'SOURCES.json':(HERE/'SOURCES.json').read_bytes()})
    binding=dict(native_joins=joins,production_sources={n:dict(path=SOURCES[n],sha256=common.sha(raw))for n,raw in original.items()},
        model_words=227062,address_width=19,request_fifo_depth=2,request_fifo_data_width=256,
        readonly_observer_exports={'boot.sv':{'f_observe_reads_o':19,'f_observe_final_return_o':1},
            'fifo.sv':{'f_observe_state_o':44},'adapter.sv':{'f_observe_read_owned_o':1}},
        internal_rtl_cuts=[],sha_engine_assumed_correct=False)
    scope=('Actual native boot controller, FIFO2 and DDR adapter, including all 227062 words and full '
        '256-bit data arrays. All original boundary inputs arbitrary, no protocol assumptions or internal '
        'cuts. Read-only observer ports expose boot-read count and actual queued descriptors; none feeds '
        'production. Model writes form a prefix before the first boundary output read, and no queued '
        'model write remains at LOCK; LOCK also requires an earlier actual boundary output read. '
        'No outer watchdog/SHA, asynchronous transport, vendor DDR, physical '
        'timing or whole-machine theorem. Only early boot writes are covered; complete LOCK reachability '
        'is not searched at the full native model length.')
    raise SystemExit(engine.check(args.run,files,top=TOP,
        reset_constraints='initial\nassume (= [app_reset_n_i] false)\nstate 1\nassume (= [app_reset_n_i] false)\n',
        assertions=boot_monitor.count('assert(')+parent_monitor.count('assert('),
        covers=2,binding=binding,scope=scope,cuts=[],depth=12,induction_depth=8,cover_depth=18,
        timeout=args.timeout,expected_memories=0,
        expected_register_memories={
            'u_request_fifo.write_q':{'width':1,'size':2},
            'u_request_fifo.addr_q':{'width':19,'size':2},
            'u_request_fifo.data_q':{'width':256,'size':2}},
        source_list=['boot.sv','fifo.sv','adapter.sv','boundary.sv'],
        solver_cli={'cvc5':['--unroll']},mutant=args.mutant))


if __name__=='__main__':main()
