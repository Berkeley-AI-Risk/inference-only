#!/usr/bin/env python3
"""Bind the shared-crypto simulation results to the native build's inputs.

This checks source identity, not equivalence of the simulated PHY with hardware,
physical entropy quality, successful placement/routing, or timing closure.
"""
import argparse
import datetime
import hashlib
import json
import re
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
import clock_variant
import shared_selector
import permit_register
import shared_boot_compressor
import publication_guard
import registered_nonce
import compact_norm
import registered_collision
import sha_data_reset
import verifier_reset_arm
import startup_reset_phase
import startup_reset_qualifier
import qspi_reset_guard
import startup_min_delay
import qspi_phase_reset
import permit_fanout
import qspi_core_buffers

ROOT = Path(__file__).resolve().parents[1]


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--simulation', type=Path, required=True)
    p.add_argument('--native', type=Path, required=True)
    p.add_argument('--output', type=Path, required=True)
    args = p.parse_args()
    assert not args.output.exists(), 'Preserve existing evidence'
    receipt = args.simulation / 'BUILD.json'
    sim = json.loads(receipt.read_text())
    assert sim['result'] == 'PASS'
    source = sim['source_sha256']
    simroot = Path(sim['build_directory'])
    native = Path(json.loads((args.native / 'STARTED.json').read_text())['directory'])
    inputs = json.loads((args.native / 'INPUTS.json').read_text())
    options = json.loads((args.native / 'PROVENANCE.json').read_text())['options']
    assert not options.get('core_only_report',False),'Diagnostic core-only timing reports cannot qualify a board build'
    divider=options.get('core_divider',2)
    assert divider==sim.get('configuration',{}).get('core_divider',2),'Simulator/native core clocks differ'
    assert options.get('shared_message_selector',False)==sim.get('configuration',{}).get('shared_message_selector',False),'Simulator/native message selector differs'
    assert options.get('registered_permit',False)==sim.get('configuration',{}).get('registered_permit',False),'Simulator/native permission reset differs'
    assert options.get('shared_boot_compressor',False)==sim.get('configuration',{}).get('shared_boot_compressor',False),'Simulator/native boot compressor sharing differs'
    assert options.get('direct_publication_guard',False)==sim.get('configuration',{}).get('direct_publication_guard',False),'Simulator/native publication guard differs'
    assert options.get('registered_nonce_data',False)==sim.get('configuration',{}).get('registered_nonce_data',False),'Simulator/native private nonce connection differs'
    assert options.get('compact_norm_loader',False)==sim.get('configuration',{}).get('compact_norm_loader',False),'Simulator/native normalization loader differs'
    assert options.get('narrow_norm_carry',False)==sim.get('configuration',{}).get('narrow_norm_carry',False),'Simulator/native carry merge differs'
    assert options.get('registered_metadata_collision',False)==sim.get('configuration',{}).get('registered_metadata_collision',False),'Simulator/native metadata collision latch differs'
    assert options.get('resetless_sha_data',False)==sim.get('configuration',{}).get('resetless_sha_data',False),'Simulator/native SHA private data reset differs'
    assert options.get('registered_verifier_reset',False)==sim.get('configuration',{}).get('registered_verifier_reset',False),'Simulator/native verifier reset differs'
    assert options.get('falling_edge_startup_reset',False)==sim.get('configuration',{}).get('falling_edge_startup_reset',False),'Simulator/native startup reset edge differs'
    assert options.get('phase_qualified_startup_reset',False)==sim.get('configuration',{}).get('phase_qualified_startup_reset',False),'Simulator/native startup reset qualifier differs'
    assert options.get('qualified_qspi_reset',False)==sim.get('configuration',{}).get('qualified_qspi_reset',False),'Simulator/native QSPI reset guard differs'
    assert options.get('phase_qualified_qspi_reset',False)==sim.get('configuration',{}).get('phase_qualified_qspi_reset',False),'Simulator/native QSPI phase reset differs'
    assert options.get('permit_reset_maxfan',0)==sim.get('configuration',{}).get('permit_reset_maxfan',0),'Simulator/native permission fanout hints differ'
    assert options.get('qspi_core_reset_buffers',0)==sim.get('configuration',{}).get('qspi_core_reset_buffers',0),'Simulator/native QSPI reset buffers differ'
    clock_cfg=clock_variant.config(divider)
    if options.get('share_core_clock',False):
        assert divider==4
        phy=(simroot/'phy_model.sv').read_text()
        assert 'reg core_clk=0,trusted_clk=0,app_clk=0;' in phy
        assert 'always #40 core_clk=~core_clk;' in phy
        assert 'always #40 trusted_clk=~trusted_clk;' in phy
    assert options['shared_nonce_hash'] is True
    testbench=(simroot/'tb_home_tang.sv').read_text()
    assert ".SHARE_NONCE_HASH(1'b1)" in testbench
    assert options.get('shared_lms_hash',False) == (".SHARE_LMS_HASH(1'b1)" in testbench), 'Simulator/native SHA sharing modes differ'
    assert len(set(options['local_entropy_controls'])) == 21

    checks = []
    for scenario in range(4):
        result_path = args.simulation / f'scenario-{scenario}/RESULT.json'
        result = json.loads(result_path.read_text())
        assert result['result'] == 'PASS' and result['exit_code'] == 0
        assert result['scenario'] == scenario
        assert result['build_receipt_sha256'] == digest(receipt)
        log = result_path.parent / 'run.log'
        assert result['log_sha256'] == digest(log)
        checks.append({'scenario': scenario, 'result_file': str(result_path),
                       'sha256': digest(result_path)})

    # Include all recorded project inputs and the testbench/conditioner, not
    # helper scripts or documentation modified after the simulation completed.
    bound = {}
    for name, sha in source.items():
        if not (name.startswith('integration/project/') or
                name.startswith('integration/tests/') or
                name == 'nonce/nonce_frontend.sv'):
            continue
        assert digest(ROOT / name) == sha, name
        bound[name] = sha
        if name.startswith('integration/project/'):
            rel=name[len('integration/project/'):]
            expected=(ROOT/name).read_bytes()
            if rel in clock_variant.PROJECT_FILES:
                expected=clock_variant.project_text(rel,expected.decode(),divider).encode()
            if options.get('falling_edge_startup_reset',False):
                expected=startup_reset_phase.transform(rel,expected.decode()).encode()
            if options.get('phase_qualified_startup_reset',False):
                expected=startup_reset_qualifier.transform(rel,expected.decode()).encode()
            if options.get('qualified_qspi_reset',False):
                expected=qspi_reset_guard.transform(rel,expected.decode()).encode()
            if options.get('phase_qualified_qspi_reset',False):
                expected=qspi_phase_reset.transform(rel,expected.decode()).encode()
            if options.get('qspi_core_reset_buffers',0):
                expected=qspi_core_buffers.transform(rel,expected.decode(),options['qspi_core_reset_buffers']).encode()
            if options.get('shared_message_selector',False):
                expected=shared_selector.transform(rel,expected.decode()).encode()
            if options.get('registered_permit',False):
                expected=permit_register.transform(rel,expected.decode()).encode()
            if options.get('permit_reset_maxfan',0):
                expected=permit_fanout.transform(rel,expected.decode(),options['permit_reset_maxfan']).encode()
            if options.get('shared_boot_compressor',False):
                expected=shared_boot_compressor.transform(rel,expected.decode()).encode()
            if options.get('direct_publication_guard',False):
                expected=publication_guard.transform(rel,expected.decode()).encode()
            if options.get('compact_norm_loader',False):
                expected=compact_norm.transform(rel,expected.decode(),options.get('narrow_norm_carry',False)).encode()
            if options.get('registered_metadata_collision',False):
                expected=registered_collision.transform(rel,expected.decode()).encode()
            if options.get('resetless_sha_data',False):
                expected=sha_data_reset.transform(rel,expected.decode()).encode()
            if options.get('registered_verifier_reset',False):
                expected=verifier_reset_arm.transform(rel,expected.decode()).encode()
            assert (simroot / name[len('integration/'):]).read_bytes()==expected,name
    expected_nonce=(ROOT/'nonce/nonce_frontend.sv').read_text()
    if options.get('registered_nonce_data',False):expected_nonce=registered_nonce.frontend(expected_nonce)
    assert (simroot/'nonce_frontend.sv').read_text()==expected_nonce
    expected_tb=clock_variant.testbench_text((ROOT/'integration/tests/tb_home_tang.sv').read_text(),divider)
    if options.get('registered_permit',False):expected_tb=permit_register.testbench_text(expected_tb)
    if options.get('registered_nonce_data',False):expected_tb=registered_nonce.testbench(expected_tb)
    assert (simroot/'tb_home_tang.sv').read_text()==expected_tb
    assert (simroot/'phy_model.sv').read_text()==clock_variant.phy_text((ROOT/'integration/tests/phy_model.sv').read_text(),divider)
    for name,sha in sim.get('compiled_snapshot_sha256',{}).items():
        assert digest(simroot/name)==sha,name
    if 'simulator_sha256' in sim:
        assert digest(Path(sim['binary']))==sim['simulator_sha256']
    for name, sha in inputs.items():
        assert digest(native / name) == sha, name

    # The native builder exports the existing core clock/reset only to the
    # private wrapper, prefixes constraint paths, and adds physical-source files.
    project = ROOT / 'integration/project'
    changed = set()
    for path in project.rglob('*'):
        if not path.is_file():continue
        rel=str(path.relative_to(project));expected=path.read_bytes()
        if rel in clock_variant.PROJECT_FILES:
            expected=clock_variant.project_text(rel,expected.decode(),divider).encode()
        if options.get('falling_edge_startup_reset',False):
            expected=startup_reset_phase.transform(rel,expected.decode()).encode()
        if options.get('phase_qualified_startup_reset',False):
            expected=startup_reset_qualifier.transform(rel,expected.decode()).encode()
        if options.get('qualified_qspi_reset',False):
            expected=qspi_reset_guard.transform(rel,expected.decode()).encode()
        if options.get('phase_qualified_qspi_reset',False):
            expected=qspi_phase_reset.transform(rel,expected.decode()).encode()
        if options.get('qspi_core_reset_buffers',0):
            expected=qspi_core_buffers.transform(rel,expected.decode(),options['qspi_core_reset_buffers']).encode()
        if options.get('shared_message_selector',False):
            expected=shared_selector.transform(rel,expected.decode()).encode()
        if options.get('shared_boot_compressor',False):
            expected=shared_boot_compressor.transform(rel,expected.decode()).encode()
        if options.get('direct_publication_guard',False):
            expected=publication_guard.transform(rel,expected.decode()).encode()
        if options.get('compact_norm_loader',False):
            expected=compact_norm.transform(rel,expected.decode(),options.get('narrow_norm_carry',False)).encode()
        if options.get('registered_metadata_collision',False):
            expected=registered_collision.transform(rel,expected.decode()).encode()
        if options.get('resetless_sha_data',False):
            expected=sha_data_reset.transform(rel,expected.decode()).encode()
        if options.get('registered_verifier_reset',False):
            expected=verifier_reset_arm.transform(rel,expected.decode()).encode()
        if options.get('share_core_clock',False):
            assert divider==4
            expected=clock_variant.shared_clock_text(rel,expected.decode()).encode()
        if rel==clock_variant.CONTROLLER and options.get('plain_core_divider',False):
            assert divider==4
            expected=expected.replace(b'(* syn_preserve=1 *) CLKDIV u_core_clkdiv (',b'CLKDIV u_core_clkdiv (')
        if expected!=(native/'project'/rel).read_bytes():changed.add(rel)
    assert changed == {'product.gprj', 'top.sv', 'constraints/board1_fixed_product.cst', 'constraints/product.sdc'}, changed
    top = clock_variant.project_text('top.sv',(project/'top.sv').read_text(),divider)
    if options.get('falling_edge_startup_reset',False):top=startup_reset_phase.transform('top.sv',top)
    if options.get('phase_qualified_startup_reset',False):top=startup_reset_qualifier.transform('top.sv',top)
    if options.get('qualified_qspi_reset',False):top=qspi_reset_guard.transform('top.sv',top)
    if options.get('direct_publication_guard',False):
        top=publication_guard.transform('top.sv',top)
    if options.get('registered_metadata_collision',False):
        top=registered_collision.transform('top.sv',top)
    maxfan=options.get('home_mode_maxfan',0)
    if maxfan:
        assert 0<maxfan<=128
        top=top.replace('logic home_mode_q,home_stop_q;',
            f'logic home_mode_q /* synthesis syn_maxfan = {maxfan} */;\n    logic home_stop_q;')
    if options.get('primary_token_reset',False):
        top=top.replace('wire token_reset_n=core_reset_n && home_enabled && !home_stop_q;',
            'wire token_reset_asserted /* synthesis syn_keep = 1 */=!(core_reset_n && home_enabled && !home_stop_q);\n    wire token_reset_n=~token_reset_asserted;')
    if options.get('registered_permit',False):
        top=permit_register.transform('top.sv',top)
    if options.get('permit_reset_maxfan',0):
        top=permit_fanout.transform('top.sv',top,options['permit_reset_maxfan'])
    top = top.replace('output wire private_nonce_request_o,',
                      'output wire private_nonce_request_o,\n    output wire private_core_clk_o,private_core_reset_n_o,')
    top = top.replace('endmodule', 'assign private_core_clk_o=core_clk;\n    assign private_core_reset_n_o=core_reset_n;\nendmodule')
    assert top == (native / 'project/top.sv').read_text()
    for name in ['board1_fixed_product.cst', 'product.sdc']:
        expected = clock_variant.project_text('constraints/'+name,(project/'constraints'/name).read_text(),divider).replace('u_raw_controller/', 'u_core/u_raw_controller/')
        if options.get('share_core_clock',False):
            expected=clock_variant.shared_clock_text('constraints/'+name,expected)
        if name.endswith('.cst'):
            expected += '\n' + (ROOT / 'nonce/entropy-controls.cst').read_text()
            extra_controls=options.get('local_control_nets',[])
            assert extra_controls in ([],['u_core/home_mode_q'])
            if extra_controls:
                expected += '\n// UART owner control is data, not a sampling clock.\nCLOCK_LOC "u_core/home_mode_q" LOCAL_CLOCK;\n'
            if options.get('primary_token_reset',False):
                expected += '\n// Active-high inference reset uses primary reset-pin routing.\nCLOCK_LOC "u_core/token_reset_asserted" BUFG = SR;\n'
            for control in options.get('additional_local_control_nets',[]):
                assert re.fullmatch(r'[A-Za-z0-9_./\[\]]+',control)
                expected += f'\n// Ordinary routing for a selected control net.\nCLOCK_LOC "{control}" LOCAL_CLOCK;\n'
        if name=='product.sdc'and options.get('startup_min_delay_ns',0):
            assert not options.get('phase_qualified_startup_reset',False)and not options.get('falling_edge_startup_reset',False)
            expected+=startup_min_delay.constraints(options['startup_min_delay_ns'])
        assert expected == (native / 'project/constraints' / name).read_text(), name
    for source_name in ['nonce_frontend.sv', 'entropy_source.vhd']:
        if source_name=='nonce_frontend.sv':assert (native/'project/home'/source_name).read_text()==expected_nonce
        else:assert digest(ROOT / 'nonce' / source_name) == digest(native / 'project/home' / source_name)
    assert digest(ROOT / 'nonce/vendor/neoTRNG.vhd') == digest(native / 'project/home/neoTRNG.vhd')
    wrapper = (native / 'project/home/home_product_top.sv').read_text()
    assert ".USE_SHARED_HASH(1'b1)" in wrapper
    assert ".SHARE_NONCE_HASH(1'b1)" in wrapper
    assert ('.private_nonce_i(registered_nonce)' if options.get('registered_nonce_data',False) else '.private_nonce_i(nonce)') in wrapper
    if options.get('shared_lms_hash', False):
        assert ".SHARE_LMS_HASH(1'b1)" in wrapper
        assert '.USE_SHARED_HASH(SHARE_LMS_HASH)' in (native / 'project/swic/swic_boot_admission.sv').read_text()
    assert '.request_i(nonce_request && (!1\'b1 || model_ready))' in wrapper
    for key,seconds in [('HOME_RESPONSE_CYCLES',4),('HOME_LEASE_CYCLES',10),('HOME_RENEW_CYCLES',5)]:
        assert f'.{key}({seconds*clock_cfg["core_hz"]})' in wrapper,key
    if divider==4:
        assert '.TIMEOUT_CYCLES(12500000)' in wrapper
    assert 'SIM_MODE=>false' in (native / 'project/home/entropy_source.vhd').read_text()

    record = {'result': 'PASS',
              'scope': 'Four full RTL scenarios using shared LMS verification and shared boot-root SHA nonce conditioning; deterministic raw input and modeled external PHY/flash.',
              'checked_utc': datetime.datetime.now(datetime.timezone.utc).isoformat(),
              'simulation_build_sha256': digest(receipt), 'checks': checks,
              'compiled_source_hashes': bound,
              'native_inputs_sha256': digest(args.native / 'INPUTS.json'),
              'native_input_files_unchanged': len(inputs),
              'native_transform_checked': sorted(changed),
              'logic_preserving_attributes': {'home_mode_maxfan': maxfan,'plain_core_divider':options.get('plain_core_divider',False),'permit_reset_maxfan':options.get('permit_reset_maxfan',0)},
              'phase_qualified_qspi_reset':options.get('phase_qualified_qspi_reset',False),
              'qspi_core_reset_buffers':options.get('qspi_core_reset_buffers',0),
              'qspi_phase_reset_transformer_sha256':digest(ROOT/'integration/qspi_phase_reset.py'),
              'identical_div4_clocks_shared':options.get('share_core_clock',False),
              'shared_message_selector':options.get('shared_message_selector',False),
              'registered_permit':options.get('registered_permit',False),
              'shared_boot_compressor':options.get('shared_boot_compressor',False),
              'direct_publication_guard':options.get('direct_publication_guard',False),
              'registered_nonce_data':options.get('registered_nonce_data',False),
              'compact_norm_loader':options.get('compact_norm_loader',False),
              'narrow_norm_carry':options.get('narrow_norm_carry',False),
              'registered_metadata_collision':options.get('registered_metadata_collision',False),
              'resetless_sha_data':options.get('resetless_sha_data',False),
              'sha_data_reset_transformer_sha256':digest(ROOT/'integration/sha_data_reset.py'),
              'collision_transformer_sha256':digest(ROOT/'integration/registered_collision.py'),
              'compact_norm_transformer_sha256':digest(ROOT/'integration/compact_norm.py'),
              'registered_nonce_transformer_sha256':digest(ROOT/'integration/registered_nonce.py'),
              'publication_guard_transformer_sha256':digest(ROOT/'integration/publication_guard.py'),
              'boot_compressor_transformer_sha256':digest(ROOT/'integration/shared_boot_compressor.py'),
              'implementation_retiming_requested':options.get('retiming_resource','none'),
              'gate_level_equivalence_checked':False,
              'permit_transformer_sha256':digest(ROOT/'integration/permit_register.py'),
              'message_selector_transformer_sha256':digest(ROOT/'integration/shared_selector.py'),
              'physical_source_simulation_mode': False,
              'shared_lms_hash': options.get('shared_lms_hash', False),
              'clock_configuration':clock_cfg,
              'clock_transformer_sha256':digest(ROOT/'integration/clock_variant.py'),
              'physical_board_qualified': False, 'timing_qualified': False,
              'entropy_qualified': False, 'formal_proof': False}
    args.output.write_text(json.dumps(record, indent=2) + '\n')
    print(json.dumps({k: record[k] for k in ['result', 'native_input_files_unchanged', 'physical_board_qualified']}))


if __name__ == '__main__':
    main()
