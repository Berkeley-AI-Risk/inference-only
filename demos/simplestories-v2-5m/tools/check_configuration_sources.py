#!/usr/bin/env python3
"""Check selected Tang build inputs and source-list scope, without running tools.

This is an offline consistency check. It does not build, prove, program, inspect
a live FPGA, or grant qualification to a modified/rebuilt configuration.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET


CONFIGURATIONS = {
    'baseline': ('hardware', 'host-app/hardware-inputs.json', 'prebuilt/inference'),
    'kv-protected': ('variants/kv-protected/hardware', 'host-app/hardware-inputs-kv-protected.json', 'prebuilt/kv-protected'),
    'encrypted-memory': ('variants/encrypted-memory/hardware', 'host-app/hardware-inputs-encrypted-memory.json', 'prebuilt/encrypted-memory'),
    'seeded-sampling': ('variants/seeded-sampling/hardware', 'host-app/hardware-inputs-seeded-sampling.json', 'prebuilt/seeded-sampling'),
    'signed-update': ('variants/signed-update/tang/hardware', 'variants/signed-update/tang/SOURCE-IDENTITY.json', 'variants/signed-update/tang/prebuilt/swic_product.fs'),
    'home-authorization': ('variants/home-authorization/hardware', 'variants/home-authorization/SOURCE-IDENTITY.json', 'variants/home-authorization/prebuilt/home_product.fs'),
}
HOME_ADDITIONS = {
    'home/home_boot_gate.sv', 'home/home_uart_transport.sv',
    'home/home_product_top.sv', 'home/nonce_frontend.sv',
}
HOME_VHDL = {'home/neoTRNG.vhd', 'home/entropy_source.vhd'}
TYPES = {'file.verilog', 'file.vhdl', 'file.cst', 'file.sdc'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def relative_name(name):
    p = PurePosixPath(name)
    require(bool(name) and not p.is_absolute() and '..' not in p.parts
            and str(p) == name and '\\' not in name, 'Unsafe relative input: ' + name)
    return name


def local_file(root, name):
    path = root / relative_name(name)
    require(not any(p.is_symlink() for p in (path, *path.parents) if p.is_relative_to(root)),
            'Linked input: ' + name)
    require(path.is_file(), 'Missing local input: ' + name)
    return path


def source_lists(project, configuration):
    entries = []
    for element in ET.parse(local_file(project, 'product.gprj')).getroot().iter('File'):
        if element.get('enable', '1') != '1':
            continue
        name = relative_name(element.get('path', ''))
        kind = element.get('type')
        require(kind in TYPES, 'Unrecognized enabled file type: ' + str(kind))
        entries.append((name, kind))
    require(len({name for name, _ in entries}) == len(entries), 'Duplicate enabled project input')
    members = [s.strip() for s in local_file(project, 'production_sources.f').read_text().splitlines()
               if s.strip() and not s.lstrip().startswith('#')]
    for member in members:
        relative_name(member)
        require(not member.startswith('-'), 'Expected plain member paths, not compiler flags')
    require(len(set(members)) == len(members), 'Duplicate source-list member')
    verilog = [name for name, kind in entries if kind == 'file.verilog']
    vhdl = {name for name, kind in entries if kind == 'file.vhdl'}
    extra = set(verilog) - set(members)
    require(not set(members) - set(verilog), 'Source list contains a disabled or absent project file')
    if configuration == 'home-authorization':
        require(extra == HOME_ADDITIONS and vhdl == HOME_VHDL,
                'Unexpected home base-list exception or VHDL selection')
        scope = 'inherited-base-members; incomplete for home physical top'
    else:
        require(not extra and not vhdl, 'Unexpected incomplete source list')
        scope = 'complete-verilog-members'
    order_matches = [name for name in verilog if name in members] == members
    return dict(entries=entries, verilog=verilog, vhdl=sorted(vhdl), members=members,
                project_only_verilog=sorted(extra), source_list_scope=scope,
                common_members_same_order=order_matches)


def check_vendor(directory, dependencies):
    if directory is None:
        return 'not-acquired; four external inputs remain prerequisites'
    directory = Path(directory).resolve(strict=True)
    for name, row in dependencies.items():
        path = local_file(directory, name)
        require(path.stat().st_size == row['bytes'] and sha(path) == row['sha256'],
                'Different external vendor input: ' + name)
    return 'four acquired inputs match recorded sizes and hashes'


def check_configuration(model, configuration, vendor_dir=None):
    model = Path(model).resolve(strict=True)
    hardware_name, inventory_name, image_name = CONFIGURATIONS[configuration]
    hardware = model / hardware_name
    project = hardware / 'project'
    inventory_path = local_file(model, inventory_name)
    identity = json.loads(inventory_path.read_text())
    dependencies = json.loads(local_file(model, 'VENDOR-DEPENDENCIES.json').read_text())['downloads']
    external = {'project/official/' + name: row['sha256'] for name, row in dependencies.items()}
    if 'native_inputs' in identity:
        pins = dict(identity['native_inputs'])
        require(not set(pins).intersection(external), 'External source unexpectedly included in native local inventory')
        pins.update(external)
        image = local_file(model, image_name)
        image_sha = identity['prebuilt_sha256']
    else:
        pins = identity
        build_path = local_file(model, image_name + '/BUILD.json')
        build = json.loads(build_path.read_text())
        canonical = (json.dumps(pins, sort_keys=True, separators=(',', ':')) + '\n').encode()
        require(hashlib.sha256(canonical).hexdigest() == build['hardware_inputs_sha256'],
                'Selected input inventory differs from build receipt')
        require(build['flow_completed'] and build['source_inputs_verified'] and build['source_inputs_unchanged'],
                'Incomplete selected build receipt')
        image = local_file(model, image_name + '/' + relative_name(build['image_relative_path']))
        image_sha = build['image_sha256']
    for name, digest in pins.items():
        relative_name(name)
        if name in external:
            require(digest == external[name], 'External inventory hash mismatch')
        else:
            require(sha(local_file(hardware, name)) == digest, 'Selected local input changed: ' + name)
    require(sha(image) == image_sha, 'Selected bitstream changed')
    lists = source_lists(project, configuration)
    enabled = {name for name, _ in lists['entries']}
    require({name for name in enabled if name.startswith('official/')} ==
            {'official/' + name for name in dependencies}, 'Wrong enabled vendor source set')
    for name in enabled:
        require('project/' + name in pins, 'Enabled project input has no selected identity: ' + name)
    tcl = local_file(hardware, 'run.tcl').read_text()
    require('open_project [file join [pwd] project product.gprj]' in tcl,
            'Unrecognized project build entry')
    options = dict(re.findall(r'^set_option -(\w+) (\S+)\s*$', tcl, re.M))
    top = options.get('top_module')
    require(bool(top), 'Missing selected physical top')
    declarations = []
    notes = []
    for name in lists['verilog']:
        if name.startswith('official/'):
            continue
        source = local_file(project, name)
        text = source.read_text()
        if re.search(r'^\s*module\s+' + re.escape(top) + r'\b', text, re.M):
            declarations.append(name)
        if Path(name).name == 'candidate.sv':
            modules = re.findall(r'^\s*module\s+(\w+)', text, re.M)
            notes.append(dict(path=name, role='enabled source; filename does not determine status', modules=modules))
        if 'not the qualified image' in text:
            notes.append(dict(path=name, role='stale presentation label; use this configuration inventory and evidence', sha256=sha(source)))
    require(len(declarations) == 1, 'Physical top is missing or duplicated in selected local Verilog')
    defines = re.findall(r'^`define\s+(\w+)([^\n]*)', local_file(project, 'defines.v').read_text(), re.M)
    return dict(configuration=configuration, result='SELECTED_SOURCE_ROUTE_CONSISTENT',
                source_inventory=inventory_name, source_inventory_sha256=sha(inventory_path),
                selected_input_count=len(pins), local_pinned_inputs=len(pins) - len(external),
                separately_acquired_inputs=len(external),
                hardware_root=hardware_name, top_module=top, top_source=declarations[0],
                build_entry=hardware_name + '/run.tcl', actual_source_authority=hardware_name + '/project/product.gprj',
                enabled_file_counts={kind: sum(k == kind for _, k in lists['entries']) for kind in sorted(TYPES)},
                member_list=hardware_name + '/project/production_sources.f',
                source_list_scope=lists['source_list_scope'], common_members_same_order=lists['common_members_same_order'],
                project_only_verilog=lists['project_only_verilog'], additional_vhdl=lists['vhdl'],
                defines={name: value.strip() for name, value in defines}, build_options=options,
                selected_image=str(image.relative_to(model)), selected_image_sha256=image_sha,
                external_vendor_status=check_vendor(vendor_dir, dependencies), presentation_notes=notes,
                hardware_access=False, network_access=False, compiler_or_solver_execution=False,
                scope='Recorded source/build selection consistency only; not a new build, timing qualification, proof replay or live-image attestation.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--model-root', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--configuration', choices=tuple(CONFIGURATIONS))
    parser.add_argument('--vendor-dir', type=Path, help='Optional already-acquired vendor directory; never downloads')
    args = parser.parse_args()
    names = [args.configuration] if args.configuration else list(CONFIGURATIONS)
    rows = [check_configuration(args.model_root, name, args.vendor_dir) for name in names]
    print(json.dumps(dict(result='PASS', configurations=rows, checker_sha256=sha(Path(__file__)),
                          writes=False, hardware_access=False, network_access=False), indent=2))


if __name__ == '__main__':
    main()
