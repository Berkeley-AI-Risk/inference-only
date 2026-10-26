"""Joint proof of real memory parent, runtime adapter and boot handoff.

Only the boot authenticator's outgoing signals are replaced by arbitrary input
ports. No boot-lock authenticity is assumed or claimed. Runtime request/response
ports are also arbitrary. Every production runtime gate remains in this model.
"""
import argparse
import importlib.util
from pathlib import Path
import re

HERE = Path(__file__).resolve().parent


def load(name):
    spec = importlib.util.spec_from_file_location('_assurance_'+name,HERE/(name+'.py'))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main():
    common,engine = load('run_handoff'),load('engine')
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--variant',choices=('baseline','kv-protected','encrypted-memory','seeded-sampling'),required=True)
    parser.add_argument('--run',type=Path,required=True)
    parser.add_argument('--mutant',choices=('bypass-handoff-output','bypass-handoff-output-and-data'))
    args = parser.parse_args()
    pin,root,bound = common.binding(args.package.resolve(),args.variant)
    parent_raw = (root/'project/booted_memory.sv').read_bytes()
    handoff_raw = (root/'project/handoff.sv').read_bytes()
    adapter_raw = (root/'project/adapter.sv').read_bytes()
    parent,handoff = parent_raw.decode(),handoff_raw.decode()
    start = parent.index('    board1_context2048_ddr_locked_auth_watchdog_cdc_quarantined_payload u_boot (')
    end = parent.index(');',start)+2
    instance = parent[start:end]
    bindings = dict(re.findall(r'\.(\w+)\(([^()]*)\)',instance))
    outputs = {'private_loader_ready_o':1,'app_cmd_o':3,'app_cmd_en_o':1,'app_addr_o':29,
        'app_wr_data_o':256,'app_wr_data_en_o':1,'app_wr_data_end_o':1,'app_wr_data_mask_o':32,
        'app_burst_o':1,'app_self_refresh_req_o':1,'app_refresh_req_o':1,
        'model_locked_o':1,'fail_closed_o':1,'watchdog_fault_o':1}
    declarations,assigns,cuts = [],[],[]
    for port,width in outputs.items():
        net = bindings[port]
        if not net or not re.fullmatch(r'\w+',net):
            raise ValueError('Unexpected boot output connection: '+port)
        formal_port = 'f_boot_cut_'+port
        declarations.append(f'    input wire [{width-1}:0] {formal_port}')
        assigns.append(f'    assign {net} = {formal_port};')
        cuts.append(dict(instance='u_boot',output=port,width=width,connected_net=net,
                         replacement='unrestricted module input '+formal_port))
    parent = parent[:start]+'\n'.join(assigns)+parent[end:]
    header = parent.index('\n);')
    parent = parent[:header]+',\n'+',\n'.join(declarations)+parent[header:]
    # Read-only child observation; no production feedback or handshake cut.
    port = '    output logic fault_o\n'
    if handoff.count(port) != 1:
        raise ValueError('Handoff observation port boundary changed')
    handoff = handoff.replace(port,'    output logic fault_o,\n    output wire f_runtime_phase_o\n')
    child_monitor = (HERE/'handoff-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    handoff = '`undef FORMAL\n'+handoff.replace('\nendmodule',
        '\n    assign f_runtime_phase_o = runtime_q;\n'+child_monitor+'\nendmodule')
    connection = '.runtime_locked_o(handoff_locked),.fault_o(handoff_fault));'
    if parent.count(connection) != 1:
        raise ValueError('Handoff instance connection changed')
    parent = parent.replace(connection,
        '.runtime_locked_o(handoff_locked),.fault_o(handoff_fault),.f_runtime_phase_o(f_runtime_phase));')
    parent = parent.replace('    logic fault_q;','    logic fault_q;\n    wire f_runtime_phase;')
    if args.mutant:
        site = '.app_cmd_o(app_cmd_o),.app_cmd_en_o(app_cmd_en_o),.app_addr_o(app_addr_o)'
        if parent.count(site) != 1:
            raise ValueError('Output-bypass mutation site changed')
        parent = parent.replace(site,'.app_cmd_o(app_cmd_o),.app_cmd_en_o(f_unused_checked_command),.app_addr_o(app_addr_o)')
        parent = parent.replace('    logic fault_q;',
            '    logic fault_q;\n    wire f_unused_checked_command;\n    assign app_cmd_en_o = runtime_cmd_en;')
        if args.mutant == 'bypass-handoff-output-and-data':
            site = '.app_data_en_o(app_wr_data_en_o),.app_data_end_o(app_wr_data_end_o)'
            if parent.count(site) != 1:
                raise ValueError('Data-output bypass site changed')
            parent = parent.replace(site,
                '.app_data_en_o(f_unused_checked_data),.app_data_end_o(f_unused_checked_end)')
            parent = parent.replace('    logic fault_q;',
                '    logic fault_q;\n    wire f_unused_checked_data,f_unused_checked_end;\n'
                '    assign app_wr_data_en_o = runtime_data_en;\n'
                '    assign app_wr_data_end_o = runtime_data_end;')
    parent_monitor = (HERE/'memory-monitor.inc.sv').read_text().replace('__KV_LIMIT__',str(pin['kv_limit']))
    parent = '`undef FORMAL\n'+parent.replace('\nendmodule','\n'+parent_monitor+'\nendmodule')
    adapter = b'`undef FORMAL\n'+adapter_raw
    top = re.search(r'\bmodule (\w+) \(',parent).group(1)
    files = {'memory.sv':parent.encode(),'handoff.sv':handoff.encode(),'adapter.sv':adapter,
        'production-memory.sv':parent_raw,'production-handoff.sv':handoff_raw,'production-adapter.sv':adapter_raw,
        'child-monitor.inc.sv':child_monitor.encode(),'parent-monitor.inc.sv':parent_monitor.encode(),
        'runner.py':Path(__file__).read_bytes(),'binding_helper.py':(HERE/'run_handoff.py').read_bytes(),
        'SOURCES.json':(HERE/'SOURCES.json').read_bytes()}
    assertions = child_monitor.count('assert(')+parent_monitor.count('assert(')
    covers = child_monitor.count('cover(')+parent_monitor.count('cover(')
    if assertions != 30 or covers != 6:
        raise ValueError('Reviewed property inventory changed')
    constraints = ('initial\nassume (= [trusted_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n'
        'state 1\nassume (= [trusted_reset_n_i] false)\nassume (= [app_reset_n_i] false)\n')
    return engine.check(args.run,files,top=top,reset_constraints=constraints,assertions=assertions,covers=covers,
        binding=dict(variant=args.variant,**bound),cuts=cuts,depth=14,mutant=args.mutant,
        scope='Actual booted-memory parent + production ADDR_W19/32-read runtime adapter + handoff, with read-only monitors. Boot authenticator outputs arbitrary. Model write exclusion and one-way runtime/fault enforcement at semantic DDR application outputs. No authenticated-boot, physical transport, cryptographic or whole-machine numerical theorem.')


if __name__ == '__main__':
    raise SystemExit(main())
