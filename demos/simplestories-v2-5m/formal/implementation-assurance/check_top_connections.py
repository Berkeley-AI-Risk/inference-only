"""Elaborate the actual native top and check its enforcement connections.

Child headers come from the current native inventory and are blackboxed. This
is a structural wiring check, not a proof of the blackboxed implementations.
"""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import subprocess

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('_binding',HERE/'run_handoff.py')
common = importlib.util.module_from_spec(spec)
spec.loader.exec_module(common)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


CHILDREN = {
    'u_board_reset':'private_ddr_probe_reset',
    'u_raw_controller':'board1_gowin_ddr3_raw_controller_shell',
    'u_fixed_qspi_boot':'board1_context2048_qspi_image_stream',
    'u_uart_core':'board1_private_shared_uart_core',
    'u_core_fault_cdc':'board1_fixed_endpoint_fault_cdc',
    'u_transport':'board1_thin_ddr_app_transport',
}


def connections(top):
    cells = top['cells']
    checks = []
    inputs = {name for name,p in top['ports'].items() if p['direction'] == 'input'}
    inouts = {name for name,p in top['ports'].items() if p['direction'] == 'inout'}
    if inputs != {'clk_50mhz','reset_button','uart_rx'} or inouts != {'flash_dq','ddr_dq','ddr_dqs','ddr_dqs_n'}:
        raise ValueError('Unexpected external control/data input port')
    def signal(cell,port):
        return cells[cell]['connections'][port]
    def same(a,b):
        if signal(*a) != signal(*b):
            raise ValueError('Enforcement connection mismatch: '+'.'.join(a)+' -> '+'.'.join(b))
        checks.append(dict(a='.'.join(a),b='.'.join(b),width=len(signal(*a))))
    # Private UART requests and replies must cross the memory enforcement parent.
    for source,target in {
        'private_endpoint_req_valid_o':'private_req_valid_i',
        'private_endpoint_req_write_o':'private_req_write_i',
        'private_endpoint_req_word_address_o':'private_req_word_i',
        'private_endpoint_req_write_data_o':'private_req_data_i',
        'private_endpoint_req_ready_i':'private_req_ready_o',
        'private_endpoint_rsp_valid_i':'private_rsp_valid_o',
        'private_endpoint_rsp_error_i':'private_rsp_error_o',
        'private_endpoint_rsp_data_i':'private_rsp_data_o',
        'private_model_locked_i':'private_model_locked_o',
        'private_endpoint_upstream_fault_i':'private_fail_closed_o',
    }.items():
        same(('u_uart_core',source),('u_memory',target))
    # The actual memory policy outputs feed the physical transport's admission.
    for source,target in {
        'app_cmd_o':'core_cmd_i','app_cmd_en_o':'core_cmd_en_i','app_addr_o':'core_addr_i',
        'app_wr_data_o':'core_wr_data_i','app_wr_data_en_o':'core_wr_en_i',
        'app_wr_data_end_o':'core_wr_end_i','app_wr_data_mask_o':'core_wr_mask_i',
        'app_cmd_ready_i':'core_cmd_ready_o','app_wr_data_ready_i':'core_wr_ready_o',
        'app_rd_data_i':'core_rd_data_o','app_rd_data_valid_i':'core_rd_valid_o',
        'app_rd_data_end_i':'core_rd_end_o','app_burst_o':'core_burst_i',
        'app_self_refresh_req_o':'core_self_refresh_i','app_refresh_req_o':'core_refresh_i',
    }.items():
        same(('u_memory',source),('u_transport',target))
    # No policy output bypasses the transport on its way to the vendor shell.
    for source,target in {
        'app_cmd_o':'app_cmd_i','app_cmd_en_o':'app_cmd_en_i','app_addr_o':'app_addr_i',
        'app_wr_data_o':'app_wr_data_i','app_wr_en_o':'app_wr_data_en_i',
        'app_wr_end_o':'app_wr_data_end_i','app_wr_mask_o':'app_wr_data_mask_i',
        'app_cmd_ready_i':'app_cmd_ready_o','app_wr_ready_i':'app_wr_data_ready_o',
        'app_rd_data_i':'app_rd_data_o','app_rd_valid_i':'app_rd_data_valid_o',
        'app_rd_end_i':'app_rd_data_end_o','app_burst_o':'app_burst_i',
        'app_self_refresh_o':'app_self_refresh_req_i','app_refresh_o':'app_refresh_req_i',
        'controller_pll_lock_i':'controller_pll_lock_o','controller_calibrated_i':'controller_init_calib_complete_o',
    }.items():
        same(('u_transport',source),('u_raw_controller',target))
    for source,target in {
        'fixed_source_ready_o':'private_fixed_source_ready_i','boot_progress_o':'private_boot_progress_i',
        'loader_data_o':'private_loader_data_i','loader_valid_o':'private_loader_valid_i',
        'loader_ready_i':'private_loader_ready_o','loader_done_o':'private_loader_done_i',
    }.items():
        same(('u_fixed_qspi_boot',source),('u_memory',target))
    same(('u_uart_core','private_fail_closed_o'),('u_core_fault_cdc','core_fail_closed_i'))
    same(('u_core_fault_cdc','app_fail_closed_o'),('u_memory','private_runtime_app_fault_i'))
    # Clock and reset identities are checked separately from child behavior.
    for target in [('u_memory','app_clk_i'),('u_uart_core','app_clk_i'),('u_transport','core_clk_i'),
                   ('u_core_fault_cdc','app_clk_i'),('u_fixed_qspi_boot','app_clk_i')]:
        same(('u_uart_core','core_clk_i'),target)
    same(('u_transport','app_clk_i'),('u_raw_controller','app_clk_100mhz_o'))
    for target in [('u_memory','app_reset_n_i'),('u_transport','core_reset_n_i'),
                   ('u_core_fault_cdc','app_reset_n_i'),('u_fixed_qspi_boot','app_reset_n_i')]:
        same(('u_uart_core','reset_n_i'),target)
    same(('u_memory','trusted_clk_i'),('u_fixed_qspi_boot','trusted_clk_i'))
    same(('u_memory','trusted_reset_n_i'),('u_fixed_qspi_boot','trusted_reset_n_i'))
    same(('u_transport','app_reset_n_i'),('u_raw_controller','app_reset_n_o'))
    if signal('u_uart_core','uart_rx_i') != top['ports']['uart_rx']['bits']:
        raise ValueError('External UART RX bypassed the real UART core')
    if signal('u_uart_core','uart_tx_o') != top['ports']['uart_tx']['bits']:
        raise ValueError('External UART TX bypassed the real UART core')
    return checks


def header(source,name):
    match = re.search(r'^module\s+'+re.escape(name)+r'\b',source,re.M)
    if not match:
        return None
    # The pinned ANSI headers have no embedded semicolons or macros.
    end = source.index(';',match.start())+1
    return source[match.start():end]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,default=common.DEFAULT_PACKAGE)
    parser.add_argument('--out',type=Path,required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True,exist_ok=False)
    results = {}
    for variant in ('baseline','kv-protected','encrypted-memory','seeded-sampling'):
        pin,root,bound = common.binding(args.package.resolve(),variant)
        inventory = json.loads(common.safe(common.model_package(args.package),pin['native_inventory']).read_text())
        native = {name:common.safe(root,name).read_text() for name in inventory
            if name not in pin['omitted_vendor_inputs'] and name.endswith(('.sv','.v'))}
        names = dict(CHILDREN,u_memory='tang_confidential_booted_shared_ddr' if variant == 'encrypted-memory' else 'board1_private_booted_shared_ddr')
        stubs,headers = [],{}
        for instance,module in names.items():
            matches = [(name,header(raw,module)) for name,raw in native.items() if header(raw,module)]
            if len(matches) != 1:
                raise ValueError('Ambiguous native child header: '+module)
            name,text = matches[0]
            stubs.append('(* blackbox *)\n'+text+'\nendmodule\n')
            headers[instance] = dict(module=module,native_path=name,source_sha256=sha((root/name).read_bytes()),header_sha256=sha(text.encode()))
        work = args.out/variant
        work.mkdir()
        (work/'top.sv').write_bytes((root/'project/top.sv').read_bytes())
        (work/'stubs.sv').write_text('\n'.join(stubs))
        (work/'elaborate.ys').write_text('read_verilog -sv -D SYNTHESIS -defer top.sv stubs.sv\nhierarchy -check -top board1_fixed_shared_product_top\nproc\nopt_clean\ncheck -assert\nwrite_json top.json\n')
        with (work/'yosys.log').open('w') as out:
            cp = subprocess.run(['yosys','-Q','elaborate.ys'],cwd=work,stdout=out,stderr=subprocess.STDOUT,timeout=30)
        if cp.returncode:
            raise ValueError('Top elaboration failed: '+variant)
        elaborated = json.loads((work/'top.json').read_text())
        top = elaborated['modules']['board1_fixed_shared_product_top']
        for instance,module in names.items():
            if top['cells'][instance]['type'] != module:
                raise ValueError('Actual top-level child instance changed')
        checked = connections(top)
        # Deliberate, width-preserving bypasses must fail the same connection audit.
        mutants = []
        for instance,port in [('u_memory','private_req_word_i'),('u_transport','core_cmd_en_i'),('u_memory','app_reset_n_i')]:
            changed = json.loads(json.dumps(top))
            original = changed['cells'][instance]['connections'][port]
            changed['cells'][instance]['connections'][port] = ['0']*len(original)
            try:
                connections(changed)
            except ValueError as error:
                mutants.append(dict(instance=instance,port=port,rejected=True,reason=str(error)))
            else:
                raise ValueError('Connection bypass was not detected')
        results[variant] = dict(passed=True,binding=bound,blackboxed_children=headers,
            native_top_sha256=sha((root/'project/top.sv').read_bytes()),checks=checked,
            negative_controls=mutants,elaborated_sha256=sha((work/'top.json').read_bytes()),
            yosys_log_sha256=sha((work/'yosys.log').read_bytes()))
        print(variant,'PASS',len(checked),'connections',flush=True)
    (args.out/'checker.py').write_bytes(Path(__file__).read_bytes())
    record = dict(schema='current-native-top-enforcement-connections-v1',passed=True,variants=results,
        child_behavior_proved=False,physical_transport_payload_proved=False,
        source_to_bitstream_equivalence=False,whole_machine_theorem=False,
        checker_sha256=sha(Path(__file__).read_bytes()))
    (args.out/'FINISHED.json').write_text(json.dumps(record,indent=2,sort_keys=True)+'\n')


if __name__ == '__main__':
    main()
